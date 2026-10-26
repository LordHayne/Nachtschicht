import Foundation

/// What a game's files reveal before it runs: the graphics interfaces its programs link, its
/// engine, anti-cheat, .NET and the other launchers it needs. Read from the Windows import tables
/// and the file names; nothing is executed.
struct GameAnalysis: Codable, Equatable {
    enum API: String, Codable, CaseIterable, Comparable {
        case legacy, d3d9, d3d10, d3d11, d3d12, vulkan, openGL

        var label: String {
            switch self {
            case .legacy: return "DirectX 7/8"
            case .d3d9: return "DirectX 9"
            case .d3d10: return "DirectX 10"
            case .d3d11: return "DirectX 11"
            case .d3d12: return "DirectX 12"
            case .vulkan: return "Vulkan"
            case .openGL: return "OpenGL"
            }
        }

        static func < (a: API, b: API) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
    }

    enum GameEngine: String, Codable {
        case unreal, unity, other
    }

    var apis: Set<API> = []
    var engine = GameEngine.other
    /// "Easy Anti-Cheat", "BattlEye": online play with them doesn't work on a Mac.
    var antiCheat: [String] = []
    /// A .NET program (or a .NET launcher in front of the game): it needs Wine Mono.
    var usesDotNet = false
    /// Another company's launcher the game starts through ("Ubisoft Connect", "EA app", …).
    var launcher: String?
    /// Microsoft WebView2 draws some of its windows (login, news); under Wine they often stay empty.
    var usesWebView2 = false

    /// Direct3D 10/11 is what DXMT and DXVK translate.
    var usesD3D11: Bool { apis.contains(.d3d10) || apis.contains(.d3d11) }
    var usesD3D9: Bool { apis.contains(.d3d9) || apis.contains(.legacy) }
    /// Nothing Nightforge can translate well: Direct3D 12 and no other way to draw.
    var onlyD3D12: Bool { apis == [.d3d12] }

    /// Arguments that make a game with both Direct3D 11 and 12 pick 11, which runs far better on a
    /// Mac. Only for engines whose switch is known.
    var preferD3D11Arguments: [String] {
        guard apis.contains(.d3d12), usesD3D11 else { return [] }
        switch engine {
        case .unreal: return ["-dx11"]
        case .unity: return ["-force-d3d11"]
        case .other: return []
        }
    }

    /// "DirectX 11 · Unity" for the game's details and problem reports.
    var summary: String {
        var parts = [apis.sorted().map(\.label).joined(separator: ", ")]
        if engine == .unreal { parts.append("Unreal Engine") }
        if engine == .unity { parts.append("Unity") }
        if usesDotNet { parts.append(".NET") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension GameAnalysis {
    /// Looks at the program Steam starts (`launchExecutable`, relative to the game folder), the
    /// engine binaries next to it and, for Unreal's small starter programs, the real game program.
    static func analyze(installDir: URL, launchExecutable: String?) -> GameAnalysis {
        let fm = FileManager.default
        var analysis = GameAnalysis()
        let contents = scan(installDir)
        let programs = contents.programs
        var targets: [URL] = []
        if let launchExecutable {
            let relative = launchExecutable.replacingOccurrences(of: "\\", with: "/")
            targets.append(installDir.appendingPathComponent(relative))
        }
        targets += programs.filter { $0.lastPathComponent.lowercased().contains("-shipping") }
        // Steam may start a launcher that draws nothing itself; then the biggest program is the game.
        let fallback = targets.count
        if let largest = programs.max(by: { size($0) < size($1) }) { targets.append(largest) }

        var engineLibraries: [URL] = []
        for (index, file) in targets.enumerated() where fm.fileExists(atPath: file.path) {
            if index == fallback, !analysis.apis.isEmpty || analysis.engine == .unity { break }
            guard let imports = PEImports.dlls(of: file) else { continue }
            let folder = file.deletingLastPathComponent()
            analysis.apis.formUnion(imports.compactMap(api(forDLL:)))
            if imports.contains("mscoree.dll") { analysis.usesDotNet = true }
            // The game's own big libraries can be where it draws (Source's engine.dll and the like);
            // upscalers and SDKs link every graphics interface they support, so they don't count.
            engineLibraries += imports
                .filter { dll in !middleware.contains { dll.hasPrefix($0) } && !dll.hasPrefix("api-ms-") }
                .compactMap { existingFile(folder.appendingPathComponent($0)) }
                .filter { size($0) > 3_000_000 }
            // Direct3D 12's Agility SDK ships as D3D12Core.dll in a folder next to the game.
            if ["D3D12/D3D12Core.dll", "D3D12Core.dll"].contains(where: { existingFile(folder.appendingPathComponent($0)) != nil }) {
                analysis.apis.insert(.d3d12)
            }
            if existingFile(folder.appendingPathComponent("UnityPlayer.dll")) != nil { analysis.engine = .unity }
        }
        if analysis.engine == .unity {
            // UnityPlayer.dll links every interface Unity has; the game uses Direct3D 11 unless its
            // build carries Direct3D 12 (the D3D12 folder found above).
            analysis.apis.formUnion([.d3d11])
            analysis.apis.subtract([.openGL])
        } else if analysis.apis.isEmpty {
            for library in engineLibraries.prefix(6) {
                analysis.apis.formUnion((PEImports.dlls(of: library) ?? []).compactMap(api(forDLL:)))
            }
        }
        // Source games (Left 4 Dead 2, Team Fortress 2, …) load their renderer at run time from
        // bin/shaderapi*.dll, so no import names it; Direct3D 9 is the one they use.
        if analysis.apis.isEmpty, contents.hasItem(named: "shaderapidx9.dll") {
            analysis.apis.insert(.d3d9)
        }
        if analysis.engine == .other, programs.contains(where: { $0.lastPathComponent.lowercased().contains("-win64-shipping") })
            || fm.fileExists(atPath: installDir.appendingPathComponent("Engine/Binaries").path) {
            analysis.engine = .unreal
        }
        analysis.antiCheat = [("Easy Anti-Cheat", "easyanticheat"), ("BattlEye", "battleye")]
            .filter { contents.hasItem(named: $0.1) }.map(\.0)
        analysis.launcher = launchers.first { $0.paths.contains(where: contents.has) }?.name
        analysis.usesWebView2 = contents.hasItem(named: "webview2loader.dll")
        return analysis
    }

    /// Launchers of other stores, recognised by files they leave in the game folder (paths are
    /// relative to it; a bare name may be anywhere).
    private static let launchers: [(name: String, paths: [String])] = [
        ("Ubisoft Connect", ["upc_r2_loader64.dll", "upc_r1_loader64.dll", "uplay_r1_loader64.dll", "uplay_r2_loader64.dll", "uplay_r164.dll"]),
        ("EA app", ["__installer/installerdata.xml"]),
        ("Rockstar Games Launcher", ["playgtav.exe", "playrdr2.exe", "rockstar-games-launcher.exe"]),
        ("Paradox Launcher", ["launcher-settings.json"]),
    ]

    private static func api(forDLL dll: String) -> API? {
        switch dll {
        case "ddraw.dll", "d3d8.dll": return .legacy
        case "d3d9.dll": return .d3d9
        case "d3d10.dll", "d3d10_1.dll", "d3d10core.dll": return .d3d10
        case "d3d11.dll": return .d3d11
        case "d3d12.dll", "d3d12core.dll": return .d3d12
        case "vulkan-1.dll": return .vulkan
        case "opengl32.dll": return .openGL
        default: return nil
        }
    }

    /// Libraries games ship that link graphics interfaces for their own purposes (upscalers,
    /// overlays, SDKs), by name prefix.
    private static let middleware = [
        "sl.", "libxess", "nvngx", "gfsdk", "amd_", "ffx", "nvlowlatency", "openvr", "steam_api", "eossdk",
        "galaxy", "discord", "bink", "fmod", "physx", "nvapi", "d3dcompiler", "msvcp", "vcruntime", "ucrtbase",
    ]

    /// The game folder a few levels deep (where Unity and Unreal put their programs).
    private struct Contents {
        /// Windows programs, without installers and crash reporters.
        var programs: [URL] = []
        /// Every file and folder, lower-cased and relative to the game folder.
        var paths = Set<String>()

        /// `path` relative to the game folder, or a bare name anywhere in it.
        func has(_ path: String) -> Bool { path.contains("/") ? paths.contains(path) : hasItem(named: path) }
        func hasItem(named name: String) -> Bool { paths.contains(name) || paths.contains { $0.hasSuffix("/" + name) } }
    }

    private static func scan(_ dir: URL) -> Contents {
        var contents = Contents()
        guard let files = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return contents }
        let base = dir.standardizedFileURL.path.count + 1
        let helpers = ["crash", "redist", "dxsetup", "vcredist", "setup", "installer", "unins", "easyanticheat", "beservice", "report"]
        for case let file as URL in files {
            if files.level > 4 { files.skipDescendants(); continue }
            let path = String(file.standardizedFileURL.path.dropFirst(base)).lowercased()
            contents.paths.insert(path)
            let name = file.lastPathComponent.lowercased()
            let installers = path.hasPrefix("_commonredist") || path.hasPrefix("__installer")
            if name.hasSuffix(".exe"), !installers, !helpers.contains(where: name.contains) { contents.programs.append(file) }
        }
        return contents
    }

    private static func size(_ file: URL) -> Int {
        (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// Windows file names ignore case; the Mac's disk usually does too, but not always.
    private static func existingFile(_ url: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return url }
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent.lowercased()
        return (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .first { $0.lastPathComponent.lowercased() == name }
    }
}

/// The DLLs a Windows program loads at start or on first use (delay-load), from its PE headers.
enum PEImports {
    static func dlls(of file: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
            return try? handle.read(upToCount: count)
        }

        guard let dos = read(0, 64), dos.count == 64, dos.u16(0) == 0x5A4D else { return nil }  // "MZ"
        let pe = UInt64(dos.u32(0x3C))
        guard let coff = read(pe, 24), coff.count == 24, coff.u32(0) == 0x4550 else { return nil }  // "PE\0\0"
        let sectionCount = Int(coff.u16(6))
        let optionalSize = Int(coff.u16(20))
        guard let optional = read(pe + 24, optionalSize), optional.count == optionalSize, optionalSize >= 96 else { return nil }
        let is64 = optional.u16(0) == 0x20B
        let directories = is64 ? 112 : 96
        let imageBase = is64 ? optional.u64(24) : UInt64(optional.u32(28))
        func directory(_ index: Int) -> UInt32 {
            let at = directories + index * 8
            return at + 8 <= optional.count ? optional.u32(at) : 0
        }

        guard let table = read(pe + 24 + UInt64(optionalSize), sectionCount * 40), table.count == sectionCount * 40 else { return nil }
        func fileOffset(_ rva: UInt32) -> UInt64? {
            for index in 0..<sectionCount {
                let at = index * 40
                let virtualSize = table.u32(at + 8), address = table.u32(at + 12)
                let rawSize = table.u32(at + 16), rawPointer = table.u32(at + 20)
                if rva >= address, rva < address &+ max(virtualSize, rawSize) {
                    return UInt64(rawPointer) + UInt64(rva - address)
                }
            }
            return nil
        }
        func name(at rva: UInt32) -> String? {
            guard rva != 0, let offset = fileOffset(rva), let bytes = read(offset, 128) else { return nil }
            let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self).lowercased()
            return text.hasSuffix(".dll") || text.hasSuffix(".drv") ? text : nil
        }

        var names: [String] = []
        // Import descriptors: 20 bytes each, the DLL name's address at +12, ended by an empty one.
        if let start = fileOffset(directory(1)), directory(1) != 0, let block = read(start, 20 * 512) {
            var at = 0
            while at + 20 <= block.count, block.u32(at + 12) != 0 {
                if let dll = name(at: block.u32(at + 12)) { names.append(dll) }
                at += 20
            }
        }
        // Delay-load descriptors: 32 bytes each, the name at +4 (an address in old linkers).
        if let start = fileOffset(directory(13)), directory(13) != 0, let block = read(start, 32 * 256) {
            var at = 0
            while at + 32 <= block.count, block.u32(at + 4) != 0 {
                var rva = block.u32(at + 4)
                if block.u32(at) & 1 == 0, UInt64(rva) > imageBase { rva = UInt32(truncatingIfNeeded: UInt64(rva) - imageBase) }
                if let dll = name(at: rva) { names.append(dll) }
                at += 32
            }
        }
        return names
    }
}

private extension Data {
    func u16(_ at: Int) -> UInt16 {
        guard at + 2 <= count else { return 0 }
        return UInt16(self[startIndex + at]) | UInt16(self[startIndex + at + 1]) << 8
    }

    func u32(_ at: Int) -> UInt32 {
        guard at + 4 <= count else { return 0 }
        return UInt32(u16(at)) | UInt32(u16(at + 2)) << 16
    }

    func u64(_ at: Int) -> UInt64 {
        guard at + 8 <= count else { return 0 }
        return UInt64(u32(at)) | UInt64(u32(at + 4)) << 32
    }
}
