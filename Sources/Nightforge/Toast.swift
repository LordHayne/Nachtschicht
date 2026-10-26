import AppKit
import SwiftUI

/// A short message at the bottom of the main window ("Library is up to date"), optionally with
/// one button ("Undo", "Play", "Show"). It goes away by itself: after 2.8 s, or 5 s with a button,
/// and not while the pointer or the pad's highlight is on it. A newer message replaces it.
@MainActor
final class Toasts: ObservableObject {
    static let shared = Toasts()

    struct Action {
        /// Already translated, like the message.
        let label: String
        let run: () -> Void
    }

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let action: Action?
    }

    @Published private(set) var current: Toast?
    private var hideTask: Task<Void, Never>?
    /// The pointer is on it: it stays until the pointer leaves.
    private var hovering = false

    static let padID = "toast.action"

    func show(_ message: String, action: Action? = nil) {
        let toast = Toast(message: message, action: action)
        current = toast
        scheduleHide(after: action == nil ? 2.8 : 5)
        // VoiceOver reads it out without moving the focus.
        if let window = NSApp.mainWindow {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    /// The button: does its action and closes the message.
    func runAction() {
        guard let action = current?.action else { return }
        dismiss()
        action.run()
    }

    func dismiss() {
        hideTask?.cancel()
        if PadFocus.shared.focused == Self.padID { PadFocus.shared.clear() }
        current = nil
    }

    func setHovering(_ hovering: Bool) {
        self.hovering = hovering
        if !hovering, current != nil { scheduleHide(after: 2) }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        let id = current?.id
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.current?.id == id else { return }
            // Someone is about to press its button: wait for them.
            if self.hovering || PadFocus.shared.focused == Self.padID {
                self.scheduleHide(after: 1)
            } else {
                self.current = nil
            }
        }
    }
}

/// Where messages show: bottom centre, above the hint bar. Put it over the main window's content.
struct ToastHost: View {
    @ObservedObject private var toasts = Toasts.shared
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, 72)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: toasts.current?.id)
    }
}

private struct ToastView: View {
    let toast: Toasts.Toast

    var body: some View {
        // As wide as the message, up to 560 pt; longer ones wrap onto a second line.
        ViewThatFits(in: .horizontal) {
            pill(oneLine: true)
            pill(oneLine: false)
        }
    }

    private func pill(oneLine: Bool) -> some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(oneLine ? 1 : 2)
                .fixedSize(horizontal: oneLine, vertical: true)
                .frame(maxWidth: oneLine ? nil : .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.trailing, toast.action == nil ? 6 : 0)
            if let action = toast.action {
                Button(action: { Toasts.shared.runAction() }) {
                    Text(action.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.night)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                // ⌘↩ from the keyboard; Return alone stays Play.
                .keyboardShortcut(.return, modifiers: .command)
                .help(action.label + " (⌘↩)")
                .padFocus(Toasts.padID, cornerRadius: 14) { Toasts.shared.runAction() }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.action == nil ? 10 : 6)
        .padding(.vertical, 6)
        .frame(width: oneLine ? nil : 560)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Theme.slate.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
        .onHover { Toasts.shared.setHovering($0) }
        .accessibilityElement(children: .contain)
    }
}
