import Foundation

struct Bottle: Hashable {
    let name: String
    let url: URL
    /// Nachtschicht's own prefix, run with the downloaded engine instead of CrossOver.
    var isBuiltIn = false
}

enum InstallState: Hashable {
    case installed
    /// Owned on Steam but not on this Mac yet.
    case notInstalled
    /// Steam is downloading it; nil while Steam hasn't worked out the size yet.
    case downloading(Double?)
}

struct Game: Identifiable, Hashable {
    let appID: Int
    let name: String
    let bottle: Bottle
    /// macOS path of the Steam install inside the bottle
    let steamRoot: URL
    /// Windows path of steam.exe, as Wine sees it
    let steamExeWindowsPath: String
    let installDir: URL
    let sizeOnDisk: Int64
    var lastPlayed: Date?
    var playtimeMinutes: Int?
    var install: InstallState = .installed
    /// Needs a VR headset, which the Mac can't run.
    var isVROnly = false
    /// Name of the folder under steamapps/common (needed to ask Steam for a download).
    var installDirName = ""

    var id: String { "\(bottle.name)#\(appID)" }
    var isInstalled: Bool { install == .installed }
}

/// Reads installed Steam games straight from the bottles' appmanifest files.
/// No login, no network, no background service.
enum LibraryScanner {
    /// Redistributables and runtimes Steam installs as "apps".
    static let ignoredAppIDs: Set<Int> = [228980, 1070560, 1391110, 1628350, 1493710, 2180100, 2805730]

    static func defaultBottlesRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles", isDirectory: true)
    }

    static func scan(bottlesRoot: URL, extraBottles: [Bottle] = []) -> [Game] {
        let fm = FileManager.default
        var games: [Game] = extraBottles.flatMap { scan(bottle: $0) }

        // The chosen folder may itself be a single bottle/prefix.
        if fm.fileExists(atPath: bottlesRoot.appendingPathComponent("drive_c").path) {
            games += scan(bottle: Bottle(name: bottlesRoot.lastPathComponent, url: bottlesRoot))
        } else if let entries = try? fm.contentsOfDirectory(
            at: bottlesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for dir in entries where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                games += scan(bottle: Bottle(name: dir.lastPathComponent, url: dir))
            }
        }

        // Installed games first (most recently played first), then downloads, then the rest of the
        // Steam library alphabetically.
        func rank(_ game: Game) -> Int {
            switch game.install {
            case .installed: return 0
            case .downloading: return 1
            case .notInstalled: return 2
            }
        }
        return games.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if a.install == .notInstalled {
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            switch (a.lastPlayed, b.lastPlayed) {
            case let (x?, y?): return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    static func scan(bottle: Bottle) -> [Game] {
        let fm = FileManager.default
        let candidates: [(folder: String, exe: String)] = [
            ("Program Files (x86)", #"C:\Program Files (x86)\Steam\steam.exe"#),
            ("Program Files", #"C:\Program Files\Steam\steam.exe"#),
        ]

        var result: [Game] = []
        var seen = Set<Int>()

        for candidate in candidates {
            let steamRoot = bottle.url.appendingPathComponent("drive_c/\(candidate.folder)/Steam", isDirectory: true)
            guard fm.fileExists(atPath: steamRoot.appendingPathComponent("steam.exe").path) else { continue }

            let usage = readUsage(steamRoot: steamRoot)

            for steamapps in libraryFolders(steamRoot: steamRoot, bottle: bottle) {
                for manifest in manifests(in: steamapps) {
                    guard let game = readManifest(
                        manifest, steamapps: steamapps, bottle: bottle,
                        steamRoot: steamRoot, steamExe: candidate.exe, usage: usage
                    ), !seen.contains(game.appID) else { continue }
                    seen.insert(game.appID)
                    result.append(game)
                }
            }

            // Nachtschicht's own Steam: show the whole library, not only what's on disk.
            if bottle.isBuiltIn {
                let catalog = SteamCatalog.ownedGames(steamRoot: steamRoot)
                let vrOnly = Set(catalog.filter(\.vrOnly).map(\.appID))
                for index in result.indices where vrOnly.contains(result[index].appID) {
                    result[index].isVROnly = true
                }
                let steamapps = steamRoot.appendingPathComponent("steamapps", isDirectory: true)
                for app in catalog
                where !seen.contains(app.appID) && !ignoredAppIDs.contains(app.appID) {
                    seen.insert(app.appID)
                    var game = Game(
                        appID: app.appID, name: app.name, bottle: bottle, steamRoot: steamRoot,
                        steamExeWindowsPath: candidate.exe,
                        installDir: steamapps.appendingPathComponent("common/\(app.installDir)", isDirectory: true),
                        sizeOnDisk: app.size,
                        lastPlayed: usage[app.appID]?.lastPlayed,
                        playtimeMinutes: usage[app.appID]?.playtimeMinutes
                    )
                    game.install = .notInstalled
                    game.installDirName = app.installDir
                    game.isVROnly = app.vrOnly
                    result.append(game)
                }
            }
        }
        return result
    }

    // MARK: - Manifests

    private static func manifests(in steamapps: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
    }

    private static func readManifest(
        _ url: URL, steamapps: URL, bottle: Bottle,
        steamRoot: URL, steamExe: String, usage: [Int: Usage]
    ) -> Game? {
        guard let state = VDF.parse(contentsOf: url)?["appstate"],
              let appID = state["appid"]?.string.flatMap({ Int($0) }),
              !ignoredAppIDs.contains(appID),
              let name = state["name"]?.string, !name.isEmpty,
              let installDirName = state["installdir"]?.string
        else { return nil }

        // StateFlags bit 4 = fully installed; anything else is a download in progress.
        let flags = state["stateflags"]?.string.flatMap { Int($0) } ?? 4
        let toDownload = state["bytestodownload"]?.string.flatMap { Double($0) } ?? 0
        let downloaded = state["bytesdownloaded"]?.string.flatMap { Double($0) } ?? 0
        let install: InstallState = flags & 4 != 0
            ? .installed
            : .downloading(toDownload > 0 ? min(downloaded / toDownload, 1) : nil)

        let lower = name.lowercased()
        if lower.contains("redistributable") || lower.hasPrefix("steam linux runtime") || lower.hasPrefix("proton ") {
            return nil
        }

        var game = Game(
            appID: appID,
            name: name,
            bottle: bottle,
            steamRoot: steamRoot,
            steamExeWindowsPath: steamExe,
            installDir: steamapps.appendingPathComponent("common/\(installDirName)", isDirectory: true),
            sizeOnDisk: install == .installed
                ? state["sizeondisk"]?.string.flatMap { Int64($0) } ?? 0
                : Int64(toDownload),
            lastPlayed: usage[appID]?.lastPlayed,
            playtimeMinutes: usage[appID]?.playtimeMinutes
        )
        game.install = install
        game.installDirName = installDirName
        return game
    }

    // MARK: - Extra library folders (e.g. D:\SteamLibrary)

    private static func libraryFolders(steamRoot: URL, bottle: Bottle) -> [URL] {
        var urls = [steamRoot.appendingPathComponent("steamapps", isDirectory: true)]

        let vdfURL = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let folders = VDF.parse(contentsOf: vdfURL)?["libraryfolders"]?.object {
            for (_, entry) in folders {
                // New format: "0" { "path" "C:\\..." }   Old format: "1" "D:\\SteamLibrary"
                guard let windowsPath = entry["path"]?.string ?? entry.string,
                      let macPath = macPath(forWindowsPath: windowsPath, in: bottle)
                else { continue }
                urls.append(macPath.appendingPathComponent("steamapps", isDirectory: true))
            }
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()).inserted }
    }

    static func macPath(forWindowsPath path: String, in bottle: Bottle) -> URL? {
        let parts = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).map(String.init)
        guard let drive = parts.first?.lowercased(), drive.count == 2, drive.hasSuffix(":") else { return nil }

        var url = bottle.url.appendingPathComponent("dosdevices/\(drive)").resolvingSymlinksInPath()
        if !FileManager.default.fileExists(atPath: url.path) {
            guard drive == "c:" else { return nil }
            url = bottle.url.appendingPathComponent("drive_c", isDirectory: true)
        }
        for component in parts.dropFirst() {
            url.appendPathComponent(component)
        }
        return url
    }

    // MARK: - Last played / playtime from localconfig.vdf

    struct Usage {
        var lastPlayed: Date?
        var playtimeMinutes: Int?
    }

    private static func readUsage(steamRoot: URL) -> [Int: Usage] {
        var out: [Int: Usage] = [:]
        let userdata = steamRoot.appendingPathComponent("userdata", isDirectory: true)
        guard let users = try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil) else {
            return out
        }

        for user in users {
            let config = user.appendingPathComponent("config/localconfig.vdf")
            guard let apps = VDF.parse(contentsOf: config)?["userlocalconfigstore"]?["software"]?["valve"]?["steam"]?["apps"]?.object
            else { continue }

            for (key, value) in apps {
                guard let appID = Int(key) else { continue }
                let lastPlayed = value["lastplayed"]?.string
                    .flatMap { Double($0) }
                    .flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                let playtime = value["playtime"]?.string.flatMap { Int($0) }

                // Several Steam accounts in one bottle: keep the most recent.
                if let existing = out[appID]?.lastPlayed, let new = lastPlayed, existing > new { continue }
                out[appID] = Usage(lastPlayed: lastPlayed, playtimeMinutes: playtime)
            }
        }
        return out
    }
}
