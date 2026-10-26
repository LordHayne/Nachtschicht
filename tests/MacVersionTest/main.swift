// Checks VersionChoice, the Mac facts read from Steam's catalog, the Steam for Mac library and how
// both versions merge into one entry per game: tests/MacVersionTest/run.sh
import Foundation

@main
struct MacVersionTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    // MARK: Binary KeyValues as Steam writes them

    indirect enum KV {
        case object([(String, KV)])
        case string(String)
        case int(Int32)
    }

    static func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(value >> (8 * $0) & 0xFF) } }
    static func le64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(value >> (8 * UInt64($0)) & 0xFF) } }

    /// One object body; with `table`, key names are indices into it (appinfo v29).
    static func encode(_ pairs: [(String, KV)], table: inout [String]?) -> [UInt8] {
        var out: [UInt8] = []
        for (key, value) in pairs {
            switch value {
            case .object: out.append(0)
            case .string: out.append(1)
            case .int: out.append(2)
            }
            if table != nil {
                if let index = table!.firstIndex(of: key) {
                    out += le32(UInt32(index))
                } else {
                    table!.append(key)
                    out += le32(UInt32(table!.count - 1))
                }
            } else {
                out += Array(key.utf8) + [0]
            }
            switch value {
            case .object(let children): out += encode(children, table: &table)
            case .string(let text): out += Array(text.utf8) + [0]
            case .int(let number): out += le32(UInt32(bitPattern: number))
            }
        }
        return out + [8]
    }

    /// appinfo.vdf v29 with the given apps' "appinfo" sections.
    static func appinfo(_ apps: [(Int, [(String, KV)])]) -> Data {
        var table: [String]? = []
        var body: [UInt8] = []
        for (appID, info) in apps {
            let kv = encode([("appinfo", .object(info))], table: &table)
            let header = [UInt8](repeating: 0, count: 60)  // state, update time, token, hashes, change number
            body += le32(UInt32(appID)) + le32(UInt32(header.count + kv.count)) + header + kv
        }
        body += le32(0)
        let tableOffset = 16 + body.count
        var strings = le32(UInt32(table!.count))
        for key in table! { strings += Array(key.utf8) + [0] }
        return Data(le32(0x0756_4429) + le32(1) + le64(UInt64(tableOffset)) + body + strings)
    }

    /// packageinfo.vdf with one licence holding `appIDs`.
    static func packageinfo(_ appIDs: [Int]) -> Data {
        var none: [String]?
        let apps = appIDs.enumerated().map { (String($0.offset), KV.int(Int32($0.element))) }
        let kv = encode([("1", .object([("packageid", .int(1)), ("appids", .object(apps))]))], table: &none)
        let entry = le32(1) + [UInt8](repeating: 0, count: 20 + 4 + 8) + kv
        return Data(le32(0x0656_5528) + le32(1) + entry + le32(0xFFFF_FFFF))
    }

    static func game(_ appID: Int, _ name: String, platform: Platform = .windows, bottle: Bottle = Engine.bottle,
                     install: InstallState = .installed, size: Int64 = 1000) -> Game {
        var game = Game(appID: appID, name: name, bottle: bottle, steamRoot: bottle.url, steamExeWindowsPath: "",
                        installDir: bottle.url.appendingPathComponent("steamapps/common/\(name)", isDirectory: true),
                        sizeOnDisk: size)
        game.install = install
        game.installDirName = name
        game.platform = platform
        return game
    }

    static func main() {
        // MARK: Decision
        typealias Facts = VersionChoice.Facts
        func decide(_ facts: Facts, _ choice: GameVersion = .automatic, preferWindows: Bool = false,
                    macFailed: Bool = false) -> String {
            let (platform, reason) = VersionChoice.decide(facts, choice: choice, preferWindows: preferWindows, macFailed: macFailed)
            return "\(platform.rawValue) \(reason.rawValue)"
        }
        let mac64 = Facts(macNative: true, mac64: true)
        check(decide(Facts()) == "windows only", "no Mac version: Windows")
        check(decide(mac64) == "mac macRuns", "a 64-bit Mac version wins")
        check(decide(Facts(macNative: true, mac64: true, windowsInstalled: true)) == "mac macRuns",
              "even when the Windows version is installed")
        check(decide(Facts(macNative: true)) == "windows macTooOld", "a 32-bit (or unknown) Mac version doesn't")
        check(decide(Facts(macNative: true, macInstalled: true)) == "mac macInstalled", "unless it's the one installed")
        check(decide(Facts(macNative: true, macInstalled: true, windowsInstalled: true)) == "windows macTooOld",
              "with both installed, an old Mac version stays out")
        check(decide(mac64, preferWindows: true) == "windows windowsBetter", "a profile can prefer Windows")
        check(decide(mac64, macFailed: true) == "windows macFailed", "a Mac version that didn't start hands over")
        check(decide(mac64, .windows) == "windows chosen", "choosing Windows")
        check(decide(Facts(macNative: true), .mac) == "mac chosen", "choosing Mac beats its age")
        check(decide(mac64, .mac, preferWindows: true, macFailed: true) == "mac chosen", "choosing beats profile and health")
        check(decide(Facts(macNative: true, mac64: true, windows: false), .windows) == "mac only", "Mac-only game")

        // MARK: Catalog
        let fm = FileManager.default
        let steam = fm.temporaryDirectory.appendingPathComponent("mvt-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: steam.appendingPathComponent("appcache"), withIntermediateDirectories: true)
        func depot(_ os: String, size: String, arch: KV? = nil, language: String? = nil) -> KV {
            var config: [(String, KV)] = [("oslist", .string(os))]
            if let arch { config.append(("osarch", arch)) }
            if let language { config.append(("language", .string(language))) }
            return .object([("config", .object(config)), ("manifests", .object([("public", .object([("size", .string(size))]))]))])
        }
        func app(_ name: String, oslist: String, extended: String = "", depots: [(String, KV)] = [],
                 ufs: [(String, KV)] = []) -> [(String, KV)] {
            [("common", .object([("name", .string(name)), ("type", .string("Game")), ("oslist", .string(oslist)),
                                 ("osextended", .string(extended))])),
             ("config", .object([("installdir", .string(name))])),
             ("depots", .object(depots)),
             ("ufs", .object(ufs))]
        }
        // No Man's Sky's rules as Steam has them, plus a Windows-only rule and one in the game folder.
        let nmsCloud: [(String, KV)] = [
            ("savefiles", .object([
                ("0", .object([("root", .string("WinAppDataRoaming")), ("path", .string("HelloGames/NMS/st_{64BitSteamID}/")),
                               ("pattern", .string("*.hg"))])),
                ("1", .object([("root", .string("WinMyDocuments")), ("path", .string("Only Windows")), ("pattern", .string("*")),
                               ("platforms", .object([("1", .string("Windows"))]))])),
                ("2", .object([("root", .string("gameinstall")), ("path", .string("SNAppData/SavedGames")),
                               ("pattern", .string("*.*")), ("recursive", .int(1))])),
            ])),
            ("rootoverrides", .object([
                ("0", .object([("root", .string("WinAppDataRoaming")), ("os", .string("MacOS")), ("oscompare", .string("=")),
                               ("useinstead", .string("MacAppSupport")), ("addpath", .string(""))])),
                ("1", .object([("root", .string("gameinstall")), ("os", .string("MacOS")), ("oscompare", .string("=")),
                               ("useinstead", .string("gameinstall")), ("addpath", .string("Silicon.app/"))])),
            ])),
        ]
        let apps: [(Int, [(String, KV)])] = [
            (1001, app("Silicon", oslist: "windows,macos", extended: "macos64,macosapplesilicon,macosnotarized",
                       depots: [("10011", depot("windows", size: "3000")), ("10012", depot("macos", size: "2000"))],
                       ufs: nmsCloud)),
            (1002, app("DepotArch", oslist: "windows,macos",
                       depots: [("10021", depot("macos", size: "500", arch: .int(64))),
                                ("10022", depot("macos", size: "70", arch: .int(32), language: "hungarian")),
                                ("10023", depot("", size: "100"))])),
            (1003, app("OldPort", oslist: "windows,macos", depots: [("10031", depot("macos", size: "900", arch: .string("32")))])),
            (1004, app("WindowsOnly", oslist: "windows")),
            (1005, app("MacOnly", oslist: "macos", extended: "macos64")),
            (1006, app("NotOwned", oslist: "windows,macos", extended: "macos64")),
        ]
        try? appinfo(apps).write(to: steam.appendingPathComponent("appcache/appinfo.vdf"))
        try? packageinfo([1001, 1002, 1003, 1004, 1005]).write(to: steam.appendingPathComponent("appcache/packageinfo.vdf"))
        let catalog = Dictionary(SteamCatalog.ownedGames(steamRoot: steam).map { ($0.appID, $0) }, uniquingKeysWith: { a, _ in a })
        check(catalog.count == 5, "owned games read: \(catalog.keys.sorted())")
        let silicon = catalog[1001]
        check(silicon?.macNative == true && silicon?.mac64 == true && silicon?.macAppleSilicon == true,
              "osextended macos64/macosapplesilicon: \(String(describing: silicon))")
        check(silicon?.size == 3000 && silicon?.macSize == 2000, "sizes per OS: \(silicon?.size ?? -1) / \(silicon?.macSize ?? -1)")
        check(catalog[1002]?.mac64 == true && catalog[1002]?.macAppleSilicon == false, "a 64-bit Mac depot counts")
        check(catalog[1002]?.macSize == 600, "Mac size: 64-bit depot plus shared content: \(catalog[1002]?.macSize ?? -1)")
        check(catalog[1003]?.macNative == true && catalog[1003]?.mac64 == false, "a 32-bit Mac depot doesn't")
        check(catalog[1004]?.macNative == false, "Windows only")
        check(catalog[1005]?.windows == false && catalog[1005]?.mac64 == true, "Mac only")

        // MARK: Saves along when the version changes
        let rules = SteamCatalog.saveRules(appID: 1001, steamRoot: steam)
        check(rules == [
            SaveRule(root: "WinAppDataRoaming", path: "HelloGames/NMS/st_{64BitSteamID}/", pattern: "*.hg", recursive: false,
                     macRoot: "MacAppSupport", macAddPath: ""),
            SaveRule(root: "gameinstall", path: "SNAppData/SavedGames", pattern: "*.*", recursive: true,
                     macRoot: "gameinstall", macAddPath: "Silicon.app/"),
        ], "Steam Cloud's save rules, Windows-only ones left out: \(rules)")
        let home = steam.appendingPathComponent("home", isDirectory: true)
        var places = SaveTransfer.Places()
        places.prefix = steam.appendingPathComponent("prefix", isDirectory: true)
        places.windowsUser = "player"
        places.windowsInstall = steam.appendingPathComponent("win/Silicon", isDirectory: true)
        places.macHome = home
        places.macInstall = steam.appendingPathComponent("mac/Silicon", isDirectory: true)
        let windowsSaves = places.prefix.appendingPathComponent("drive_c/users/player/AppData/Roaming/HelloGames/NMS/st_76561198118309630")
        let macSaves = home.appendingPathComponent("Library/Application Support/HelloGames/NMS/st_76561198118309630")
        try? fm.createDirectory(at: windowsSaves.appendingPathComponent("cache"), withIntermediateDirectories: true)
        for name in ["save.hg", "save5.hg", "mf_save5.hg", "cache/feed.json", "steam_autocloud.vdf"] {
            try? Data(name.utf8).write(to: windowsSaves.appendingPathComponent(name))
        }
        let inGame = places.windowsInstall!.appendingPathComponent("SNAppData/SavedGames/slot1", isDirectory: true)
        try? fm.createDirectory(at: inGame, withIntermediateDirectories: true)
        try? Data("world".utf8).write(to: inGame.appendingPathComponent("world.bin"))
        let suite = UserDefaults(suiteName: "mvt-\(UUID().uuidString)")!
        check(SaveTransfer.beforeStart(appID: 1001, platform: .mac, rules: rules, places: places, defaults: suite) == 4,
              "the first Mac start takes the Windows saves along")
        let carried = ((try? fm.contentsOfDirectory(atPath: macSaves.path)) ?? []).sorted()
        check(carried == ["mf_save5.hg", "save.hg", "save5.hg"], "only what Steam Cloud would carry: \(carried)")
        check(fm.fileExists(atPath: places.macInstall!.appendingPathComponent("Silicon.app/SNAppData/SavedGames/slot1/world.bin").path),
              "saves in the game folder go into the app bundle, subfolders too")
        try? Data("newer on the Mac".utf8).write(to: macSaves.appendingPathComponent("save.hg"))
        try? Data("played on Windows".utf8).write(to: windowsSaves.appendingPathComponent("save9.hg"))
        check(SaveTransfer.beforeStart(appID: 1001, platform: .mac, rules: rules, places: places, defaults: suite) == 0
              && !fm.fileExists(atPath: macSaves.appendingPathComponent("save9.hg").path), "the same version again: nothing moves")
        check(SaveTransfer.beforeStart(appID: 1001, platform: .windows, rules: rules, places: places, defaults: suite) == 0
              && (try? String(contentsOf: windowsSaves.appendingPathComponent("save.hg"), encoding: .utf8)) == "save.hg",
              "a folder with saves is never overwritten")
        check(SaveTransfer.beforeStart(appID: 1001, platform: .mac, rules: rules, places: places, defaults: suite) == 0
              && (try? String(contentsOf: macSaves.appendingPathComponent("save.hg"), encoding: .utf8)) == "newer on the Mac",
              "back on the Mac, its own saves stay")
        check(SaveTransfer.resolve("HelloGames/NMS/st_{64BitSteamID}/", under: places.prefix.appendingPathComponent("drive_c/users/player/AppData/Roaming"))
              == ["HelloGames/NMS/st_76561198118309630"], "placeholders match the folder that's there")

        // MARK: Steam for Mac's library
        let steamapps = steam.appendingPathComponent("steamapps", isDirectory: true)
        try? fm.createDirectory(at: steamapps, withIntermediateDirectories: true)
        func manifest(_ appID: Int, _ name: String, flags: Int, size: Int = 0) {
            let text = """
            "AppState"
            {
            \t"appid"\t\t"\(appID)"
            \t"name"\t\t"\(name)"
            \t"StateFlags"\t\t"\(flags)"
            \t"installdir"\t\t"\(name)"
            \t"SizeOnDisk"\t\t"\(size)"
            }
            """
            try? text.write(to: steamapps.appendingPathComponent("appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)
        }
        manifest(1001, "Silicon", flags: 4, size: 2100)
        try? Engine.requestDownload(appID: 1002, name: "DepotArch", installDir: "DepotArch", steamapps: steamapps)
        manifest(2000, "MacExclusive", flags: 4, size: 10)
        let onMac = LibraryScanner.scanMac(root: steam)
        let macByID = Dictionary(onMac.map { ($0.appID, $0) }, uniquingKeysWith: { a, _ in a })
        check(onMac.count == 3 && onMac.allSatisfy { $0.platform == .mac }, "Mac library: \(onMac.map(\.appID))")
        check(macByID[1001]?.isInstalled == true && macByID[1001]?.sizeOnDisk == 2100 && macByID[1001]?.macAppleSilicon == true,
              "installed Mac version with its catalog facts")
        check(macByID[1002]?.install == .downloading(nil), "a requested download is pending: \(String(describing: macByID[1002]?.install))")

        // MARK: Merge
        var silicon1001 = game(1001, "Silicon", size: 3100)
        silicon1001.adoptMacFacts(catalog[1001]!)
        var old1003 = game(1003, "OldPort")
        old1003.adoptMacFacts(catalog[1003]!)
        var depot1002 = game(1002, "DepotArch", install: .notInstalled)
        depot1002.adoptMacFacts(catalog[1002]!)
        var macOnly1005 = game(1005, "MacOnly", install: .notInstalled)
        macOnly1005.adoptMacFacts(catalog[1005]!)
        let plain = game(1004, "WindowsOnly")
        let crossOver = Bottle(name: "Games", url: steam)
        var twice = game(1001, "Silicon", bottle: crossOver)
        twice.adoptMacFacts(catalog[1001]!)
        let windows = [silicon1001, old1003, depot1002, macOnly1005, plain, twice]

        func merged(prefer: Set<Int> = [], choices: [Int: GameVersion] = [:], failed: Set<Int> = []) -> [Game] {
            LibraryScanner.merge(windows, mac: onMac, preferWindows: prefer,
                                 choice: { choices[$0] ?? .automatic }, macFailed: { failed.contains($0) })
        }
        var list = merged()
        func entries(_ appID: Int) -> [Game] { list.filter { $0.appID == appID } }
        let nms = entries(1001)
        check(nms.count == 2, "two bottles keep two entries: \(nms.count)")
        let macEntry = nms.first { $0.platform == .mac }
        check(macEntry?.isInstalled == true && macEntry?.bottle.name == MacSteam.bottle.name, "the Mac version is used and installed")
        check(macEntry?.id == silicon1001.id, "the entry keeps its place: \(macEntry?.id ?? "-")")
        check(macEntry?.windowsLeftover == 3100, "the Windows version left behind: \(String(describing: macEntry?.windowsLeftover))")
        check(macEntry?.switchable == true && macEntry?.versionReason == .macRuns, "switchable, because it runs")
        check(nms.contains { $0.platform == .windows && $0.bottle.name == "Games" && !$0.switchable }, "the second bottle stays Windows")
        let oldPort = entries(1003).first
        check(oldPort?.platform == .windows && oldPort?.versionReason == .macTooOld, "an old Mac port stays Windows")
        let download = entries(1002).first
        check(download?.platform == .mac && download?.install == .downloading(nil), "the Mac download shows: \(String(describing: download?.install))")
        let macOnly = entries(1005).first
        check(macOnly?.platform == .mac && macOnly?.install == .notInstalled && macOnly?.switchable == false
              && macOnly?.sizeOnDisk == 0 && macOnly?.installDir.path.hasSuffix("steamapps/common/MacOnly") == true,
              "a Mac-only game downloads through Steam for Mac")
        check(entries(1004).first?.platform == .windows && entries(1004).first?.switchable == false, "Windows only stays as it was")
        check(entries(2000).first?.platform == .mac && entries(2000).first?.switchable == false, "a Mac game no Windows Steam knows is listed")
        check(list.count == 7, "one entry per game and bottle: \(list.map(\.appID))")

        list = merged(prefer: [1001])
        check(entries(1001).allSatisfy { $0.platform == .windows }
              && entries(1001).first?.versionReason == .windowsBetter, "preferWindows keeps the Windows version")
        list = merged(choices: [1001: .windows])
        check(entries(1001).first?.versionReason == .chosen && entries(1001).first?.windowsLeftover == nil, "Windows chosen")
        list = merged(choices: [1003: .mac])
        let notOnMac = entries(1003).first
        check(notOnMac?.platform == .mac && notOnMac?.install == .notInstalled && notOnMac?.sizeOnDisk == 900 && notOnMac?.listID == old1003.id,
              "Mac chosen for a game Steam for Mac hasn't got yet")
        check(list.firstIndex { $0.appID == 1003 }! < list.firstIndex { $0.appID == 1005 }!,
              "still playable through its Windows copy, it stays with the installed games")
        // Played through its installed Windows version: it stays that way while the Mac version comes.
        var downloadingMac = game(1002, "DepotArch", size: 4000)
        downloadingMac.adoptMacFacts(catalog[1002]!)
        var notYet = game(3001, "Fresh")
        notYet.adoptMacFacts(catalog[1001]!)
        let seamless = LibraryScanner.merge([downloadingMac, notYet], mac: onMac, preferWindows: [],
                                            choice: { _ in .automatic }, macFailed: { _ in false })
        let comingIn = seamless.first { $0.appID == 1002 }
        check(comingIn?.platform == .windows && comingIn?.isInstalled == true && comingIn?.macPending == .downloading(nil)
              && comingIn?.versionReason == .macRuns, "playable while its Mac version downloads: \(String(describing: comingIn?.macPending))")
        let offered = seamless.first { $0.appID == 3001 }
        check(offered?.platform == .windows && offered?.macPending == .notInstalled && offered?.switchable == true,
              "the Mac version is offered, the Windows one plays")
        let fetch = offered.map { LibraryScanner.macEntry(for: $0) }
        check(fetch?.platform == .mac && fetch?.install == .notInstalled && fetch?.listID == notYet.id
              && fetch?.installDir.path.hasSuffix("steamapps/common/Fresh") == true, "what loading the Mac version asks Steam for")
        list = merged(failed: [1001])
        check(entries(1001).first?.versionReason == .macFailed, "a failed Mac version hands over")

        // MARK: Settings
        let profile = try? JSONDecoder().decode(GameProfile.self, from: Data(#"{"name": "X", "preferWindows": true}"#.utf8))
        check(profile?.preferWindows == true, "profiles read preferWindows")
        let defaults = String(decoding: (try? JSONEncoder().encode(GameOptions())) ?? Data(), as: UTF8.self)
        check(!defaults.contains("version"), "Automatic isn't stored: \(defaults)")
        var options = GameOptions()
        options.version = .mac
        let stored = (try? JSONEncoder().encode(options)).flatMap { try? JSONDecoder().decode(GameOptions.self, from: $0) }
        check(stored?.version == .mac, "the chosen version is kept")
        let newer = try? JSONDecoder().decode(GameOptions.self, from: Data(#"{"version": "linux", "extraArgs": "-x"}"#.utf8))
        check(newer?.version == .automatic && newer?.extraArgs == "-x", "an unknown version reads as Automatic")

        let app = 990_002
        MacHealth.reset(app)
        check(!MacHealth.failed(app) && !MacHealth.confirmed(app), "nothing known at first")
        MacHealth.fail(app)
        check(MacHealth.failed(app), "a failed start is remembered")
        MacHealth.confirm(app)
        check(MacHealth.confirmed(app) && !MacHealth.failed(app), "a good start replaces it")
        MacHealth.reset(app)

        // MARK: Removing a Mac version
        let folder = steamapps.appendingPathComponent("common/Silicon", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Engine.removeGameFiles(appID: 1001, installDirName: "Silicon", steamapps: steamapps)
        check(!fm.fileExists(atPath: folder.path) && !fm.fileExists(atPath: steamapps.appendingPathComponent("appmanifest_1001.acf").path),
              "files and manifest removed")
        check(fm.fileExists(atPath: steamapps.appendingPathComponent("appmanifest_2000.acf").path), "other games stay")
        try? Engine.removeGameFiles(appID: 2000, installDirName: "..", steamapps: steamapps)
        check(fm.fileExists(atPath: steamapps.path), "an odd folder name never removes the library")

        // MARK: Download progress from Steam's content log
        let contentLog = """
        [2026-10-26 11:09:00] AppID 1001 update started : download 0/100, store 0/0, reuse 0/0, delta 0/0, stage 0/120
        [2026-10-26 11:09:30] AppID 1001 App update changed : None
        [2026-10-26 11:10:05] AppID 275850 App update changed : Running Update,Preallocating,
        [2026-10-26 11:10:12] AppID 275850 update started : download 1000/29035054496, store 0/0, reuse 0/0, delta 0/0, stage 0/32837541510
        [2026-10-26 11:10:12] AppID 275850 App update changed : Running Update,Downloading,Staging,
        [2026-10-26 11:10:52] Increasing target number of download connections to 10 (rate was 67.085, now 144.000)
        [2026-10-26 11:11:23] Current download rate: 160.000 Mbps
        [2026-10-26 11:12:23] Current download rate: 168.000 Mbps
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let run = MacSteamProgress.currentRun(appID: 275850, log: contentLog)
        check(run?.done == 1000 && run?.total == 29_035_054_496, "the running download and what it had before: \(String(describing: run))")
        check(MacSteamProgress.currentRun(appID: 1001, log: contentLog) == nil, "a finished download isn't running")
        check(MacSteamProgress.currentRun(appID: 27585, log: contentLog) == nil, "another app ID doesn't match")
        if let started = run?.started {
            let sum = MacSteamProgress.received(since: started, log: contentLog, now: started.addingTimeInterval(161))
            // 40 s ramp-up at half of 18 MB/s, 31 s at 20 MB/s, 60 s at 21 MB/s, 30 s at 21 MB/s
            let expected: Int64 = 40 * 9_000_000 + 31 * 20_000_000 + 60 * 21_000_000 + 30 * 21_000_000
            check(sum == expected, "logged rates add up: \(sum)")
        }

        // MARK: One sign-in per account
        let connectionLog = steam.appendingPathComponent("logs/connection_log.txt")
        try? fm.createDirectory(at: connectionLog.deletingLastPathComponent(), withIntermediateDirectories: true)
        func connection(_ lines: [String]) {
            try? (lines.joined(separator: "\r\n") + "\r\n").write(to: connectionLog, atomically: true, encoding: .utf8)
        }
        let signIn = [
            "[2026-10-26 10:29:43] Client version: 1792618285",
            "[2026-10-26 11:10:00] [Logging On, 4, 63] [U:1:158043902] RecvMsgClientLogOnResponse() : [U:1:158043902] 'OK'",
            "[2026-10-26 11:10:00] [Logged On, 4, 63] [U:1:158043902] RecvMsgClientLogOnResponse() : processing complete",
            "[2026-10-26 11:10:00] CClientJobGetClientUpdateHosts: received update from server",
        ]
        connection(signIn)
        check(Engine.signedIn(steamRoot: steam) && !Engine.sessionReplaced(steamRoot: steam), "signed in")
        let replaced = [
            "[2026-10-26 11:16:46] [Logged On, 4, 63] [U:1:158043902] RecvMsgClientLoggedOff('Session Replaced')",
            "[2026-10-26 11:16:47] [Logged Off, 4, 0] [U:1:158043902] ConnectionDisconnected('Disconnected By Remote Host') : 'Session Replaced'",
            "[2026-10-26 11:16:47] [Logged Off, 4, 0] [U:1:158043902] ConnectionDisconnected() not auto reconnecting due to Session Replaced",
        ]
        connection(signIn + replaced)
        check(!Engine.signedIn(steamRoot: steam) && Engine.sessionReplaced(steamRoot: steam), "signed out by the other Steam")
        connection(signIn + replaced + ["[2026-10-26 11:50:00] Client version: 1792618285"] + Array(signIn.dropFirst()))
        check(Engine.signedIn(steamRoot: steam) && !Engine.sessionReplaced(steamRoot: steam), "a fresh start signs in again")
        connection(signIn + [replaced[0]])
        check(!Engine.signedIn(steamRoot: steam), "the sign-out line itself still says Logged On")

        // tests/MacVersionTest/run.sh --progress 275850: what Nightforge reads from the real Steam for Mac.
        if let flag = CommandLine.arguments.firstIndex(of: "--progress"), let appID = Int(CommandLine.arguments[flag + 1]) {
            print("  progress of \(appID): \(MacSteamProgress.fraction(appID: appID).map { String(format: "%.1f %%", $0 * 100) } ?? "not downloading")")
        }

        // tests/MacVersionTest/run.sh --library 275850: how the real library shows a game.
        if let flag = CommandLine.arguments.firstIndex(of: "--library"), let appID = Int(CommandLine.arguments[flag + 1]) {
            let windows = LibraryScanner.scan(bottlesRoot: LibraryScanner.defaultBottlesRoot(), extraBottles: [Engine.bottle])
            let mac = LibraryScanner.scanMac()
            for entry in windows + mac where entry.appID == appID {
                print("  scanned: \(entry.bottle.name) \(entry.platform) \(entry.install) mac64=\(entry.mac64)")
            }
            for entry in LibraryScanner.merge(windows, mac: mac, preferWindows: []) where entry.appID == appID {
                print("  shown: \(entry.platform) \(entry.install) pending=\(String(describing: entry.macPending)) reason=\(String(describing: entry.versionReason))")
            }
        }

        try? fm.removeItem(at: steam)
        print(failures == 0 ? "✓ all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
