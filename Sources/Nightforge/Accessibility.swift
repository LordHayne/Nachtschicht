import SwiftUI

/// "Reduce motion" for Nightforge's own animations (cover zoom, rail scrolling, toasts sliding in):
/// macOS's setting until the player changes it in Settings › General. SwiftUI's own
/// `accessibilityReduceMotion` can't be overridden, so the views read this one.
private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var reduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
}

/// Puts the setting into a window's environment.
struct ReduceMotionFromSettings: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var system
    @AppStorage(Prefs.Keys.reduceMotion) private var stored = ""

    func body(content: Content) -> some View {
        content.environment(\.reduceMotion, Prefs.reduceMotion(system: system, stored: stored))
    }
}
