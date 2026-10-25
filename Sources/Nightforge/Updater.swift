import AppKit
import Foundation

/// A newer Nightforge release on GitHub.
struct AppUpdate: Equatable {
    let version: String
    let archive: URL
    let page: URL
}

/// Keeps Nightforge itself current: one look at the newest GitHub release per app start, and a
/// one-click install that downloads the zip, checks its signature, swaps the app and restarts it.
enum Updater {
    private static let latestRelease = URL(string: "https://api.github.com/repos/LordHayne/Nightforge/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The newest release when it's newer than this copy, else nil (also when offline).
    static func check() async -> AppUpdate? {
        var request = URLRequest(url: latestRelease)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]],
              let zip = assets.compactMap({ $0["browser_download_url"] as? String })
                  .first(where: { $0.hasSuffix(".zip") && $0.contains("Nightforge-") })
                  .flatMap(URL.init(string:))
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: currentVersion) else { return nil }
        return AppUpdate(version: version, archive: zip, page: page)
    }

    /// "0.2.0" > "0.1.10" > "0.1.4"; a version with a suffix ("0.2.0-dev") comes before the plain one.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func split(_ version: String) -> (numbers: [Int], suffix: Bool) {
            let parts = version.split(separator: "-", maxSplits: 1)
            return (parts[0].split(separator: ".").map { Int($0) ?? 0 }, parts.count > 1)
        }
        let (a, aSuffix) = split(candidate)
        let (b, bSuffix) = split(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return !aSuffix && bSuffix
    }

    enum Failure: LocalizedError {
        case download, unpack, signature, notWritable

        var errorDescription: String? {
            switch self {
            case .download: return L10n.t("The update could not be downloaded. Check your internet connection.")
            case .unpack: return L10n.t("The update download is damaged. Please try again.")
            case .signature: return L10n.t("The update isn't signed correctly, so it wasn't installed.")
            case .notWritable: return L10n.t("Nightforge can't replace itself in this folder. Download the update from the release page instead.")
            }
        }
    }

    /// Downloads and installs `update` over the running app, then restarts it.
    static func install(_ update: AppUpdate) async throws {
        let fm = FileManager.default
        let app = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: app.deletingLastPathComponent().path) else { throw Failure.notWritable }

        let work = fm.temporaryDirectory.appendingPathComponent("nightforge-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        guard let (download, response) = try? await URLSession.shared.download(from: update.archive),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { throw Failure.download }
        let zip = work.appendingPathComponent("Nightforge.zip")
        try fm.moveItem(at: download, to: zip)

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) else { throw Failure.unpack }
        let fresh = unpacked.appendingPathComponent("Nightforge.app", isDirectory: true)
        guard Bundle(url: fresh)?.bundleIdentifier == Bundle.main.bundleIdentifier else { throw Failure.unpack }
        guard run("/usr/bin/codesign", ["--verify", "--deep", fresh.path]) else { throw Failure.signature }

        // Swap in one step; the running copy keeps working from memory until the restart.
        _ = try fm.replaceItemAt(app, withItemAt: fresh)
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try relaunch.run()
        await MainActor.run { NSApp.terminate(nil) }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
