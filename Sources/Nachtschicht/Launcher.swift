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

struct GameOptions: Codable, Equatable {
    var metalHUD = false
    var extraArgs = ""
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

/// Follows Steam's console log after a launch request so Nachtschicht knows whether the game really
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
            guard line.contains("AppID \(appID)") else { continue }
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

    static func launch(_ game: Game, runnerPath: String, options: GameOptions) throws {
        guard FileManager.default.isExecutableFile(atPath: runnerPath) else {
            throw LaunchError.runnerMissing(runnerPath)
        }

        let runner = URL(fileURLWithPath: runnerPath)
        var environment = game.bottle.isBuiltIn ? Engine.environment(wine: runner) : ProcessInfo.processInfo.environment
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
        if options.metalHUD {
            environment["MTL_HUD_ENABLED"] = "1"
        }

        arguments += [game.steamExeWindowsPath]
        if game.bottle.isBuiltIn { arguments += Engine.steamArguments }
        arguments += ["-silent", "-applaunch", String(game.appID)]
        arguments += splitArguments(options.extraArgs)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: runnerPath)
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
