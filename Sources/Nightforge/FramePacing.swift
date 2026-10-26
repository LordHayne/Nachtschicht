import Foundation

/// The frame limit a game holds on this Mac. "Sharp & smooth" starts every game at an even share of
/// the display's refresh rate (60 on 120 Hz). A game that can't keep that up stutters, while a
/// lower even share it does hold (40 on 120 Hz: every frame lasts three refreshes) looks smooth.
/// DXMT (engine/patches/dxmt-0.80-frame-log.patch) and Nightforge's Vulkan layer write the frame
/// rate to wine.log; at the game's next start Nightforge reads its last session and moves the
/// automatic limit down when it didn't hold. After a few sessions that held, it tries the next
/// higher limit again – less often each time that fails.
enum FramePacing {
    /// What the measurements depend on; a change starts over.
    struct Context: Codable, Equatable {
        var refreshRate: Int
        var upscaling: Bool
        /// The layer the game draws through: DXMT and D3DMetal hold very different rates.
        var graphics: GraphicsLayer?
    }

    struct State: Codable, Equatable {
        var context: Context
        /// The learned limit; nil = the automatic default.
        var limit: Int?
        /// Sessions in a row that held `limit`.
        var heldSessions = 0
        /// How many of those before trying the next higher limit.
        var waitBeforeTrying = 3
        /// `limit` is a try of a higher limit.
        var trying = false
        /// The session started last: where its part of the log begins, and its limit (nil when the
        /// player chose one, which says nothing about what the game holds).
        var mark: UInt64?
        var ranWith: Int?
    }

    /// The automatic frame limit for a start, and whether it's Nightforge's to learn (nothing
    /// chosen by the player or a profile).
    static func automaticLimit(appID: Int, options: GameOptions, profile: GameProfile?,
                               refreshRate: Int) -> (limit: Int, learning: Bool) {
        let standard = options.effectiveFrameLimit(displayRefreshRate: refreshRate, profile: profile)
        guard options.frameLimit == nil, Prefs.sharpAndSmooth, profile?.frameLimit == nil, standard > 0 else {
            return (standard, false)
        }
        let context = Context(refreshRate: refreshRate, upscaling: options.effectiveUpscaling(profile: profile),
                              graphics: options.graphics)
        guard let state = load(appID), state.context == context, let learned = state.limit else { return (standard, true) }
        return (min(learned, standard), true)
    }

    /// Remembers a start, so its session can be read at the next one.
    static func recordStart(appID: Int, options: GameOptions, profile: GameProfile?, refreshRate: Int,
                            logMark: UInt64, limit: Int, learning: Bool) {
        let context = Context(refreshRate: refreshRate, upscaling: options.effectiveUpscaling(profile: profile),
                              graphics: options.graphics)
        var state = load(appID).flatMap { $0.context == context ? $0 : nil } ?? State(context: context)
        state.mark = logMark
        state.ranWith = learning ? limit : nil
        save(appID, state)
    }

    /// Reads the game's last session from the log and learns from it (once per session).
    static func learn(appID: Int, installDir: URL) {
        guard var state = load(appID), let mark = state.mark else { return }
        let rates = rates(in: GameLog.text(since: mark), programs: Set(Engine.executables(in: installDir)))
        state = next(state, rates: rates, standard: standardLimit(state.context.refreshRate))
        state.mark = nil
        save(appID, state)
    }

    /// The decision after a session with these frame rates (one per minute of steady play).
    static func next(_ state: State, rates: [Double], standard: Int) -> State {
        var state = state
        // A few minutes of play at least: menus and loading alone say little.
        guard rates.count >= 3, let ranWith = state.ranWith, ranWith > 0 else { return state }
        let sorted = rates.sorted()
        let low = sorted[sorted.count / 4]  // what the game kept up three quarters of the time
        let limits = candidates(refreshRate: state.context.refreshRate, upTo: standard)
        if low < Double(ranWith) * 0.95 {
            if state.trying { state.waitBeforeTrying *= 2 }  // the higher limit failed again
            let lower = limits.first { Double($0) <= low * 0.97 } ?? limits.last ?? ranWith
            state.limit = min(lower, ranWith) == standard ? nil : min(lower, ranWith)
            state.heldSessions = 0
            state.trying = false
            return state
        }
        if state.trying { state.waitBeforeTrying = 3 }
        state.trying = false
        state.heldSessions += 1
        if let limit = state.limit, state.heldSessions >= state.waitBeforeTrying,
           let higher = limits.last(where: { $0 > limit }) {
            state.limit = higher == standard ? nil : higher
            state.trying = true
            state.heldSessions = 0
        }
        return state
    }

    /// Even shares of the refresh rate down to 30 FPS, highest first, never above `upTo`
    /// (120 Hz, up to 60: 60, 40, 30).
    static func candidates(refreshRate: Int, upTo standard: Int) -> [Int] {
        var limits = (1...8).filter { refreshRate % $0 == 0 }.map { refreshRate / $0 }
            .filter { $0 >= 30 && $0 <= standard }
        if !limits.contains(standard) { limits.insert(standard, at: 0) }
        return limits.sorted(by: >)
    }

    /// "Sharp & smooth" without a profile (GameOptions.effectiveFrameLimit).
    private static func standardLimit(_ refreshRate: Int) -> Int {
        refreshRate >= 100 ? refreshRate / 2 : refreshRate
    }

    /// Frame rates of full-minute periods from the given programs' lines:
    /// "[nightforge-dxmt] Game: 58.2 FPS over 60 s, …" (DXMT names the program without ".exe").
    static func rates(in text: String, programs: Set<String>) -> [Double] {
        let names = Set(programs.map(baseName))
        var rates: [Double] = []
        for line in text.split(whereSeparator: \.isNewline) where line.contains("[nightforge-") {
            guard let tag = line.range(of: "] "), let colon = line.range(of: ": ", range: tag.upperBound..<line.endIndex),
                  names.contains(baseName(String(line[tag.upperBound..<colon.lowerBound])))
            else { continue }
            let fields = line[colon.upperBound...].split(separator: " ")
            guard fields.count >= 5, fields[1] == "FPS", fields[2] == "over",
                  let fps = Double(fields[0]), let seconds = Double(fields[3]), seconds >= 50
            else { continue }
            rates.append(fps)
        }
        return rates
    }

    private static func baseName(_ program: String) -> String {
        let lower = program.lowercased()
        return lower.hasSuffix(".exe") ? String(lower.dropLast(4)) : lower
    }

    private static func key(_ appID: Int) -> String { "framePacing.\(appID)" }

    private static func load(_ appID: Int) -> State? {
        UserDefaults.standard.data(forKey: key(appID)).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
    }

    private static func save(_ appID: Int, _ state: State) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key(appID)) }
    }
}
