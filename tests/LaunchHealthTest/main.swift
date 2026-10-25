// Checks GameAnalysis, LaunchHealth and GameLog: tests/LaunchHealthTest/run.sh [Steam folder]
import Foundation

@main
struct LaunchHealthTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A minimal 64-bit Windows program whose only content is an import table naming `imports`.
    static func writePE(_ url: URL, imports: [String]) {
        var bytes = [UInt8](repeating: 0, count: 0x400)
        func put16(_ value: Int, _ at: Int) { bytes[at] = UInt8(value & 0xFF); bytes[at + 1] = UInt8(value >> 8 & 0xFF) }
        func put32(_ value: Int, _ at: Int) { put16(value & 0xFFFF, at); put16(value >> 16, at + 2) }
        bytes[0] = 0x4D; bytes[1] = 0x5A                                    // "MZ"
        put32(0x40, 0x3C)                                                   // → PE header
        bytes.replaceSubrange(0x40..<0x44, with: [0x50, 0x45, 0, 0])        // "PE\0\0"
        put16(0x8664, 0x44); put16(1, 0x46); put16(240, 0x54)               // x86-64, 1 section, PE32+ header
        let optional = 0x58
        put16(0x20B, optional)                                              // PE32+
        put32(0x1000, optional + 112 + 8); put32(20 * (imports.count + 1), optional + 112 + 12)  // import directory
        let section = optional + 240
        put32(0x200, section + 8); put32(0x1000, section + 12); put32(0x200, section + 16); put32(0x200, section + 20)
        var name = 0x200 + 20 * (imports.count + 1)
        for (index, dll) in imports.enumerated() {
            put32(0x1000 + name - 0x200, 0x200 + index * 20 + 12)           // descriptor → name
            bytes.replaceSubrange(name..<name + dll.utf8.count, with: Array(dll.utf8))
            name += dll.utf8.count + 1
        }
        FileManager.default.createFile(atPath: url.path, contents: Data(bytes))
    }

    static func ids(_ analysis: GameAnalysis, _ profileJSON: String? = nil) -> [String] {
        let profile = profileJSON.flatMap { try? JSONDecoder().decode(GameProfile.self, from: Data($0.utf8)) }
        return LaunchHealth.attempts(for: analysis, profile: profile).map(\.id)
    }

    static func main() {
        // MARK: Ladders
        check(ids(GameAnalysis(apis: [.d3d11])) == ["dxmt", "dxvk"], "DirectX 11: DXMT, then DXVK")
        check(ids(GameAnalysis(apis: [.d3d11]), #"{"graphics": "dxvk"}"#) == ["dxvk", "dxmt"], "a profile's layer goes first")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unity)) == ["dxmt -force-d3d11", "dxvk -force-d3d11", "dxmt"],
              "Unity with DirectX 12 is held to 11, 12 comes last")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal)).first == "dxmt -dx11", "Unreal is held to DirectX 11")
        check(ids(GameAnalysis(apis: [.d3d11, .d3d12])) == ["dxmt", "dxvk"], "unknown engine: no switch to guess")
        check(ids(GameAnalysis(apis: [.d3d9])) == ["dxvk", "wined3d"], "DirectX 9: DXVK, then WineD3D")
        check(ids(GameAnalysis(apis: [.vulkan])) == ["dxmt"], "Vulkan has one way")
        check(ids(GameAnalysis(apis: [.d3d12])) == ["dxmt"] && GameAnalysis(apis: [.d3d12]).onlyD3D12, "DirectX 12 only")
        check(ids(GameAnalysis()) == ["dxmt", "dxvk"], "nothing detected: the DirectX 11 ladder")

        // MARK: State
        let app = 990_001
        let ladder = LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d11]), profile: nil)
        LaunchHealth.reset(app)
        check(LaunchHealth.current(app, ladder) == (0, false), "starts at the first way")
        LaunchHealth.recordStart(app, ladder)
        check(LaunchHealth.advance(app, ladder), "there is a second way")
        check(LaunchHealth.current(app, ladder) == (1, false), "moved to DXVK")
        check(LaunchHealth.note(app, ladder)?.contains("DXVK") == true, "the note names the new way")
        LaunchHealth.confirm(app, ladder)
        check(LaunchHealth.current(app, ladder) == (1, true), "DXVK confirmed")
        check(!LaunchHealth.advance(app, ladder) && LaunchHealth.current(app, ladder) == (0, false), "after the last way it starts over")
        let longer = LaunchHealth.attempts(for: GameAnalysis(apis: [.d3d11, .d3d12], engine: .unity), profile: nil)
        _ = LaunchHealth.advance(app, ladder)
        check(LaunchHealth.current(app, longer) == (0, false), "a different ladder starts over")
        LaunchHealth.reset(app)
        UserDefaults.standard.set(true, forKey: "health.dxmtFailed.\(app)")
        check(LaunchHealth.current(app, ladder).index == 1, "0.2's \"DXMT failed\" carries over")
        check(UserDefaults.standard.object(forKey: "health.dxmtFailed.\(app)") == nil, "the old key is gone")

        // MARK: Review from Steam's log
        let steam = FileManager.default.temporaryDirectory.appendingPathComponent("lht-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: steam.appendingPathComponent("logs"), withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func session(seconds: TimeInterval, startedAt start: Date) {
            let lines = [
                "[\(formatter.string(from: start.addingTimeInterval(2)))] Game process added : AppID \(app) \"C:\\game.exe\", ProcID 100, IP 0.0.0.0:0",
                "[\(formatter.string(from: start.addingTimeInterval(2 + seconds)))] Game process removed: AppID \(app) \"C:\\game.exe\", ProcID 100",
            ]
            // Steam writes Windows line ends.
            try? (lines.joined(separator: "\r\n") + "\r\n").write(to: steam.appendingPathComponent("logs/console_log.txt"), atomically: true, encoding: .utf8)
        }
        LaunchHealth.reset(app)
        let now = Date().addingTimeInterval(-300)
        LaunchHealth.recordStart(app, ladder, at: now)
        session(seconds: 6, startedAt: now)
        LaunchHealth.review(app, ladder, steamRoot: steam)
        check(LaunchHealth.current(app, ladder) == (1, false), "a 6 s session moves on")
        LaunchHealth.recordStart(app, ladder, at: now)
        session(seconds: 600, startedAt: now)
        LaunchHealth.review(app, ladder, steamRoot: steam)
        check(LaunchHealth.current(app, ladder) == (1, true), "a 10 min session confirms")

        // MARK: Launch watcher on Steam's log
        let console = steam.appendingPathComponent("logs/console_log.txt")
        func write(_ lines: [String]) {
            try? (lines.map { "[2026-10-25 23:11:51] " + $0 }.joined(separator: "\r\n") + "\r\n")
                .write(to: console, atomically: true, encoding: .utf8)
        }
        func append(_ lines: [String]) {
            let handle = try? FileHandle(forWritingTo: console)
            _ = try? handle?.seekToEnd()
            try? handle?.write(contentsOf: Data((lines.map { "[2026-10-25 23:12:00] " + $0 }.joined(separator: "\r\n") + "\r\n").utf8))
            try? handle?.close()
        }
        let action = "GameAction [AppID \(app), ActionID 1] : LaunchApp"
        write(["\(action) waiting for user response to CreatingProcess \"\"", "\(action) continues with user response \"CreatingProcess\"",
               "\(action) changed task to Completed with \"\""])
        var watcher = LaunchWatcher(steamRoot: steam, appID: app)
        check(watcher.poll() == nil, "a finished launch earlier in the log isn't an open question")
        append(["ExecCommandLine: \"\"C:\\Steam\\steam.exe\" -silent -applaunch \(app)\"", "\(action) waiting for user response to ShowEula \"\""])
        check(watcher.poll() == .needsConfirmation, "a new question is seen")
        check(watcher.steamReceivedLaunch, "Steam took the launch request")
        append(["\(action) continues with user response \"ShowEula\"", "Game process added : AppID \(app) \"C:\\game.exe\", ProcID 7, IP 0.0.0.0:0"])
        check(watcher.poll() == .running, "then the game runs")
        write(["\(action) waiting for user response to ShowEula \"\""])
        watcher = LaunchWatcher(steamRoot: steam, appID: app)
        check(watcher.poll() == .needsConfirmation, "a question still open from before is seen")

        try? FileManager.default.removeItem(at: steam)
        LaunchHealth.reset(app)

        // MARK: Log
        let log = """
        0124:err:module:import_dll Library MSVCP120.dll (which is needed by L"C:\\\\Program Files (x86)\\\\Steam\\\\steamapps\\\\common\\\\Some Game\\\\Game.exe") not found
        0124:err:module:import_dll Library d3dx9_43.dll (which is needed by L"C:\\\\Program Files (x86)\\\\Steam\\\\steamapps\\\\common\\\\Some Game\\\\Game.exe") not found
        0130:err:module:import_dll Library steamclient.dll (which is needed by L"C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe") not found
        wine: Call from 00006FFFFFC2E3A4 to unimplemented function msvcp140.dll.?_Xbad_alloc@std@@YAXXZ, aborting
        [mvk-error] VK_ERROR_OUT_OF_DEVICE_MEMORY: vkCreateQueryPool(): Each occlusion query pool can support a maximum of 32768 queries.
        [mvk-error] VK_ERROR_OUT_OF_DEVICE_MEMORY: vkCreateQueryPool(): Each occlusion query pool can support a maximum of 32768 queries.
        err:   DXGI: Failed to create swap chain
        info:  Game: Game.exe
        """
        check(GameLog.missingRuntimes(in: log, gameFolder: "Some Game") == ["vcrun2013", "d3dx9", "vcrun2022"],
              "runtimes: \(GameLog.missingRuntimes(in: log, gameFolder: "Some Game"))")
        let errors = GameLog.errors(in: log)
        check(errors.count == 6, "errors without repeats: \(errors.count)")
        check(errors.first?.hasPrefix("err:module") == true, "thread ids dropped: \(errors.first ?? "")")
        check(errors.contains("err:   DXGI: Failed to create swap chain"), "DXVK's own error lines kept")

        // MARK: Analysis of a made-up game folder
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lht-game-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: folder.appendingPathComponent("EasyAntiCheat"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: folder.appendingPathComponent("__Installer"), withIntermediateDirectories: true)
        writePE(folder.appendingPathComponent("Game.exe"), imports: ["KERNEL32.dll", "mscoree.dll"])
        writePE(folder.appendingPathComponent("__Installer/Touchup.exe"), imports: ["d3d12.dll"])
        for name in ["uplay_r1_loader64.dll", "WebView2Loader.dll"] { fm.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data()) }
        check(PEImports.dlls(of: folder.appendingPathComponent("Game.exe")) == ["kernel32.dll", "mscoree.dll"], "the PE reader reads imports")
        var analysis = GameAnalysis.analyze(installDir: folder, launchExecutable: "Game.exe")
        check(analysis.usesDotNet, ".NET recognised")
        check(analysis.launcher == "Ubisoft Connect", "Ubisoft Connect recognised: \(analysis.launcher ?? "none")")
        check(analysis.usesWebView2, "WebView2 recognised")
        check(analysis.antiCheat == ["Easy Anti-Cheat"], "anti-cheat recognised")
        check(!analysis.apis.contains(.d3d12), "programs in __Installer don't count")
        try? fm.removeItem(at: folder.appendingPathComponent("uplay_r1_loader64.dll"))
        fm.createFile(atPath: folder.appendingPathComponent("__Installer/installerdata.xml").path, contents: Data())
        writePE(folder.appendingPathComponent("Game.exe"), imports: ["d3d9.dll"])
        analysis = GameAnalysis.analyze(installDir: folder, launchExecutable: "Game.exe")
        check(analysis.launcher == "EA app" && analysis.usesD3D9 && !analysis.usesDotNet, "EA app and DirectX 9: \(analysis)")
        try? fm.removeItem(at: folder)
        check(GameLog.missingRuntimes(in: "0040:err:mscoree:CLRRuntimeInfo_GetRuntimeHost Wine Mono is not installed", gameFolder: "x")
              == [GameLog.wineMono], "missing Mono recognised")

        // MARK: Installed games
        if CommandLine.arguments.count > 1 {
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let common = root.appendingPathComponent("steamapps/common")
            for folder in (try? FileManager.default.contentsOfDirectory(at: common, includingPropertiesForKeys: nil)) ?? [] {
                let analysis = GameAnalysis.analyze(installDir: folder, launchExecutable: nil)
                guard !analysis.apis.isEmpty || analysis.engine != .other else { continue }
                print("  \(folder.lastPathComponent): \(analysis.summary) → " +
                      LaunchHealth.attempts(for: analysis, profile: nil).map(\.label).joined(separator: " → "))
            }
        }

        print(failures == 0 ? "✓ all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
