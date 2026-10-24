import Foundation

/// Nachtschicht's own free Wine setup: the engine component, one Windows environment ("prefix")
/// and the Windows Steam client inside it. Used when CrossOver isn't the chosen runner.
enum Engine {
    static let engineID = "wine"
    /// Nachtschicht's own DXMT build for Wine 11 (with winemac.so); plain upstream DXMT as fallback.
    static let graphicsID = "graphics"
    static let upstreamGraphicsID = "dxmt"
    /// What "Automatic" means: DXMT ran OxyRail better than DXVK (fewer layers, correct video
    /// memory); games that don't work with it can be switched to DXVK in their options.
    static let defaultGraphics = GraphicsLayer.dxmt

    static func graphicsComponent(in manifest: ComponentManifest) -> Component? {
        manifest.component(graphicsID) ?? manifest.component(upstreamGraphicsID)
    }
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
    /// Settings games inherit from the background Steam. Bump `steamConfigVersion` whenever this
    /// or `steamDLLOverrides` changes, so a running Steam gets restarted with them.
    static let steamConfigVersion = 5
    static var gameEnvironment: [String: String] {
        var env = [
            // Compile shaders in the background instead of stalling the frame that first needs them.
            "DXVK_ASYNC": "1",
        ]
        // Apple's Metal HUD: DXMT draws with Metal directly, so this is its FPS display. Only an
        // environment variable turns it on, and games get theirs from Steam, hence app-wide.
        if Prefs.performanceHUD { env["MTL_HUD_ENABLED"] = "1" }
        return env
    }

    /// Steam starts its games with a fresh environment built from the Windows registry, not with
    /// its own – so the game settings go into the user environment (HKCU\Environment) as well,
    /// where every Windows program, games included, picks them up at start.
    static func applyGameEnvironment(wine: URL) {
        let managed = ["DXVK_ASYNC", "MTL_HUD_ENABLED"]
        let current = gameEnvironment
        let values = managed.map { name in
            current[name].map { "\"\(name)\"=\"\($0)\"" } ?? "\"\(name)\"=-"
        }
        importRegistry("[HKEY_CURRENT_USER\\Environment]\n" + values.joined(separator: "\n"), wine: wine)
    }

    /// Changes whenever the background Steam has to restart to hand games different settings.
    static var steamConfigSignature: String {
        "\(steamConfigVersion)-hud\(Prefs.performanceHUD ? 1 : 0)"
    }

    /// Wine's builtin crypto avoids TLS failures in Steam's browser; the overlay DLL deadlocks games.
    /// Games inherit these from Steam, so DirectX goes to DXVK's DLLs in the prefix (native first).
    /// The Direct3D choice itself lives in the registry (see `installDXVK` / `applyGraphics`): an
    /// override in this variable would beat the per-game AppDefaults.
    static let steamDLLOverrides = "bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"

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
        killLeftovers()
    }

    /// Wine helpers (winedevice.exe in particular) sometimes outlive `wineserver -k` and then
    /// hang around for days. Anything still running with its working directory in our prefix
    /// after the server is gone is such a leftover.
    static func killLeftovers() {
        let root = prefix.resolvingSymlinksInPath().path
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return }
        for pid in pids.prefix(Int(bytes)) where pid > 0 {
            var info = proc_vnodepathinfo()
            let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { continue }
            let cwd = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            if cwd.hasPrefix(root) { kill(pid, SIGKILL) }
        }
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
        guard let engine = manifest.component(engineID), let graphics = graphicsComponent(in: manifest) else {
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
        try installGraphics(graphicsDir, into: wine, matchesEngine: graphics.version.hasPrefix(engine.version + "-"))
        applyGameEnvironment(wine: wine)
        if let dxvk = manifest.component(dxvkID) {
            try installDXVK(try await store.install(dxvk), wine: wine)
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
    /// Nachtschicht's package also carries winemac.so built for one Wine version; it's only used
    /// when that matches the engine (`matchesEngine`), since a mismatched driver breaks every window.
    static func installGraphics(_ dxmtDir: URL, into wine: URL, matchesEngine: Bool = false) throws {
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
                if file.lastPathComponent == "winemac.so" && !matchesEngine { continue }
                let destination = target.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: file, to: destination)
            }
        }
    }

    /// Direct3D DLLs a game can take from DXVK (native, in the prefix) or DXMT (builtin, in the engine).
    private static let direct3DLibraries = ["dxgi", "d3d11", "d3d10core", "d3d9"]

    /// Copies DXVK's DLLs into the prefix (64-bit → system32, 32-bit → syswow64) and makes them the
    /// default for every program; games set to DXMT override that in `applyGraphics`. Safe to repeat.
    static func installDXVK(_ dxvkDir: URL, wine: URL) throws {
        defer {
            let values = direct3DLibraries.map { "\"\($0)\"=\"native,builtin\"" }.joined(separator: "\n")
            importRegistry("[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\n\(values)", wine: wine)
        }
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

    /// Points one game's executables at DXMT or back to the DXVK default, via Wine's per-program
    /// settings (HKCU\Software\Wine\AppDefaults\<name>.exe), which also apply when Steam starts it.
    static func applyGraphics(_ choice: GraphicsLayer, installDir: URL, wine: URL) {
        let layer = choice == .automatic ? defaultGraphics : choice
        let exes = executables(in: installDir)
        guard !exes.isEmpty else { return }
        let sections = exes.map { exe -> String in
            let key = "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(exe)\\DllOverrides"
            guard layer == .dxmt else { return "[-\(key)]" }
            // d3d9 stays with DXVK: DXMT only covers Direct3D 10/11.
            let values = ["dxgi", "d3d11", "d3d10core"].map { "\"\($0)\"=\"builtin\"" }.joined(separator: "\n")
            return "[\(key)]\n\(values)"
        }
        importRegistry(sections.joined(separator: "\n\n"), wine: wine)
    }

    /// Windows programs in a game folder (a few levels deep, where Unity/Unreal put them).
    private static func executables(in dir: URL) -> [String] {
        guard let files = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var names = Set<String>()
        for case let file as URL in files {
            if files.level > 3 { files.skipDescendants(); continue }
            if file.pathExtension.lowercased() == "exe" { names.insert(file.lastPathComponent) }
        }
        return names.sorted()
    }

    /// Imports registry settings into the prefix and waits only for regedit itself (not for the
    /// wineserver, which keeps running as long as Steam does).
    static func importRegistry(_ body: String, wine: URL) {
        let temp = prefix.appendingPathComponent("drive_c/windows/temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appendingPathComponent("nachtschicht-\(UUID().uuidString).reg")
        guard (try? ("REGEDIT4\n\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: file) }

        let regedit = Process()
        regedit.executableURL = wine
        regedit.arguments = ["regedit", "/S", #"C:\windows\temp\"# + file.lastPathComponent]
        regedit.environment = environment(wine: wine)
        regedit.standardOutput = FileHandle.nullDevice
        regedit.standardError = FileHandle.nullDevice
        guard (try? regedit.run()) != nil else { return }
        regedit.waitUntilExit()
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
    /// A Steam started with older game settings is restarted, unless `busy` (a game is running).
    static func ensureSteamRunning(_ wine: URL, busy: Bool = false) async throws {
        let key = "steamConfigSignature"
        let current = UserDefaults.standard.string(forKey: key) == steamConfigSignature
        if isSteamRunning {
            guard !current, !busy else { return }
            try await restartSteamInBackground(wine)
        } else {
            try startSteam(wine, arguments: ["-silent"])
        }
        UserDefaults.standard.set(steamConfigSignature, forKey: key)
    }

    /// DXVK settings also go into dxvk.conf in the game folder, which DXVK reads on its own –
    /// the game is started by the already running Steam, so environment variables may not reach it.
    static func writeGameConfig(installDir: URL, options: GameOptions) {
        let file = installDir.appendingPathComponent("dxvk.conf")
        let marker = "# Written by Nachtschicht"
        let ours = (try? String(contentsOf: file, encoding: .utf8))?.hasPrefix(marker) ?? false
        guard ours || !FileManager.default.fileExists(atPath: file.path) else { return }  // the game ships its own
        var lines = [
            "\(marker) before each start – changes here are overwritten.",
            "dxvk.enableAsync = True",
        ]
        if Prefs.performanceHUD { lines.append("dxvk.hud = fps,frametimes,gpuload") }
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
        var env = environment(wine: wine).merging(gameEnvironment) { _, new in new }
        env["WINEDLLOVERRIDES"] = steamDLLOverrides
        process.environment = env.merging(extraEnvironment) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
