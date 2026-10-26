import Foundation

/// Where the main window is: Home (what you play) → Library (every game) → one game's page.
/// Back (Esc, B) always goes one level up, to where the page was opened from.
enum Route: Equatable {
    case home, library
    case detail(gameID: String, from: Level)

    enum Level: Equatable { case home, library }

    /// The section the top bar shows: a game's page belongs to where it was opened from.
    var level: Level {
        switch self {
        case .home: return .home
        case .library: return .library
        case .detail(_, let from): return from
        }
    }

    var isDetail: Bool {
        if case .detail = self { return true }
        return false
    }
}

/// Home's rail: only what you're likely to play next, so it stays short with hundreds of games.
/// Everything else is one step away in the library (the rail's last tile).
enum HomeRail {
    static let limit = 12

    /// Indices into `games`: downloads first, then installed games, the ones played last first
    /// (never played after them, by name).
    static func pick(_ games: [Game]) -> [Int] {
        let candidates = games.indices.filter { index in
            switch games[index].install {
            case .installed, .downloading: return true
            case .notInstalled, .inStore: return false
            }
        }
        func downloading(_ game: Game) -> Bool {
            if case .downloading = game.install { return true }
            return false
        }
        let sorted = candidates.sorted { a, b in
            let ga = games[a], gb = games[b]
            if downloading(ga) != downloading(gb) { return downloading(ga) }
            switch (ga.lastPlayed, gb.lastPlayed) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return ga.name.localizedStandardCompare(gb.name) == .orderedAscending
            }
        }
        return Array(sorted.prefix(limit))
    }
}
