// Checks GameShortcut: which links it understands, the file name of a game's app, and what the app
// it writes contains (into a temporary folder): tests/GameShortcutTest/run.sh
import AppKit

@main
struct GameShortcutTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        check(GameShortcut.action(from: URL(string: "nightforge://play/1086940")!) == .play(1086940), "play link")
        check(GameShortcut.action(from: URL(string: "nightforge://show/570")!) == .show(570), "show link")
        check(GameShortcut.action(from: URL(string: "nightforge://delete/570")!) == nil, "nothing else")
        check(GameShortcut.action(from: URL(string: "nightforge://play/abc")!) == nil, "an app ID is a number")
        check(GameShortcut.action(from: URL(string: "https://play/570")!) == nil, "only Nightforge's own links")
        check(GameShortcut.url(play: 570).absoluteString == "nightforge://play/570", "the link a game's app opens")

        var game = Game(appID: 1086940, name: "Baldur's Gate 3: Deluxe/Edition", bottle: Engine.bottle, steamRoot: Engine.bottle.url,
                        steamExeWindowsPath: "", installDir: Engine.bottle.url, sizeOnDisk: 0)
        game.install = .installed
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nightforge-shortcut-test-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        check(GameShortcut.appURL(for: game, in: folder).lastPathComponent == "Baldur's Gate 3 – Deluxe-Edition.app",
              "a file name without / and : \(GameShortcut.appURL(for: game, in: folder).lastPathComponent)")

        let cover = NSImage(size: NSSize(width: 60, height: 90), flipped: false) { rect in NSColor.orange.setFill(); rect.fill(); return true }
        do {
            let app = try GameShortcut.create(for: game, icon: cover, in: folder)
            let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            check(plist?["CFBundleExecutable"] as? String == "play", "Info.plist names the script")
            check(plist?["CFBundleIdentifier"] as? String == "io.github.lordhayne.nightforge.game.1086940", "an identifier of its own")
            check(plist?["LSUIElement"] as? Bool == true, "no Dock icon while it hands over")
            let script = app.appendingPathComponent("Contents/MacOS/play")
            let text = (try? String(contentsOf: script, encoding: .utf8)) ?? ""
            check(text.contains("open \"nightforge://play/1086940\""), "the script opens the game's link: \(text)")
            check(FileManager.default.isExecutableFile(atPath: script.path), "the script can run")
            check(NSWorkspace.shared.icon(forFile: app.path).size.width > 0, "it has an icon")
            // Adding it again replaces it instead of failing.
            _ = try GameShortcut.create(for: game, icon: nil, in: folder)
            check(FileManager.default.fileExists(atPath: script.path), "adding again replaces the app")
        } catch {
            check(false, "writing the app failed: \(error)")
        }

        print(failures == 0 ? "✓ GameShortcut" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
