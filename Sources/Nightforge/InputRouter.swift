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
    private var held = 0
    private var stickDirection = 0

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

        GCController.controllers().forEach { attach($0) }
        refreshConnected()
    }

    // MARK: - Keyboard

    private func handleKey(code: UInt16, chars: String, plain: Bool) -> Bool {
        guard plain, let model, !model.showingOptions else { return false }
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
        model?.controllerConnected = GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    private func attach(_ controller: GCController?) {
        guard let pad = controller?.extendedGamepad else { return }
        refreshConnected()

        pad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.dpad(-1, pressed: pressed) }
        }
        pad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.dpad(1, pressed: pressed) }
        }
        pad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.model?.moveRow(-1) }
        }
        pad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.model?.moveRow(1) }
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.model?.toggleLibrary() }
        }
        pad.leftThumbstick.xAxis.valueChangedHandler = { [weak self] _, value in
            MainActor.assumeIsolated { self?.stick(value) }
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
        guard let model, !model.showingOptions else { return }
        if model.showingLibrary { model.showSelectedGame() } else { model.primaryAction() }
    }

    private func toggleOptions() {
        guard let model, let game = model.selected, game.install != .inStore else { return }
        model.showingOptions.toggle()
    }

    private func dpad(_ direction: Int, pressed: Bool) {
        if pressed {
            setHeld(direction)
        } else if held == direction {
            setHeld(0)
        }
    }

    private func stick(_ value: Float) {
        let direction = value > 0.55 ? 1 : (value < -0.55 ? -1 : 0)
        guard direction != stickDirection else { return }
        stickDirection = direction
        setHeld(direction)
    }

    /// First step immediately, then a short pause, then fast repeat while held.
    private func setHeld(_ direction: Int) {
        guard direction != held else { return }
        held = direction
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard direction != 0, let model, !model.showingOptions else { return }

        model.move(direction)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startFastRepeat() }
        }
    }

    private func startFastRepeat() {
        guard held != 0 else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.held != 0 else { return }
                self.model?.move(self.held)
            }
        }
    }
}
