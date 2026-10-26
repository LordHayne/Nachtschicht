// Checks Home's rail (what's on it, in which order, how many) and which section a game's page
// belongs to: tests/NavigationTest/run.sh
import Foundation

@main
struct NavigationTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func game(_ id: Int, _ install: InstallState, playedDaysAgo: Double? = nil, name: String? = nil) -> Game {
        var game = Game(appID: id, name: name ?? "Game \(id)", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.install = install
        game.lastPlayed = playedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
        return game
    }

    static func main() {
        // Only what's on the Mac: downloads first, then games played in the last 90 days, latest first.
        let games = [
            game(0, .notInstalled, playedDaysAgo: 1),
            game(1, .installed, playedDaysAgo: 30),
            game(2, .inStore),
            game(3, .installed, playedDaysAgo: 2),
            game(4, .downloading(0.4)),
            game(5, .installed, name: "B never played"),
            game(6, .installed, name: "A never played"),
            game(7, .installed, playedDaysAgo: 200),
        ]
        let rail = HomeRail.pick(games)
        check(rail == [4, 3, 1], "downloads, then played lately; not long ago or never: \(rail)")
        check(!rail.contains(0) && !rail.contains(2), "games not on this Mac stay in the library")

        // A new library with little played lately: other installed games fill up to three.
        let fresh = [game(0, .installed, playedDaysAgo: 400), game(1, .installed, name: "B"), game(2, .installed, name: "A"),
                     game(3, .notInstalled), game(4, .installed, playedDaysAgo: 3)]
        check(HomeRail.pick(fresh) == [4, 0, 2], "filled up: the latest played, then never played by name: \(HomeRail.pick(fresh))")

        // 100+ games: the rail stays short (12 games and the "All games" tile).
        let many = (0..<140).map { game($0, $0 % 3 == 0 ? .notInstalled : .installed, playedDaysAgo: Double($0)) }
        let long = HomeRail.pick(many)
        check(long.count == HomeRail.limit, "at most \(HomeRail.limit) games: \(long.count)")
        check(long.first == 1 && long == long.sorted(), "the most recent first: \(long.prefix(4))")
        check(HomeRail.pick([]).isEmpty, "no games, no rail")

        // Pinned games lead the rail (by name), even ones not played for long; only games on this Mac.
        let pinned = HomeRail.pick(games, pinned: [5, 0, 7])
        check(pinned == [5, 7, 4, 3, 1], "pinned first (by name), even unplayed; a pinned game not on the Mac stays off: \(pinned)")
        let pinnedMany = HomeRail.pick(many, pinned: [139, 137])
        check(pinnedMany.prefix(2) == [137, 139] && pinnedMany.count == HomeRail.limit, "pins beat recent games and the limit holds: \(pinnedMany.prefix(3))")

        // Hidden and pinned marks survive a restart (UserDefaults), by app ID.
        let defaults = UserDefaults(suiteName: "nightforge.navigation-test")!
        defaults.removePersistentDomain(forName: "nightforge.navigation-test")
        GameMarks.save([570, 10], .hidden, to: defaults)
        GameMarks.save([1091500], .pinned, to: defaults)
        check(GameMarks.load(.hidden, from: defaults) == [570, 10], "hidden games come back")
        check(GameMarks.load(.pinned, from: defaults) == [1091500], "pinned games come back")
        check(GameMarks.load(.hidden, from: UserDefaults(suiteName: "nightforge.navigation-test.empty")!).isEmpty, "nothing marked at first")
        defaults.removePersistentDomain(forName: "nightforge.navigation-test")

        // The Dock menu: installed games played before, the last first, five at most, none hidden.
        let dock = MacIntegration.recentGames(games + many.map { var g = $0; g.lastPlayed = nil; return g }, hidden: [3])
        check(dock.map(\.appID) == [1, 7], "only installed and played, hidden left out, latest first: \(dock.map(\.appID))")
        check(MacIntegration.recentGames(many).count == MacIntegration.dockLimit, "five at most")

        // The hint bar's controller line.
        check(ControllerStatus(name: "DualSense Wireless Controller", battery: 0.8).label == "DualSense · 80 %", "DualSense · 80 %")
        check(ControllerStatus(name: "Xbox Wireless Controller", battery: nil).label == "Xbox", "no battery reported: the name alone")
        check(ControllerStatus(name: "DualSense Wireless Controller", battery: 0.1).isLow, "below 20 % is low")
        check(!ControllerStatus(name: "DualSense Wireless Controller", battery: 0.1, charging: true).isLow, "not while charging")

        // A game's page belongs to where it was opened; Back goes there.
        check(Route.detail(gameID: "x", from: .library).level == .library, "a page opened in the library is in the library")
        check(Route.detail(gameID: "x", from: .home).level == .home, "a page opened on Home is on Home")
        check(Route.home.level == .home && Route.library.level == .library, "the levels are their own section")
        check(Route.detail(gameID: "x", from: .home).isDetail && !Route.library.isDetail, "only a game's page is a detail")

        print(failures == 0 ? "✓ Navigation" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
