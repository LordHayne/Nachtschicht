import Foundation

/// Before a download: is there room for it, and if not, which games could make room. Nothing is
/// downloaded that would stop halfway for lack of space.
enum SpaceCheck {
    /// Room Steam needs beyond the download itself (unpacking, updates on the way).
    static let margin: Int64 = 1 << 30
    /// Played within this many days, a game isn't offered for removal.
    static let staleDays = 30
    static let candidateLimit = 8

    /// How much is missing for a download of `needed` bytes with `free` bytes free; nil when it fits
    /// (or the size isn't known).
    static func shortfall(needed: Int64, free: Int64) -> Int64? {
        guard needed > 0 else { return nil }
        let missing = needed + margin - free
        return missing > 0 ? missing : nil
    }

    /// Installed games not played for a month (or never), biggest first – what's offered to remove.
    static func candidates(_ games: [Game], except game: Game, now: Date = Date()) -> [Game] {
        let since = now.addingTimeInterval(-Double(staleDays) * 86_400)
        return games
            .filter { $0.isInstalled && $0.id != game.id && $0.sizeOnDisk > 0 && ($0.lastPlayed.map { $0 < since } ?? true) }
            .sorted { $0.sizeOnDisk > $1.sizeOnDisk }
            .prefix(candidateLimit)
            .map { $0 }
    }

    /// The first candidates that together free `shortfall` (all of them when even that isn't enough).
    static func preselect(_ candidates: [Game], shortfall: Int64) -> Set<String> {
        var picked: Set<String> = [], freed: Int64 = 0
        for game in candidates where freed < shortfall {
            picked.insert(game.id)
            freed += game.sizeOnDisk
        }
        return picked
    }

    /// The nearest folder that exists, for asking its volume about space (a game's own folder
    /// doesn't exist before it's downloaded).
    static func existingFolder(for url: URL) -> URL {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder.deleteLastPathComponent()
        }
        return folder
    }

    /// Whether two folders are on the same volume (removing a game there makes room here).
    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let one = try? existingFolder(for: a).resourceValues(forKeys: key).volumeIdentifier as? NSObject,
              let other = try? existingFolder(for: b).resourceValues(forKeys: key).volumeIdentifier as? NSObject
        else { return false }
        return one.isEqual(other)
    }
}

/// A download waiting for room: shown as a sheet with games to remove.
struct SpaceRequest: Identifiable {
    let game: Game
    let free: Int64
    let shortfall: Int64
    let candidates: [Game]
    var id: String { game.id }
}
