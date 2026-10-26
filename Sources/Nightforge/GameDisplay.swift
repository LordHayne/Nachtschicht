import AppKit
import CoreGraphics

/// The screen games are played on: the one Nightforge's window is on. When a TV or another
/// external screen is connected, the window moves there by itself (full screen on a TV), and for
/// as long as a game runs that screen is the main one – Wine and Mac games open their full screen
/// on the main display, and the menu bar would otherwise keep it on a MacBook's own screen.
/// Moving the window back to the Mac's screen is the way to play there; Nightforge remembers it.
@MainActor
enum GameDisplay {
    struct Candidate: Equatable {
        let id: CGDirectDisplayID
        let name: String
        let builtIn: Bool
        let pixels: Int
    }

    /// The external screen to play on: a TV before a monitor, then the biggest. None without one.
    nonisolated static func pick(_ displays: [Candidate]) -> CGDirectDisplayID? {
        displays.filter { !$0.builtIn }
            .max { ($0.isTV ? 1 : 0, $0.pixels) < ($1.isTV ? 1 : 0, $1.pixels) }?.id
    }

    /// The screen a game will open on.
    static var screen: NSScreen? { window?.screen ?? NSScreen.main }

    private static var window: NSWindow? { NSApp.windows.first { $0.title == "Nightforge" } }

    private enum Keys {
        /// The main display before a game made another one main, while that lasts.
        static let restoreMain = "gameDisplayRestoreMain"
        /// An external screen the player moved Nightforge's window away from.
        static let declined = "gameDisplayDeclined"
    }

    private static var known: Set<CGDirectDisplayID> = []
    private static var lastScreen: CGDirectDisplayID?
    private static var placing = false

    // MARK: - The launcher

    /// Puts the window on the screen to play on now and whenever one is connected.
    static func follow() {
        restoreLeftover()
        known = Set(candidates().map(\.id))
        Task {
            // The window shows up a moment after the app finished launching.
            for _ in 0..<50 where window == nil { try? await Task.sleep(for: .milliseconds(100)) }
            lastScreen = window?.screen.flatMap(id)
            await place()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let now = Set(candidates().map(\.id))
                let connected = !now.subtracting(known).isEmpty
                known = now
                guard connected else { return }
                UserDefaults.standard.removeObject(forKey: Keys.declined)  // plugged in again: try it
                Task { await place() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification,
                                               object: nil, queue: .main) { note in
            MainActor.assumeIsolated { windowMoved(note.object as? NSWindow) }
        }
    }

    /// The player moved the window: away from the picked screen means "not there", onto it "yes".
    /// A screen that went away taking the window along says nothing.
    private static func windowMoved(_ moved: NSWindow?) {
        guard let moved, moved === window, let now = moved.screen.flatMap(id) else { return }
        defer { lastScreen = now }
        guard !placing, let before = lastScreen, before != now,
              NSScreen.screens.contains(where: { id($0) == before }),
              let picked = pick(candidates())
        else { return }
        if before == picked {
            UserDefaults.standard.set(Int(picked), forKey: Keys.declined)
        } else if now == picked {
            UserDefaults.standard.removeObject(forKey: Keys.declined)
        }
    }

    private static func place() async {
        guard let window, !running,
              let picked = pick(candidates()),
              UserDefaults.standard.object(forKey: Keys.declined) as? Int != Int(picked),
              let target = NSScreen.screens.first(where: { id($0) == picked }),
              window.screen.flatMap(id) != picked
        else { return }
        placing = true
        defer { placing = false }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            for _ in 0..<30 where window.styleMask.contains(.fullScreen) {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let area = target.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        frame.origin = CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        window.setFrame(frame, display: true)
        lastScreen = picked
        if candidates().first(where: { $0.id == picked })?.isTV == true {
            try? await Task.sleep(for: .milliseconds(300))  // let the move land first
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - While a game runs

    private static var running = false

    /// Before a game starts: the game screen becomes the main display.
    static func enterGame() {
        running = true
        guard let game = screen.flatMap(id) else { return }
        let main = CGMainDisplayID()
        guard game != main, makeMain(game) else { return }
        if UserDefaults.standard.object(forKey: Keys.restoreMain) == nil {
            UserDefaults.standard.set(Int(main), forKey: Keys.restoreMain)
        }
    }

    /// After the game: the main display goes back to what it was.
    static func leaveGame() {
        running = false
        restoreLeftover()
    }

    /// When Nightforge quits with no game running.
    static func quitting() {
        if !running { restoreLeftover() }
    }

    /// Also at start, after Nightforge quit while a game ran.
    private static func restoreLeftover() {
        guard let stored = UserDefaults.standard.object(forKey: Keys.restoreMain) as? Int else { return }
        UserDefaults.standard.removeObject(forKey: Keys.restoreMain)
        let main = CGDirectDisplayID(stored)
        if CGDisplayIsActive(main) != 0, main != CGMainDisplayID() { _ = makeMain(main) }
    }

    /// The main display is the one at the origin: shift every screen so `display` lands there.
    /// For this login session only, so a restart puts things back anyway.
    private static func makeMain(_ display: CGDirectDisplayID) -> Bool {
        let shift = CGDisplayBounds(display).origin
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        // A mirrored screen follows the one it mirrors.
        for other in displays.prefix(Int(count)) where CGDisplayMirrorsDisplay(other) == kCGNullDirectDisplay {
            let origin = CGDisplayBounds(other).origin
            CGConfigureDisplayOrigin(config, other, Int32(origin.x - shift.x), Int32(origin.y - shift.y))
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return true
    }

    // MARK: - Screens

    private static func id(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func candidates() -> [Candidate] {
        NSScreen.screens.compactMap { screen in
            guard let display = id(screen) else { return nil }
            return Candidate(id: display, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(display) != 0,
                             pixels: CGDisplayPixelsWide(display) * CGDisplayPixelsHigh(display))
        }
    }
}

extension GameDisplay.Candidate {
    /// TVs name themselves so over HDMI ("LG TV SSCR2", "SAMSUNG", "SONY TV  *00").
    var isTV: Bool {
        let words = name.uppercased().split { !$0.isLetter && !$0.isNumber }
        let brands: Set<Substring> = ["TV", "SAMSUNG", "SONY", "VIZIO", "HISENSE", "TCL", "PANASONIC", "BRAVIA"]
        return words.contains { brands.contains($0) }
    }
}
