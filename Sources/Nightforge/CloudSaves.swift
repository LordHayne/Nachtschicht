import Foundation

/// Whether a game's save has reached the Steam Cloud after a session, from Steam's own record of it
/// (userdata/<account>/<app ID>/remotecache.vdf: one entry per cloud file, `syncstate` 1 when it's
/// in step with the cloud). Only said once Steam has rewritten that record after the game ended.
enum CloudSaves {
    enum State: Equatable {
        /// No cloud record for the game: its saves stay on this Mac.
        case noCloud
        /// Steam hasn't confirmed the files since the game ended.
        case syncing
        /// Every file is in step with the cloud, recorded after the game ended.
        case synced
    }

    /// The game's cloud record, from the account folder that touched it last.
    static func record(appID: Int, steamRoot: URL) -> URL? {
        let userdata = steamRoot.appendingPathComponent("userdata", isDirectory: true)
        let accounts = (try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)) ?? []
        return accounts
            .map { $0.appendingPathComponent("\(appID)/remotecache.vdf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max { modified($0) < modified($1) }
    }

    static func state(appID: Int, steamRoot: URL, endedAt: Date) -> State {
        guard let record = record(appID: appID, steamRoot: steamRoot),
              let cache = VDF.parse(contentsOf: record)?["\(appID)"] else { return .noCloud }
        return state(of: cache, recordedAt: modified(record), endedAt: endedAt)
    }

    /// `cache`: the parsed record; its files are the entries that have a `syncstate`.
    static func state(of cache: VDF, recordedAt: Date, endedAt: Date) -> State {
        let files = (cache.object ?? [:]).values.compactMap { $0["syncstate"]?.string }
        guard !files.isEmpty else { return .noCloud }
        return recordedAt >= endedAt && files.allSatisfy { $0 == "1" } ? .synced : .syncing
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
