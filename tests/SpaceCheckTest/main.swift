// Checks SpaceCheck: when a download doesn't fit, which games are offered to make room, which are
// picked first, and the volume helpers: tests/SpaceCheckTest/run.sh
import Foundation

@main
struct SpaceCheckTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let gb: Int64 = 1 << 30

    static func game(_ id: Int, _ install: InstallState, gb size: Int64, playedDaysAgo: Double? = nil) -> Game {
        var game = Game(appID: id, name: "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url, steamExeWindowsPath: "",
                        installDir: Engine.bottle.url, sizeOnDisk: size * gb)
        game.install = install
        game.lastPlayed = playedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
        return game
    }

    static func main() {
        check(SpaceCheck.shortfall(needed: 40 * gb, free: 100 * gb) == nil, "fits with room to spare")
        check(SpaceCheck.shortfall(needed: 40 * gb, free: 40 * gb) == SpaceCheck.margin, "exactly the size isn't enough: Steam needs a little more")
        check(SpaceCheck.shortfall(needed: 50 * gb, free: 20 * gb) == 30 * gb + SpaceCheck.margin, "how much is missing")
        check(SpaceCheck.shortfall(needed: 0, free: 0) == nil, "an unknown size doesn't stop a download")

        let target = game(0, .notInstalled, gb: 50)
        let games = [
            target,
            game(1, .installed, gb: 30, playedDaysAgo: 2),     // played lately: kept
            game(2, .installed, gb: 12, playedDaysAgo: 200),
            game(3, .installed, gb: 45),                        // never played
            game(4, .installed, gb: 8, playedDaysAgo: 40),
            game(5, .notInstalled, gb: 60),                     // not on the Mac
            game(6, .downloading(0.3), gb: 20, playedDaysAgo: 400),
        ]
        let candidates = SpaceCheck.candidates(games, except: target)
        check(candidates.map(\.appID) == [3, 2, 4], "installed, unplayed for a month or never, biggest first: \(candidates.map(\.appID))")
        check(SpaceCheck.preselect(candidates, shortfall: 10 * gb) == ["Nightforge#3"], "the biggest alone is enough")
        check(SpaceCheck.preselect(candidates, shortfall: 50 * gb) == ["Nightforge#3", "Nightforge#2"], "then the next")
        check(SpaceCheck.preselect(candidates, shortfall: 500 * gb).count == 3, "all when even that isn't enough")
        check(SpaceCheck.preselect([], shortfall: gb).isEmpty, "nothing to offer, nothing picked")
        let many = (10..<30).map { game($0, .installed, gb: Int64($0)) }
        check(SpaceCheck.candidates(many, except: target).count == SpaceCheck.candidateLimit, "a short list")

        // A folder that doesn't exist yet is asked about through the nearest one that does.
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nightforge-space-test/steamapps/common/Game")
        check(SpaceCheck.existingFolder(for: missing) == FileManager.default.temporaryDirectory.standardizedFileURL
              || SpaceCheck.existingFolder(for: missing).path == FileManager.default.temporaryDirectory.path.replacingOccurrences(of: "/$", with: "", options: .regularExpression),
              "the nearest existing folder: \(SpaceCheck.existingFolder(for: missing).path)")
        check(SpaceCheck.sameVolume(missing, FileManager.default.temporaryDirectory), "a folder and its parent share a volume")

        print(failures == 0 ? "✓ SpaceCheck" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
