import AppKit
import GameController

/// Keyboard and gamepad navigation. GameController only delivers input while the
/// launcher is the active app, so it never reacts while you're in a game.
@MainActor
final class InputRouter {
    private weak var model: LibraryModel?
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var repeatTimer: Timer?
    private var held = Step()
    private var dpadStep = Step()
    private var stickStep = Step()

    func start(model: LibraryModel) {
        self.model = model

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let chars = event.charactersIgnoringModifiers ?? ""
            let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let command = event.modifierFlags.intersection([.command, .control, .option]) == .command
            let handled = MainActor.assumeIsolated {
                if command, chars.lowercased() == "f" {
                    self?.model?.focusSearch()
                    return true
                }
                // ⌘⌫ like "Move to Trash" in Finder – asks before removing anything.
                if command, code == 51, NSApp.keyWindow?.firstResponder is NSText == false {
                    self?.model?.requestUninstall()
                    return true
                }
                return self?.handleKey(code: code, chars: chars, plain: plain) ?? false
            }
            return handled ? nil : event
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            let controller = note.object as? GCController
            MainActor.assumeIsolated { self?.attach(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.letGo()
                self?.refreshConnected()
            }
        })
        // In the background (a game in front) GameController delivers nothing, not even the
        // release of a held stick – without this the selection would run on by itself.
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.letGo() }
        })
        // The pad last touched becomes current: its own button labels go into the hints.
        observers.append(center.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnected() }
        })

        GCController.controllers().forEach { attach($0) }
        refreshConnected()
    }

    // MARK: - Keyboard

    private func handleKey(code: UInt16, chars: String, plain: Bool) -> Bool {
        guard plain, let model, !model.showingOptions, model.macSetup == nil else { return false }
        guard let window = NSApp.keyWindow, window.title == "Nightforge" else { return false }
        if window.firstResponder is NSText { return false }

        switch code {
        case 123: model.move(-1); return true            // ←
        case 124: model.move(1); return true             // →
        case 126: model.moveRow(-1); return model.showingLibrary // ↑
        case 125: model.moveRow(1); return model.showingLibrary  // ↓
        case 115: model.jump(toStart: true); return true // Pos1
        case 119: model.jump(toStart: false); return true // Ende
        case 36, 76:                                     // Return / Enter
            if model.showingLibrary { model.showSelectedGame() } else { model.primaryAction() }
            return true
        case 53:                                         // Esc
            if model.awaitingSteam { model.cancelLaunch(); return true }
            if model.showingLibrary { model.showingLibrary = false; return true }
            if !model.searchText.isEmpty { model.searchText = ""; return true }
            return false
        default: break
        }
        switch chars.lowercased() {
        case "o" where model.selected.map { $0.install != .inStore } ?? false:
            model.showingOptions = true
            return true
        case "l":
            model.toggleLibrary()
            return true
        case "/":
            model.focusSearch()
            return true
        default:
            return false
        }
    }

    // MARK: - Gamepad

    private func refreshConnected() {
        let pads = GCController.controllers().compactMap(\.extendedGamepad)
        model?.controllerConnected = !pads.isEmpty
        let current = GCController.current?.extendedGamepad ?? pads.first
        if let current, model?.padSymbols != PadSymbols(current) { model?.padSymbols = PadSymbols(current) }
    }

    private func attach(_ controller: GCController?) {
        guard let pad = controller?.extendedGamepad else { return }
        refreshConnected()

        // D-pad and left stick both move in all four directions, repeating while held.
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.steer(.dpad, x: x, y: y) }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.steer(.stick, x: x, y: y) }
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.toggleLibrary()
            }
        }
        // A presses the highlighted control (PadFocus). Otherwise, in a dialog or sheet, A and B
        // are its Return and Esc: confirm, or cancel and close.
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                if let key = NSApp.keyWindow, let item = PadFocus.shared.focusedItem(in: key) {
                    item.activate()
                } else if let window = self?.padWindow, window !== Self.mainWindow {
                    // Nothing highlighted yet: the first press shows where you are, it doesn't save.
                    PadFocus.shared.move(dx: 0, dy: 1, in: window)
                } else if let dialog = self?.dialog {
                    Self.press(36, "\r", in: dialog)
                } else {
                    self?.primary()
                }
            }
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard let self, let model = self.model else { return }
                let main = Self.mainWindow
                if let key = NSApp.keyWindow, key === main, PadFocus.shared.focusedItem(in: key) != nil {
                    PadFocus.shared.clear()  // from the buttons back to the games
                } else if model.showingOptions, NSApp.modalWindow == nil {
                    model.showingOptions = false
                } else if let dialog = self.dialog {
                    // A window of its own (Settings) closes; a sheet or alert cancels.
                    if dialog.sheetParent == nil, NSApp.modalWindow == nil {
                        dialog.performClose(nil)
                    } else {
                        Self.press(53, "\u{1B}", in: dialog)
                    }
                } else if model.awaitingSteam {
                    model.cancelLaunch()  // stop waiting for a game Steam hasn't started
                } else if model.showingLibrary {
                    model.showingLibrary = false
                } else if !model.searchText.isEmpty {
                    model.searchText = ""  // like Esc: back from a filtered list to the whole library
                }
            }
        }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.toggleOptions() }
        }
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.toggleOptions() }
        }
        pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.move(-5)
            }
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.move(5)
            }
        }
        // L2/R2: first and last game, like Home and End on the keyboard.
        pad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.jump(toStart: true)
            }
        }
        pad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard self?.dialog == nil else { return }
                self?.model?.jump(toStart: false)
            }
        }
    }

    /// The window in front of the library when it's an alert or sheet (game options, Steam for
    /// Mac setup, a question): controller input belongs to it, not to the library behind.
    private var dialog: NSWindow? {
        guard let main = Self.mainWindow else { return nil }
        if let sheet = main.attachedSheet { return sheet }
        if let modal = NSApp.modalWindow { return modal }
        if let key = NSApp.keyWindow, key !== main, key.isVisible { return key }
        return nil
    }

    private static var mainWindow: NSWindow? { NSApp.windows.first { $0.title == "Nightforge" } }

    /// The key window when its controls are on PadFocus's map (options, settings, setup sheets).
    private var padWindow: NSWindow? {
        guard let key = NSApp.keyWindow, PadFocus.shared.hasItems(in: key) else { return nil }
        return key
    }

    /// One key press (down and up) into `window`, as if typed.
    private static func press(_ keyCode: UInt16, _ characters: String, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// Forgets every held direction and stops the repeat.
    private func letGo() {
        dpadStep = Step()
        stickStep = Step()
        setHeld(Step())
    }

    private func primary() {
        guard let model, !model.showingOptions, model.macSetup == nil else { return }
        if model.showingLibrary { model.showSelectedGame() } else { model.primaryAction() }
    }

    private func toggleOptions() {
        guard let model, let game = model.selected, game.install != .inStore else { return }
        // Opens over the library only; closes its own sheet but never one behind a question.
        guard model.showingOptions ? NSApp.modalWindow == nil : dialog == nil else { return }
        model.showingOptions.toggle()
    }

    private enum Source { case dpad, stick }

    /// A step on the grid: left/right within a row, up/down a whole row.
    private struct Step: Equatable {
        var dx = 0, dy = 0
        var isNone: Bool { dx == 0 && dy == 0 }
    }

    /// The stronger axis wins, so a slightly diagonal stick still moves straight.
    private func steer(_ source: Source, x: Float, y: Float) {
        var step = Step()
        if abs(x) >= abs(y) {
            step.dx = x > 0.55 ? 1 : (x < -0.55 ? -1 : 0)
        } else {
            step.dy = y > 0.55 ? -1 : (y < -0.55 ? 1 : 0)  // stick up is +y, a row up is -1
        }
        switch source {
        case .dpad: dpadStep = step
        case .stick: stickStep = step
        }
        // The one just moved leads; letting go of it hands over to the other if that's still held.
        setHeld(step.isNone ? (source == .dpad ? stickStep : dpadStep) : step)
    }

    /// Down on the start page opens the library; up from its top row goes back. Returns true when
    /// the view changed: holding on then mustn't run on through the other view.
    @discardableResult
    private func perform(_ step: Step) -> Bool {
        guard let model else { return false }
        if let window = padWindow {
            let focus = PadFocus.shared
            if window !== Self.mainWindow {
                focus.move(dx: step.dx, dy: step.dy, in: window)
                return false
            }
            // Main window: the games have the pad until up on the start page enters the buttons
            // above them; down past the lowest button hands back to the games.
            if focus.focusedItem(in: window) != nil {
                if !focus.move(dx: step.dx, dy: step.dy, in: window), step.dy > 0 {
                    focus.clear()
                    return true
                }
                return false
            }
            if step.dy < 0, !model.showingLibrary {
                focus.move(dx: 0, dy: -1, in: window)
                return true
            }
        }
        if step.dx != 0 { model.move(step.dx) }
        if step.dy > 0, !model.showingLibrary {
            model.showingLibrary = true
            return true
        }
        if step.dy < 0, model.showingLibrary, model.selectionInTopGridRow {
            model.showingLibrary = false
            return true
        }
        if step.dy != 0 { model.moveRow(step.dy) }
        return false
    }

    /// First step immediately, then a short pause, then fast repeat while held.
    private func setHeld(_ step: Step) {
        guard step != held else { return }
        held = step
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard !step.isNone, model != nil, dialog == nil || padWindow != nil else { return }

        guard !perform(step) else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startFastRepeat() }
        }
    }

    private func startFastRepeat() {
        guard !held.isNone else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.held.isNone else { return }
                if self.perform(self.held) {
                    self.repeatTimer?.invalidate()
                    self.repeatTimer = nil
                }
            }
        }
    }
}

/// The SF Symbols a controller gives its own buttons: ✕ ○ □ △ on a PlayStation pad, A B X Y on
/// Xbox, the Nintendo layout on a Switch pad. The defaults are Xbox's.
struct PadSymbols: Equatable {
    var confirm = "a.circle.fill"
    var back = "b.circle.fill"
    var library = "x.circle.fill"
    var options = "y.circle.fill"
    var stick = "l.joystick.fill"

    init() {}

    @MainActor
    init(_ pad: GCExtendedGamepad) {
        confirm = Self.filled(pad.buttonA.sfSymbolsName) ?? confirm
        back = Self.filled(pad.buttonB.sfSymbolsName) ?? back
        library = Self.filled(pad.buttonX.sfSymbolsName) ?? library
        options = Self.filled(pad.buttonY.sfSymbolsName) ?? options
        stick = Self.filled(pad.leftThumbstick.sfSymbolsName) ?? stick
    }

    /// The filled variant where one exists (they read better at hint size), else the symbol itself.
    private static func filled(_ name: String?) -> String? {
        guard let name, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return nil }
        let fill = name.hasSuffix(".fill") ? name : name + ".fill"
        return NSImage(systemSymbolName: fill, accessibilityDescription: nil) != nil ? fill : name
    }
}
