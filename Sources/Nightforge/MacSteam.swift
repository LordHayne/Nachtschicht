import AppKit
import Foundation

/// Valve's Steam for Mac, which Nightforge sets up and runs in the background for the games whose
/// native Mac version it uses (VersionChoice): the Windows Steam under Wine can't download macOS
/// builds. Like the Wine one, it is signed in to only in its own window – Nightforge never sees
/// the login.
enum MacSteam {
    static let bundleID = "com.valvesoftware.steam"
    static let installerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/steam.dmg")!
    /// Valve's Developer ID: the Steam.app from the download has to be signed with it.
    private static let codeRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "MXGJJ98X76""#

    /// Steam for Mac's own folder: the client it downloads on first start, the library and the logs.
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Steam", isDirectory: true)
    }

    static var steamapps: URL { root.appendingPathComponent("steamapps", isDirectory: true) }

    static var bottle: Bottle { Bottle(name: "Steam for Mac", url: root) }

    /// Steam.app – in Applications, where Valve's installer and Nightforge put it, or wherever
    /// the player moved it (but not the client inside Steam's own folder).
    static var app: URL? {
        let fm = FileManager.default
        let candidates = ["/Applications/Steam.app", NSHomeDirectory() + "/Applications/Steam.app"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let found = candidates.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("Contents/Info.plist").path) }) {
            return found
        }
        guard let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              !registered.path.hasPrefix(root.path), !registered.path.hasPrefix("/Volumes/")
        else { return nil }
        return registered
    }

    static var isInstalled: Bool { app != nil }

    /// Someone has signed in to Steam for Mac on this Mac.
    static var hasSignedIn: Bool {
        let users = VDF.parse(contentsOf: root.appendingPathComponent("config/loginusers.vdf"))?["users"]?.object
        return !(users ?? [:]).isEmpty
    }

    /// Games can go through it: installed, and signed in once.
    static var isReady: Bool { isInstalled && hasSignedIn }

    /// The Steam running now has signed in.
    static var signedIn: Bool { Engine.signedIn(steamRoot: root) }

    static var running: [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) }

    static var isRunning: Bool { !running.isEmpty }

    /// Nightforge started the Steam that runs now, so it ends it again when it quits
    /// (Engine.scheduleSteamShutdown). A Steam the player started stays.
    static var startedByNightforge: Bool {
        get { UserDefaults.standard.bool(forKey: "macSteamStartedByNightforge") }
        set { UserDefaults.standard.set(newValue, forKey: "macSteamStartedByNightforge") }
    }

    // MARK: - Setup

    /// Downloads Valve's installer (a few MB), checks it's signed by Valve and puts Steam.app into
    /// Applications – the player's own when the shared one isn't writable. Steam fetches the rest
    /// of itself on its first start.
    static func install() async throws {
        guard !isInstalled else { return }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("nightforge-steam-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let image = work.appendingPathComponent("steam.dmg")
        do {
            let (download, response) = try await URLSession.shared.download(from: installerURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MacSteamError.downloadFailed }
            try fm.moveItem(at: download, to: image)
        } catch {
            throw MacSteamError.downloadFailed
        }

        let volume = work.appendingPathComponent("volume", isDirectory: true)
        try fm.createDirectory(at: volume, withIntermediateDirectories: true)
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard run("/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", volume.path, image.path) == 0
            else { throw MacSteamError.installFailed }
            defer { run("/usr/bin/hdiutil", "detach", volume.path, "-force") }
            let source = volume.appendingPathComponent("Steam.app", isDirectory: true)
            guard run("/usr/bin/codesign", "--verify", "--deep", "--strict", "-R=" + codeRequirement, source.path) == 0
            else { throw MacSteamError.notFromValve }
            let shared = URL(fileURLWithPath: "/Applications", isDirectory: true)
            let folder = fm.isWritableFile(atPath: shared.path)
                ? shared : fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            guard run("/usr/bin/ditto", source.path, folder.appendingPathComponent("Steam.app").path) == 0
            else { throw MacSteamError.installFailed }
        }.value
    }

    // MARK: - Running it

    /// Starts Steam in the background (hidden, without its main window), or brings it to the
    /// front with its main window when `visible` – for signing in, or a question it waits on.
    static func start(visible: Bool = false) {
        guard let app else { return }
        if visible && isRunning {
            show()
            return
        }
        if !isRunning { startedByNightforge = true }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = visible
        configuration.hides = !visible
        configuration.arguments = visible ? [] : ["-silent"]
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    /// Steam's main window in front, e.g. for a question it asks before starting a game.
    static func show() {
        guard isRunning else { return start(visible: true) }
        for app in running { app.unhide() }
        open("open/main", activate: true)
    }

    /// Back to the background after the player has dealt with it.
    static func hide() {
        for app in running { app.hide() }
    }

    /// Hands Steam a steam:// command ("run/275850"), which starts it if it isn't running.
    static func open(_ command: String, activate: Bool = false) {
        guard let app, let url = URL(string: "steam://" + command) else { return }
        if !isRunning { startedByNightforge = true }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    }

    /// Asks Steam to quit (it saves its state and cloud files) and ends it the hard way after 20 s.
    static func quit() async {
        for app in running { app.terminate() }
        for _ in 0..<20 {
            guard isRunning else { return }
            try? await Task.sleep(for: .seconds(1))
        }
        for app in running { app.forceTerminate() }
    }

    // MARK: - Games

    private static func manifest(_ appID: Int) -> URL { steamapps.appendingPathComponent("appmanifest_\(appID).acf") }

    /// Asks Steam for Mac to download a game without an install dialog: like the Windows Steam
    /// (Engine.requestDownload) it fetches a game whose manifest says "update required" when it
    /// starts. A Steam that started before the manifest was written is restarted for that – unless
    /// it's one the player opened, or a Mac game runs that would go with it: then Steam shows its
    /// install dialog instead.
    static func download(appID: Int, name: String, installDir: String, macGameRunning: Bool) async throws {
        let written = { (try? manifest(appID).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        if isRunning, written() == nil, macGameRunning || !startedByNightforge {
            open("install/\(appID)", activate: true)
            return
        }
        try Engine.requestDownload(appID: appID, name: name, installDir: installDir, steamapps: steamapps)
        guard isRunning else { return start() }
        if let launched = running.compactMap(\.launchDate).min(), let written = written(), launched > written { return }
        await quit()
        start()
    }

    /// Steam has taken up a requested download – it knows the size, or the files are coming in – or
    /// is busy with another one, behind which it queues this one.
    static func downloadStarted(appID: Int) -> Bool {
        let state = VDF.parse(contentsOf: manifest(appID))?["appstate"]
        let bytes = state?["bytestodownload"]?.string.flatMap { Int64($0) } ?? 0
        let flags = state?["stateflags"]?.string.flatMap { Int($0) } ?? 0
        let downloading = (try? FileManager.default.contentsOfDirectory(
            atPath: steamapps.appendingPathComponent("downloading").path)) ?? []
        return state == nil || bytes > 0 || flags & 4 != 0 || downloading.contains { Int($0) != nil }
    }

    /// Removes a Mac version the way Engine.uninstall removes a Windows one: with Steam closed,
    /// its manifest and files go. A Steam that was running starts again in the background.
    static func uninstall(appID: Int, installDir: URL) async throws {
        let wasRunning = isRunning
        let ours = startedByNightforge
        if wasRunning { await quit() }
        defer {
            if wasRunning {
                start(visible: !ours)  // the player's own Steam comes back as they had it
                startedByNightforge = ours
            }
        }
        // The game's own library folder: steamapps/common/<folder>.
        let library = installDir.deletingLastPathComponent().deletingLastPathComponent()
        try Engine.removeGameFiles(appID: appID, installDirName: installDir.lastPathComponent, steamapps: library)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: String...) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

enum MacSteamError: LocalizedError {
    case downloadFailed, notFromValve, installFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return L10n.t("Steam for Mac could not be downloaded. Check your internet connection.")
        case .notFromValve: return L10n.t("The Steam for Mac download isn't signed by Valve, so it wasn't installed.")
        case .installFailed: return L10n.t("Steam for Mac could not be installed.")
        }
    }
}
