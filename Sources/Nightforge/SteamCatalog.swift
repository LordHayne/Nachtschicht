import Foundation

/// A game the signed-in Steam account owns, installed or not.
struct CatalogApp: Hashable {
    let appID: Int
    let name: String
    let installDir: String
    /// Windows download size of the default (English) depots, 0 if Steam doesn't say.
    let size: Int64
    /// Steam marks it as playable only with a VR headset.
    var vrOnly = false
    /// Steam also has a macOS version of it.
    var macNative = false
    /// That Mac version is 64-bit, so it still runs: macOS dropped 32-bit apps with Catalina.
    var mac64 = false
    /// It's built for Apple silicon, not only for Intel Macs (which Rosetta stands in for).
    var macAppleSilicon = false
    /// Download size of the Mac version, 0 if Steam doesn't say.
    var macSize: Int64 = 0
    /// Steam has a Windows version (nearly always; a few games are Mac or Linux only).
    var windows = true
}

/// One Steam Cloud save location of a game: a folder under a Windows root ("WinAppDataRoaming",
/// "gameinstall", …) holding files that match `pattern`, and where Steam puts it on macOS.
struct SaveRule: Equatable {
    let root: String
    /// May hold Steam's placeholders, e.g. "HelloGames/NMS/st_{64BitSteamID}/".
    let path: String
    let pattern: String
    let recursive: Bool
    /// The macOS root ("MacAppSupport", …) and what goes in front of `path` there; nil: no Mac folder.
    let macRoot: String?
    let macAddPath: String
}

/// Reads the owned-games list from the binary caches Steam keeps after sign-in:
/// `appcache/packageinfo.vdf` (licenses → app IDs) and `appcache/appinfo.vdf` (name, type, depots).
/// No API key, no network: Steam has already downloaded both for its own library view.
enum SteamCatalog {
    /// Per Steam install, keyed by when its catalog files last changed.
    private static var cache: [String: (modified: Date, apps: [CatalogApp])] = [:]
    private static let lock = NSLock()

    static func ownedGames(steamRoot: URL) -> [CatalogApp] {
        let appinfo = steamRoot.appendingPathComponent("appcache/appinfo.vdf")
        let packageinfo = steamRoot.appendingPathComponent("appcache/packageinfo.vdf")
        let modified = [appinfo, packageinfo]
            .compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
            .max() ?? .distantPast

        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[steamRoot.path], cached.modified == modified { return cached.apps }

        guard let apps = try? Data(contentsOf: appinfo), let packages = try? Data(contentsOf: packageinfo) else { return [] }
        let owned = ownedAppIDs(Array(packages))
        let games = gameEntries(Array(apps)).filter { owned.contains($0.appID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cache[steamRoot.path] = (modified, games)
        return games
    }

    // MARK: - Launch options

    /// Easy Anti-Cheat and BattlEye don't run under Wine on a Mac, so a game that offers a Windows
    /// launch option without them (7 Days to Die: "Launch game without EAC") should use it. Returns
    /// what that option adds to the default one; Steam appends extra -applaunch arguments to the
    /// default option, which gives the same command line. Empty when there's no such option.
    static func antiCheatOffArguments(appID: Int, steamRoot: URL) -> [String] {
        let windows = windowsLaunchOptions(appID: appID, steamRoot: steamRoot)
        guard let standard = windows.first else { return [] }

        func words(_ option: [String: BinaryKV]) -> [String] {
            (option["arguments"]?.string ?? "").split(separator: " ").map(String.init)
        }
        let markers = ["-noeac", "-forceeac off", "-nobattleye", "-noanticheat", "-no-anticheat"]
        let candidate = windows.dropFirst().first { option in
            let arguments = (option["arguments"]?.string ?? "").lowercased()
            let description = (option["description"]?.string ?? "").lowercased()
            let mentionsAntiCheat = ["eac", "anti-cheat", "anticheat", "battleye"].contains { description.contains($0) }
            let saysWithout = ["without", "no eac", "no anti", "no battleye", "disable", "ohne"].contains { description.contains($0) }
            return markers.contains { arguments.contains($0) } || (mentionsAntiCheat && saysWithout)
        }
        guard let candidate,
              candidate["executable"]?.string?.lowercased() == standard["executable"]?.string?.lowercased()
        else { return [] }
        let base = words(standard)
        let extra = words(candidate)
        guard extra.starts(with: base) else {
            return extra.filter { !base.contains($0) }
        }
        return Array(extra.dropFirst(base.count))
    }

    /// The program Steam starts with the game's default Windows launch option, relative to the
    /// game folder ("Binaries\NMS.exe"); nil when Steam doesn't say.
    static func launchExecutable(appID: Int, steamRoot: URL) -> String? {
        windowsLaunchOptions(appID: appID, steamRoot: steamRoot).first?["executable"]?.string
    }

    /// Where Steam Cloud finds a game's saves (appinfo ufs/savefiles), with the macOS folder each
    /// Windows one maps to (ufs/rootoverrides). Rules only for other systems are left out.
    static func saveRules(appID: Int, steamRoot: URL) -> [SaveRule] {
        guard let bytes = try? Data(contentsOf: steamRoot.appendingPathComponent("appcache/appinfo.vdf")),
              let ufs = appInfo(Array(bytes), appID: appID)?["ufs"]?.object
        else { return [] }
        let overrides = (ufs["rootoverrides"]?.object ?? [:]).values.compactMap(\.object)
            .filter { ($0["os"]?.string ?? "").lowercased() == "macos" && $0["pathtransforms"] == nil }
        return (ufs["savefiles"]?.object ?? [:]).sorted { $0.key < $1.key }.compactMap { _, value in
            guard let rule = value.object, let root = rule["root"]?.string else { return nil }
            let platforms = (rule["platforms"]?.object ?? [:]).values.compactMap { $0.string?.lowercased() }
            if !platforms.isEmpty && !platforms.contains("all") && !(platforms.contains("windows") && platforms.contains("macos")) {
                return nil
            }
            let mac = overrides.first { $0["root"]?.string?.lowercased() == root.lowercased() }
            return SaveRule(root: root, path: rule["path"]?.string ?? "", pattern: rule["pattern"]?.string ?? "*",
                            recursive: rule["recursive"]?.int == 1,
                            macRoot: mac?["useinstead"]?.string ?? (root.lowercased() == "gameinstall" ? root : nil),
                            macAddPath: mac?["addpath"]?.string ?? "")
        }
    }

    /// The game's launch options that apply to Windows, in Steam's order.
    private static func windowsLaunchOptions(appID: Int, steamRoot: URL) -> [[String: BinaryKV]] {
        guard let bytes = try? Data(contentsOf: steamRoot.appendingPathComponent("appcache/appinfo.vdf")),
              let info = appInfo(Array(bytes), appID: appID),
              let launch = info["config"]?.object?["launch"]?.object
        else { return [] }
        return launch
            .compactMap { key, value -> (index: Int, option: [String: BinaryKV])? in
                guard let index = Int(key), let option = value.object else { return nil }
                let os = option["config"]?.object?["oslist"]?.string ?? ""
                return os.isEmpty || os.contains("windows") ? (index, option) : nil
            }
            .sorted { $0.index < $1.index }
            .map(\.option)
    }

    /// The "appinfo" section of one app in appinfo.vdf.
    private static func appInfo(_ bytes: [UInt8], appID wanted: Int) -> [String: BinaryKV]? {
        var reader = ByteReader(bytes)
        guard let magic = reader.u32(), reader.u32() != nil else { return nil }
        var strings: [String]?
        if magic == 0x0756_4429 {
            guard let tableOffset = reader.i64(), tableOffset > 0, Int(tableOffset) < bytes.count else { return nil }
            var table = ByteReader(bytes, at: Int(tableOffset))
            let count = table.u32() ?? 0
            strings = (0..<count).compactMap { _ in table.cString() }
        } else if magic != 0x0756_4428 && magic != 0x0756_4427 {
            return nil
        }
        let headerSkip = 4 + 4 + 8 + 20 + 4 + (magic >= 0x0756_4428 ? 20 : 0)
        while let appID = reader.u32(), appID != 0, let size = reader.u32() {
            let end = reader.position + Int(size)
            if appID == wanted {
                reader.skip(headerSkip)
                return BinaryKV.parse(&reader, strings: strings)?["appinfo"]?.object
            }
            reader.position = end
        }
        return nil
    }

    // MARK: - packageinfo.vdf

    private static func ownedAppIDs(_ bytes: [UInt8]) -> Set<Int> {
        var reader = ByteReader(bytes)
        guard let magic = reader.u32(), reader.u32() != nil else { return [] }
        let hasToken = magic >= 0x0656_5528
        var owned = Set<Int>()

        while let packageID = reader.u32(), packageID != 0xFFFF_FFFF {
            reader.skip(20 + 4 + (hasToken ? 8 : 0))  // sha1, change number, PICS token
            guard case .object(let root)? = BinaryKV.parse(&reader, strings: nil) else { break }
            for case .object(let package) in root.values {
                guard case .object(let appIDs)? = package["appids"] else { continue }
                for value in appIDs.values {
                    if let id = value.int { owned.insert(id) }
                }
            }
        }
        return owned
    }

    // MARK: - appinfo.vdf

    private static func gameEntries(_ bytes: [UInt8]) -> [CatalogApp] {
        var reader = ByteReader(bytes)
        guard let magic = reader.u32(), reader.u32() != nil else { return [] }
        // v29 keeps key names in a string table at the end of the file.
        var strings: [String]?
        if magic == 0x0756_4429 {
            guard let tableOffset = reader.i64(), tableOffset > 0, Int(tableOffset) < bytes.count else { return [] }
            var table = ByteReader(bytes, at: Int(tableOffset))
            let count = table.u32() ?? 0
            strings = (0..<count).compactMap { _ in table.cString() }
        } else if magic != 0x0756_4428 && magic != 0x0756_4427 {
            return []
        }
        let headerSkip = 4 + 4 + 8 + 20 + 4 + (magic >= 0x0756_4428 ? 20 : 0)

        var games: [CatalogApp] = []
        while let appID = reader.u32(), appID != 0, let size = reader.u32() {
            let end = reader.position + Int(size)
            reader.skip(headerSkip)
            if case .object(let root)? = BinaryKV.parse(&reader, strings: strings),
               let info = root["appinfo"]?.object,
               let common = info["common"]?.object,
               common["type"]?.string?.lowercased() == "game",
               let name = common["name"]?.string?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                let installDir = info["config"]?.object?["installdir"]?.string ?? name
                let oslist = common["oslist"]?.string ?? ""
                let depots = info["depots"]?.object
                var game = CatalogApp(appID: Int(appID), name: name, installDir: installDir,
                                      size: downloadSize(depots, os: "windows"),
                                      vrOnly: common["onlyvrsupport"]?.int == 1,
                                      macNative: oslist.contains("macos"),
                                      windows: oslist.isEmpty || oslist.contains("windows"))
                if game.macNative {
                    (game.mac64, game.macAppleSilicon) = macBuild(common: common, depots: depots,
                                                                  launch: info["config"]?.object?["launch"]?.object)
                    game.macSize = downloadSize(depots, os: "macos")
                }
                games.append(game)
            }
            reader.position = end
        }
        return games
    }

    /// Whether the Mac version still runs on current macOS. Valve marks 64-bit Mac builds with
    /// "macos64" in common/osextended (Apple silicon ones also with "macosapplesilicon"); some
    /// entries only say it per depot or launch option (osarch 64). Unknown counts as 32-bit.
    private static func macBuild(common: [String: BinaryKV], depots: [String: BinaryKV]?,
                                 launch: [String: BinaryKV]?) -> (is64: Bool, appleSilicon: Bool) {
        let extended = (common["osextended"]?.string ?? "").lowercased()
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let appleSilicon = extended.contains("macosapplesilicon")
        if appleSilicon || extended.contains("macos64") { return (true, appleSilicon) }
        let configs = (depots ?? [:]).values.compactMap { $0.object?["config"]?.object }
            + (launch ?? [:]).values.compactMap { $0.object?["config"]?.object }
        let declares64 = configs.contains { ($0["oslist"]?.string ?? "").contains("macos") && $0["osarch"]?.string == "64" }
        return (declares64, false)
    }

    /// Download size of the default (English) depots for one OS ("windows", "macos").
    private static func downloadSize(_ depots: [String: BinaryKV]?, os: String) -> Int64 {
        var total: Int64 = 0
        for (key, value) in depots ?? [:] where Int(key) != nil {
            guard let depot = value.object else { continue }
            // DLC content, shared redistributables and optional extras aren't part of the base download.
            if depot["dlcappid"] != nil || depot["sharedinstall"] != nil || depot["depotfromapp"] != nil { continue }
            let config = depot["config"]?.object
            if config?["optionaldlc"] != nil || config?["lowviolence"]?.int == 1 { continue }
            if let arch = config?["osarch"]?.string, arch == "32", depots?.values.contains(where: {
                $0.object?["config"]?.object?["osarch"]?.string == "64"
            }) == true { continue }
            if let list = config?["oslist"]?.string, !list.isEmpty, !list.contains(os) { continue }
            if let language = config?["language"]?.string, !language.isEmpty, language != "english" { continue }
            let manifest = depot["manifests"]?.object?["public"]
            let size = manifest?.object?["size"]?.string.flatMap { Int64($0) } ?? manifest?.object?["size"]?.int.map(Int64.init)
            total += size ?? 0
        }
        return total
    }
}

/// Valve's binary KeyValues as used in appinfo/packageinfo.
private indirect enum BinaryKV {
    case object([String: BinaryKV])
    case string(String)
    case number(Int64)

    var object: [String: BinaryKV]? { if case .object(let o) = self { return o } else { return nil } }
    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .object: return nil
        }
    }
    var int: Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        case .object: return nil
        }
    }

    subscript(key: String) -> BinaryKV? { object?[key] }

    /// Parses one object body (until its 0x08 terminator). Keys are lowercased.
    static func parse(_ reader: inout ByteReader, strings: [String]?) -> BinaryKV? {
        var dict: [String: BinaryKV] = [:]
        while let type = reader.u8() {
            if type == 0x08 { return .object(dict) }
            let key: String?
            if let strings {
                key = reader.u32().flatMap { Int($0) < strings.count ? strings[Int($0)] : nil }
            } else {
                key = reader.cString()
            }
            guard let name = key?.lowercased() else { return nil }

            switch type {
            case 0x00: guard let child = parse(&reader, strings: strings) else { return nil }; dict[name] = child
            case 0x01: guard let s = reader.cString() else { return nil }; dict[name] = .string(s)
            case 0x02: guard let v = reader.u32() else { return nil }; dict[name] = .number(Int64(Int32(bitPattern: v)))
            case 0x03: reader.skip(4)  // float, not needed
            case 0x07: guard let v = reader.i64() else { return nil }; dict[name] = .number(v)
            case 0x0A: guard let v = reader.i64() else { return nil }; dict[name] = .number(v)
            default: return nil
            }
        }
        return nil
    }
}

private struct ByteReader {
    let bytes: [UInt8]
    var position: Int

    init(_ bytes: [UInt8], at position: Int = 0) {
        self.bytes = bytes
        self.position = position
    }

    mutating func skip(_ count: Int) { position += count }

    mutating func u8() -> UInt8? {
        guard position < bytes.count else { return nil }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func u32() -> UInt32? {
        guard position + 4 <= bytes.count else { return nil }
        defer { position += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[position + $1]) << (8 * $1) }
    }

    mutating func i64() -> Int64? {
        guard position + 8 <= bytes.count else { return nil }
        defer { position += 8 }
        let raw = (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[position + $1]) << (8 * UInt64($1)) }
        return Int64(bitPattern: raw)
    }

    mutating func cString() -> String? {
        guard let end = bytes[position...].firstIndex(of: 0) else { return nil }
        defer { position = end + 1 }
        return String(decoding: bytes[position..<end], as: UTF8.self)
    }
}
