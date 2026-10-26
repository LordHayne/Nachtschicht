import Foundation

/// What Wine, DXVK and MoltenVK print while Steam and its games run. Steam's output lands here
/// (Engine.startSteam) and its games inherit it. Nightforge reads it after a start that went
/// wrong, to fix what it recognises by itself, and for problem reports.
enum GameLog {
    static var url: URL { Engine.supportDir.appendingPathComponent("Logs/wine.log") }

    /// Wine's own messages that help: libraries a program can't load, and .NET without Mono.
    /// Everything else stays quiet.
    static let wineDebug = "-all,err+module,err+mscoree"

    /// Not a winetricks verb: Wine Mono, which Nightforge installs itself (Engine.installWineMono).
    static let wineMono = "wine-mono"

    /// For a Steam about to start: appends to the log, starting a fresh one when it has grown large.
    static func handleForSteam() -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > 8_000_000 {
            let previous = url.deletingLastPathComponent().appendingPathComponent("wine.previous.log")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: url, to: previous)
        }
        // O_APPEND: an old Steam still shutting down and the new one both write to it.
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        return descriptor < 0 ? nil : FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Where the log ends now; what a launch prints comes after it.
    static func mark() -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64 ?? 0
    }

    static func text(since mark: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = mark <= end ? mark : 0  // a fresh log was started meanwhile
        try? handle.seek(toOffset: max(start, end > 4_000_000 ? end - 4_000_000 : 0))
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }

    /// The game died on a processor instruction Rosetta doesn't run – what a game does that takes
    /// Rosetta's AVX hint (`ROSETTA_ADVERTISE_AVX`) at its word on a path Rosetta lacks. Wine says
    /// so in the log; Unreal games catch it themselves and leave a crash report in their folder.
    static func illegalInstruction(since mark: UInt64, installDir: URL, startedAt: Date) -> Bool {
        illegalInstruction(in: text(since: mark)) || unrealCrashes(in: installDir, since: startedAt).contains {
            ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").contains("EXCEPTION_ILLEGAL_INSTRUCTION")
        }
    }

    static func illegalInstruction(in text: String) -> Bool {
        text.lowercased().contains("unhandled illegal instruction") || text.contains("EXCEPTION_ILLEGAL_INSTRUCTION")
    }

    /// Unreal's crash reports (…/Saved/Crashes/<id>/CrashContext.runtime-xml) written since `date`.
    static func unrealCrashes(in installDir: URL, since date: Date) -> [URL] {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: installDir, includingPropertiesForKeys: [.contentModificationDateKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let file as URL in files {
            if files.level > 5 { files.skipDescendants(); continue }
            guard file.lastPathComponent == "CrashContext.runtime-xml",
                  let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified >= date
            else { continue }
            found.append(file)
        }
        return found
    }

    /// Runtimes (winetricks verbs) a game's programs needed and didn't find, since `mark`.
    static func missingRuntimes(since mark: UInt64, gameFolder: String) -> [String] {
        missingRuntimes(in: text(since: mark), gameFolder: gameFolder)
    }

    static func missingRuntimes(in text: String, gameFolder: String) -> [String] {
        var verbs: [String] = []
        let folder = gameFolder.lowercased()
        for line in text.split(whereSeparator: \.isNewline) {
            let lower = line.lowercased()
            let dll: Substring?
            if lower.contains("import_dll"), lower.contains("not found") || lower.contains("failed"),
               lower.contains(folder) || !lower.contains("which is needed by") {
                // err:module:import_dll Library MSVCP120.dll (which is needed by L"C:\\…\\Game.exe") not found
                dll = lower.range(of: "library ").map { lower[$0.upperBound...].prefix { $0 != " " } }
            } else if lower.contains("wine mono is not installed") || lower.contains("install mono for windows") {
                if !verbs.contains(wineMono) { verbs.append(wineMono) }
                dll = nil
            } else if let range = lower.range(of: "unimplemented function ") {
                // wine: Call from … to unimplemented function msvcp140.dll.?_Xbad_alloc@std@@YAXXZ, aborting
                let function = lower[range.upperBound...]
                dll = function.range(of: ".dll").map { function[..<$0.upperBound] }
            } else {
                dll = nil
            }
            if let dll, let verb = winetricksVerb(forDLL: String(dll)), !verbs.contains(verb) { verbs.append(verb) }
        }
        return verbs
    }

    /// Which winetricks verb installs a Windows library Wine lacks or only half implements.
    static func winetricksVerb(forDLL dll: String) -> String? {
        let name = dll.lowercased()
        let table: [(prefixes: [String], verb: String)] = [
            (["msvcp140", "vcruntime140", "concrt140", "vcomp140", "mfc140", "vccorlib140"], "vcrun2022"),
            (["msvcp120", "msvcr120", "vcomp120", "mfc120"], "vcrun2013"),
            (["msvcp110", "msvcr110", "vcomp110", "mfc110"], "vcrun2012"),
            (["msvcp100", "msvcr100", "vcomp100", "mfc100"], "vcrun2010"),
            (["msvcp90", "msvcr90", "mfc90"], "vcrun2008"),
            (["d3dx9_"], "d3dx9"),
            (["d3dx10_"], "d3dx10"),
            (["d3dx11_"], "d3dx11_43"),
            (["d3dcompiler_43"], "d3dcompiler_43"),
            (["d3dcompiler_47"], "d3dcompiler_47"),
            (["xinput1_3"], "xinput"),
            (["physxloader", "physxcore", "physxcooking"], "physx"),
            (["openal32"], "openal"),
        ]
        return table.first { entry in entry.prefixes.contains { name.hasPrefix($0) } }?.verb
    }

    /// Whether the Direct3D layer gave up since `mark`: DXVK couldn't create its device or its
    /// buffers on MoltenVK. The game then shows its own error box ("Failed to create D3D device")
    /// and stays open, so running past its first seconds doesn't mean it started.
    static func graphicsFailed(since mark: UInt64) -> Bool {
        graphicsFailed(in: text(since: mark))
    }

    static func graphicsFailed(in text: String) -> Bool {
        let signs = ["dxvkadapter: failed to create device", "dxvkbuffer: failed to create buffer"]
        let lower = text.lowercased()
        return signs.contains { lower.contains($0) }
    }

    /// The error lines since `mark`, for a problem report: Wine, DXVK and MoltenVK errors, without
    /// repeats and with the Mac's home folder left out.
    static func errors(since mark: UInt64, limit: Int = 30) -> [String] {
        errors(in: text(since: mark), limit: limit)
    }

    static func errors(in text: String, limit: Int = 30) -> [String] {
        let home = NSHomeDirectory()
        var seen = Set<String>()
        var result: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let lower = line.lowercased()
            guard lower.contains(":err:") || lower.contains("mvk-error") || lower.hasPrefix("err:")
                || lower.hasPrefix("wine:") || lower.contains("unhandled")
            else { continue }
            // Thread ids ("0124:err:…") differ between otherwise equal lines.
            var cleaned = String(line)
            if line.count > 5, line.prefix(4).allSatisfy(\.isHexDigit), line.dropFirst(4).first == ":" {
                cleaned = String(line.dropFirst(5))
            }
            cleaned = cleaned.replacingOccurrences(of: home, with: "~")
            if seen.insert(cleaned).inserted { result.append(cleaned) }
        }
        return Array(result.suffix(limit))
    }
}
