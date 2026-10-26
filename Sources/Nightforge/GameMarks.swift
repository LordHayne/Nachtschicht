import Foundation

/// Games the player hid from the library or pinned to Home. Kept by Steam app ID, so a game
/// keeps its mark when it changes between its Mac and Windows versions.
enum GameMarks {
    enum Kind: String {
        case hidden, pinned
    }

    private static func key(_ kind: Kind) -> String { "library.\(kind.rawValue)" }

    static func load(_ kind: Kind, from defaults: UserDefaults = .standard) -> Set<Int> {
        Set((defaults.array(forKey: key(kind)) as? [Int]) ?? [])
    }

    static func save(_ ids: Set<Int>, _ kind: Kind, to defaults: UserDefaults = .standard) {
        defaults.set(ids.sorted(), forKey: key(kind))
    }
}
