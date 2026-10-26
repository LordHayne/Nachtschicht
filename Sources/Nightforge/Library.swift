import Foundation

struct Bottle: Hashable {
    let name: String
    let url: URL
    /// Nightforge's own prefix, run with the downloaded engine instead of CrossOver.
    var isBuiltIn = false
}

enum InstallState: Hashable {
    case installed
    /// Owned on Steam but not on this Mac yet.
    case notInstalled
    /// Steam is downloading it; nil while Steam hasn't worked out the size yet.
    case downloading(Double?)
    /// Not owned: a hit from the Steam store search.
    case inStore
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
    /// Steam stopped its download for lack of disk space: the space it needs for it (download and
    /// unpacking). Steam leaves such a download paused for good, so it waits for the player.
    var downloadNeedsSpace: Int64?
    /// Name of the folder under steamapps/common (needed to ask Steam for a download).
    var installDirName = ""
    /// Steam also sells a macOS version (which may or may not run on current Macs).
    var macNative = false
    /// That Mac version is 64-bit, so it runs on current macOS.
    var mac64 = false
    /// … and built for Apple silicon, not only for Intel Macs.
    var macAppleSilicon = false
    /// Download size of the Mac version.
    var macSize: Int64 = 0
    /// Steam has a Windows version of it (nearly always).
    var windowsBuild = true
    /// Playable with a controller (from the couch) – or only in part, or not.
    var controller = ControllerSupport.none
    /// Its anti-cheat stops it on a Mac (Windows versions only).
    var antiCheatBlock: AntiCheatBlock?
    /// Steam lists no single-player mode: there's nothing to play without going online.
    var onlineOnly = false
    /// The version Nightforge runs: Windows through Wine, or Mac through Steam for Mac.
    var platform = Platform.windows
    /// Steam has both versions and Nightforge can run either, so the options offer the choice.
    var switchable = false
    /// Why this version (only for switchable games).
    var versionReason: VersionChoice.Reason?
    /// Mac version in use while the Windows one is still installed in Nightforge's own Steam: its size.
    var windowsLeftover: Int64?
    /// … and where that Windows version lies.
    var windowsLeftoverDir: URL?
    /// The Mac version Nightforge switches to once it's on the Mac, while the installed Windows
    /// version is still the one played: not downloaded yet, or downloading.
    var macPending: InstallState?
    /// Keeps a game's place in the list when it changes version.
    var listID: String?
    /// Store hits only: price as shown in the store, and the Metacritic score.
    var storePrice: String?
    var metascore: Int?

    var id: String { listID ?? "\(bottle.name)#\(appID)" }
    var isInstalled: Bool { install == .installed }
    /// Anti-cheat stops it on a Mac, but GeForce Now streams it: Play goes there instead.
    var playsInCloud: Bool {
        antiCheatBlock?.geforceNowURL != nil && (install == .notInstalled || install == .installed)
    }
}

extension Game {
    /// What the Steam catalog says about the game: VR only, controller, its Mac version.
    mutating func adoptCatalogFacts(_ app: CatalogApp) {
        isVROnly = app.vrOnly
        controller = app.controller
        onlineOnly = !app.singlePlayer
        macNative = app.macNative
        mac64 = app.mac64
        macAppleSilicon = app.macAppleSilicon
        macSize = app.macSize
        windowsBuild = app.windows
    }
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

        return sorted(games)
    }

    /// Installed games first (most recently played first), then downloads, then the rest of the
    /// Steam library alphabetically.
    static func sorted(_ games: [Game]) -> [Game] {
        func rank(_ game: Game) -> Int {
            // Switched to its Mac version but still playable (Play fetches it): keeps its place.
            if game.windowsLeftover != nil { return 0 }
            switch game.install {
            case .installed: return 0
            case .downloading: return 1
            case .notInstalled: return 2
            case .inStore: return 3
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

            // What Steam knows about each game: VR only, a Mac version.
            let catalog = SteamCatalog.ownedGames(steamRoot: steamRoot)
            let known = Dictionary(catalog.map { ($0.appID, $0) }, uniquingKeysWith: { first, _ in first })
            for index in result.indices {
                guard let app = known[result[index].appID] else { continue }
                result[index].adoptCatalogFacts(app)
            }

            // Nightforge's own Steam: show the whole library, not only what's on disk.
            if bottle.isBuiltIn {
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
                    game.adoptCatalogFacts(app)
                    result.append(game)
                }
            }
        }
        return result
    }

    // MARK: - Mac versions

    /// Games in Steam for Mac's library (installed or downloading), as Mac versions.
    static func scanMac(root: URL = MacSteam.root) -> [Game] {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("steamapps").path) else { return [] }
        let bottle = Bottle(name: MacSteam.bottle.name, url: root)
        let usage = readUsage(steamRoot: root)
        let catalog = Dictionary(SteamCatalog.ownedGames(steamRoot: root).map { ($0.appID, $0) },
                                 uniquingKeysWith: { first, _ in first })
        var result: [Game] = []
        var seen = Set<Int>()
        for steamapps in libraryFolders(steamRoot: root, bottle: bottle) {
            for manifest in manifests(in: steamapps) {
                guard var game = readManifest(manifest, steamapps: steamapps, bottle: bottle,
                                              steamRoot: root, steamExe: "", usage: usage, measureStaging: false),
                      seen.insert(game.appID).inserted
                else { continue }
                game.platform = .mac
                if case .downloading = game.install, let fraction = MacSteamProgress.fraction(appID: game.appID, steamRoot: root) {
                    game.install = .downloading(fraction)
                }
                if let app = catalog[game.appID] { game.adoptCatalogFacts(app) }
                game.macNative = true
                result.append(game)
            }
        }
        return result
    }

    /// One entry per game: the Windows scan's, switched to the Mac version where VersionChoice
    /// says so, plus Mac versions in Steam for Mac that no scanned Windows Steam knows.
    static func merge(_ windows: [Game], mac: [Game], preferWindows: Set<Int>,
                      choice: (Int) -> GameVersion = { GameOptionsStore.load($0).version },
                      macFailed: (Int) -> Bool = MacHealth.failed) -> [Game] {
        let onMac = Dictionary(mac.map { ($0.appID, $0) }, uniquingKeysWith: { first, _ in first })
        var taken = Set<Int>()  // two bottles with the same game: one entry gets the Mac version
        var result: [Game] = []
        for var game in windows {
            let installedMac = onMac[game.appID]
            guard game.install != .inStore, game.macNative || installedMac != nil, !taken.contains(game.appID) else {
                result.append(game)
                continue
            }
            taken.insert(game.appID)
            let facts = VersionChoice.Facts(
                macNative: true, mac64: game.mac64 || installedMac?.mac64 == true, windows: game.windowsBuild,
                macInstalled: installedMac?.isInstalled == true, windowsInstalled: game.isInstalled)
            let (platform, reason) = VersionChoice.decide(facts, choice: choice(game.appID),
                                                          preferWindows: preferWindows.contains(game.appID),
                                                          macFailed: macFailed(game.appID))
            let switchable = reason != .only
            game.switchable = switchable
            game.versionReason = switchable ? reason : nil
            guard platform == .mac else {
                result.append(game)
                continue
            }
            var entry = macEntry(for: game, onMac: installedMac)
            entry.mac64 = facts.mac64
            entry.switchable = switchable
            entry.versionReason = switchable ? reason : nil
            // Seamless: a game that plays through its installed Windows version stays playable
            // that way while its Mac version is fetched; it switches once that is installed.
            if game.isInstalled && !entry.isInstalled && reason != .chosen {
                game.macPending = entry.install
                result.append(game)
                continue
            }
            result.append(entry)
        }
        let listed = Set(windows.filter { $0.install != .inStore }.map(\.appID))
        result += mac.filter { !listed.contains($0.appID) }
        return sorted(result)
    }

    /// Marks Windows versions whose anti-cheat stops them on a Mac – unless Steam offers to start
    /// them without it, which Launcher then does (`SteamCatalog.antiCheatOffArguments`).
    static func markAntiCheat(_ games: [Game], blocks: [Int: AntiCheatBlock]) -> [Game] {
        games.map { game in
            var game = game
            guard game.platform == .windows, game.install != .inStore, let block = blocks[game.appID],
                  !block.onlineOnly || game.onlineOnly,
                  SteamCatalog.antiCheatOffArguments(appID: game.appID, steamRoot: game.steamRoot).isEmpty
            else { return game }
            game.antiCheatBlock = block
            return game
        }
    }

    /// The Mac version's entry for a game the Windows scan found: what Steam for Mac has of it
    /// (`onMac`), else not downloaded. It keeps the game's place in the list.
    static func macEntry(for game: Game, onMac: Game? = nil) -> Game {
        var entry: Game
        if let onMac {
            entry = onMac
        } else {
            entry = Game(appID: game.appID, name: game.name, bottle: MacSteam.bottle, steamRoot: MacSteam.root,
                         steamExeWindowsPath: "",
                         installDir: MacSteam.steamapps.appendingPathComponent("common/\(game.installDirName)", isDirectory: true),
                         sizeOnDisk: game.macSize)
            entry.install = game.macPending ?? .notInstalled
            entry.installDirName = game.installDirName
        }
        entry.platform = .mac
        entry.macNative = true
        entry.mac64 = game.mac64 || onMac?.mac64 == true
        entry.macAppleSilicon = game.macAppleSilicon || onMac?.macAppleSilicon == true
        entry.macSize = max(game.macSize, onMac?.macSize ?? 0)
        entry.isVROnly = game.isVROnly
        entry.controller = game.controller != .none ? game.controller : onMac?.controller ?? .none
        entry.lastPlayed = [game.lastPlayed, onMac?.lastPlayed].compactMap { $0 }.max()
        entry.playtimeMinutes = [game.playtimeMinutes, onMac?.playtimeMinutes].compactMap { $0 }.max()
        entry.windowsBuild = game.windowsBuild
        entry.switchable = game.switchable
        entry.versionReason = game.versionReason
        entry.listID = game.id
        entry.macPending = nil
        if game.isInstalled && game.bottle.isBuiltIn {
            entry.windowsLeftover = game.sizeOnDisk
            entry.windowsLeftoverDir = game.installDir
        }
        return entry
    }

    // MARK: - Manifests

    private static func manifests(in steamapps: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
    }

    /// `measureStaging`: the files a download has unpacked so far say how far it is – not with
    /// Steam for Mac, which reserves the whole game up front.
    private static func readManifest(
        _ url: URL, steamapps: URL, bottle: Bottle,
        steamRoot: URL, steamExe: String, usage: [Int: Usage], measureStaging: Bool = true
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
        let toStage = state["bytestostage"]?.string.flatMap { Double($0) } ?? 0
        let install: InstallState
        if flags & 4 != 0 {
            install = .installed
        } else if toDownload > 0 || toStage > 0 {
            // Steam only writes BytesDownloaded when a download pauses or ends; meanwhile the
            // unpacked files pile up in steamapps/downloading/<appid>, so measure that too and
            // take whichever is further along.
            let reported = toDownload > 0 ? downloaded / toDownload : 0
            let staged = toStage > 0 && measureStaging
                ? Double(folderSize(steamapps.appendingPathComponent("downloading/\(appID)", isDirectory: true))) / toStage
                : 0
            install = .downloading(min(max(reported, staged), 0.99))
        } else {
            install = .downloading(nil)
        }

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
        // UpdateResult 12: Steam's "not enough disk space".
        if flags & 4 == 0, state["updateresult"]?.string == "12" {
            game.downloadNeedsSpace = Int64(max(toDownload, toStage))
        }
        return game
    }

    private static func folderSize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Extra library folders (e.g. D:\SteamLibrary)

    private static func libraryFolders(steamRoot: URL, bottle: Bottle) -> [URL] {
        var urls = [steamRoot.appendingPathComponent("steamapps", isDirectory: true)]

        let vdfURL = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let folders = VDF.parse(contentsOf: vdfURL)?["libraryfolders"]?.object {
            for (_, entry) in folders {
                // New format: "0" { "path" "C:\\..." }   Old format: "1" "D:\\SteamLibrary"
                // Steam for Mac writes Mac paths.
                guard let path = entry["path"]?.string ?? entry.string,
                      let folder = path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true)
                                                       : macPath(forWindowsPath: path, in: bottle)
                else { continue }
                urls.append(folder.appendingPathComponent("steamapps", isDirectory: true))
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
