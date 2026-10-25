import Foundation

/// One way to start a game: which layer draws its Direct3D, and what's added to its command line.
struct LaunchAttempt: Equatable {
    var graphics: GraphicsLayer
    /// "-dx11" and the like, for a game that would otherwise pick Direct3D 12.
    var arguments: [String] = []

    var id: String { ([graphics.rawValue] + arguments).joined(separator: " ") }
    var label: String { ([graphics.label] + arguments).joined(separator: " ") }
    var shortLabel: String { ([graphics.shortLabel] + arguments).joined(separator: " ") }
}

/// Self-healing launches. A game left on "Automatic" gets a list of ways to start it, best first,
/// from what its files reveal (GameAnalysis). The first start with each way is watched: a game that
/// ends within its first seconds moves on to the next way, one that keeps running keeps its way
/// for good. Nightforge watches live when it can and otherwise looks at Steam's log of when the
/// game's processes started and ended, at the next launch.
enum LaunchHealth {
    /// A session this short counts as "didn't start" (crash, black window closed by the game).
    static let failureWindow: TimeInterval = 30

    /// The ways to try, in order.
    static func attempts(for analysis: GameAnalysis, profile: GameProfile?) -> [LaunchAttempt] {
        if analysis.usesD3D11 || analysis.apis.isEmpty {
            let arguments = analysis.preferD3D11Arguments
            let first = profile?.graphics ?? Engine.defaultGraphics
            let second: GraphicsLayer = first == .dxmt ? .dxvk : .dxmt
            var list = [LaunchAttempt(graphics: first, arguments: arguments), LaunchAttempt(graphics: second, arguments: arguments)]
            // Direct3D 12 through Wine is the last resort for engines that would pick it.
            if !arguments.isEmpty { list.append(LaunchAttempt(graphics: first)) }
            return list
        }
        if analysis.usesD3D9 {
            return [LaunchAttempt(graphics: .dxvk), LaunchAttempt(graphics: .wined3d)]
        }
        // Vulkan, OpenGL and Direct3D 12 have one way each; there's nothing to switch.
        return [LaunchAttempt(graphics: Engine.defaultGraphics)]
    }

    private struct State: Codable {
        /// The attempts' ids when this was saved; a different list starts over.
        var ladder: [String]
        var index = 0
        /// The current way has run past its first seconds once.
        var confirmed = false
        /// When the current, unconfirmed way was last started.
        var startedAt: Date?
    }

    private static func key(_ appID: Int) -> String { "launchHealth.\(appID)" }

    private static func load(_ appID: Int, _ attempts: [LaunchAttempt]) -> State {
        let ladder = attempts.map(\.id)
        if let data = UserDefaults.standard.data(forKey: key(appID)),
           let state = try? JSONDecoder().decode(State.self, from: data), state.ladder == ladder {
            return state
        }
        var state = State(ladder: ladder)
        // Up to 0.2: only "DXMT failed, DXVK from now on" was remembered.
        let legacy = "health.dxmtFailed.\(appID)"
        if UserDefaults.standard.bool(forKey: legacy), let dxvk = attempts.firstIndex(where: { $0.graphics == .dxvk }) {
            state.index = dxvk
        }
        UserDefaults.standard.removeObject(forKey: legacy)
        UserDefaults.standard.removeObject(forKey: "health.launch.\(appID)")
        return state
    }

    private static func save(_ appID: Int, _ state: State) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key(appID)) }
    }

    /// The way to start the game now.
    static func current(_ appID: Int, _ attempts: [LaunchAttempt]) -> (index: Int, confirmed: Bool) {
        let state = load(appID, attempts)
        return (min(state.index, max(attempts.count - 1, 0)), state.confirmed)
    }

    static func recordStart(_ appID: Int, _ attempts: [LaunchAttempt], at date: Date = Date()) {
        var state = load(appID, attempts)
        state.startedAt = date
        save(appID, state)
    }

    static func confirm(_ appID: Int, _ attempts: [LaunchAttempt]) {
        var state = load(appID, attempts)
        state.confirmed = true
        state.startedAt = nil
        save(appID, state)
    }

    /// Moves on to the next way. False when there is none: then the list starts over next time.
    static func advance(_ appID: Int, _ attempts: [LaunchAttempt]) -> Bool {
        var state = load(appID, attempts)
        state.startedAt = nil
        state.confirmed = false
        let next = state.index + 1 < attempts.count
        state.index = next ? state.index + 1 : 0
        save(appID, state)
        return next
    }

    /// Choosing a layer by hand starts over: the player wants to try for themselves.
    static func reset(_ appID: Int) {
        UserDefaults.standard.removeObject(forKey: key(appID))
        UserDefaults.standard.removeObject(forKey: "health.dxmtFailed.\(appID)")
    }

    /// Looks at how the last unconfirmed start went when Nightforge wasn't there to watch it.
    static func review(_ appID: Int, _ attempts: [LaunchAttempt], steamRoot: URL) {
        let state = load(appID, attempts)
        guard !state.confirmed, let started = state.startedAt,
              let span = sessionSpan(appID: appID, since: started, steamRoot: steamRoot)
        else { return }
        if span < failureWindow {
            _ = advance(appID, attempts)
        } else {
            confirm(appID, attempts)
        }
    }

    /// What the player should know about the way Nightforge picked, if it isn't the first.
    static func note(_ appID: Int, _ attempts: [LaunchAttempt]) -> String? {
        let (index, _) = current(appID, attempts)
        guard index > 0 else { return nil }
        return L10n.t("This game didn't start with %@, so Nightforge uses %@ for it automatically.",
                      attempts[index - 1].label, attempts[index].label)
    }

    /// How long the game's processes ran in the first session after `since`: from the first
    /// "Game process added" to the moment the last of them was removed. nil when Steam's log
    /// doesn't show a finished session (never started, still running, or log gone).
    static func sessionSpan(appID: Int, since: Date, steamRoot: URL) -> TimeInterval? {
        let logs = ["logs/console_log.previous.txt", "logs/console_log.txt"].map { steamRoot.appendingPathComponent($0) }
        let text = logs.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        // Launchers end after a few seconds and start the game itself; a process that follows
        // within this gap still belongs to the same session.
        let handOver: TimeInterval = 15
        var first: Date?
        var ended: Date?
        var running = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("[") {
            let added = line.contains("Game process added : AppID \(appID) ")
            let removed = line.contains("Game process removed: AppID \(appID) ")
            guard added || removed,
                  let close = line.firstIndex(of: "]"),
                  let time = formatter.date(from: String(line[line.index(after: line.startIndex)..<close])),
                  time >= since.addingTimeInterval(-2)
            else { continue }
            let process = line.range(of: "ProcID ").map { String(line[$0.upperBound...].prefix { $0.isNumber }) } ?? ""
            if added {
                if let ended, time.timeIntervalSince(ended) > handOver { break }  // a later session
                first = first ?? time
                ended = nil
                running.insert(process)
            } else if first != nil {
                running.remove(process)
                if running.isEmpty { ended = time }
            }
        }
        guard let first, let ended, running.isEmpty else { return nil }
        return ended.timeIntervalSince(first)
    }
}

/// What Nightforge found out about a game by itself, beyond the profile list: runtimes its
/// programs turned out to need, and where its last start begins in GameLog.
enum LearnedFixes {
    private static func winetricksKey(_ appID: Int) -> String { "learned.winetricks.\(appID)" }
    private static func markKey(_ appID: Int) -> String { "learned.logMark.\(appID)" }

    static func winetricks(_ appID: Int) -> [String] {
        UserDefaults.standard.stringArray(forKey: winetricksKey(appID)) ?? []
    }

    static func addWinetricks(_ verbs: [String], for appID: Int) {
        let known = winetricks(appID)
        UserDefaults.standard.set(known + verbs.filter { !known.contains($0) }, forKey: winetricksKey(appID))
    }

    static func setLastLaunch(_ appID: Int, logMark: UInt64) {
        UserDefaults.standard.set(String(logMark), forKey: markKey(appID))
    }

    static func lastLaunchMark(_ appID: Int) -> UInt64? {
        UserDefaults.standard.string(forKey: markKey(appID)).flatMap(UInt64.init)
    }
}
