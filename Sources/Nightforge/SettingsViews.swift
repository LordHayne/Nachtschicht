import AppKit
import SwiftUI

struct GameOptionsSheet: View {
    let game: Game
    /// What Nightforge knows about the game: which layers fit it and which way "Automatic" takes.
    let insight: GameInsight?
    let report: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options: GameOptions
    /// Known fixes for the game, so "Automatic" shows what it will really do.
    @State private var profile: GameProfile?

    init(game: Game, insight: GameInsight?, report: @escaping () -> Void) {
        self.game = game
        self.insight = insight
        self.report = report
        _options = State(initialValue: GameOptionsStore.load(game.appID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(game.name)
                    .font(Theme.display(22))
                    .lineLimit(2)
                if let origin = profileOrigin {
                    Label(origin.text, systemImage: origin.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(profile?.note ?? origin.text)
                }
                if options != GameOptions() {
                    HStack(spacing: 8) {
                        Text(L10n.t("Your own settings."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(profileOrigin == nil ? L10n.t("Back to Automatic") : L10n.t("Back to the Profile")) { options = GameOptions() }
                            .controlSize(.small)
                            .padFocus("options.reset", activate: { options = GameOptions() })
                    }
                }
            }

            if game.switchable {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(L10n.t("Version"), selection: $options.version) {
                        Text(automaticLabel(automaticVersion == .mac ? "Mac" : "Windows")).tag(GameVersion.automatic)
                        Text("Mac").tag(GameVersion.mac)
                        Text("Windows").tag(GameVersion.windows)
                    }
                    .padFocus("options.version", selection: $options.version, values: [.automatic, .mac, .windows])
                    Text(game.platform == .mac
                         ? L10n.t("Mac runs Steam's native Mac version through Steam for Mac, without any Windows translation; its graphics settings are in the game itself. Windows runs the Windows version through Wine. Automatic takes the Mac version when it runs on current Macs.")
                         : L10n.t("Mac runs Steam's native Mac version through Steam for Mac, without any Windows translation. Windows runs the Windows version through Wine. Automatic takes the Mac version when it runs on current Macs."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !game.bottle.isBuiltIn && game.platform == .windows {
                Toggle(isOn: $options.metalHUD) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Performance HUD in game"))
                        Text(L10n.t("Shows frames per second, frame times and GPU load in the top left corner of the game."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padFocus("options.hud", toggle: $options.metalHUD)
            }

            if game.bottle.isBuiltIn {
                VStack(alignment: .leading, spacing: 6) {
                    if layers.isEmpty {
                        Text(L10n.t("Graphics"))
                    } else {
                        Picker(L10n.t("Graphics"), selection: $options.graphics) {
                            ForEach(layers) { layer in
                                Text(layer == .automatic ? automaticLabel(automaticWay.shortLabel) : layer.label).tag(layer)
                            }
                        }
                        .padFocus("options.graphics", selection: $options.graphics, values: layers)
                    }
                    Text(graphicsCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Picker(L10n.t("Frame limit"), selection: $options.frameLimit) {
                        // What the next start uses, including what Nightforge learned (FramePacing).
                        Text(automaticLabel(FramePacing.automaticLimit(
                            appID: game.appID, options: { var o = options; o.frameLimit = nil; return o }(),
                            profile: profile, refreshRate: refreshRate).limit.fpsLabel))
                            .tag(Int?.none)
                        ForEach(GameOptions.frameLimits, id: \.self) { limit in
                            Text(limit.fpsLabel).tag(Int?.some(limit))
                        }
                    }
                    .padFocus("options.frameLimit", selection: $options.frameLimit,
                              values: [Int?.none] + GameOptions.frameLimits.map { Int?.some($0) })
                    Picker(L10n.t("MetalFX upscaling"), selection: $options.upscaling) {
                        Text(automaticLabel(GameOptions().effectiveUpscaling(profile: profile) ? L10n.t("On") : L10n.t("Off"))).tag(Choice.automatic)
                        Text(L10n.t("On")).tag(Choice.on)
                        Text(L10n.t("Off")).tag(Choice.off)
                    }
                    .disabled(!drawsWith.upscales || layers.isEmpty)
                    .padFocus("options.upscaling", enabled: drawsWith.upscales && !layers.isEmpty,
                              selection: $options.upscaling, values: [.automatic, .on, .off])
                    Text(L10n.t("Automatic follows “Sharp & smooth” in Settings. The frame limit keeps frames even; MetalFX upscales the picture to full Retina sharpness (not with WineD3D) – set a lower resolution in the game for more FPS."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: $options.hdr) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HDR")
                        Text(L10n.t("For games that draw through Vulkan, on the XDR display. Off by default: under Wine HDR mostly looks washed out."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .disabled(drawsWith == .dxmt && insight?.analysis.apis.contains(.vulkan) != true)
                .padFocus("options.hdr", enabled: !(drawsWith == .dxmt && insight?.analysis.apis.contains(.vulkan) != true),
                          toggle: $options.hdr)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("Launch Options"))
                TextField(L10n.t("e.g. -dx11 -skipintro"), text: $options.extraArgs)
                    .textFieldStyle(.roundedBorder)
                Text(L10n.t("Passed straight to the game at launch."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if game.bottle.isBuiltIn {
                    Button(L10n.t("Report problem …"), action: reportProblem)
                        .padFocus("options.report", activate: reportProblem)
                    .help(L10n.t("Opens a problem report on GitHub, filled in with what Nightforge knows about the game. Nothing is sent until you submit it there."))
                }
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padFocus("options.cancel", activate: { dismiss() })
                Button(L10n.t("Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .padFocus("options.save", activate: save)
            }
        }
        .padding(28)
        .frame(width: 470)
        .task {
            if game.bottle.isBuiltIn || game.switchable { profile = await ProfileStore.shared.profile(for: game.appID) }
        }
    }
}

private extension GameOptionsSheet {
    func reportProblem() {
        report()
        dismiss()
    }

    func save() {
        // Picking a layer or version by hand overrides what self-healing learned.
        if options.graphics != .automatic { LaunchHealth.reset(game.appID) }
        if options.version != GameOptionsStore.load(game.appID).version { MacHealth.reset(game.appID) }
        GameOptionsStore.save(options, for: game.appID)
        dismiss()
    }

    var refreshRate: Int { GameDisplay.screen?.maximumFramesPerSecond ?? 60 }

    /// Where the game's known fixes come from: Nightforge's own test, or umu-protonfixes.
    var profileOrigin: (text: String, symbol: String)? {
        guard let profile else { return nil }
        if profile.fromNightforge {
            let chips = Compatibility.chips(in: profile.note)
            return (chips.isEmpty ? L10n.t("Tested by Nightforge") : L10n.t("Tested by Nightforge on %@", chips.joined(separator: ", ")),
                    "checkmark.seal")
        }
        if profile.hasFixes { return (L10n.t("Community fix · from umu-protonfixes"), "person.2") }
        return nil
    }

    func automaticLabel(_ value: String) -> String { L10n.t("Automatic (%@)", value) }

    /// The version "Automatic" would play (VersionChoice), from what the entry knows about both.
    var automaticVersion: Platform {
        let facts = VersionChoice.Facts(
            macNative: true, mac64: game.mac64, windows: game.windowsBuild,
            macInstalled: game.platform == .mac && game.isInstalled,
            windowsInstalled: game.platform == .windows ? game.isInstalled : game.windowsLeftover != nil)
        return VersionChoice.decide(facts, choice: .automatic, preferWindows: profile?.preferWindows == true,
                                    macFailed: MacHealth.failed(game.appID)).0
    }

    /// The layers that fit what the game draws with; none for Vulkan, OpenGL and DirectX 12.
    var layers: [GraphicsLayer] {
        var list: [GraphicsLayer]
        if let analysis = insight?.analysis, !analysis.usesD3D11, !analysis.apis.isEmpty {
            list = analysis.usesD3D9 ? [.automatic, .dxvk, .wined3d] : []
        } else {
            list = [.automatic, .dxmt, .dxvk]
        }
        if !list.isEmpty, !list.contains(options.graphics) { list.append(options.graphics) }
        return list
    }

    /// The way "Automatic" takes right now (LaunchHealth).
    var automaticWay: LaunchAttempt {
        guard let attempts = insight?.attempts, !attempts.isEmpty else { return LaunchAttempt(graphics: Engine.defaultGraphics) }
        return attempts[LaunchHealth.current(game.appID, attempts).index]
    }

    var drawsWith: GraphicsLayer { options.graphics == .automatic ? automaticWay.graphics : options.graphics }

    var graphicsCaption: String {
        guard let analysis = insight?.analysis, !analysis.apis.isEmpty else {
            return L10n.t("How DirectX 10/11 reaches the Mac's graphics. DXMT translates straight to Metal and is usually faster; DXVK takes a detour through Vulkan and works with more games.")
        }
        if analysis.usesD3D11 {
            return L10n.t("This game uses %@. DXMT translates DirectX 10/11 straight to Metal and is usually faster; DXVK takes a detour through Vulkan and works with more games. Automatic switches by itself if a game doesn't start.", analysis.summary)
        }
        if analysis.usesD3D9 {
            return L10n.t("This game uses %@. DXVK is usually faster; WineD3D runs some older games DXVK can't. Automatic switches by itself if a game doesn't start.", analysis.summary)
        }
        return L10n.t("This game uses %@ and draws without a DirectX layer, so there's nothing to choose here.", analysis.summary)
    }
}

private extension Int {
    var fpsLabel: String { self == 0 ? L10n.t("Off") : "\(self) FPS" }
}
