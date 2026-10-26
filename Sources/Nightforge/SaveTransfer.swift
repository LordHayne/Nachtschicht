import Foundation

/// Takes a game's saves along when it changes between its Windows and Mac versions. Steam Cloud
/// does that too, but only when the Steam that played last could upload them – one Steam sign-in
/// per account makes that miss now and then, and then the other version starts empty. So before
/// a version starts for the first time after a switch, every save folder it has (the folders
/// Steam Cloud uses, SteamCatalog.saveRules) that holds no saves yet gets the other version's.
/// A folder with saves in it is never touched; Steam Cloud and the player decide there.
enum SaveTransfer {
    /// Where the game's two versions keep their files: the Wine prefix and both install folders.
    struct Places {
        var prefix: URL = Engine.prefix
        var windowsUser = NSUserName()
        var windowsInstall: URL?
        var macHome = FileManager.default.homeDirectoryForCurrentUser
        var macInstall: URL?
    }

    private static func key(_ appID: Int) -> String { "saves.lastVersion.\(appID)" }

    /// Before `platform` starts: copies saves over if the game last ran as the other version (or
    /// Nightforge hasn't seen it run yet). Returns how many files were copied.
    @discardableResult
    static func beforeStart(appID: Int, platform: Platform, rules: [SaveRule], places: Places,
                            defaults: UserDefaults = .standard) -> Int {
        defer { defaults.set(platform.rawValue, forKey: key(appID)) }
        guard defaults.string(forKey: key(appID)) != platform.rawValue else { return 0 }
        return carryOver(to: platform, rules: rules, places: places)
    }

    /// Fills each empty save folder of `platform` from the other version's.
    static func carryOver(to platform: Platform, rules: [SaveRule], places: Places) -> Int {
        var copied = 0
        for rule in rules {
            guard let windows = windowsRoot(rule.root, places), let macRootName = rule.macRoot,
                  let mac = macRoot(macRootName, places)
            else { continue }
            let (from, to) = platform == .mac
                ? (windows, mac.appendingPathComponent(rule.macAddPath))
                : (mac.appendingPathComponent(rule.macAddPath), windows)
            for folder in resolve(rule.path, under: from) {
                let source = from.appendingPathComponent(folder, isDirectory: true)
                let target = to.appendingPathComponent(folder, isDirectory: true)
                let saves = files(in: source, matching: rule.pattern, recursive: rule.recursive)
                guard !saves.isEmpty, files(in: target, matching: rule.pattern, recursive: rule.recursive).isEmpty else { continue }
                for relative in saves {
                    let destination = target.appendingPathComponent(relative)
                    try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if (try? FileManager.default.copyItem(at: source.appendingPathComponent(relative), to: destination)) != nil {
                        copied += 1
                    }
                }
            }
        }
        return copied
    }

    /// A Windows root inside the Wine prefix. Folders that still lead out of it (a user folder
    /// linked to the Mac's own) are left alone: macOS would ask for access to them.
    private static func windowsRoot(_ root: String, _ places: Places) -> URL? {
        let user = places.prefix.appendingPathComponent("drive_c/users/\(places.windowsUser)", isDirectory: true)
        let folder: URL
        switch root.lowercased() {
        case "gameinstall": return places.windowsInstall
        case "winappdataroaming": folder = user.appendingPathComponent("AppData/Roaming", isDirectory: true)
        case "winappdatalocal": folder = user.appendingPathComponent("AppData/Local", isDirectory: true)
        case "winappdatalocallow": folder = user.appendingPathComponent("AppData/LocalLow", isDirectory: true)
        case "winmydocuments": folder = user.appendingPathComponent("Documents", isDirectory: true)
        case "winsavedgames": folder = user.appendingPathComponent("Saved Games", isDirectory: true)
        default: return nil
        }
        let inside = places.prefix.resolvingSymlinksInPath().path
        return folder.resolvingSymlinksInPath().path.hasPrefix(inside) ? folder : nil
    }

    /// A macOS root. Documents, Desktop and Downloads are out: reading them makes macOS ask.
    private static func macRoot(_ root: String, _ places: Places) -> URL? {
        switch root.lowercased() {
        case "gameinstall": return places.macInstall
        case "macappsupport": return places.macHome.appendingPathComponent("Library/Application Support", isDirectory: true)
        case "maccaches": return places.macHome.appendingPathComponent("Library/Caches", isDirectory: true)
        default: return nil
        }
    }

    /// The concrete folders a rule's path names under `root`. Placeholders like {64BitSteamID}
    /// match whatever folder is there ("st_76561198118309630"), so no account ID is needed.
    static func resolve(_ path: String, under root: URL) -> [String] {
        var found = [""]
        for part in path.split(separator: "/").map(String.init) where !part.isEmpty {
            guard part.contains("{") else {
                found = found.map { $0.isEmpty ? part : $0 + "/" + part }
                continue
            }
            let pattern = part.replacingOccurrences(of: #"\{[^}]*\}"#, with: "*", options: .regularExpression)
            found = found.flatMap { parent -> [String] in
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(parent).path)) ?? []
                return entries.filter { fnmatch(pattern, $0, 0) == 0 }.map { parent.isEmpty ? $0 : parent + "/" + $0 }
            }
        }
        return found
    }

    /// Files under `folder` matching `pattern`, as paths relative to it.
    private static func files(in folder: URL, matching pattern: String, recursive: Bool) -> [String] {
        let fm = FileManager.default
        guard let entries = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                          options: recursive ? [] : [.skipsSubdirectoryDescendants])
        else { return [] }
        let base = folder.standardizedFileURL.path + "/"
        var result: [String] = []
        for case let url as URL in entries {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  fnmatch(pattern, url.lastPathComponent, 0) == 0,
                  url.lastPathComponent != "steam_autocloud.vdf"
            else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(base) { result.append(String(path.dropFirst(base.count))) }
        }
        return result
    }
}
