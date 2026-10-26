import Foundation

/// Fixes for one game from profiles/profiles.json, built nightly from umu-protonfixes plus
/// Nightforge's own Mac profiles (scripts/build-profiles.py). Applied silently at launch.
struct GameProfile: Decodable, Equatable {
    var name: String?
    /// Graphics layer for games left on "Automatic".
    var graphics: GraphicsLayer?
    /// Appended to the game's command line.
    var arguments: [String]?
    /// DLL → load order as Wine writes it ("native,builtin", "" = disabled), for the game's programs.
    var dllOverrides: [String: String]?
    var registry: [RegistryEntry]?
    /// Windows version the game's programs see ("win7", …); the rest of the prefix keeps its own.
    var windowsVersion: String?
    /// winetricks verbs installed into the prefix before the first start.
    var winetricks: [String]?
    /// false: MetalFX upscaling misbehaves in this game, so "Automatic" leaves it off.
    var metalFX: Bool?
    /// Frame limit "Automatic" uses for this game instead of the display-based one.
    var frameLimit: Int?
    /// Vulkan games: samplers per shader stage reported to the game. MoltenVK says 16, which
    /// stops some games at start; Metal's argument buffers hold more.
    var vulkanSamplers: Int?
    /// The game's Windows version runs better than its Mac one (old OpenGL ports, say), so
    /// "Automatic" keeps to Windows even though Steam has a 64-bit Mac version.
    var preferWindows: Bool?
    /// Save folders for games Steam Cloud doesn't know the folders of (SaveTransfer).
    var saves: [SaveRule]?
    /// Anti-cheat that stops the game's Windows version on a Mac ("BattlEye", …), from
    /// AreWeAntiCheatYet; an empty list (a Mac profile) means it runs after all.
    var antiCheat: [String]?
    /// Anti-cheat that only stops online play on a Mac: it blocks games that have nothing else.
    var antiCheatOnline: [String]?
    /// Its game id on GeForce Now, NVIDIA's cloud gaming, where such a game can be streamed instead.
    var geforceNow: String?
    /// false: the game crashes when Rosetta advertises AVX/AVX2, so it starts without.
    var avx: Bool?
    /// Changes to the game's own settings files before it starts, for settings that crash it on a
    /// Mac: in `path` (relative to the game folder) `find` becomes `replace`.
    var fileEdits: [FileEdit]?

    struct FileEdit: Decodable, Equatable {
        let path: String
        let find: String
        let replace: String
    }

    struct RegistryEntry: Decodable, Equatable {
        let key: String
        let name: String?
        let type: String?
        let value: String?
    }

    private enum CodingKeys: String, CodingKey {
        case name, graphics, arguments, dllOverrides, registry, windowsVersion, winetricks, metalFX, frameLimit
        case vulkanSamplers, preferWindows, saves, antiCheat, antiCheatOnline, geforceNow, avx, fileEdits
    }

    /// {"root": "WinAppDataRoaming", "path": "7DaysToDie/Saves", "pattern": "*", "recursive": true, "mac": "MacAppSupport"}
    private struct SaveFolder: Decodable {
        let root: String
        let path: String
        var pattern: String?
        var recursive: Bool?
        let mac: String
        var macPath: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        // An unknown layer from a newer list just means "no preference" here.
        graphics = (try? container.decodeIfPresent(String.self, forKey: .graphics)).flatMap { $0.flatMap(GraphicsLayer.init(rawValue:)) }
        arguments = try? container.decodeIfPresent([String].self, forKey: .arguments)
        dllOverrides = try? container.decodeIfPresent([String: String].self, forKey: .dllOverrides)
        registry = try? container.decodeIfPresent([RegistryEntry].self, forKey: .registry)
        windowsVersion = try? container.decodeIfPresent(String.self, forKey: .windowsVersion)
        winetricks = try? container.decodeIfPresent([String].self, forKey: .winetricks)
        metalFX = try? container.decodeIfPresent(Bool.self, forKey: .metalFX)
        frameLimit = try? container.decodeIfPresent(Int.self, forKey: .frameLimit)
        vulkanSamplers = try? container.decodeIfPresent(Int.self, forKey: .vulkanSamplers)
        preferWindows = try? container.decodeIfPresent(Bool.self, forKey: .preferWindows)
        saves = (try? container.decodeIfPresent([SaveFolder].self, forKey: .saves))?.map {
            SaveRule(root: $0.root, path: $0.path, pattern: $0.pattern ?? "*", recursive: $0.recursive ?? true,
                     macRoot: $0.mac, macAddPath: $0.macPath ?? "")
        }
        antiCheat = try? container.decodeIfPresent([String].self, forKey: .antiCheat)
        antiCheatOnline = try? container.decodeIfPresent([String].self, forKey: .antiCheatOnline)
        geforceNow = try? container.decodeIfPresent(String.self, forKey: .geforceNow)
        avx = try? container.decodeIfPresent(Bool.self, forKey: .avx)
        fileEdits = try? container.decodeIfPresent([FileEdit].self, forKey: .fileEdits)
    }
}

/// A game that doesn't start on a Mac because its anti-cheat needs Windows itself: Wine can't
/// run it, and getting around it would get the player banned.
struct AntiCheatBlock: Hashable {
    let antiCheat: [String]
    /// Its GeForce Now game id, when it can be streamed there instead.
    let geforceNow: String?
    /// The anti-cheat only stops online play, so this blocks only games that are online only.
    var onlineOnly = false

    /// GeForce Now's deep link to the game's page, where it can be played
    /// (NVIDIA GeForce NOW SDK, doc/GfnSdk-Deep-Linking.md).
    var geforceNowURL: URL? {
        guard let geforceNow else { return nil }
        var link = URLComponents(string: "https://play.geforcenow.com/games")
        link?.queryItems = [
            URLQueryItem(name: "game-id", value: geforceNow),
            URLQueryItem(name: "utm_source", value: "nightforge"),
            URLQueryItem(name: "utm_campaign", value: "library"),
        ]
        return link?.url
    }
}

private struct ProfileDocument: Decodable {
    let formatVersion: Int
    let games: [String: Lenient]

    /// One odd entry shouldn't cost every other game its profile.
    struct Lenient: Decodable {
        let profile: GameProfile?
        init(from decoder: Decoder) throws { profile = try? GameProfile(from: decoder) }
    }
}

/// Keeps the profile list current: the online copy (`NightforgeProfilesURL`) once per app run,
/// else the last one fetched, else the copy bundled with the app.
actor ProfileStore {
    static let shared = ProfileStore()
    static let supportedFormat = 1

    private let remoteURL = (Bundle.main.object(forInfoDictionaryKey: "NightforgeProfilesURL") as? String)
        .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    private var cachedURL: URL { Engine.supportDir.appendingPathComponent("profiles.json") }
    private var profiles: [Int: GameProfile]?
    private var refreshed = false

    func profile(for appID: Int) async -> GameProfile? {
        if !refreshed { await refresh() }
        loadLocalIfNeeded()
        return profiles?[appID]
    }

    /// Games whose profile keeps them on the Windows version, from the list at hand: the library
    /// scan doesn't wait for the online copy, the next scan picks it up.
    func preferWindows() -> Set<Int> {
        loadLocalIfNeeded()
        return Set((profiles ?? [:]).filter { $0.value.preferWindows == true }.keys)
    }

    /// Games whose anti-cheat stops them on a Mac, from the list at hand (like `preferWindows`).
    func antiCheatBlocks() -> [Int: AntiCheatBlock] {
        loadLocalIfNeeded()
        return (profiles ?? [:]).compactMapValues { profile in
            if let antiCheat = profile.antiCheat, !antiCheat.isEmpty {
                return AntiCheatBlock(antiCheat: antiCheat, geforceNow: profile.geforceNow)
            }
            if let antiCheat = profile.antiCheatOnline, !antiCheat.isEmpty {
                return AntiCheatBlock(antiCheat: antiCheat, geforceNow: profile.geforceNow, onlineOnly: true)
            }
            return nil
        }
    }

    private func loadLocalIfNeeded() {
        guard profiles == nil else { return }
        for local in [cachedURL, Bundle.main.url(forResource: "profiles", withExtension: "json")].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: local), let decoded = decode(data) {
                profiles = decoded
                return
            }
        }
    }

    /// Fetches the online list; keeps what's there when offline or when the list is too new.
    func refresh() async {
        refreshed = true
        guard let remoteURL else { return }
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = decode(data)
        else { return }
        profiles = decoded
        try? FileManager.default.createDirectory(at: Engine.supportDir, withIntermediateDirectories: true)
        try? data.write(to: cachedURL, options: .atomic)
    }

    private func decode(_ data: Data) -> [Int: GameProfile]? {
        guard let document = try? JSONDecoder().decode(ProfileDocument.self, from: data),
              document.formatVersion <= Self.supportedFormat
        else { return nil }
        return Dictionary(uniqueKeysWithValues: document.games.compactMap { key, value in
            guard let appID = Int(key), let profile = value.profile else { return nil }
            return (appID, profile)
        })
    }
}
