import AppKit

/// What the Mac offers a game right now, for the automatic choices of "Sharp & smooth": whether
/// the screen the game opens on has Retina pixels (MetalFX has something to upscale to) and whether
/// Low Power Mode holds CPU and GPU back. Taken on the main thread (`refresh`) before a start or
/// when the options show, and read from anywhere afterwards, like Prefs.
/// The chip itself is left to FramePacing: what a game holds on this Mac says more than a GPU tier.
enum Hardware {
    struct State: Equatable {
        var retina = true
        var lowPower = false
    }

    private static let lock = NSLock()
    private static var state = State()

    static var current: State { lock.withLock { state } }

    @MainActor static func refresh() {
        set(State(retina: (GameDisplay.screen?.backingScaleFactor ?? 2) >= 2,
                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
    }

    /// For refresh and tests.
    static func set(_ new: State) {
        lock.withLock { state = new }
    }
}
