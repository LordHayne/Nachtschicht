// Checks the Direct3D layouts of both engines: tests/EngineLayoutTest/run.sh [D3DMetal payload folder]
import Foundation

@main
struct EngineLayoutTest {
    static var failures = 0
    static let fm = FileManager.default

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A DLL-sized file, builtin-marked like Wine's own when `builtin`.
    static func dll(_ tag: String, builtin: Bool = false) -> Data {
        var bytes = Data(count: 0x100)
        bytes[0] = 0x4D; bytes[1] = 0x5A
        if builtin { bytes.replaceSubrange(0x40..<0x50, with: Data("Wine builtin DLL".utf8)) }
        bytes.append(Data(tag.utf8))
        return bytes
    }

    /// A minimal Windows program header: PE32+ (64-bit) or PE32.
    static func writeExe(_ url: URL, bits64: Bool) {
        var bytes = [UInt8](repeating: 0, count: 0x200)
        bytes[0] = 0x4D; bytes[1] = 0x5A; bytes[0x3C] = 0x40
        bytes.replaceSubrange(0x40..<0x44, with: [0x50, 0x45, 0, 0])
        bytes[0x40 + 24] = 0x0B; bytes[0x40 + 25] = bits64 ? 0x02 : 0x01  // 0x20B PE32+, 0x10B PE32
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data(bytes))
    }

    static func write(_ data: Data, _ url: URL) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static func main() {
        let work = fm.temporaryDirectory.appendingPathComponent("elt-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }

        // MARK: Which copy of each DLL a layer takes
        check(Engine.layerOverrides(.dxmt, d3dMetalEngine: false) == ["dxgi": "builtin", "d3d11": "builtin", "d3d10core": "builtin"],
              "Gcenx: DXMT is the builtin")
        check(Engine.layerOverrides(.dxvk, d3dMetalEngine: false).isEmpty, "Gcenx: DXVK is the default native")
        check(Engine.layerOverrides(.dxmt, d3dMetalEngine: true) == ["dxgi": "native", "d3d11": "native", "d3d10core": "native",
                                                                    "d3d12": "native", "d3d12core": "native"],
              "winecx: DXMT is the native in system32, and D3DMetal's d3d12 stays away from it")
        check(Engine.layerOverrides(.dxvk, d3dMetalEngine: true)["d3d11"] == "native", "winecx: DXVK is native (next to the game)")
        let metal = Engine.layerOverrides(.d3dmetal, d3dMetalEngine: true)
        check(["dxgi", "d3d11", "d3d12", "d3d12core"].allSatisfy { metal[$0] == "builtin" }, "D3DMetal takes the builtins")
        check(Engine.layerOverrides(.wined3d, d3dMetalEngine: true) == ["d3d9": "builtin"], "WineD3D unchanged")
        check(Engine.defaultLoadOrder("dxgi", d3dMetalEngine: true) == "builtin"
              && Engine.defaultLoadOrder("d3d9", d3dMetalEngine: true) == "native,builtin",
              "winecx: programs without a choice (Steam's browser) don't get DXMT")
        check(Engine.defaultLoadOrder("dxgi", d3dMetalEngine: false) == "native,builtin", "Gcenx: DXVK stays the default")
        check(GraphicsLayer.d3dmetal.upscales, "D3DMetal upscales with MetalFX (a game's DLSS)")

        // MARK: Builtin marker
        let marked = work.appendingPathComponent("marked.dll")
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        try? Engine.writeAsNative(dll("dxmt", builtin: true), to: marked)
        let written = (try? Data(contentsOf: marked)) ?? Data()
        check(written.count == dll("dxmt", builtin: true).count && written.subdata(in: 0x40..<0x50) == Data(count: 16),
              "the builtin marker is cleared")
        check(written.suffix(4) == Data("dxmt".utf8), "the rest of the DLL is kept")
        let plain = work.appendingPathComponent("plain.dll")
        try? Engine.writeAsNative(dll("dxvk"), to: plain)
        check((try? Data(contentsOf: plain)) == dll("dxvk"), "a native DLL is copied as it is")

        // MARK: DXMT natives in the prefix
        let graphics = work.appendingPathComponent("graphics/v0.80", isDirectory: true)
        for name in ["dxgi", "d3d11", "d3d10core", "winemetal", "nvapi64"] {
            write(dll("64-\(name)", builtin: true), graphics.appendingPathComponent("x86_64-windows/\(name).dll"))
        }
        for name in ["dxgi", "d3d11", "winemetal"] {
            write(dll("32-\(name)", builtin: true), graphics.appendingPathComponent("i386-windows/\(name).dll"))
        }
        let windows = work.appendingPathComponent("prefix/drive_c/windows", isDirectory: true)
        for folder in ["system32", "syswow64"] {
            try? fm.createDirectory(at: windows.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try? Engine.installDXMTNatives(work.appendingPathComponent("graphics"), windows: windows)
        let d3d11 = (try? Data(contentsOf: windows.appendingPathComponent("system32/d3d11.dll"))) ?? Data()
        check(d3d11.suffix(8) == Data("64-d3d11".utf8),
              "64-bit DXMT goes to system32")
        check(d3d11.count > 0x50 && d3d11.subdata(in: 0x40..<0x50) == Data(count: 16), "…as a native")
        check(fm.fileExists(atPath: windows.appendingPathComponent("syswow64/dxgi.dll").path), "32-bit DXMT goes to syswow64")
        check(!fm.fileExists(atPath: windows.appendingPathComponent("system32/winemetal.dll").path),
              "winemetal stays a builtin in the engine")

        let engineLib = work.appendingPathComponent("wcx/Libraries/Wine/lib/wine/x86_64-windows", isDirectory: true)
        write(dll("wine's d3d12", builtin: true), engineLib.appendingPathComponent("d3d12.dll.wine"))
        try? Engine.installWineD3D12Natives(wine: work.appendingPathComponent("wcx/Libraries/Wine/bin/wine"), windows: windows)
        let wineD3D12 = (try? Data(contentsOf: windows.appendingPathComponent("system32/d3d12.dll"))) ?? Data()
        check(wineD3D12.suffix(12) == Data("wine's d3d12".utf8) && wineD3D12.subdata(in: 0x40..<0x50) == Data(count: 16),
              "Wine's own d3d12 waits in system32 as a native for games on DXMT and DXVK")

        // MARK: DXVK next to the game
        let dxvk = work.appendingPathComponent("dxvk/dxvk-1.10.3", isDirectory: true)
        for arch in ["x64", "x32"] {
            for name in Engine.dxvkGameLibraries + ["d3d9.dll"] { write(dll("\(arch)-\(name)"), dxvk.appendingPathComponent("\(arch)/\(name)")) }
        }
        let game = work.appendingPathComponent("common/Game", isDirectory: true)
        writeExe(game.appendingPathComponent("Game.exe"), bits64: true)
        writeExe(game.appendingPathComponent("Old/Launcher.exe"), bits64: false)
        write(dll("the game's own"), game.appendingPathComponent("Old/dxgi.dll"))
        check(Engine.isPE32Plus(game.appendingPathComponent("Game.exe")) == true, "a 64-bit program is recognised")
        check(Engine.isPE32Plus(game.appendingPathComponent("Old/Launcher.exe")) == false, "a 32-bit program is recognised")
        Engine.placeDXVK(true, dxvkDir: work.appendingPathComponent("dxvk"), installDir: game)
        check((try? Data(contentsOf: game.appendingPathComponent("d3d11.dll"))) == dll("x64-d3d11.dll"), "64-bit DXVK next to the 64-bit program")
        check((try? Data(contentsOf: game.appendingPathComponent("Old/d3d11.dll"))) == dll("x32-d3d11.dll"), "32-bit DXVK next to the 32-bit one")
        check((try? Data(contentsOf: game.appendingPathComponent("Old/dxgi.dll"))) == dll("the game's own"), "a DLL the game ships stays")
        check(!fm.fileExists(atPath: game.appendingPathComponent("d3d9.dll").path), "d3d9 stays in system32")
        Engine.placeDXVK(false, dxvkDir: work.appendingPathComponent("dxvk"), installDir: game)
        check(!fm.fileExists(atPath: game.appendingPathComponent("d3d11.dll").path)
              && !fm.fileExists(atPath: game.appendingPathComponent("Old/d3d11.dll").path), "another layer takes DXVK away again")
        check((try? Data(contentsOf: game.appendingPathComponent("Old/dxgi.dll"))) == dll("the game's own"), "…but not the game's own DLL")

        writeExe(game.appendingPathComponent("b1/Binaries/Win64/b1-Win64-Shipping.exe"), bits64: true)
        check(Engine.executables(in: game).contains("b1-Win64-Shipping.exe"), "Unreal's program four levels down is found")
        try? fm.removeItem(at: game.appendingPathComponent("b1"))

        // MARK: Engine trees
        let winecx = work.appendingPathComponent("winecx/4.7.3", isDirectory: true)
        let wine = winecx.appendingPathComponent("Libraries/Wine/bin/wine")
        write(Data("#!/bin/sh\n".utf8), wine)
        _ = try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        check(Engine.wineBinary(in: winecx) == wine, "winecx's Libraries/Wine tree is found")
        check(!Engine.isGPTKCapable(wine: wine), "no version file: not D3DMetal-capable")
        let plist = try? PropertyListSerialization.data(fromPropertyList: ["gptkCapable": true], format: .xml, options: 0)
        write(plist ?? Data(), winecx.appendingPathComponent("Libraries/WhiskyWineVersion.plist"))
        check(Engine.isGPTKCapable(wine: wine), "gptkCapable in the version file")
        check(!Engine.isD3DMetalDeployed(wine: wine), "no D3DMetal before installing it")

        // MARK: D3DMetal
        let fake = work.appendingPathComponent("fake-gptk/lib", isDirectory: true)
        write(Data("not apple".utf8), fake.appendingPathComponent("external/libd3dshared.dylib"))
        try? fm.createDirectory(at: fake.appendingPathComponent("external/D3DMetal.framework"), withIntermediateDirectories: true)
        write(dll("apple d3d12", builtin: true), fake.appendingPathComponent("wine/x86_64-windows/d3d12.dll"))
        check(Engine.d3dMetalPayloadRoot(in: work.appendingPathComponent("fake-gptk")) == fake.standardizedFileURL
              || Engine.d3dMetalPayloadRoot(in: work.appendingPathComponent("fake-gptk"))?.resolvingSymlinksInPath() == fake.resolvingSymlinksInPath(),
              "the payload is found inside its download")
        check((try? Engine.installD3DMetal(work.appendingPathComponent("fake-gptk"), into: wine)) == nil,
              "a payload Apple didn't sign is refused")
        check(!Engine.isD3DMetalDeployed(wine: wine), "…and nothing of it installed")
        if let real = CommandLine.arguments.dropFirst().first {
            let lib = winecx.appendingPathComponent("Libraries/Wine/lib/wine", isDirectory: true)
            write(dll("wine's d3d12", builtin: true), lib.appendingPathComponent("x86_64-windows/d3d12.dll"))
            try? fm.createDirectory(at: lib.appendingPathComponent("x86_64-unix"), withIntermediateDirectories: true)
            do {
                try Engine.installD3DMetal(URL(fileURLWithPath: real), into: wine)
                check(Engine.isD3DMetalDeployed(wine: wine), "Apple's D3DMetal is installed")
                if fm.fileExists(atPath: lib.appendingPathComponent("x86_64-windows/nvngx-on-metalfx.dll").path) {
                    check(fm.contentsEqual(atPath: lib.appendingPathComponent("x86_64-windows/nvngx.dll").path,
                                           andPath: lib.appendingPathComponent("x86_64-windows/nvngx-on-metalfx.dll").path)
                          && (try? fm.destinationOfSymbolicLink(atPath: lib.appendingPathComponent("x86_64-unix/nvngx.so").path)) != nil,
                          "DLSS → MetalFX under NVIDIA's name, as Apple's readme says")
                }
                check((try? fm.destinationOfSymbolicLink(atPath: lib.appendingPathComponent("x86_64-unix/dxgi.so").path))
                      == "../../external/libd3dshared.dylib", "unix bridges link to libd3dshared")
                check((try? Data(contentsOf: lib.appendingPathComponent("x86_64-windows/d3d12.dll.wine"))) == dll("wine's d3d12", builtin: true),
                      "Wine's own d3d12 is kept")
                try Engine.installD3DMetal(URL(fileURLWithPath: real), into: wine)
                check((try? Data(contentsOf: lib.appendingPathComponent("x86_64-windows/d3d12.dll.wine"))) == dll("wine's d3d12", builtin: true),
                      "installing again keeps Wine's original, not Apple's copy")
            } catch {
                check(false, "the real payload installs (\(error))")
            }
        }

        // MARK: CrossOver's user folder
        let users = work.appendingPathComponent("prefix/drive_c/users", isDirectory: true)
        try? fm.createDirectory(at: users.appendingPathComponent("thomas"), withIntermediateDirectories: true)
        Engine.linkCrossOverProfile(users: users, userName: "thomas")
        check((try? fm.destinationOfSymbolicLink(atPath: users.appendingPathComponent("crossover").path)) == "thomas",
              "crossover points at the existing user folder")
        Engine.linkCrossOverProfile(users: users, userName: "thomas")
        check((try? fm.destinationOfSymbolicLink(atPath: users.appendingPathComponent("crossover").path)) == "thomas", "repeating is harmless")

        // MARK: AVX
        check(GameLog.illegalInstruction(in: "wine: Unhandled illegal instruction at address 0000000140123456"),
              "Wine's crash line is read")
        check(!GameLog.illegalInstruction(in: "err:module:import_dll Library foo.dll not found"), "other errors aren't")
        let crash = game.appendingPathComponent("b1/Saved/Crashes/UECC-1/CrashContext.runtime-xml")
        write(Data("<ErrorMessage>Unhandled Exception: EXCEPTION_ILLEGAL_INSTRUCTION</ErrorMessage>".utf8), crash)
        check(GameLog.illegalInstruction(since: UInt64.max, installDir: game, startedAt: Date().addingTimeInterval(-60)),
              "Unreal's crash report is read")
        check(!GameLog.illegalInstruction(since: UInt64.max, installDir: game, startedAt: Date().addingTimeInterval(60)),
              "an older crash report doesn't count")
        let noAVXProfile = try? JSONDecoder().decode(GameProfile.self, from: Data(#"{"avx": false}"#.utf8))
        let app = 990_002
        UserDefaults.standard.removeObject(forKey: "learned.noAVX.\(app)")
        check(LearnedFixes.avx(app, profile: nil), "AVX is advertised by default")
        check(!LearnedFixes.avx(app, profile: noAVXProfile), "a profile turns it off")
        LearnedFixes.setNoAVX(app)
        check(!LearnedFixes.avx(app, profile: nil), "a learned crash turns it off")
        UserDefaults.standard.removeObject(forKey: "learned.noAVX.\(app)")

        // MARK: Steam's environment
        Engine.launchEnvironment = [:]
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true),
              "a DXMT game with AVX needs no restart")
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: true, frameLimit: 60, upscaling: true)
              && Engine.steamEnvironment["D3DM_MAX_FPS"] == "60" && Engine.steamEnvironment["D3DM_ENABLE_METALFX"] == "1",
              "a D3DMetal game brings its frame limit and MetalFX into Steam's environment")
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: true, frameLimit: 60, upscaling: true),
              "the next D3DMetal game with the same settings needs no restart")
        check(!Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 40, upscaling: false),
              "a DXMT game in between leaves D3DMetal's settings alone")
        check(Engine.prepareLaunchEnvironment(avx: false, d3dMetal: true, frameLimit: 60, upscaling: true)
              && Engine.steamEnvironment["ROSETTA_ADVERTISE_AVX"] == nil, "a game without AVX gets a Steam without the hint")
        check(Engine.prepareLaunchEnvironment(avx: true, d3dMetal: false, frameLimit: 60, upscaling: true)
              && Engine.steamEnvironment["ROSETTA_ADVERTISE_AVX"] == "1", "…and the next one gets it back")
        check(Engine.steamConfigSignature.contains("D3DM_MAX_FPS=60"), "Steam restarts when these change")
        Engine.launchEnvironment = [:]

        // MARK: Settings files
        let settings = game.appendingPathComponent("b1/Saved/Config/Windows/GameUserSettings.ini")
        let edits = (try? JSONDecoder().decode(GameProfile.self, from: Data(#"""
            {"fileEdits": [{"path": "b1/Saved/Config/Windows/GameUserSettings.ini",
                            "find": "(\"InsertFrame\", \"1\")", "replace": "(\"InsertFrame\", \"0\")"},
                           {"path": "../../escape.txt", "find": "a", "replace": "b"}]}
            """#.utf8)))?.fileEdits ?? []
        check(edits.count == 2, "a profile's file edits are read")
        check(!Engine.applyFileEdits(edits, installDir: game), "no settings file yet: nothing to change")
        write(Data(#"UISettingData=(("Dlss", "1"),("InsertFrame", "1"),("Rtx", "0"))"#.utf8), settings)
        let escape = game.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("escape.txt")
        write(Data("a".utf8), escape)
        check(Engine.applyFileEdits(edits, installDir: game), "the game's settings file is changed")
        check((try? String(contentsOf: settings, encoding: .utf8)) == #"UISettingData=(("Dlss", "1"),("InsertFrame", "0"),("Rtx", "0"))"#,
              "frame generation goes off, everything else stays")
        check((try? String(contentsOf: escape, encoding: .utf8)) == "a", "nothing outside the game folder is touched")
        check(!Engine.applyFileEdits(edits, installDir: game), "a second time there's nothing left to change")

        print(failures == 0 ? "✓ all checks passed" : "\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
