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
}

/// Reads the owned-games list from the binary caches Steam keeps after sign-in:
/// `appcache/packageinfo.vdf` (licenses → app IDs) and `appcache/appinfo.vdf` (name, type, depots).
/// No API key, no network: Steam has already downloaded both for its own library view.
enum SteamCatalog {
    private static var cache: (key: Date, apps: [CatalogApp])?
    private static let lock = NSLock()

    static func ownedGames(steamRoot: URL) -> [CatalogApp] {
        let appinfo = steamRoot.appendingPathComponent("appcache/appinfo.vdf")
        let packageinfo = steamRoot.appendingPathComponent("appcache/packageinfo.vdf")
        let modified = [appinfo, packageinfo]
            .compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
            .max() ?? .distantPast

        lock.lock()
        defer { lock.unlock() }
        if let cache, cache.key == modified { return cache.apps }

        guard let apps = try? Data(contentsOf: appinfo), let packages = try? Data(contentsOf: packageinfo) else { return [] }
        let owned = ownedAppIDs(Array(packages))
        let games = gameEntries(Array(apps)).filter { owned.contains($0.appID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cache = (modified, games)
        return games
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
                games.append(CatalogApp(appID: Int(appID), name: name, installDir: installDir,
                                        size: windowsSize(info["depots"]?.object),
                                        vrOnly: common["onlyvrsupport"]?.int == 1))
            }
            reader.position = end
        }
        return games
    }

    private static func windowsSize(_ depots: [String: BinaryKV]?) -> Int64 {
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
            if let os = config?["oslist"]?.string, !os.isEmpty, !os.contains("windows") { continue }
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
