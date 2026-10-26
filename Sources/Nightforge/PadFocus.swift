import AppKit
import SwiftUI

/// Controller focus for everything besides the game list: buttons, switches and pickers in every
/// window (game options, settings, setup, the top bar) mark themselves with `.padFocus`, and the
/// pad moves a highlight between them by where they sit on screen – so a control added later
/// works with the pad without any wiring. The highlight only shows once the pad moved it.
@MainActor
final class PadFocus: ObservableObject {
    static let shared = PadFocus()

    struct Item {
        weak var view: NSView?
        var enabled: Bool
        var activate: () -> Void
        /// Left/right on a switch or picker change its value instead of moving on.
        var adjust: ((Int) -> Void)?
    }

    @Published private(set) var focused: String?
    private var items: [String: Item] = [:]

    func register(_ id: String, _ item: Item) { items[id] = item }

    /// Only when `view` still holds the id: a control rebuilt under the same id keeps its place.
    func unregister(_ id: String, view: NSView) {
        guard items[id]?.view === view || items[id]?.view == nil else { return }
        items[id] = nil
        if focused == id { focused = nil }
    }

    /// The usable controls in `window`, with their frames in window coordinates (y up).
    private func entries(in window: NSWindow) -> [(id: String, item: Item, frame: CGRect)] {
        items.compactMap { id, item in
            guard item.enabled, let view = item.view, view.window === window, !view.isHiddenOrHasHiddenAncestor,
                  view.visibleRect.width > 0 else { return nil }
            return (id, item, view.convert(view.bounds, to: nil))
        }
    }

    func hasItems(in window: NSWindow) -> Bool { !entries(in: window).isEmpty }

    /// The focused control when it's in `window`.
    func focusedItem(in window: NSWindow) -> Item? {
        guard let focused else { return nil }
        return entries(in: window).first { $0.id == focused }?.item
    }

    func clear() { focused = nil }

    /// Moves the highlight one step (dx: -1 left, 1 right; dy: -1 up, 1 down). With nothing
    /// focused yet, up enters from the bottom (the main window's action row, above the games)
    /// and any other direction from the top. Returns false when there's nothing that way.
    @discardableResult
    func move(dx: Int, dy: Int, in window: NSWindow) -> Bool {
        let all = entries(in: window)
        guard !all.isEmpty else { return false }
        guard let current = all.first(where: { $0.id == focused }) else {
            let sorted = all.sorted { a, b in
                abs(a.frame.midY - b.frame.midY) > 8 ? a.frame.midY > b.frame.midY : a.frame.minX < b.frame.minX
            }
            // Bottom row when coming up from below: its leftmost control (the play button).
            let start = dy < 0 ? sorted.filter { abs($0.frame.midY - sorted.last!.frame.midY) < 8 }.min { $0.frame.minX < $1.frame.minX }
                               : sorted.first
            focused = start?.id
            return start != nil
        }
        if dx != 0, let adjust = current.item.adjust {
            adjust(dx)
            return true
        }
        // Nearest control in that direction; straying sideways costs more than distance.
        let from = current.frame
        let best = all.filter { $0.id != current.id }.compactMap { other -> (String, CGFloat)? in
            let along: CGFloat, across: CGFloat
            if dx != 0 {
                along = (other.frame.midX - from.midX) * CGFloat(dx)
                across = abs(other.frame.midY - from.midY)
            } else {
                along = (from.midY - other.frame.midY) * CGFloat(dy)  // window y grows upward
                across = abs(other.frame.midX - from.midX)
            }
            // Sideways stays in the row (within 45°); up and down may reach across to the next one.
            guard along > 4, dx == 0 || across < along else { return nil }
            return (other.id, along + across * 2)
        }.min { $0.1 < $1.1 }
        guard let best else { return false }
        focused = best.0
        return true
    }
}

extension View {
    /// Makes a control reachable with the pad. `activate` is what A does on it; `adjust`, for
    /// switches and pickers, what left/right do. `shape` is the highlight's corner radius.
    func padFocus(_ id: String, enabled: Bool = true, cornerRadius: CGFloat = 10,
                  activate: @escaping () -> Void, adjust: ((Int) -> Void)? = nil) -> some View {
        modifier(PadFocusModifier(id: id, enabled: enabled, cornerRadius: cornerRadius, activate: activate, adjust: adjust))
    }

    /// A switch: A and left/right flip it.
    func padFocus(_ id: String, enabled: Bool = true, toggle: Binding<Bool>) -> some View {
        padFocus(id, enabled: enabled, activate: { toggle.wrappedValue.toggle() },
                 adjust: { _ in toggle.wrappedValue.toggle() })
    }

    /// A picker: left/right step through `values`, A steps forward and wraps around.
    func padFocus<Value: Equatable>(_ id: String, enabled: Bool = true, selection: Binding<Value>, values: [Value]) -> some View {
        func step(_ delta: Int, wrap: Bool) {
            guard !values.isEmpty else { return }
            let index = values.firstIndex(of: selection.wrappedValue) ?? 0
            let next = wrap ? (index + delta + values.count) % values.count : min(max(index + delta, 0), values.count - 1)
            selection.wrappedValue = values[next]
        }
        return padFocus(id, enabled: enabled, activate: { step(1, wrap: true) }, adjust: { step($0, wrap: false) })
    }
}

private struct PadFocusModifier: ViewModifier {
    let id: String
    let enabled: Bool
    let cornerRadius: CGFloat
    let activate: () -> Void
    let adjust: ((Int) -> Void)?
    @ObservedObject private var focus = PadFocus.shared

    func body(content: Content) -> some View {
        content
            .background(PadAnchor(id: id, enabled: enabled, activate: activate, adjust: adjust))
            .overlay {
                if focus.focused == id {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.sodium, lineWidth: 3)
                        .padding(-5)
                        .shadow(color: Theme.sodium.opacity(0.5), radius: 8)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: focus.focused == id)
    }
}

/// Puts the control on the map: its NSView tells PadFocus the window and where it sits, and every
/// SwiftUI update hands over fresh actions (they capture the view's current state).
private struct PadAnchor: NSViewRepresentable {
    let id: String
    let enabled: Bool
    let activate: () -> Void
    let adjust: ((Int) -> Void)?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier(id)
        PadFocus.shared.register(id, .init(view: view, enabled: enabled, activate: activate, adjust: adjust))
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        MainActor.assumeIsolated {
            if let id = view.identifier?.rawValue { PadFocus.shared.unregister(id, view: view) }
        }
    }
}
