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
        check(Engine.layerOverrides(.dxmt, d3dMetalEngine: true) == ["dxgi": "native", "d3d11": "native", "d3d10core": "native"],
              "winecx: DXMT is the native in system32")
        check(Engine.layerOverrides(.dxvk, d3dMetalEngine: true)["d3d11"] == "native", "winecx: DXVK is native (next to the game)")
        let metal = Engine.layerOverrides(.d3dmetal, d3dMetalEngine: true)
        check(["dxgi", "d3d11", "d3d12", "d3d12core"].allSatisfy { metal[$0] == "builtin" }, "D3DMetal takes the builtins")
        check(Engine.layerOverrides(.wined3d, d3dMetalEngine: true) == ["d3d9": "builtin"], "WineD3D unchanged")
        check(!GraphicsLayer.d3dmetal.upscales, "D3DMetal brings its own MetalFX")

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

        print(failures == 0 ? "✓ all checks passed" : "\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
