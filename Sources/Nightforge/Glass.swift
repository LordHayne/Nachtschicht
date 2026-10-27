import SwiftUI

/// The design's glass: frosted, lit from above – a bright rim, a sheen in the upper half – and
/// lifted off the backdrop by a shadow. Drawn by hand rather than with macOS 26's Liquid Glass, so
/// it looks the same from macOS 14 on and shows in the offscreen renders the screens are checked with.
struct Glass: Equatable {
    /// Coloured glass: sodium for the main action, ink for a switch that's on.
    var tint: Color?
    /// Darker and denser, for messages laid over everything.
    var thick = false
    /// The tint's light falls around the glass – only the one main action.
    var glows = false

    static let regular = Glass()
    static let thick = Glass(thick: true)

    static func tinted(_ color: Color, glows: Bool = false) -> Glass {
        Glass(tint: color, glows: glows)
    }
}

/// The glass behind a control's content.
struct GlassBackground<S: InsettableShape>: View {
    let glass: Glass
    let shape: S
    var hovering = false
    /// A busy main action: the tint at half strength.
    var dimmed = false
    /// Part of the glass filled with the full tint from the left (a download's progress).
    var progress: Double?

    var body: some View {
        ZStack(alignment: .leading) {
            if let tint = glass.tint {
                // Solid coloured glass; a busy one lets the frosted backdrop through.
                if dimmed { shape.fill(.ultraThinMaterial) }
                shape.fill(tint.opacity(dimmed ? 0.55 : 1))
                    .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
                if let progress {
                    GeometryReader { geo in
                        shape.fill(tint).frame(width: max(geo.size.height, geo.size.width * progress))
                    }
                }
                // Deeper towards the bottom, like the light through a lens.
                shape.fill(LinearGradient(colors: [.black.opacity(0), .black.opacity(hovering ? 0.04 : 0.1)],
                                          startPoint: .center, endPoint: .bottom))
            } else {
                shape.fill(.ultraThinMaterial)
                    .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
                if glass.thick { shape.fill(Theme.night.opacity(0.55)) }
                shape.fill(LinearGradient(colors: [.white.opacity(glass.thick ? 0.06 : hovering ? 0.16 : 0.09),
                                                   .white.opacity(glass.thick ? 0.02 : hovering ? 0.06 : 0.03)],
                                          startPoint: .top, endPoint: .bottom))
            }
            // The sheen: the upper half catches the light.
            shape.inset(by: 1.5)
                .fill(LinearGradient(colors: [.white.opacity(sheen), .white.opacity(0)], startPoint: .top, endPoint: .center))
            shape.strokeBorder(LinearGradient(stops: rim, startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }

    private var sheen: Double {
        if glass.tint != nil { return hovering ? 0.55 : 0.45 }
        return glass.thick ? 0.04 : hovering ? 0.12 : 0.07
    }

    /// Bright at the top where the light hits, nearly gone in the middle, a faint reflection below.
    private var rim: [Gradient.Stop] {
        let top = glass.tint != nil ? 0.65 : glass.thick ? 0.22 : hovering ? 0.55 : 0.42
        return [.init(color: .white.opacity(top), location: 0),
                .init(color: .white.opacity(top * 0.25), location: 0.35),
                .init(color: .white.opacity(top * 0.1), location: 0.65),
                .init(color: .white.opacity(top * 0.4), location: 1)]
    }

    private var shadow: (color: Color, radius: CGFloat, y: CGFloat) {
        if glass.glows, let tint = glass.tint { return (tint.opacity(hovering ? 0.6 : 0.4), hovering ? 24 : 16, 6) }
        if glass.tint != nil { return (.black.opacity(0.25), 8, 4) }
        if glass.thick { return (.black.opacity(0.45), 18, 8) }
        return (.black.opacity(0.28), 10, 5)
    }
}

/// A button on glass: brighter under the pointer, a little smaller while pressed.
struct GlassButtonStyle<S: InsettableShape>: ButtonStyle {
    var glass = Glass.regular
    let shape: S
    var dimmed = false
    var progress: Double?
    /// Off for a button that stays readable while it can't be pressed (Play while a game starts).
    var fadesWhenDisabled = true

    func makeBody(configuration: Configuration) -> some View {
        GlassControl(label: configuration.label, glass: glass, shape: shape, pressed: configuration.isPressed,
                     dimmed: dimmed, progress: progress, fadesWhenDisabled: fadesWhenDisabled)
    }
}

/// A text button on glass, for the ones beside the big buttons ("Clear filters", "Load Mac Version").
struct GlassTextButtonStyle: ButtonStyle {
    /// Sodium glass for the action a screen is about.
    var prominent = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        GlassControl(label: configuration.label
                        .font(.system(size: small ? 12.5 : 14, weight: .semibold))
                        .foregroundStyle(prominent ? Theme.night : Theme.ink)
                        .padding(.horizontal, small ? 14 : 22)
                        .frame(height: small ? 30 : 42),
                     glass: prominent ? .tinted(Theme.sodium) : .regular, shape: Capsule(), pressed: configuration.isPressed)
    }
}

/// A button inside a shared piece of glass (the top bar's downloads, rescan and settings): no glass of
/// its own, a light capsule under the pointer.
struct GlassGroupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassGroupButton(label: configuration.label, pressed: configuration.isPressed)
    }
}

/// The thin line between buttons that share a piece of glass.
struct GlassDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 16)
    }
}

private struct GlassGroupButton<Label: View>: View {
    let label: Label
    let pressed: Bool
    @State private var hovering = false
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        label
            .foregroundStyle(Theme.ink.opacity(hovering ? 1 : 0.9))
            .frame(width: 36, height: 30)
            .background(Capsule().fill(.white.opacity(hovering ? 0.15 : 0)))
            .contentShape(Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.9 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct GlassControl<Label: View, S: InsettableShape>: View {
    let label: Label
    let glass: Glass
    let shape: S
    let pressed: Bool
    var dimmed = false
    var progress: Double?
    var fadesWhenDisabled = true
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        label
            .background(GlassBackground(glass: glass, shape: shape, hovering: hovering && isEnabled, dimmed: dimmed, progress: progress))
            .contentShape(shape)
            .opacity(isEnabled || !fadesWhenDisabled ? 1 : 0.5)
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: pressed)
    }
}
