import CryptoKit
import Foundation

/// One downloadable building block (Wine engine, graphics layer, tool) from components/manifest.json.
struct Component: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case engine, graphics, tool
    }

    let id: String
    let kind: Kind
    let version: String
    let url: URL
    let sha256: String
    let size: Int64
    let license: String
    let source: URL

    /// id, version and the file name become paths under Application Support and the url is
    /// downloaded: a changed list may not point them elsewhere (`..`) or at a plain-HTTP or local file.
    var isSafeToInstall: Bool {
        func plainName(_ text: String) -> Bool {
            !text.isEmpty && !text.hasPrefix(".") && text.count <= 128
                && text.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || "._+-".unicodeScalars.contains($0) }
        }
        return url.scheme == "https" && plainName(id) && plainName(version) && plainName(url.lastPathComponent)
    }
}

struct ComponentManifest: Codable {
    static let supportedSchema = 1

    let schemaVersion: Int
    let generated: String
    let components: [Component]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generated, components
    }

    /// One entry this version doesn't understand (a new kind, a changed field) or can't install safely
    /// is left out; the rest of the list still counts.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generated = (try? container.decode(String.self, forKey: .generated)) ?? ""
        components = try container.decode([Lenient<Component>].self, forKey: .components)
            .compactMap(\.value).filter(\.isSafeToInstall)
    }

    func component(_ id: String) -> Component? {
        components.first { $0.id == id }
    }
}

/// A list element that decodes to nil instead of failing the whole list.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

enum ComponentError: LocalizedError {
    case unsupportedSchema(Int)
    case noManifest
    case checksumMismatch(String)
    case extractFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return L10n.t("Component list version %ld needs a newer Nightforge.", version)
        case .noManifest:
            return L10n.t("No component list available. Check your internet connection.")
        case .checksumMismatch(let id):
            return L10n.t("The download of %@ is damaged. Please try again.", id)
        case .extractFailed(let id, let status):
            return L10n.t("%@ could not be unpacked (tar exit %d).", id, status)
        }
    }
}

/// Downloads, verifies and unpacks components into Application Support.
///
/// The manifest comes from `NightforgeManifestURL` in Info.plist when set, falls back to the last
/// copy that was fetched, and finally to the one bundled with the app, so a fresh install works offline.
actor ComponentStore {
    static let shared = ComponentStore()

    let root: URL
    private let remoteManifestURL: URL?
    private let bundledManifestURL: URL?

    init(
        root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge/Components", isDirectory: true),
        remoteManifestURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "NightforgeManifestURL") as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) },
        bundledManifestURL: URL? = Bundle.main.url(forResource: "manifest", withExtension: "json")
    ) {
        self.root = root
        self.remoteManifestURL = remoteManifestURL
        self.bundledManifestURL = bundledManifestURL
    }

    private var cachedManifestURL: URL { root.appendingPathComponent("manifest.json") }
    /// The online list is fetched once per app run. Asking again for every engine lookup would
    /// make each launch wait for the network – up to a minute when offline.
    private var fetched: ComponentManifest?
    private var triedRemote = false
    private var installing: [String: Task<URL, Error>] = [:]

    func manifest() async throws -> ComponentManifest {
        if let fetched { return fetched }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if !triedRemote, let remote = remoteManifestURL {
            triedRemote = true
            var request = URLRequest(url: remote)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData  // a fix published minutes ago should arrive
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode ?? 200 == 200,
               let manifest = try? decode(data) {
                try? data.write(to: cachedManifestURL, options: .atomic)
                fetched = manifest
                return manifest
            }
        }
        // A damaged or too-new cached copy mustn't hide the one bundled with the app.
        var failure: Error = ComponentError.noManifest
        for local in [cachedManifestURL, bundledManifestURL].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: local) else { continue }
            do {
                return try decode(data)
            } catch {
                failure = error
            }
        }
        throw failure
    }

    /// The list at hand without asking the network (Settings › About): the last one fetched, else
    /// the one bundled with the app.
    static func localManifest() -> ComponentManifest? {
        let cached = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge/Components/manifest.json")
        for url in [cached, Bundle.main.url(forResource: "manifest", withExtension: "json")].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(ComponentManifest.self, from: data) {
                return manifest
            }
        }
        return nil
    }

    private func decode(_ data: Data) throws -> ComponentManifest {
        let manifest = try JSONDecoder().decode(ComponentManifest.self, from: data)
        guard manifest.schemaVersion <= ComponentManifest.supportedSchema else {
            throw ComponentError.unsupportedSchema(manifest.schemaVersion)
        }
        return manifest
    }

    /// Folder of an installed component, or nil when this exact version isn't installed yet.
    func installedPath(for component: Component) -> URL? {
        let dir = directory(for: component)
        let marker = dir.appendingPathComponent(".sha256")
        guard (try? String(contentsOf: marker, encoding: .utf8)) == component.sha256 else { return nil }
        return dir
    }

    /// Installs `component` unless it's already there. `progress` reports 0...1 while downloading.
    /// A second request for the same component while it downloads waits for that download.
    func install(_ component: Component, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        if let dir = installedPath(for: component) { return dir }
        let key = "\(component.id)@\(component.version)"
        if let running = installing[key] { return try await running.value }
        let task = Task { try await self.download(component, progress: progress) }
        installing[key] = task
        defer { installing[key] = nil }
        return try await task.value
    }

    private func download(_ component: Component, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {

        let fm = FileManager.default
        let downloads = root.appendingPathComponent(".downloads", isDirectory: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let archive = downloads.appendingPathComponent(component.url.lastPathComponent)
        try? fm.removeItem(at: archive)

        try await Downloader.download(component.url, to: archive, expectedSize: component.size, progress: progress)
        defer { try? fm.removeItem(at: archive) }

        guard try Self.sha256(of: archive) == component.sha256 else {
            throw ComponentError.checksumMismatch(component.id)
        }

        // Unpack into a staging folder first so a half-extracted component is never picked up.
        let dir = directory(for: component)
        let staging = downloads.appendingPathComponent("\(component.id)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        if Self.isArchive(archive) {
            let status = try Self.untar(archive, into: staging)
            guard status == 0 else { throw ComponentError.extractFailed(component.id, status) }
        } else {
            let file = staging.appendingPathComponent(archive.lastPathComponent)
            try fm.copyItem(at: archive, to: file)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }

        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: dir)
        try component.sha256.write(to: dir.appendingPathComponent(".sha256"), atomically: true, encoding: .utf8)
        progress(1)
        return dir
    }

    private func directory(for component: Component) -> URL {
        root.appendingPathComponent(component.id, isDirectory: true)
            .appendingPathComponent(component.version, isDirectory: true)
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func isArchive(_ file: URL) -> Bool {
        let name = file.lastPathComponent
        return [".tar.gz", ".tgz", ".tar.xz", ".tar.zst", ".tar"].contains { name.hasSuffix($0) }
    }

    private static func untar(_ archive: URL, into dir: URL) throws -> Int32 {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path, "-C", dir.path]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        return tar.terminationStatus
    }
}

/// URLSession download with progress, written to a fixed destination.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSize: Int64
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?

    private init(destination: URL, expectedSize: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    static func download(_ url: URL, to destination: URL, expectedSize: Int64, progress: @escaping @Sendable (Double) -> Void) async throws {
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: destination)
            return
        }
        let delegate = Downloader(destination: destination, expectedSize: expectedSize, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
        let expected = total > 0 ? total : expectedSize
        if expected > 0 { progress(min(Double(written) / Double(expected), 1)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        do {
            guard status == 200 else { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
