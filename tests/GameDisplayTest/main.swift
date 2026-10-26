// Checks which screen GameDisplay picks to play on and which ones count as TVs:
// tests/GameDisplayTest/run.sh
import Foundation

@main
struct GameDisplayTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func screen(_ id: UInt32, _ name: String, builtIn: Bool = false, _ width: Int = 1920, _ height: Int = 1080)
        -> GameDisplay.Candidate {
        GameDisplay.Candidate(id: id, name: name, builtIn: builtIn, pixels: width * height)
    }

    static func main() {
        let macBook = screen(1, "Built-in Retina Display", builtIn: true, 3024, 1964)

        check(GameDisplay.pick([macBook]) == nil, "a MacBook alone stays on its own screen")
        check(GameDisplay.pick([]) == nil, "no screens, no pick")
        check(GameDisplay.pick([macBook, screen(2, "LG TV SSCR2", 3840, 2160)]) == 2, "a TV next to a MacBook")
        check(GameDisplay.pick([screen(3, "DELL U2720Q", 3840, 2160)]) == 3, "a Mac mini's only monitor")
        check(GameDisplay.pick([macBook, screen(4, "DELL U2720Q", 3840, 2160), screen(5, "SONY TV  *00")]) == 5,
              "a TV wins over a bigger monitor")
        check(GameDisplay.pick([macBook, screen(6, "DELL P2419H"), screen(7, "LG UltraFine", 5120, 2880)]) == 7,
              "of two monitors the bigger one")

        for name in ["LG TV SSCR2", "SAMSUNG", "SONY TV  *00", "Hisense", "TCL TV", "VIZIO M55", "BRAVIA 4K"] {
            check(screen(9, name).isTV, "\(name) is a TV")
        }
        for name in ["DELL U2720Q", "LG UltraFine", "Studio Display", "Built-in Retina Display", "PHL 276E8V", "Odyssey G7"] {
            check(!screen(9, name).isTV, "\(name) is no TV")
        }

        if failures == 0 { print("✓ GameDisplay: all checks passed") }
        exit(failures == 0 ? 0 : 1)
    }
}
