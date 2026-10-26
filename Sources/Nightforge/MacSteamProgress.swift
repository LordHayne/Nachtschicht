import AppKit
import Foundation

/// How far Steam for Mac is with a download. It writes the progress into the game's manifest only
/// when the download pauses or ends, and it reserves the game's whole size on disk up front, so
/// neither file says it. What Steam has received over the network does – macOS counts that per
/// process – from the moment its content log says the download (re)started.
enum MacSteamProgress {
    private struct Sample {
        let pid: pid_t
        let date: Date
        let bytesIn: Int64
    }

    private static let lock = NSLock()
    /// Nightforge's last look at Steam's counter, and per download where counting starts.
    private static var lastSample: Sample?
    private static var baselines: [String: Int64] = [:]

    /// Fraction done of the download Steam is running for `appID` right now; nil when it isn't
    /// downloading that game at the moment (queued, paused) or can't tell.
    static func fraction(appID: Int, steamRoot: URL = MacSteam.root) -> Double? {
        guard let pid = MacSteam.clientPID, let bytesIn = bytesReceived(pid: pid) else { return nil }
        let sample = Sample(pid: pid, date: Date(), bytesIn: bytesIn)
        lock.lock()
        defer {
            lastSample = sample
            lock.unlock()
        }
        let log = (try? tail(of: steamRoot.appendingPathComponent("logs/content_log.txt"))) ?? ""
        guard let run = currentRun(appID: appID, log: log) else { return nil }

        let key = "\(sample.pid)-\(appID)-\(run.started.timeIntervalSince1970)"
        let baseline: Int64
        if let known = baselines[key] {
            baseline = known
        } else if let last = lastSample, last.pid == sample.pid, last.date <= run.started {
            baseline = last.bytesIn  // Nightforge was watching when it started
        } else {
            // Started while Nightforge wasn't looking: what Steam's logged rates add up to since then.
            baseline = max(0, bytesIn - received(since: run.started, log: log, now: sample.date))
        }
        baselines[key] = baseline
        guard run.total > 0 else { return nil }
        return min(max(Double(run.done + bytesIn - baseline) / Double(run.total), 0), 0.99)
    }

    /// The latest download run of the game in Steam's content log, if it's downloading now:
    /// "AppID 275850 update started : download 0/29035054496, …" and a state with "Downloading".
    static func currentRun(appID: Int, log: String) -> (started: Date, done: Int64, total: Int64)? {
        var run: (started: Date, done: Int64, total: Int64)?
        var downloading = false
        let prefix = "AppID \(appID) "
        for line in log.split(whereSeparator: \.isNewline) {
            guard let close = line.firstIndex(of: "]") else { continue }
            let text = line[line.index(after: close)...].drop { $0 == " " }
            guard text.hasPrefix(prefix) else { continue }
            if text.contains("update started : download "),
               let date = date(line),
               let numbers = text.range(of: "download ").map({ text[$0.upperBound...].prefix { $0 != "," } }) {
                let parts = numbers.split(separator: "/").compactMap { Int64($0) }
                if parts.count == 2 { run = (date, parts[0], parts[1]) }
            } else if text.contains("App update changed :") {
                downloading = text.contains("Downloading")
            }
        }
        return downloading ? run : nil
    }

    /// Bytes Steam's logged download rates add up to between `since` and `now`: "Current download
    /// rate: 169.9 Mbps" about once a minute, and "… connections to 10 (rate was 67.1, now 138.8)"
    /// while it speeds up. The ramp-up before the first counts half.
    static func received(since: Date, log: String, now: Date) -> Int64 {
        var points: [(date: Date, bytesPerSecond: Double)] = []
        for line in log.split(whereSeparator: \.isNewline) {
            let marker = line.range(of: "Current download rate: ")
                ?? (line.contains("download connections") ? line.range(of: ", now ") : nil)
            guard let marker, let date = date(line), date >= since,
                  let mbps = Double(line[marker.upperBound...].prefix { $0.isNumber || $0 == "." })
            else { continue }
            points.append((date, mbps * 1_000_000 / 8))
        }
        guard let first = points.first, let last = points.last else { return 0 }
        var total = first.date.timeIntervalSince(since) * first.bytesPerSecond / 2
        for (a, b) in zip(points, points.dropFirst()) {
            total += b.date.timeIntervalSince(a.date) * b.bytesPerSecond
        }
        total += min(now.timeIntervalSince(last.date), 90) * last.bytesPerSecond
        return Int64(total)
    }

    /// What a process has received over the network since it started (`nettop`).
    private static func bytesReceived(pid: pid_t) -> Int64? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-J", "bytes_in", "-p", String(pid)]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        // ",bytes_in,\nsteam_osx.53069,4312550781,"
        guard let line = output.split(whereSeparator: \.isNewline).last, line.contains(".\(pid),") else { return nil }
        return line.split(separator: ",").dropFirst().first.flatMap { Int64($0) }
    }

    private static func tail(of url: URL, bytes: UInt64 = 262_144) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size > bytes ? size - bytes : 0)
        return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    /// "[2026-10-26 11:10:12] …"
    private static func date(_ line: Substring) -> Date? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        return formatter.date(from: String(line[line.index(after: line.startIndex)..<close]))
    }
}
