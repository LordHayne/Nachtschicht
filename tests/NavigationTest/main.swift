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
        // Only what's on the Mac, downloads first, then the ones played last.
        let games = [
            game(0, .notInstalled, playedDaysAgo: 1),
            game(1, .installed, playedDaysAgo: 30),
            game(2, .inStore),
            game(3, .installed, playedDaysAgo: 2),
            game(4, .downloading(0.4)),
            game(5, .installed, name: "B never played"),
            game(6, .installed, name: "A never played"),
        ]
        let rail = HomeRail.pick(games)
        check(rail == [4, 3, 1, 6, 5], "downloads, then recently played, then never played by name: \(rail)")
        check(!rail.contains(0) && !rail.contains(2), "games not on this Mac stay in the library")

        // 100+ games: the rail stays short (12 games and the "All games" tile).
        let many = (0..<140).map { game($0, $0 % 3 == 0 ? .notInstalled : .installed, playedDaysAgo: Double($0)) }
        let long = HomeRail.pick(many)
        check(long.count == HomeRail.limit, "at most \(HomeRail.limit) games: \(long.count)")
        check(long.first == 1 && long == long.sorted(), "the most recent first: \(long.prefix(4))")
        check(HomeRail.pick([]).isEmpty, "no games, no rail")

        // A game's page belongs to where it was opened; Back goes there.
        check(Route.detail(gameID: "x", from: .library).level == .library, "a page opened in the library is in the library")
        check(Route.detail(gameID: "x", from: .home).level == .home, "a page opened on Home is on Home")
        check(Route.home.level == .home && Route.library.level == .library, "the levels are their own section")
        check(Route.detail(gameID: "x", from: .home).isDetail && !Route.library.isDetail, "only a game's page is a detail")

        print(failures == 0 ? "✓ Navigation" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
