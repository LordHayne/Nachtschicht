// Checks PadFocus: entering, moving by position, adjusting, and staying in its own window:
// tests/PadFocusTest/run.sh
import AppKit

@main
struct PadFocusTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    @MainActor
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let focus = PadFocus.shared
        var pressed: [String] = []
        var value = 0
        var views: [NSView] = []

        // Window y grows upward: a top row (y 300) with two buttons, a picker in the middle,
        // and a bottom row (y 40) with play and options.
        func add(_ id: String, _ frame: NSRect, in window: NSWindow = window, enabled: Bool = true, adjust: ((Int) -> Void)? = nil) {
            let view = NSView(frame: frame)
            window.contentView!.addSubview(view)
            views.append(view)
            focus.register(id, .init(view: view, enabled: enabled, activate: { pressed.append(id) }, adjust: adjust))
        }
        add("top.left", NSRect(x: 40, y: 300, width: 80, height: 30))
        add("top.right", NSRect(x: 460, y: 300, width: 80, height: 30))
        add("picker", NSRect(x: 40, y: 170, width: 200, height: 30), adjust: { value += $0 })
        add("play", NSRect(x: 40, y: 40, width: 160, height: 50))
        add("options", NSRect(x: 230, y: 40, width: 50, height: 50))
        add("disabled", NSRect(x: 320, y: 40, width: 50, height: 50), enabled: false)
        add("elsewhere", NSRect(x: 40, y: 40, width: 50, height: 50), in: other)

        check(focus.move(dx: 0, dy: -1, in: window) && focus.focused == "play", "up from below enters at the bottom left: \(focus.focused ?? "nil")")
        focus.move(dx: 1, dy: 0, in: window)
        check(focus.focused == "options", "right moves along the row: \(focus.focused ?? "nil")")
        check(!focus.move(dx: 1, dy: 0, in: window) && focus.focused == "options", "disabled controls are skipped, nothing further right")
        focus.move(dx: 0, dy: -1, in: window)
        check(focus.focused == "picker", "up reaches the picker: \(focus.focused ?? "nil")")
        focus.move(dx: 1, dy: 0, in: window)
        focus.move(dx: 1, dy: 0, in: window)
        focus.move(dx: -1, dy: 0, in: window)
        check(value == 1 && focus.focused == "picker", "left/right on a picker change its value")
        focus.move(dx: 0, dy: -1, in: window)
        check(focus.focused == "top.left", "up goes to the nearest control above, not the far one: \(focus.focused ?? "nil")")
        focus.focusedItem(in: window)?.activate()
        check(pressed == ["top.left"], "A presses the highlighted control")
        check(focus.focusedItem(in: other) == nil, "focus in one window isn't focus in another")
        focus.clear()
        check(focus.move(dx: 0, dy: 1, in: window) && focus.focused == "top.left", "any other way enters at the top left")
        focus.unregister("top.left", view: views[0])
        check(focus.focused == nil, "a control that goes away takes the highlight with it")

        print(failures == 0 ? "✓ PadFocus" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
