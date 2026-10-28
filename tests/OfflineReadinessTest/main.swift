// Checks OfflineReadiness: what stops a game from playing offline, in order, and how a remembered
// Steam account is read from loginusers.vdf: tests/OfflineReadinessTest/run.sh
import Foundation

@main
struct OfflineReadinessTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        var game = Game(appID: 570, name: "Game", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.lastPlayed = Date()
        check(OfflineReadiness.of(game, analysis: nil, accountRemembered: true) == .ready, "played, nothing online: ready")
        check(OfflineReadiness.of(game, analysis: nil, accountRemembered: false) == .signInRemembered, "no remembered account: not yet")
        var update = game
        update.pendingUpdate = 0
        check(OfflineReadiness.of(update, analysis: nil, accountRemembered: true) == .updateFirst, "an update waits: update first")
        var fresh = game
        fresh.lastPlayed = nil
        check(OfflineReadiness.of(fresh, analysis: nil, accountRemembered: true) == .startOnlineOnce, "never started: start online once")
        var online = game
        online.onlineOnly = true
        check(OfflineReadiness.of(online, analysis: nil, accountRemembered: true) == .onlineOnly, "online only: needs internet")
        var analysis = GameAnalysis()
        analysis.launcher = "EA app"
        check(OfflineReadiness.of(game, analysis: analysis, accountRemembered: true) == .launcher("EA app"), "a launcher: needs internet")

        let steam = FileManager.default.temporaryDirectory.appendingPathComponent("nightforge-offline-test-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: steam) }
        try? FileManager.default.createDirectory(at: steam.appendingPathComponent("config"), withIntermediateDirectories: true)
        check(!OfflineReadiness.accountRemembered(steamRoot: steam), "no loginusers.vdf: nothing remembered")
        func users(_ remember: String) -> String {
            "\"users\"\n{\n\t\"76561190000000000\"\n\t{\n\t\t\"AccountName\"\t\t\"x\"\n\t\t\"RememberPassword\"\t\t\"\(remember)\"\n\t}\n}\n"
        }
        try? users("0").write(to: steam.appendingPathComponent("config/loginusers.vdf"), atomically: true, encoding: .utf8)
        check(!OfflineReadiness.accountRemembered(steamRoot: steam), "RememberPassword 0: not remembered")
        try? users("1").write(to: steam.appendingPathComponent("config/loginusers.vdf"), atomically: true, encoding: .utf8)
        check(OfflineReadiness.accountRemembered(steamRoot: steam), "RememberPassword 1: remembered")

        print(failures == 0 ? "✓ OfflineReadiness" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
