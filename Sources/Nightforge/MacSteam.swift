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

    /// Games can go through it: installed, and signed in once – or right now: Steam writes its
    /// account list a few seconds after the sign-in.
    static var isReady: Bool { isInstalled && (hasSignedIn || signedIn) }

    /// The Steam running now has signed in.
    static var signedIn: Bool { Engine.signedIn(steamRoot: root) }

    /// Started up far enough to take steam:// commands.
    static var startupFinished: Bool { Engine.startupFinished(steamRoot: root) }

    /// Signed out because the Wine Steam signed in with the same account (Engine.sessionReplaced).
    static var sessionReplaced: Bool { Engine.sessionReplaced(steamRoot: root) }

    static var running: [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) }

    /// The Steam client's process. NSRunningApplication doesn't always say (its pid can read -1),
    /// so it's looked up by its program: Steam.AppBundle/…/MacOS/steam_osx in Steam's folder.
    static var clientPID: pid_t? {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        let client = root.appendingPathComponent("Steam.AppBundle").resolvingSymlinksInPath().path
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let path = String(cString: buffer)
            if path.hasPrefix(client), path.hasSuffix("/steam_osx") { return pid }
        }
        return nil
    }

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
    /// front with its main window when `visible` – for signing in.
    static func start(visible: Bool = false) {
        guard let app else { return }
        if visible && isRunning {
            show(keepFor: 600)
            return
        }
        if !isRunning { startedByNightforge = true }
        if visible { allowVisible(for: 600) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = visible
        configuration.hides = !visible
        configuration.arguments = visible ? [] : ["-silent"]
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    /// Steam's main window in front, for something the player does there (a question, the
    /// sign-in). The window guard leaves it up while Steam waits for the player, and `keepFor`
    /// seconds besides.
    static func show(keepFor seconds: TimeInterval = 0) {
        guard isRunning else { return start(visible: true) }
        allowVisible(for: seconds)
        for app in running { app.unhide() }
        open("open/main", activate: true)
    }

    /// A Steam dialog the player answers (steam://install/… asks where to install).
    static func ask(_ command: String) {
        allowVisible(for: 300)
        open(command, activate: true)
    }

    /// Until when Nightforge wants Steam's window up although Steam doesn't log that it waits.
    private static let visibleLock = NSLock()
    private static var visibleUntil = Date.distantPast

    private static func allowVisible(for seconds: TimeInterval) {
        visibleLock.lock()
        visibleUntil = max(visibleUntil, Date().addingTimeInterval(seconds))
        visibleLock.unlock()
    }

    private static var allowedVisible: Bool {
        visibleLock.lock()
        defer { visibleLock.unlock() }
        return Date() < visibleUntil
    }

    /// Back to the background after the player has dealt with it.
    static func hide() {
        for app in running { app.hide() }
    }

    /// Keeps Steam for Mac out of sight while Nightforge runs. Its window comes up when it starts,
    /// after signing in, when it starts a game and when a game ends (macOS hands it the focus),
    /// and it doesn't even know the games Nightforge plays through Wine. It stays up only while
    /// Steam waits for the player – a question before a start, a cloud conflict, its sign-in.
    @MainActor
    static func guardWindows() async {
        while !Task.isCancelled {
            if running.contains(where: { !$0.isHidden }), !allowedVisible, hasSignedIn, !waitingForPlayer {
                hide()
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Steam waits for the player: a question before a game starts ("waiting for user response"
    /// in its console log), a cloud sync it couldn't finish, or its sign-in window.
    static var waitingForPlayer: Bool {
        let now = Date()
        let console = logLines("console_log.txt")
        if let last = console.last(where: { $0.contains("GameAction [AppID") }), last.contains("waiting for user response"),
           let date = logDate(last), now.timeIntervalSince(date) < 600 {
            return true
        }
        let cloud = logLines("cloud_log.txt").filter { $0.contains("[AppID") }
        if let last = cloud.last(where: { ["Starting sync", "conflict", "Failed sync", "complete"].contains(where: $0.contains) }),
           last.contains("conflict") || last.contains("Failed sync"), let date = logDate(last), now.timeIntervalSince(date) < 120 {
            return true
        }
        // Still signed out a while after starting – and not because the Wine Steam signed in.
        if !signedIn, !sessionReplaced, let launched = running.compactMap(\.launchDate).min(), now.timeIntervalSince(launched) > 25 {
            return true
        }
        return false
    }

    private static func logLines(_ name: String) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: root.appendingPathComponent("logs/\(name)")) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 32_768 ? size - 32_768 : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        return text.split(whereSeparator: \.isNewline)
    }

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    /// "[2026-10-26 11:10:12] …"
    private static func logDate(_ line: Substring) -> Date? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        return logFormatter.date(from: String(line[line.index(after: line.startIndex)..<close]))
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
            ask("install/\(appID)")
            return
        }
        try Engine.requestDownload(appID: appID, name: name, installDir: installDir, steamapps: steamapps)
        guard isRunning else { return start() }
        if !sessionReplaced, let launched = running.compactMap(\.launchDate).min(), let written = written(), launched > written {
            return
        }
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
