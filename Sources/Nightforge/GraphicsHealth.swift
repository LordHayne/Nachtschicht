import Foundation

/// Self-healing graphics: a game left on "Automatic" that doesn't survive its first seconds with
/// DXMT gets DXVK from then on. Nightforge usually quits once a game runs, so the check happens at
/// the next launch, from Steam's own log of when the game's processes started and ended.
enum GraphicsHealth {
    /// A session this short counts as "didn't start" (crash, black window closed by the game).
    static let failureWindow: TimeInterval = 30

    private static func launchKey(_ appID: Int) -> String { "health.launch.\(appID)" }
    private static func failedKey(_ appID: Int) -> String { "health.dxmtFailed.\(appID)" }

    /// DXMT didn't work for this game; "Automatic" means DXVK for it now.
    static func dxmtFailed(_ appID: Int) -> Bool {
        UserDefaults.standard.bool(forKey: failedKey(appID))
    }

    /// Choosing a layer by hand starts over: the player wants to try for themselves.
    static func reset(_ appID: Int) {
        UserDefaults.standard.removeObject(forKey: failedKey(appID))
        UserDefaults.standard.removeObject(forKey: launchKey(appID))
    }

    /// Remembers that the game is being started with DXMT now.
    static func recordDXMTLaunch(_ appID: Int, at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: launchKey(appID))
    }

    /// Looks at how the last DXMT start went. Returns true when it just now concluded that DXMT
    /// failed (so the caller can tell the player once).
    static func reviewLastDXMTLaunch(_ appID: Int, steamRoot: URL) -> Bool {
        let defaults = UserDefaults.standard
        guard !dxmtFailed(appID), let started = defaults.object(forKey: launchKey(appID)) as? Double else { return false }
        defaults.removeObject(forKey: launchKey(appID))
        let since = Date(timeIntervalSince1970: started)
        guard let span = sessionSpan(appID: appID, since: since, steamRoot: steamRoot),
              span < failureWindow
        else { return false }
        defaults.set(true, forKey: failedKey(appID))
        return true
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
        for line in text.split(separator: "\n") where line.hasPrefix("[") {
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
