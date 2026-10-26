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
            Text(game.name)
                .font(Theme.display(22))
                .lineLimit(2)

            if game.switchable {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(L10n.t("Version"), selection: $options.version) {
                        Text(automaticLabel(automaticVersion == .mac ? "Mac" : "Windows")).tag(GameVersion.automatic)
                        Text("Mac").tag(GameVersion.mac)
                        Text("Windows").tag(GameVersion.windows)
                    }
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
                    }
                    Text(graphicsCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Picker(L10n.t("Frame limit"), selection: $options.frameLimit) {
                        Text(automaticLabel(GameOptions().effectiveFrameLimit(displayRefreshRate: refreshRate, profile: profile).fpsLabel))
                            .tag(Int?.none)
                        ForEach(GameOptions.frameLimits, id: \.self) { limit in
                            Text(limit.fpsLabel).tag(Int?.some(limit))
                        }
                    }
                    Picker(L10n.t("MetalFX upscaling"), selection: $options.upscaling) {
                        Text(automaticLabel(GameOptions().effectiveUpscaling(profile: profile) ? L10n.t("On") : L10n.t("Off"))).tag(Choice.automatic)
                        Text(L10n.t("On")).tag(Choice.on)
                        Text(L10n.t("Off")).tag(Choice.off)
                    }
                    .disabled(!drawsWith.upscales || layers.isEmpty)
                    Text(L10n.t("Automatic follows “Sharp & smooth” in Settings. The frame limit keeps frames even; MetalFX (DXMT only) upscales the picture to full Retina sharpness – set a lower resolution in the game for more FPS."))
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
                    Button(L10n.t("Report problem …")) {
                        report()
                        dismiss()
                    }
                    .help(L10n.t("Opens a problem report on GitHub, filled in with what Nightforge knows about the game. Nothing is sent until you submit it there."))
                }
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("Save")) {
                    // Picking a layer or version by hand overrides what self-healing learned.
                    if options.graphics != .automatic { LaunchHealth.reset(game.appID) }
                    if options.version != GameOptionsStore.load(game.appID).version { MacHealth.reset(game.appID) }
                    GameOptionsStore.save(options, for: game.appID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
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
    var refreshRate: Int { NSScreen.main?.maximumFramesPerSecond ?? 60 }

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

struct SettingsView: View {
    @EnvironmentObject private var model: LibraryModel
    @AppStorage(Prefs.Keys.bottlesRoot) private var bottlesRoot = ""
    @AppStorage(Prefs.Keys.runnerPath) private var runnerPath = ""
    @AppStorage(Prefs.Keys.afterLaunch) private var afterLaunch = AfterLaunch.hide.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @AppStorage(Prefs.Keys.performanceHUD) private var performanceHUD = false
    @AppStorage(Prefs.Keys.gameMode) private var gameMode = true
    @AppStorage(Prefs.Keys.sharpAndSmooth) private var sharpAndSmooth = true
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                Toggle(isOn: $sharpAndSmooth) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Sharp & smooth"))
                        Text(L10n.t("Every game gets Apple's MetalFX upscaling to full Retina sharpness and an even frame rate that fits your display (60 FPS on a 120 Hz screen). Change it per game in its options."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Toggle(isOn: $gameMode) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Game Mode"))
                        Text(L10n.t("Gives games priority on the CPU and graphics and halves Bluetooth latency for controllers and headphones. Turn it off if a game's sound crackles."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: gameMode) { _, _ in model.applySteamSettings() }
                Toggle(isOn: $performanceHUD) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Performance HUD in games"))
                        Text(L10n.t("Shows frames per second and frame times while you play. Takes effect at the next game start."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: performanceHUD) { _, _ in model.applySteamSettings() }
                Picker(L10n.t("After Launch"), selection: $afterLaunch) {
                    ForEach(AfterLaunch.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
            } header: {
                Text(L10n.t("General"))
            }

            // Only for players who bring their own Wine setup; Nightforge needs none of it.
            Section {
                DisclosureGroup(L10n.t("CrossOver, Whisky and your own Wine"), isExpanded: $showAdvanced) {
                    LabeledContent(L10n.t("Bottles Folder")) {
                        HStack {
                            TextField("", text: $bottlesRoot, prompt: Text(LibraryScanner.defaultBottlesRoot().path))
                                .labelsHidden()
                            Button(L10n.t("Choose …")) { model.chooseBottlesFolder() }
                        }
                    }
                    LabeledContent("Wine") {
                        TextField("", text: $runnerPath, prompt: Text(Launcher.detectRunner()))
                            .labelsHidden()
                    }
                    Text(L10n.t("Nightforge brings everything it needs. Fill this in only to also show games from CrossOver or Whisky bottles: leave Wine empty for CrossOver, or enter the path to the wine binary of Whisky or your own Wine."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.t("Rescan Library")) { model.reload() }
                }
            } header: {
                Text(L10n.t("Advanced"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
    }
}
