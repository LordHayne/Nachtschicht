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
            MainActor.assumeIsolated { self?.refreshConnected() }
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
            MainActor.assumeIsolated { self?.model?.toggleLibrary() }
        }
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.primary() }
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated {
                guard let model = self?.model else { return }
                if model.showingOptions { model.showingOptions = false } else { model.showingLibrary = false }
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
            MainActor.assumeIsolated { self?.model?.move(-5) }
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.model?.move(5) }
        }
    }

    private func primary() {
        guard let model, !model.showingOptions, model.macSetup == nil else { return }
        if model.showingLibrary { model.showSelectedGame() } else { model.primaryAction() }
    }

    private func toggleOptions() {
        guard let model, let game = model.selected, game.install != .inStore else { return }
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

    private func perform(_ step: Step) {
        guard let model else { return }
        if step.dx != 0 { model.move(step.dx) }
        if step.dy != 0 { model.moveRow(step.dy) }
    }

    /// First step immediately, then a short pause, then fast repeat while held.
    private func setHeld(_ step: Step) {
        guard step != held else { return }
        held = step
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard !step.isNone, let model, !model.showingOptions else { return }

        perform(step)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startFastRepeat() }
        }
    }

    private func startFastRepeat() {
        guard !held.isNone else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.held.isNone else { return }
                self.perform(self.held)
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
