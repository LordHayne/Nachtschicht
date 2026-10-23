import Foundation

/// Nachtschicht's own free Wine setup: the engine component, one Windows environment ("prefix")
/// and the Windows Steam client inside it. Used when CrossOver isn't the chosen runner.
enum Engine {
    static let engineID = "wine"
    static let graphicsID = "dxmt"
    /// DirectX 9–11 → Vulkan → Metal. Draws reliably on Wine 11 today, while DXMT can't attach to
    /// Wine 11's windows yet (that needs a patched DXMT build).
    static let dxvkID = "dxvk-macos"
    static let steamSetupURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    static let steamExeWindowsPath = #"C:\Program Files (x86)\Steam\steam.exe"#
    /// Steam's web UI (CEF) paints a black window under Wine on macOS unless it renders in software
    /// in a single process. The single-process part is done by the steamwebhelper wrapper, which
    /// -noverifyfiles keeps Steam from "repairing" away; the CEF sandbox needs Windows features Wine lacks.
    static let steamArguments = [
        "-no-cef-sandbox", "-cef-single-process", "-noverifyfiles",
        "-cef-disable-gpu", "-cef-disable-gpu-compositing",
    ]
    /// Wine's builtin crypto avoids TLS failures in Steam's browser; the overlay DLL deadlocks games.
    /// Games inherit these from Steam, so DirectX goes to DXVK's DLLs in the prefix (native first).
    static let steamDLLOverrides = "dxgi,d3d11,d3d10core,d3d9=n,b;bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nachtschicht", isDirectory: true)
    }

    /// The Windows environment Steam and the games live in.
    static var prefix: URL { supportDir.appendingPathComponent("Prefix", isDirectory: true) }

    static var bottle: Bottle { Bottle(name: "Nachtschicht", url: prefix, isBuiltIn: true) }

    static var steamRoot: URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    static var isSteamInstalled: Bool {
        FileManager.default.fileExists(atPath: steamRoot.appendingPathComponent("steam.exe").path)
    }

    /// True once someone has signed in to Steam in this prefix.
    static var isSteamSignedIn: Bool {
        let users = VDF.parse(contentsOf: steamRoot.appendingPathComponent("config/loginusers.vdf"))?["users"]?.object
        return !(users ?? [:]).isEmpty
    }

    /// Steam's own login screen is up and waiting (it logs this once its update is done).
    static func isSteamWaitingForSignIn(since start: Date) -> Bool {
        let log = steamRoot.appendingPathComponent("logs/steamui_login.txt")
        guard let modified = (try? log.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              modified >= start,
              let text = try? String(contentsOf: log, encoding: .utf8)
        else { return false }
        return text.components(separatedBy: "\n").suffix(20).contains { $0.contains("WaitingForCredentials") }
    }

    /// Steam's self-update: (downloaded, total) in KB from the newest bootstrap log line, and when it last changed.
    static func steamUpdateStatus() -> (fraction: Double?, lastChange: Date?) {
        let log = steamRoot.appendingPathComponent("logs/bootstrap_log.txt")
        let modified = (try? log.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let text = try? String(contentsOf: log, encoding: .utf8),
              let line = text.components(separatedBy: "\n").last(where: { $0.contains(" KB)") })
        else { return (nil, modified) }
        // "… (12,345 von 336,229 KB) …" – the word in the middle depends on Steam's language.
        let numbers = line.split(separator: "(").last?.split(separator: " ").compactMap {
            Double($0.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: ""))
        } ?? []
        guard numbers.count >= 2, numbers[1] > 0 else { return (nil, modified) }
        return (min(numbers[0] / numbers[1], 1), modified)
    }

    /// Whether Steam's main process is running (any prefix; good enough to notice a crash or restart).
    static var isSteamRunning: Bool {
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "command"]
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return false }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return output.lowercased().contains(#"\steam\steam.exe"#)
    }

    /// Ends every Windows process in Nachtschicht's prefix.
    static func stopAll(_ wine: URL) {
        let server = Process()
        server.executableURL = wine.deletingLastPathComponent().appendingPathComponent("wineserver")
        server.arguments = ["-k"]
        server.environment = environment(wine: wine)
        try? server.run()
        server.waitUntilExit()
    }

    /// Puts the bundled steamwebhelper wrapper in place of Steam's own (which becomes
    /// steamwebhelper_real.exe). Repeats safely; returns true when it changed anything, e.g. after
    /// Steam's first update unpacked its browser or a later update replaced it.
    @discardableResult
    static func installWebHelperWrapper() -> Bool {
        guard let wrapper = Bundle.main.url(forResource: "steamwebhelper", withExtension: "exe") else { return false }
        let fm = FileManager.default
        let cef = steamRoot.appendingPathComponent("bin/cef", isDirectory: true)
        let wrapperSize = (try? fm.attributesOfItem(atPath: wrapper.path)[.size] as? Int) ?? 0
        let dirs = (try? fm.contentsOfDirectory(at: cef, includingPropertiesForKeys: nil)) ?? []
        var changed = false

        for dir in dirs where dir.lastPathComponent.hasPrefix("cef.win") {
            let helper = dir.appendingPathComponent("steamwebhelper.exe")
            let real = dir.appendingPathComponent("steamwebhelper_real.exe")
            guard let size = try? fm.attributesOfItem(atPath: helper.path)[.size] as? Int else { continue }
            if size == wrapperSize { continue }
            // Valve's helper is several MB, the wrapper ~150 KB: anything else is Steam's (new) original.
            guard size > 1_000_000 else { continue }
            do {
                try? fm.removeItem(at: real)
                try fm.moveItem(at: helper, to: real)
                try fm.copyItem(at: wrapper, to: helper)
                changed = true
            } catch {
                continue
            }
        }
        return changed
    }

    static var isRosettaInstalled: Bool {
        // Rosetta is what runs Wine's x86_64 code; `arch -x86_64` fails without it.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        probe.arguments = ["-x86_64", "/usr/bin/true"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        guard (try? probe.run()) != nil else { return false }
        probe.waitUntilExit()
        return probe.terminationStatus == 0
    }

    /// `bin/wine` inside an unpacked engine component (the archive holds a "Wine ….app" bundle).
    static func wineBinary(in engineDir: URL) -> URL? {
        let apps = (try? FileManager.default.contentsOfDirectory(at: engineDir, includingPropertiesForKeys: nil)) ?? []
        return apps
            .filter { $0.pathExtension == "app" }
            .map { $0.appendingPathComponent("Contents/Resources/wine/bin/wine") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Makes sure the engine and graphics layer from the current component list are installed –
    /// e.g. after the list moved to a newer engine. Returns the wine binary to use.
    static func ensureEngine() async throws -> URL {
        let store = ComponentStore.shared
        let manifest = try await store.manifest()
        guard let engine = manifest.component(engineID), let graphics = manifest.component(graphicsID) else {
            throw ComponentError.noManifest
        }
        let fresh = await store.installedPath(for: engine) == nil
        let engineDir = try await store.install(engine)
        let graphicsDir = try await store.install(graphics)
        guard let wine = wineBinary(in: engineDir) else { throw SetupError.engineBroken }
        if fresh {
            // A wineserver from the previous engine can't talk to the new one; end the old session.
            for dir in (try? FileManager.default.contentsOfDirectory(
                at: store.root.appendingPathComponent(engineID), includingPropertiesForKeys: nil)) ?? []
            where dir != engineDir {
                if let old = wineBinary(in: dir) { stopAll(old) }
            }
            for other in ["wine-staging"] {
                for dir in (try? FileManager.default.contentsOfDirectory(
                    at: store.root.appendingPathComponent(other), includingPropertiesForKeys: nil)) ?? [] {
                    if let old = wineBinary(in: dir) { stopAll(old) }
                }
            }
        }
        try installGraphics(graphicsDir, into: wine)
        if let dxvk = manifest.component(dxvkID) {
            try installDXVK(try await store.install(dxvk))
        }
        return wine
    }

    /// Installed engine binary, if setup has got that far.
    static func installedWine() async -> URL? {
        guard let manifest = try? await ComponentStore.shared.manifest(),
              let component = manifest.component(engineID),
              let dir = await ComponentStore.shared.installedPath(for: component)
        else { return nil }
        return wineBinary(in: dir)
    }

    /// Copies DXMT (Direct3D 10/11 → Metal) into the engine's builtin DLL folders. Safe to repeat.
    static func installGraphics(_ dxmtDir: URL, into wine: URL) throws {
        let fm = FileManager.default
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine", isDirectory: true)
        // The archive has one versioned top folder: v0.80/{x86_64-windows,i386-windows,x86_64-unix}
        let top = (try fm.contentsOfDirectory(at: dxmtDir, includingPropertiesForKeys: nil))
            .first { fm.fileExists(atPath: $0.appendingPathComponent("x86_64-windows").path) } ?? dxmtDir

        for arch in ["x86_64-windows", "i386-windows", "x86_64-unix"] {
            let source = top.appendingPathComponent(arch, isDirectory: true)
            let target = lib.appendingPathComponent(arch, isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                let destination = target.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: file, to: destination)
            }
        }
    }

    /// Copies DXVK's DLLs into the prefix (64-bit → system32, 32-bit → syswow64). Safe to repeat.
    static func installDXVK(_ dxvkDir: URL) throws {
        let fm = FileManager.default
        let top = (try fm.contentsOfDirectory(at: dxvkDir, includingPropertiesForKeys: nil))
            .first { fm.fileExists(atPath: $0.appendingPathComponent("x64").path) } ?? dxvkDir
        let windows = prefix.appendingPathComponent("drive_c/windows", isDirectory: true)
        for (arch, folder) in [("x64", "system32"), ("x32", "syswow64")] {
            let source = top.appendingPathComponent(arch, isDirectory: true)
            let target = windows.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: target.path),
                  let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "dll" {
                let destination = target.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: file, to: destination)
            }
        }
    }

    static func environment(wine: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Keeps Steam's own processes out of the Dock (wrapper/hide-steam-dock.m); games are untouched.
        if let hider = Bundle.main.url(forResource: "hide-steam-dock", withExtension: "dylib") {
            env["DYLD_INSERT_LIBRARIES"] = hider.path
        }
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        // Gecko/Mono installers would otherwise pop up dialogs during setup.
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml="
        env["PATH"] = wine.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    /// Runs a Wine command and waits for it (and the wineserver it started) to finish.
    static func run(_ wine: URL, _ arguments: [String]) async throws -> Int32 {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = wine
            process.arguments = arguments
            process.environment = environment(wine: wine)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let server = Process()
            server.executableURL = wine.deletingLastPathComponent().appendingPathComponent("wineserver")
            server.arguments = ["-w"]
            server.environment = environment(wine: wine)
            try? server.run()
            server.waitUntilExit()
            return process.terminationStatus
        }.value
    }

    /// Asks Steam to download a game without any Steam window: an appmanifest marked "update
    /// required" makes Steam fetch the game on its next start. Call `restartSteamInBackground` after.
    static func requestDownload(appID: Int, name: String, installDir: String) throws {
        let steamapps = steamRoot.appendingPathComponent("steamapps", isDirectory: true)
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appID).acf")
        guard !FileManager.default.fileExists(atPath: manifest.path) else { return }
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "'") + "\"" }
        let text = """
        "AppState"
        {
        \t"appid"\t\t\(quoted(String(appID)))
        \t"Universe"\t\t"1"
        \t"name"\t\t\(quoted(name))
        \t"StateFlags"\t\t"1026"
        \t"installdir"\t\t\(quoted(installDir))
        \t"LastUpdated"\t\t"0"
        \t"SizeOnDisk"\t\t"0"
        \t"buildid"\t\t"0"
        \t"AutoUpdateBehavior"\t\t"0"
        \t"AllowOtherDownloadsWhileRunning"\t\t"0"
        \t"ScheduledAutoUpdate"\t\t"0"
        }

        """
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try text.write(to: manifest, atomically: true, encoding: .utf8)
    }

    /// Starts Steam hidden unless it's already running. Downloads and game launches go through it.
    static func ensureSteamRunning(_ wine: URL) throws {
        guard !isSteamRunning else { return }
        try startSteam(wine, arguments: ["-silent"])
    }

    /// Quits Steam politely (so it saves its state) and starts it again hidden.
    static func restartSteamInBackground(_ wine: URL) async throws {
        try await stopSteam(wine)
        try startSteam(wine, arguments: ["-silent"])
    }

    /// Asks Steam to quit and waits up to 20 s before ending it the hard way.
    static func stopSteam(_ wine: URL) async throws {
        guard isSteamRunning else { return }
        try startSteam(wine, arguments: ["-shutdown"])
        for _ in 0..<20 {
            guard isSteamRunning else { return }
            try await Task.sleep(for: .seconds(1))
        }
        stopAll(wine)
    }

    /// Removes a game (or a download in progress) without any Steam window: with Steam stopped,
    /// its manifest and files go, and Steam simply finds it not installed when it starts again.
    /// The game stays in the Steam library, and saves outside the game folder are untouched.
    static func uninstall(appID: Int, installDirName: String, wine: URL) async throws {
        try await stopSteam(wine)
        defer { try? startSteam(wine, arguments: ["-silent"]) }

        let fm = FileManager.default
        let steamapps = steamRoot.appendingPathComponent("steamapps", isDirectory: true)
        var targets = [
            steamapps.appendingPathComponent("appmanifest_\(appID).acf"),
            steamapps.appendingPathComponent("downloading/\(appID)", isDirectory: true),
            steamapps.appendingPathComponent("shadercache/\(appID)", isDirectory: true),
        ]
        // Never let an empty or odd folder name turn into deleting all of steamapps/common.
        let name = installDirName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, !name.contains("/"), name != ".", name != ".." {
            targets.append(steamapps.appendingPathComponent("common/\(name)", isDirectory: true))
        }
        for target in targets where fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
    }

    /// Starts Steam without waiting; used for signing in and for launching games.
    static func startSteam(_ wine: URL, arguments: [String] = [], extraEnvironment: [String: String] = [:]) throws {
        installWebHelperWrapper()
        let process = Process()
        process.executableURL = wine
        process.arguments = [steamExeWindowsPath] + steamArguments + arguments
        var env = environment(wine: wine)
        env["WINEDLLOVERRIDES"] = steamDLLOverrides
        process.environment = env.merging(extraEnvironment) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
