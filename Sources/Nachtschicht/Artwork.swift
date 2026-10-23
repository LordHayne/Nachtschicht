import AppKit

enum ArtKind: String {
    case cover, hero, logo

    var fileNames: [String] {
        switch self {
        case .cover: return ["library_600x900_2x.jpg", "library_600x900.jpg"]
        case .hero: return ["library_hero.jpg"]
        case .logo: return ["logo.png"]
        }
    }
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
        cacheDir = base.appendingPathComponent("Nachtschicht/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memory.countLimit = 400
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
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    private static func load(game: Game, kind: ArtKind, cacheDir: URL, key: String) async -> NSImage? {
        let fm = FileManager.default
        let cached = cacheDir.appendingPathComponent(key)
        let missingMarker = cacheDir.appendingPathComponent(key + ".missing")

        if let image = NSImage(contentsOf: cached) { return image }
        if fm.fileExists(atPath: missingMarker.path) { return nil }

        if let local = localFile(game: game, kind: kind),
           let data = try? Data(contentsOf: local),
           let image = NSImage(data: data) {
            try? data.write(to: cached)
            return image
        }

        var everythingWas404 = true
        for url in remoteURLs(appID: game.appID, kind: kind) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let image = NSImage(data: data) {
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
