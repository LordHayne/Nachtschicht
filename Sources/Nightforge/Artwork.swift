import AppKit
import ImageIO

enum ArtKind: String {
    case cover, hero, logo

    var fileNames: [String] {
        switch self {
        // Newer games only ship the portrait cover as library_capsule.
        case .cover: return ["library_600x900_2x.jpg", "library_600x900.jpg", "library_capsule_2x.jpg", "library_capsule.jpg"]
        case .hero: return ["library_hero.jpg"]
        case .logo: return ["logo.png"]
        }
    }

    /// Covers are drawn 154 pt wide (231 tall, a little more when picked): kept at that size on a
    /// Retina screen rather than Steam's 1200×1800, a quarter of the memory per cover. Hero art
    /// fills the window, logos are small: both stay as they are.
    var maxPixelSize: Int? { self == .cover ? 640 : nil }
}

/// Loads game art in this order: memory → own disk cache → Steam's cache inside the bottle → Steam CDN.
/// After the first run everything comes from disk, so the launcher works offline.
actor ArtworkStore {
    static let shared = ArtworkStore()

    private let memory = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let cacheDir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("Nightforge/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memory.countLimit = 400
        // Decoded pixels, not files: a whole library of covers stays well within this.
        memory.totalCostLimit = 300 * 1024 * 1024
    }

    func image(for game: Game, kind: ArtKind) async -> NSImage? {
        let key = "\(game.appID)_\(kind.rawValue)"
        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let running = inflight[key] { return await running.value }

        let dir = cacheDir
        let task = Task<NSImage?, Never> {
            await Self.load(game: game, kind: kind, cacheDir: dir, key: key)
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString, cost: Self.cost(of: image)) }
        return image
    }

    private static func cost(of image: NSImage) -> Int {
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
        return max(pixels.width * pixels.height * 4, 1)
    }

    /// An image from file data, scaled down to `kind`'s size when it's larger.
    static func decode(_ data: Data, kind: ArtKind) -> NSImage? {
        guard let maxSize = kind.maxPixelSize, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Steam adds art to games now and then; a "nothing there" from a week ago is asked again.
    private static let missingLifetime: TimeInterval = 7 * 24 * 3600

    private static func load(game: Game, kind: ArtKind, cacheDir: URL, key: String) async -> NSImage? {
        let fm = FileManager.default
        let cached = cacheDir.appendingPathComponent(key)
        let missingMarker = cacheDir.appendingPathComponent(key + ".missing")

        if let data = try? Data(contentsOf: cached), let image = decode(data, kind: kind) { return image }

        // Steam's own cache first – it can gain art after a "missing" marker was written.
        if let local = localFile(game: game, kind: kind),
           let data = try? Data(contentsOf: local),
           let image = decode(data, kind: kind) {
            try? data.write(to: cached)
            try? fm.removeItem(at: missingMarker)
            return image
        }
        if let written = (try? fm.attributesOfItem(atPath: missingMarker.path))?[.modificationDate] as? Date {
            guard Date().timeIntervalSince(written) > missingLifetime else { return nil }
            try? fm.removeItem(at: missingMarker)
        }

        var everythingWas404 = true
        for url in remoteURLs(appID: game.appID, kind: kind) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let image = decode(data, kind: kind) {
                    try? data.write(to: cached)
                    return image
                }
                if status != 404 && status != 403 { everythingWas404 = false }
            } catch {
                everythingWas404 = false // offline – try again next time
            }
        }

        // Steam has no such art for this game: remember that and stop asking.
        if everythingWas404 { fm.createFile(atPath: missingMarker.path, contents: nil) }
        return nil
    }

    private static func localFile(game: Game, kind: ArtKind) -> URL? {
        let fm = FileManager.default
        let cache = game.steamRoot.appendingPathComponent("appcache/librarycache", isDirectory: true)

        // Older Steam: flat files like 1245620_library_600x900.jpg
        for name in kind.fileNames {
            let flat = cache.appendingPathComponent("\(game.appID)_\(name)")
            if fm.fileExists(atPath: flat.path) { return flat }
        }

        // Newer Steam: one folder per app, files sometimes in hashed subfolders
        let dir = cache.appendingPathComponent("\(game.appID)", isDirectory: true)
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let files = enumerator.compactMap { $0 as? URL }
        for name in kind.fileNames {
            if let hit = files.first(where: { $0.lastPathComponent == name }) { return hit }
        }
        return nil
    }

    private static func remoteURLs(appID: Int, kind: ArtKind) -> [URL] {
        let bases = [
            "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/",
            "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/",
        ]
        return kind.fileNames.flatMap { name in bases.compactMap { URL(string: $0 + name) } }
    }
}
