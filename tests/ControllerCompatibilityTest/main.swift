// Checks ControllerCompatibility: which apps read controllers the old way, and that only those get
// the synthetic pad: tests/ControllerCompatibilityTest/run.sh
import Foundation

@main
struct ControllerCompatibilityTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    /// A Steam game folder holding one app with `program` and, optionally, a bundled library.
    static func game(_ name: String, in root: URL, program: URL, library: URL? = nil, bundleID: String) throws -> URL {
        let fm = FileManager.default
        let folder = root.appendingPathComponent("common/\(name)", isDirectory: true)
        let contents = folder.appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(at: program, to: contents.appendingPathComponent("MacOS/\(name)"))
        if let library {
            try fm.createDirectory(at: contents.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
            try fm.copyItem(at: library, to: contents.appendingPathComponent("Frameworks/\(library.lastPathComponent)"))
        }
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": name, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return folder
    }

    static func synthetic(_ bundleID: String) -> Bool? {
        CFPreferencesCopyAppValue(ControllerCompatibility.key as CFString, bundleID as CFString) as? Bool
    }

    static func main() throws {
        let work = URL(fileURLWithPath: CommandLine.arguments[1])
        let old = work.appendingPathComponent("old"), modern = work.appendingPathComponent("modern")
        let sdl = work.appendingPathComponent("libSDL2.dylib")

        check(!ControllerCompatibility.links(old, "GameController.framework"), "universal HID program doesn't link GameController")
        check(ControllerCompatibility.links(modern, "GameController.framework"), "GameController program is recognised")
        check(ControllerCompatibility.links(sdl, "GameController.framework"), "SDL-style library is recognised")
        check(!ControllerCompatibility.links(work.appendingPathComponent("game.c"), "GameController.framework"), "a text file isn't Mach-O")

        let ids = (old: "nightforge.test.oldgame", modern: "nightforge.test.moderngame", sdl: "nightforge.test.sdlgame",
                   player: "nightforge.test.playerchoice")
        let all = [ids.old, ids.modern, ids.sdl, ids.player]
        func reset() {
            for id in all { CFPreferencesSetAppValue(ControllerCompatibility.key as CFString, nil, id as CFString); CFPreferencesAppSynchronize(id as CFString) }
        }
        reset()
        defer { reset() }

        let oldGame = try game("Old Game", in: work, program: old, bundleID: ids.old)
        let modernGame = try game("Modern Game", in: work, program: modern, bundleID: ids.modern)
        let sdlGame = try game("SDL Game", in: work, program: old, library: sdl, bundleID: ids.sdl)
        let playerGame = try game("Player Game", in: work, program: old, bundleID: ids.player)
        CFPreferencesSetAppValue(ControllerCompatibility.key as CFString, kCFBooleanFalse, ids.player as CFString)
        CFPreferencesAppSynchronize(ids.player as CFString)

        check(ControllerCompatibility.apps(in: oldGame).count == 1, "finds the app in the game folder")
        for folder in [oldGame, modernGame, sdlGame, playerGame] { ControllerCompatibility.prepare(installDir: folder) }
        check(synthetic(ids.old) == true, "old game gets the synthetic pad")
        check(synthetic(ids.modern) == nil, "GameController game is left alone")
        check(synthetic(ids.sdl) == nil, "game with a modern SDL is left alone")
        check(synthetic(ids.player) == false, "the player's own choice stays")

        // Installed games on this Mac, when there: Batman (Feral, HID) and No Man's Sky (GameController).
        let common = MacSteam.steamapps.appendingPathComponent("common")
        if let batman = ControllerCompatibility.apps(in: common.appendingPathComponent("Batman Arkham City GOTY")).first {
            check(ControllerCompatibility.needsSyntheticPad(batman), "Batman: Arkham City needs the synthetic pad")
        }
        if let nms = ControllerCompatibility.apps(in: common.appendingPathComponent("No Man's Sky")).first {
            check(!ControllerCompatibility.needsSyntheticPad(nms), "No Man's Sky reads controllers itself")
        }

        print(failures == 0 ? "✓ ControllerCompatibility" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
