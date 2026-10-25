import Foundation

/// Nightforge's own free Wine setup: the engine component, one Windows environment ("prefix")
/// and the Windows Steam client inside it. Used when CrossOver isn't the chosen runner.
enum Engine {
    static let engineID = "wine"
    /// Nightforge's own DXMT build for Wine 11 (with winemac.so); plain upstream DXMT as fallback.
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
        "\(steamConfigVersion)-hud\(Prefs.performanceHUD ? 1 : 0)-gamemode\(Prefs.gameMode ? 1 : 0)"
    }

    /// Wine's builtin crypto avoids TLS failures in Steam's browser; the overlay DLL deadlocks games.
    /// Games inherit these from Steam, so DirectX goes to DXVK's DLLs in the prefix (native first).
    /// The Direct3D choice itself lives in the registry (see `installDXVK` / `applyGameSettings`): an
    /// override in this variable would beat the per-game AppDefaults.
    static let steamDLLOverrides = "bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge", isDirectory: true)
    }

    /// The Windows environment Steam and the games live in.
    static var prefix: URL { supportDir.appendingPathComponent("Prefix", isDirectory: true) }

    static var bottle: Bottle { Bottle(name: "Nightforge", url: prefix, isBuiltIn: true) }

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
    /// Only Nightforge's own Steam counts – not one from a CrossOver bottle, and not a Steam left
    /// behind without its wineserver (it can't do anything any more and would block a fresh start).
    static var isSteamRunning: Bool {
        let ours = ownProcesses()
        return ours.contains { $0.command.lowercased().contains(#"\steam\steam.exe"#) }
            && ours.contains { $0.command.hasSuffix("/wineserver") || $0.command.contains("/wineserver ") }
    }

    /// Processes started from Nightforge's engine (executable inside its folder), with the command
    /// line ps shows – Wine rewrites that to the Windows program.
    static func ownProcesses(under folder: URL = supportDir) -> [(pid: pid_t, command: String)] {
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,command="]
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        let root = folder.resolvingSymlinksInPath().path
        return output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = pid_t(parts[0]), executablePath(pid)?.hasPrefix(root) == true else { return nil }
            return (pid, String(parts[1]))
        }
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Ends every Windows process in Nightforge's prefix.
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
        // Wine processes working somewhere else (Steam's own folder resolved differently, …)
        // still run Nightforge's engine.
        for process in ownProcesses() where process.pid != getpid() { kill(process.pid, SIGKILL) }
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
        installGameBundle(wine: wine)  // after the graphics: its links must point at the new files
        detachUserFolders()
        trimSteamLogs()
        excludeGamesFromBackup()
        applyGameEnvironment(wine: wine)
        if let dxvk = manifest.component(dxvkID) {
            try installDXVK(try await store.install(dxvk), wine: wine)
        }
        return wine
    }

    /// The engine's wine binary without async work (for app shutdown): the newest installed copy.
    static func installedWineNow() -> URL? {
        let dir = ComponentStore.shared.root.appendingPathComponent(engineID, isDirectory: true)
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return versions
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .lazy.compactMap(wineBinary(in:)).first
    }

    /// When Nightforge quits, Steam should go too – but not while a game runs (it uploads cloud
    /// saves after the game ends) or a download is going. Nightforge itself quits right after a
    /// launch, so a small detached script waits for that and then stops Steam and the Wine session.
    /// It gives up if Nightforge is opened again in the meantime.
    static func scheduleSteamShutdown() {
        guard isSteamInstalled, let wine = installedWineNow() else { return }
        let script = supportDir.appendingPathComponent("steam-shutdown.sh")
        let text = #"""
        #!/bin/bash
        # Written by Nightforge on quit: ends the background Steam once nothing needs it.
        WINE="$1"; PREFIX="$2"
        STEAMAPPS="$PREFIX/drive_c/Program Files (x86)/Steam/steamapps"
        # The process list is read before searching it, so the search never finds itself; -F
        # because the Windows paths are full of backslashes, which grep would read as escapes.
        has_process() { local list; list="$(ps -axo command)"; printf '%s\n' "$list" | grep -qiF -- "$1"; }
        reopened() { pgrep -qf "Nightforge.app/Contents/MacOS/Nightforge"; }
        steam_running() { has_process '\steam\steam.exe'; }
        busy() {
          has_process '\steamapps\common\' && return 0   # a game
          find "$STEAMAPPS/downloading" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q . && return 0
          return 1
        }
        while true; do
          while busy; do reopened && exit 0; sleep 10; done
          sleep 30                       # cloud saves of a game that just ended
          reopened && exit 0
          busy || break
        done
        export WINEPREFIX="$PREFIX" WINEDEBUG=-all
        if steam_running; then
          "$WINE" 'C:\Program Files (x86)\Steam\steam.exe' -shutdown >/dev/null 2>&1
          for i in $(seq 1 20); do steam_running || break; sleep 1; done
        fi
        "$(dirname "$WINE")/wineserver" -k
        sleep 2
        # Wine helpers that outlive the server, recognisable by their working directory in the prefix.
        lsof -a -d cwd -Fpn 2>/dev/null           | awk -v root="$PREFIX" '/^p/ { pid = substr($0, 2) } /^n/ { if (index(substr($0, 2), root) == 1) print pid }'           | while read -r pid; do kill -9 "$pid" 2>/dev/null; done
        """#
        guard (try? text.write(to: script, atomically: true, encoding: .utf8)) != nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, wine.path, prefix.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()  // keeps running after Nightforge has quit
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
    /// Nightforge's package also carries winemac.so built for one Wine version; it's only used
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
    /// default for every program; games set to DXMT override that in `applyGameSettings`. Safe to repeat.
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

    /// winetricks verbs that would change every game in the shared prefix, not just the one that
    /// asks (Proton gives each game its own prefix; Nightforge has one for all).
    private static let sharedPrefixUnsafeVerbs: Set<String> = ["dsound"]

    /// The profile's winetricks verbs that aren't in the prefix yet (winetricks logs what it installed).
    static func missingWinetricks(_ verbs: [String]) -> [String] {
        let log = (try? String(contentsOf: prefix.appendingPathComponent("winetricks.log"), encoding: .utf8)) ?? ""
        let installed = Set(log.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        return verbs.filter { !installed.contains($0) && !sharedPrefixUnsafeVerbs.contains($0) }
    }

    /// Installs winetricks verbs into the prefix (runtimes like vcrun2019, d3dcompiler_47). Needs the
    /// winetricks and cabextract components; returns false when something was missing or failed –
    /// the game is started anyway. Output goes to Logs/winetricks.log for troubleshooting.
    @discardableResult
    static func installWinetricks(_ verbs: [String], wine: URL) async -> Bool {
        guard !verbs.isEmpty else { return true }
        let store = ComponentStore.shared
        guard let manifest = try? await store.manifest(),
              let winetricksComponent = manifest.component("winetricks"),
              let cabextractComponent = manifest.component("cabextract"),
              let winetricksDir = try? await store.install(winetricksComponent),
              let cabextractDir = try? await store.install(cabextractComponent)
        else { return false }
        let fm = FileManager.default
        let script = winetricksDir.appendingPathComponent("winetricks")
        let cabextract = (fm.enumerator(at: cabextractDir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == "cabextract" })?.deletingLastPathComponent()
        guard fm.isExecutableFile(atPath: script.path), let cabextract else { return false }

        let logs = supportDir.appendingPathComponent("Logs", isDirectory: true)
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let logFile = logs.appendingPathComponent("winetricks.log")
        if !fm.fileExists(atPath: logFile.path) { fm.createFile(atPath: logFile.path, contents: nil) }
        let log = try? FileHandle(forWritingTo: logFile)
        _ = try? log?.seekToEnd()
        log?.write(Data("\n== \(Date()) winetricks \(verbs.joined(separator: " "))\n".utf8))

        var env = environment(wine: wine)
        env["WINEDLLOVERRIDES"] = nil  // installers like dotnet need mscoree, which setup turns off
        env["WINE"] = wine.path
        env["WINESERVER"] = wine.deletingLastPathComponent().appendingPathComponent("wineserver").path
        env["PATH"] = cabextract.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["WINETRICKS_LATEST_VERSION_CHECK"] = "disabled"
        // Its download cache (XDG_CACHE_HOME/winetricks) belongs in the Mac's cache folder, not ~/.cache.
        env["XDG_CACHE_HOME"] = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge", isDirectory: true).path

        let process = Process()
        process.executableURL = script
        process.arguments = ["--unattended"] + verbs
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log ?? FileHandle.nullDevice
        process.standardError = log ?? FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                try? log?.close()
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            if (try? process.run()) == nil {
                try? log?.close()
                continuation.resume(returning: false)
            }
        }
    }

    /// Per-program settings for a game's executables (Wine's AppDefaults): the Direct3D layer, the
    /// profile's DLL overrides and Windows version. Rewritten in full at every launch, so a changed
    /// choice or profile never leaves stale entries. The profile's registry entries go in as well.
    static func applyGameSettings(_ choice: GraphicsLayer, profile: GameProfile?, installDir: URL, wine: URL) {
        let layer = choice == .automatic ? (profile?.graphics ?? defaultGraphics) : choice
        let exes = executables(in: installDir)
        var sections: [String] = []
        for exe in exes {
            let app = "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(exe)"
            var overrides = profile?.dllOverrides ?? [:]
            if layer == .dxmt {
                // d3d9 stays with DXVK: DXMT only covers Direct3D 10/11.
                for dll in ["dxgi", "d3d11", "d3d10core"] { overrides[dll] = "builtin" }
            }
            var section = "[-\(app)\\DllOverrides]"
            if !overrides.isEmpty {
                section += "\n[\(app)\\DllOverrides]\n" + overrides.sorted { $0.key < $1.key }
                    .map { "\(regString($0.key))=\(regString($0.value))" }.joined(separator: "\n")
            }
            section += "\n[\(app)]\n\"Version\"=" + (profile?.windowsVersion.map(regString) ?? "-")
            sections.append(section)
        }
        sections += (profile?.registry ?? []).compactMap(regSection)
        guard !sections.isEmpty else { return }
        importRegistry(sections.joined(separator: "\n\n"), wine: wine)
    }

    /// A quoted .reg string.
    private static func regString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// One registry entry from a profile as a .reg section; nil for types it can't express safely.
    private static func regSection(_ entry: GameProfile.RegistryEntry) -> String? {
        let roots = ["HKLM": "HKEY_LOCAL_MACHINE", "HKCU": "HKEY_CURRENT_USER", "HKCR": "HKEY_CLASSES_ROOT"]
        var key = entry.key
        for (short, long) in roots where key.uppercased().hasPrefix(short + "\\") {
            key = long + key.dropFirst(short.count)
        }
        guard key.hasPrefix("HKEY_") else { return nil }
        let header = "[\(key)]"
        guard let name = entry.name, let type = entry.type?.uppercased(), let value = entry.value else { return header }
        let data: String
        switch type {
        case "REG_SZ": data = regString(value)
        case "REG_DWORD":
            guard let number = value.hasPrefix("0x") ? UInt32(value.dropFirst(2), radix: 16) : UInt32(value) else { return nil }
            data = String(format: "dword:%08x", number)
        default: return nil
        }
        return header + "\n" + regString(name) + "=" + data
    }

    /// Windows programs in a game folder (a few levels deep, where Unity/Unreal put them).
    private static func executables(in dir: URL) -> [String] {
        Set(executableFiles(in: dir).map(\.lastPathComponent)).sorted()
    }

    private static func executableFiles(in dir: URL) -> [URL] {
        guard let files = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [URL] = []
        for case let file as URL in files {
            if files.level > 3 { files.skipDescendants(); continue }
            if file.pathExtension.lowercased() == "exe" { found.append(file) }
        }
        return found
    }

    /// Imports registry settings into the prefix and waits only for regedit itself (not for the
    /// wineserver, which keeps running as long as Steam does).
    static func importRegistry(_ body: String, wine: URL) {
        let temp = prefix.appendingPathComponent("drive_c/windows/temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appendingPathComponent("nightforge-\(UUID().uuidString).reg")
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

    /// macOS only turns Game Mode on (CPU and GPU priority, lower Bluetooth latency) for apps whose
    /// bundle says they're games. Wine's loader is a bare binary, so this builds a small "Nightforge
    /// Game.app" next to it: the loader's folder hard-linked into Contents/MacOS, everything else it
    /// finds relative to itself linked back to the engine. Wine starts every Windows program with
    /// the loader it was started with, so Steam run from here hands it to its games.
    /// Rebuilt when a file was replaced since (graphics), which breaks its hard link.
    @discardableResult
    static func installGameBundle(wine: URL) -> URL? {
        let fm = FileManager.default
        let root = wine.deletingLastPathComponent().deletingLastPathComponent()  // …/Resources/wine
        let unix = root.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let bundle = root.appendingPathComponent(gameBundleName, isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)

        func inode(_ path: String) -> Int? { (try? fm.attributesOfItem(atPath: path))?[.systemFileNumber] as? Int }
        let files = (try? fm.contentsOfDirectory(atPath: unix.path)) ?? []
        let vulkanDriver = resources.appendingPathComponent("vulkan/icd.d/MoltenVK_icd.json")
        let current = fm.fileExists(atPath: vulkanDriver.path)
            && files.allSatisfy { name in
                let original = unix.appendingPathComponent(name).path
                var isDirectory: ObjCBool = false
                fm.fileExists(atPath: original, isDirectory: &isDirectory)
                return isDirectory.boolValue || inode(original) == inode(macOS.appendingPathComponent(name).path)
            }
        // Steam may be running from it; leave a bundle that's still right alone.
        if current { return macOS.appendingPathComponent("wine") }

        // The bundle's name under Nightforge's old name; Launch Services should forget it too.
        let legacy = root.appendingPathComponent("Nachtschicht Game.app", isDirectory: true)
        if fm.fileExists(atPath: legacy.path) {
            let unregister = Process()
            unregister.executableURL = lsregister
            unregister.arguments = ["-u", legacy.path]
            if (try? unregister.run()) != nil { unregister.waitUntilExit() }
            try? fm.removeItem(at: legacy)
        }

        do {
            try? fm.removeItem(at: bundle)
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            for file in try fm.contentsOfDirectory(at: unix, includingPropertiesForKeys: [.isDirectoryKey]) {
                let name = file.lastPathComponent
                let target = macOS.appendingPathComponent(name)
                if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try fm.createSymbolicLink(atPath: target.path, withDestinationPath: "../../../lib/wine/x86_64-unix/\(name)")
                } else {
                    try fm.linkItem(at: file, to: target)
                }
            }
            // Wine looks for its other folders next to the loader's.
            try fm.createSymbolicLink(atPath: macOS.appendingPathComponent("x86_64-unix").path, withDestinationPath: ".")
            for arch in ["x86_64-windows", "i386-windows"] {
                try fm.createSymbolicLink(atPath: macOS.appendingPathComponent(arch).path, withDestinationPath: "../../../lib/wine/\(arch)")
            }
            // Libraries are found at @loader_path/../../, i.e. the bundle folder itself.
            for name in ["bin", "share"] {
                try fm.createSymbolicLink(atPath: bundle.appendingPathComponent(name).path, withDestinationPath: "../\(name)")
            }
            for lib in try fm.contentsOfDirectory(atPath: root.appendingPathComponent("lib").path) where lib != "wine" {
                try fm.createSymbolicLink(atPath: bundle.appendingPathComponent(lib).path, withDestinationPath: "../lib/\(lib)")
            }
            // Inside an app bundle the Vulkan loader looks for drivers in Contents/Resources only.
            // Without MoltenVK there, Steam's browser loops on failing to draw and never takes
            // a game launch.
            try fm.createDirectory(at: vulkanDriver.deletingLastPathComponent(), withIntermediateDirectories: true)
            let driver: [String: Any] = [
                "file_format_version": "1.0.0",
                "ICD": [
                    "library_path": root.appendingPathComponent("lib/libMoltenVK.dylib").path,
                    "api_version": "1.4.0",
                    "is_portability_driver": true,
                ],
            ]
            try JSONSerialization.data(withJSONObject: driver, options: .prettyPrinted).write(to: vulkanDriver)
            if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                try fm.copyItem(at: icon, to: resources.appendingPathComponent("AppIcon.icns"))
            }
            let info: [String: Any] = [
                "CFBundleExecutable": "wine",
                "CFBundleIdentifier": "io.github.lordhayne.nightforge.game",
                "CFBundleName": "Nightforge Game",
                "CFBundleIconFile": "AppIcon",
                "CFBundlePackageType": "APPL",
                "LSApplicationCategoryType": "public.app-category.games",
                "LSSupportsGameMode": true,
                "NSHighResolutionCapable": true,
            ]
            let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        } catch {
            try? fm.removeItem(at: bundle)
            return nil
        }
        // Let Launch Services read the game category now rather than whenever it gets round to it.
        let register = Process()
        register.executableURL = lsregister
        register.arguments = ["-f", bundle.path]
        if (try? register.run()) != nil { register.waitUntilExit() }
        return macOS.appendingPathComponent("wine")
    }

    private static let gameBundleName = "Nightforge Game.app"
    private static let lsregister = URL(fileURLWithPath:
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")

    /// Wine links the Windows user folders (Documents, Desktop, Downloads …) to the Mac's own. Run
    /// from the game bundle, that's a new app to macOS, and the first access waits on a privacy
    /// prompt – the whole Wine session hangs. Games also have no business in those folders, so they
    /// get ordinary folders inside the prefix. Nothing in the Mac's folders is read here: even a
    /// look would make macOS ask the user for access to Documents on every new Mac.
    static func detachUserFolders() {
        let fm = FileManager.default
        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        for user in (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            for name in ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos", "Templates"] {
                let folder = user.appendingPathComponent(name)
                guard (try? fm.destinationOfSymbolicLink(atPath: folder.path)) != nil else { continue }
                try? fm.removeItem(at: folder)
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        }
    }

    /// Steam never limits its logs; under Wine its browser log alone can reach gigabytes.
    static func trimSteamLogs() {
        let logs = steamRoot.appendingPathComponent("logs", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files where ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 50_000_000 {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The program to start Steam with: the Game Mode loader when that's on and built, else `wine`.
    static func loader(for wine: URL) -> URL {
        guard Prefs.gameMode else { return wine }
        let loader = wine.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(gameBundleName).appendingPathComponent("Contents/MacOS/wine")
        return FileManager.default.isExecutableFile(atPath: loader.path) ? loader : wine
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
        if !isSteamRunning, ownProcesses().contains(where: { $0.command.lowercased().contains("steam") }) {
            stopAll(wine)  // a Steam whose wineserver is gone: clear it away before starting afresh
        }
        if isSteamRunning {
            guard !current, !busy else { return }
            try await restartSteamInBackground(wine)
        } else {
            try startSteam(wine, arguments: ["-silent"])
        }
        UserDefaults.standard.set(steamConfigSignature, forKey: key)
    }

    /// Settings for the graphics layers go into dxvk.conf and dxmt.conf, which DXVK and DXMT read
    /// from the game's working folder – the game is started by the already running Steam, so
    /// environment variables don't reach it. Written next to every program of the game, since some
    /// start from a subfolder; a config the game ships itself is left alone.
    static func writeGameConfigs(installDir: URL, frameLimit: Int, upscaling: Bool) {
        var dxvk = ["dxvk.enableAsync = True"]
        if Prefs.performanceHUD { dxvk.append("dxvk.hud = fps,frametimes,gpuload") }
        var dxmt: [String] = []
        if frameLimit > 0 {
            dxvk.append("dxgi.maxFrameRate = \(frameLimit)")
            dxmt.append("d3d11.preferredMaxFrameRate = \(frameLimit)")  // paced by Metal
        }
        if upscaling {
            dxmt.append("d3d11.metalSpatialUpscale = True")  // engine/patches/dxmt-0.80-metalfx-config.patch
            dxmt.append("d3d11.metalSpatialUpscaleFactor = 2.0")
        }
        var folders = Set([installDir.standardizedFileURL])
        for exe in executableFiles(in: installDir) { folders.insert(exe.deletingLastPathComponent().standardizedFileURL) }
        for folder in folders {
            writeConfig(folder.appendingPathComponent("dxvk.conf"), lines: dxvk)
            writeConfig(folder.appendingPathComponent("dxmt.conf"), lines: dxmt)
        }
    }

    private static func writeConfig(_ file: URL, lines: [String]) {
        let marker = "# Written by Nightforge"
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let ours = existing.hasPrefix(marker) || existing.hasPrefix("# Written by Nachtschicht")  // the old name
        guard ours || !FileManager.default.fileExists(atPath: file.path) else { return }  // the game ships its own
        let text = (["\(marker) before each start – changes here are overwritten."] + lines).joined(separator: "\n")
        try? (text + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Game files can be downloaded again any time; backing up tens of gigabytes of them would
    /// only make Time Machine busy (and the disk with it) while you play. Saves live elsewhere.
    static func excludeGamesFromBackup() {
        let steamapps = steamRoot.appendingPathComponent("steamapps", isDirectory: true)
        for name in ["common", "downloading", "shadercache", "temp"] {
            var folder = steamapps.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: folder.path),
                  (try? folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) != true
            else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
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

    /// Opens Steam's main window. Questions Steam asks before a launch (licence agreement, which
    /// version to start) appear in it, and with -silent it stays hidden. Returns the processes
    /// that draw Steam's windows, so the caller can bring them to the front.
    @discardableResult
    static func showSteamWindow(_ wine: URL) -> [pid_t] {
        try? startSteam(wine)
        return ownProcesses().filter { $0.command.lowercased().contains("steamwebhelper") }.map(\.pid)
    }

    /// Starts Steam without waiting; used for signing in and for launching games.
    static func startSteam(_ wine: URL, arguments: [String] = [], extraEnvironment: [String: String] = [:]) throws {
        installWebHelperWrapper()
        let process = Process()
        let loader = loader(for: wine)
        process.executableURL = loader
        process.arguments = [steamExeWindowsPath] + steamArguments + arguments
        var env = environment(wine: wine).merging(gameEnvironment) { _, new in new }
        env["WINEDLLOVERRIDES"] = steamDLLOverrides
        if loader != wine { env["WINELOADER"] = loader.path }
        process.environment = env.merging(extraEnvironment) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
