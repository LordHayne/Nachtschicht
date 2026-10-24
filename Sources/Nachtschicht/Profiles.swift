import Foundation

/// Fixes for one game from profiles/profiles.json, built nightly from umu-protonfixes plus
/// Nachtschicht's own Mac profiles (scripts/build-profiles.py). Applied silently at launch.
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

    struct RegistryEntry: Decodable, Equatable {
        let key: String
        let name: String?
        let type: String?
        let value: String?
    }

    private enum CodingKeys: String, CodingKey {
        case name, graphics, arguments, dllOverrides, registry, windowsVersion, winetricks
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

/// Keeps the profile list current: the online copy (`NachtschichtProfilesURL`) once per app run,
/// else the last one fetched, else the copy bundled with the app.
actor ProfileStore {
    static let shared = ProfileStore()
    static let supportedFormat = 1

    private let remoteURL = (Bundle.main.object(forInfoDictionaryKey: "NachtschichtProfilesURL") as? String)
        .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    private var cachedURL: URL { Engine.supportDir.appendingPathComponent("profiles.json") }
    private var profiles: [Int: GameProfile]?
    private var refreshed = false

    func profile(for appID: Int) async -> GameProfile? {
        if !refreshed { await refresh() }
        if profiles == nil {
            for local in [cachedURL, Bundle.main.url(forResource: "profiles", withExtension: "json")].compactMap({ $0 }) {
                if let data = try? Data(contentsOf: local), let decoded = decode(data) {
                    profiles = decoded
                    break
                }
            }
        }
        return profiles?[appID]
    }

    /// Fetches the online list; keeps what's there when offline or when the list is too new.
    func refresh() async {
        refreshed = true
        guard let remoteURL else { return }
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 15
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
