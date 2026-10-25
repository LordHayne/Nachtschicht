import Foundation

enum AfterLaunch: String, CaseIterable, Identifiable {
    case quit, hide, stay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quit: return L10n.t("Quit launcher")
        case .hide: return L10n.t("Hide launcher")
        case .stay: return L10n.t("Keep open")
        }
    }
}

enum Prefs {
    enum Keys {
        static let bottlesRoot = "bottlesRoot"
        static let runnerPath = "runnerPath"
        static let afterLaunch = "afterLaunch"
        static let performanceHUD = "performanceHUD"
        static let gameMode = "gameMode"
        static let sharpAndSmooth = "sharpAndSmooth"
    }

    /// "Sharp & smooth": MetalFX upscaling to full Retina sharpness and an even frame rate that
    /// fits the display, for every game that doesn't choose otherwise. On by default.
    static var sharpAndSmooth: Bool {
        UserDefaults.standard.object(forKey: Keys.sharpAndSmooth) as? Bool ?? true
    }

    /// macOS Game Mode for games run by Nightforge's own Steam (see Engine.installGameBundle).
    /// On by default; the switch is there for the rare game whose sound crackles with it.
    static var gameMode: Bool {
        UserDefaults.standard.object(forKey: Keys.gameMode) as? Bool ?? true
    }

    /// FPS display in games run by Nightforge's own Steam (Metal HUD for DXMT, DXVK's for DXVK).
    static var performanceHUD: Bool {
        UserDefaults.standard.bool(forKey: Keys.performanceHUD)
    }

    static var bottlesRoot: URL {
        let stored = UserDefaults.standard.string(forKey: Keys.bottlesRoot) ?? ""
        let path = stored.isEmpty ? LibraryScanner.defaultBottlesRoot().path : (stored as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Empty setting = find CrossOver automatically.
    static var runnerPath: String {
        let stored = UserDefaults.standard.string(forKey: Keys.runnerPath) ?? ""
        return stored.isEmpty ? Launcher.detectRunner() : (stored as NSString).expandingTildeInPath
    }

    static var afterLaunch: AfterLaunch {
        AfterLaunch(rawValue: UserDefaults.standard.string(forKey: Keys.afterLaunch) ?? "") ?? .quit
    }
}

/// Which translation layer runs a game's Direct3D 10/11.
enum GraphicsLayer: String, Codable, CaseIterable, Identifiable {
    /// Nightforge's default (see Engine.defaultGraphics).
    case automatic
    /// DXMT: Direct3D straight to Metal.
    case dxmt
    /// DXVK: Direct3D → Vulkan → MoltenVK → Metal.
    case dxvk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return L10n.t("Automatic")
        case .dxmt: return "DXMT (Metal)"
        case .dxvk: return "DXVK (Vulkan)"
        }
    }
}

/// Automatic follows the global "Sharp & smooth" setting; on and off override it for one game.
enum Choice: String, Codable, CaseIterable {
    case automatic, on, off
}

struct GameOptions: Codable, Equatable {
    var metalHUD = false
    var extraArgs = ""
    var graphics = GraphicsLayer.automatic
    /// Frames per second the game is held to: nil = automatic ("Sharp & smooth"), 0 = no limit.
    var frameLimit: Int?
    /// MetalFX spatial upscaling of the game's picture (DXMT only).
    var upscaling = Choice.automatic

    static let frameLimits = [0, 30, 40, 60, 120]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case metalHUD, extraArgs, graphics, fps, metalFX
        // 0.1.4 stored these; their defaults (0, false) meant "untouched", so they read as automatic.
        case frameLimit, upscaling
    }

    // Options saved before a field existed decode with that field's default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
        extraArgs = try c.decodeIfPresent(String.self, forKey: .extraArgs) ?? ""
        graphics = try c.decodeIfPresent(GraphicsLayer.self, forKey: .graphics) ?? .automatic
        let legacyLimit = try c.decodeIfPresent(Int.self, forKey: .frameLimit) ?? 0
        frameLimit = try c.decodeIfPresent(Int.self, forKey: .fps) ?? (legacyLimit > 0 ? legacyLimit : nil)
        let legacyUpscaling = try c.decodeIfPresent(Bool.self, forKey: .upscaling) ?? false
        upscaling = try c.decodeIfPresent(Choice.self, forKey: .metalFX) ?? (legacyUpscaling ? .on : .automatic)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(metalHUD, forKey: .metalHUD)
        try c.encode(extraArgs, forKey: .extraArgs)
        try c.encode(graphics, forKey: .graphics)
        try c.encodeIfPresent(frameLimit, forKey: .fps)
        try c.encode(upscaling, forKey: .metalFX)
    }

    /// The frame limit actually used: the game's own choice, or with "Sharp & smooth" half the
    /// display's refresh rate on fast displays (60 on 120 Hz) and the refresh rate on 60 Hz ones,
    /// so every frame lasts the same number of screen refreshes.
    /// A game profile (profiles/profiles.json) can set its own automatic limit.
    func effectiveFrameLimit(displayRefreshRate: Int, profile: GameProfile? = nil) -> Int {
        if let frameLimit { return frameLimit }
        guard Prefs.sharpAndSmooth else { return 0 }
        if let fromProfile = profile?.frameLimit { return fromProfile }
        guard displayRefreshRate > 0 else { return 0 }
        return displayRefreshRate >= 100 ? displayRefreshRate / 2 : displayRefreshRate
    }

    /// A game profile can rule MetalFX out for games it doesn't suit.
    func effectiveUpscaling(profile: GameProfile? = nil) -> Bool {
        switch upscaling {
        case .on: return true
        case .off: return false
        case .automatic: return Prefs.sharpAndSmooth && profile?.metalFX != false
        }
    }
}

enum GameOptionsStore {
    private static func key(_ appID: Int) -> String { "options.\(appID)" }

    static func load(_ appID: Int) -> GameOptions {
        guard let data = UserDefaults.standard.data(forKey: key(appID)),
              let options = try? JSONDecoder().decode(GameOptions.self, from: data)
        else { return GameOptions() }
        return options
    }

    static func save(_ options: GameOptions, for appID: Int) {
        if options == GameOptions() {
            UserDefaults.standard.removeObject(forKey: key(appID))
        } else if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: key(appID))
        }
    }
}

enum LaunchError: LocalizedError {
    case runnerMissing(String)

    var errorDescription: String? {
        switch self {
        case .runnerMissing(let path):
            return L10n.t("Wine was not found at %@. Install CrossOver or enter the path to your wine binary in Settings.", path)
        }
    }
}

/// Follows Steam's console log after a launch request so Nightforge knows whether the game really
/// started, or whether Steam is waiting on a question (licence, first-time setup) in its own window.
struct LaunchWatcher {
    enum Event {
        case needsConfirmation
        /// Steam got its answer (or never needed one – it logs routine steps the same way).
        case continued
        case running
        case cancelled
        case failed
    }

    private let log: URL
    private let appID: Int
    private var offset: UInt64
    /// Steam logged the "-applaunch" request, i.e. it's alive and took it.
    private(set) var steamReceivedLaunch = false
    /// Steam was already waiting on a question for this game before the launch (e.g. an earlier
    /// attempt); the new request just queues behind it.
    private var openQuestion = false

    /// Remembers where the log ends now, so only lines written after the launch count.
    init(steamRoot: URL, appID: Int) {
        log = steamRoot.appendingPathComponent("logs/console_log.txt")
        self.appID = appID
        offset = (try? FileManager.default.attributesOfItem(atPath: log.path)[.size] as? UInt64) ?? 0

        if let handle = try? FileHandle(forReadingFrom: log) {
            try? handle.seek(toOffset: offset > 65_536 ? offset - 65_536 : 0)
            let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
            try? handle.close()
            let last = tail.split(separator: "\n").last { $0.contains("GameAction [AppID \(appID),") }
            openQuestion = last?.contains("waiting for user response") ?? false
        }
    }

    /// Newest relevant event since the last call, if any.
    mutating func poll() -> Event? {
        if openQuestion {
            openQuestion = false
            return .needsConfirmation
        }
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }  // Steam started a fresh log
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        offset += UInt64(data.count)

        var event: Event?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            if line.contains("ExecCommandLine"), line.hasSuffix("-applaunch \(appID)\"") || line.contains("-applaunch \(appID) ") {
                steamReceivedLaunch = true
            }
            guard mentionsApp(line) else { continue }
            if line.contains("Game process added") || line.contains("changed task to Completed") {
                event = .running
            } else if line.contains("waiting for user response") {
                event = .needsConfirmation
            } else if line.contains("continues with user response") {
                event = .continued
            } else if line.contains("GameAction"), line.localizedCaseInsensitiveContains("cancel") {
                event = .cancelled
            } else if line.contains("GameAction"), line.localizedCaseInsensitiveContains("failed") {
                event = .failed
            }
        }
        return event
    }

    /// "AppID 10" must not match "AppID 1000": the ID has to end there.
    private func mentionsApp(_ line: Substring) -> Bool {
        var rest = line[...]
        while let range = rest.range(of: "AppID \(appID)") {
            let next = rest[range.upperBound...].first
            if next == nil || !next!.isNumber { return true }
            rest = rest[range.upperBound...]
        }
        return false
    }
}

/// Starts a game through the Windows Steam client in its bottle – one process call, nothing kept running.
enum Launcher {
    static let crossOverCandidates = [
        "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
        NSHomeDirectory() + "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
    ]

    static func detectRunner() -> String {
        crossOverCandidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? crossOverCandidates[0]
    }

    static func launch(_ game: Game, runnerPath: String, options: GameOptions, profile: GameProfile? = nil,
                       displayRefreshRate: Int = 60) throws {
        guard FileManager.default.isExecutableFile(atPath: runnerPath) else {
            throw LaunchError.runnerMissing(runnerPath)
        }

        let runner = URL(fileURLWithPath: runnerPath)
        // If Steam isn't running yet, this call starts it, so it needs the same game settings.
        var environment = game.bottle.isBuiltIn
            ? Engine.environment(wine: runner).merging(Engine.gameEnvironment) { _, new in new }
            : ProcessInfo.processInfo.environment
        var arguments: [String] = []

        if game.bottle.isBuiltIn {
            environment["WINEDLLOVERRIDES"] = Engine.steamDLLOverrides
            Engine.installWebHelperWrapper()
        } else if runnerPath.contains("CrossOver.app") {
            arguments += ["--bottle", game.bottle.name]
        } else {
            // Plain Wine / Whisky / GPTK: the bottle is the prefix
            environment["WINEPREFIX"] = game.bottle.url.path
        }
        if game.bottle.isBuiltIn {
            Engine.writeGameConfigs(installDir: game.installDir,
                                    frameLimit: options.effectiveFrameLimit(displayRefreshRate: displayRefreshRate, profile: profile),
                                    upscaling: options.effectiveUpscaling(profile: profile),
                                    vulkanSamplers: profile?.vulkanSamplers)
            Engine.applyGameSettings(options.graphics, profile: profile, installDir: game.installDir, wine: runner)
        }
        // CrossOver bottles: the game inherits this process's environment. Nightforge's own
        // games get the HUD from the background Steam instead (Prefs.performanceHUD).
        if options.metalHUD && !game.bottle.isBuiltIn {
            environment["MTL_HUD_ENABLED"] = "1"
        }

        arguments += [game.steamExeWindowsPath]
        if game.bottle.isBuiltIn { arguments += Engine.steamArguments }
        arguments += ["-silent", "-applaunch", String(game.appID)]
        if game.bottle.isBuiltIn {
            arguments += SteamCatalog.antiCheatOffArguments(appID: game.appID, steamRoot: game.steamRoot)
            arguments += profile?.arguments ?? []
        }
        arguments += splitArguments(options.extraArgs)

        let process = Process()
        process.executableURL = game.bottle.isBuiltIn ? Engine.loader(for: runner) : runner
        if process.executableURL != runner { environment["WINELOADER"] = process.executableURL?.path }
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Splits `-foo "bar baz" -x` into ["-foo", "bar baz", "-x"].
    static func splitArguments(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch.isWhitespace && !inQuotes {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
