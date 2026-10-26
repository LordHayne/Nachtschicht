import AppKit
import GameController
import SwiftUI

/// Settings in tabs: where the games come from, how they run, the controller, and what
/// Nightforge is built on. The tabs are a row of buttons, so the pad reaches them too.
struct SettingsView: View {
    enum Tab: CaseIterable {
        case stores, general, controller, storage, about

        var label: String {
            switch self {
            case .stores: return L10n.t("Stores")
            case .general: return L10n.t("General")
            case .controller: return L10n.t("Controller")
            case .storage: return L10n.t("Storage")
            case .about: return L10n.t("About")
            }
        }
    }

    @State private var tab: Tab

    init(tab: Tab = .general) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Segmented(options: Tab.allCases.map { ($0, $0.label, nil) }, selection: tab, id: "settings.tab") { tab = $0 }
                .padding(.top, 16)
                .padding(.bottom, 4)
            Group {
                switch tab {
                case .stores: StoresSettings()
                case .general: GeneralSettings()
                case .controller: ControllerSettings()
                case .storage: StorageSettings()
                        .frame(height: 560)  // the list of games scrolls
                case .about: AboutSettings()
                        .frame(height: 560)  // the list of projects scrolls
                }
            }
            .formStyle(.grouped)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Stores

private struct StoresSettings: View {
    @EnvironmentObject private var model: LibraryModel
    @AppStorage(Prefs.Keys.bottlesRoot) private var bottlesRoot = ""
    @AppStorage(Prefs.Keys.runnerPath) private var runnerPath = ""

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button(L10n.t("Open Steam")) { model.openSteam() }
                        .disabled(!Engine.isSteamInstalled)
                        .padFocus("settings.openSteam", enabled: Engine.isSteamInstalled, activate: { model.openSteam() })
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Steam")
                        Text(steamStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L10n.t("Stores"))
            }

            // Only for players who bring their own Wine setup; Nightforge needs none of it.
            Section {
                LabeledContent(L10n.t("Bottles Folder")) {
                    HStack {
                        TextField("", text: $bottlesRoot, prompt: Text(LibraryScanner.defaultBottlesRoot().path))
                            .labelsHidden()
                        Button(L10n.t("Choose …")) { model.chooseBottlesFolder() }
                            .padFocus("settings.chooseBottles", activate: { model.chooseBottlesFolder() })
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
                    .padFocus("settings.rescan", activate: { model.reload() })
            } header: {
                Text(L10n.t("CrossOver, Whisky and your own Wine"))
            }
        }
    }

    private var steamStatus: String {
        guard Engine.isSteamInstalled else { return L10n.t("Not set up yet – Nightforge does it at the first start.") }
        let games = model.visibleCount == 1 ? L10n.t("1 game") : L10n.t("%ld games", model.visibleCount)
        return Engine.steamSignedIn ? L10n.t("Signed in · %@", games) : L10n.t("Not signed in · %@", games)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var model: LibraryModel
    @AppStorage(Prefs.Keys.afterLaunch) private var afterLaunch = AfterLaunch.hide.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @AppStorage(Prefs.Keys.performanceHUD) private var performanceHUD = false
    @AppStorage(Prefs.Keys.gameMode) private var gameMode = true
    @AppStorage(Prefs.Keys.sharpAndSmooth) private var sharpAndSmooth = true
    @AppStorage(Prefs.Keys.notifyDownloads) private var notifyDownloads = true
    @AppStorage(Prefs.Keys.reduceMotion) private var reduceMotionSetting = ""
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .padFocus("settings.language", selection: $language, values: AppLanguage.allCases.map(\.rawValue))
                Toggle(isOn: $sharpAndSmooth) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Sharp & smooth"))
                        Text(L10n.t("Every game gets Apple's MetalFX upscaling to full Retina sharpness and an even frame rate that fits your display (60 FPS on a 120 Hz screen). Change it per game in its options."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padFocus("settings.sharp", toggle: $sharpAndSmooth)
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
                .padFocus("settings.gameMode", toggle: $gameMode)
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
                .padFocus("settings.hud", toggle: $performanceHUD)
                Toggle(isOn: $notifyDownloads) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Notify me when downloads finish"))
                        Text(L10n.t("A macOS notification with a Play button while Nightforge is in the background. Your last five games are in the Dock menu, too."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padFocus("settings.notify", toggle: $notifyDownloads)
                Picker(L10n.t("After Launch"), selection: $afterLaunch) {
                    ForEach(AfterLaunch.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .padFocus("settings.afterLaunch", selection: $afterLaunch, values: AfterLaunch.allCases.map(\.rawValue))
            } header: {
                Text(L10n.t("General"))
            }

            Section {
                Toggle(isOn: reduceMotion) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("Reduce motion"))
                        Text(L10n.t("No zoom on covers, no sliding – plain cross-fades. Follows “Reduce motion” in macOS until you change it here."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padFocus("settings.reduceMotion", toggle: reduceMotion)
            } header: {
                Text(L10n.t("Accessibility"))
            }
        }
    }

    /// Shows what applies now; set back to what macOS says, it follows macOS again.
    private var reduceMotion: Binding<Bool> {
        Binding(
            get: { Prefs.reduceMotion(system: systemReduceMotion, stored: reduceMotionSetting) },
            set: { reduceMotionSetting = $0 == systemReduceMotion ? "" : ($0 ? "on" : "off") }
        )
    }
}

// MARK: - Controller

private struct ControllerSettings: View {
    @EnvironmentObject private var model: LibraryModel
    @AppStorage(Prefs.Keys.padGlyphs) private var padGlyphs = PadSymbols.Style.automatic.rawValue
    /// Bumped when a controller comes or goes, or its battery may have changed.
    @State private var refresh = 0
    @State private var pairing = false

    private static let bluetoothSettings = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!

    var body: some View {
        Form {
            Section {
                let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
                if pads.isEmpty {
                    Text(L10n.t("No controller connected."))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(pads.enumerated()), id: \.offset) { _, pad in
                    LabeledContent {
                        if let battery = pad.battery, battery.batteryState != .unknown {
                            Label("\(Int((battery.batteryLevel * 100).rounded())) %",
                                  systemImage: battery.batteryState == .charging ? "battery.100.bolt" : Self.batterySymbol(battery.batteryLevel))
                                .monospacedDigit()
                                .foregroundStyle(battery.batteryLevel < 0.2 && battery.batteryState != .charging ? Theme.sodium : .primary)
                                .help(L10n.t("Controller battery"))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pad.vendorName ?? pad.productCategory)
                            Text(L10n.t("Connected · works in every game and in Nightforge"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .id(refresh)
                if pairing {
                    Text(L10n.t("PlayStation: hold PS and Create until the light flashes. Xbox: hold the pair button on top until the logo flashes. Nintendo: hold the sync button. Then choose it in the Bluetooth settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(L10n.t("Pair a Controller …"), action: pair)
                    .padFocus("settings.pair", activate: pair)
            } header: {
                Text(L10n.t("Controllers"))
            }

            Section {
                Picker(L10n.t("Button labels"), selection: $padGlyphs) {
                    ForEach(PadSymbols.Style.allCases, id: \.self) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .padFocus("settings.padGlyphs", selection: $padGlyphs, values: PadSymbols.Style.allCases.map(\.rawValue))
                .onChange(of: padGlyphs) { _, _ in model.refreshPadSymbols() }
                Text(L10n.t("What the hints at the bottom of Nightforge show for the buttons: ✕ ○ □ △ or A B X Y."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in refresh += 1; pairing = false }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in refresh += 1 }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in refresh += 1 }
    }

    /// Pairing happens in macOS: open its Bluetooth settings and say what to press on the controller.
    private func pair() {
        pairing = true
        NSWorkspace.shared.open(Self.bluetoothSettings)
    }

    private static func batterySymbol(_ level: Float) -> String {
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Storage

private struct StorageSettings: View {
    @EnvironmentObject private var model: LibraryModel
    /// Nightforge's own folder without the games in it (engine, Windows environment, Steam, caches);
    /// nil while it's being measured.
    @State private var ownSize: Int64?

    private struct Disk {
        let name: String
        let total: Int64
        let free: Int64
    }

    private var disk: Disk? {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? SpaceCheck.existingFolder(for: Engine.supportDir).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        return Disk(name: values.volumeLocalizedName ?? "Macintosh HD", total: Int64(total),
                    free: values.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Installed and downloading games, biggest first.
    private var games: [Game] {
        model.allGames.filter { $0.install != .notInstalled && $0.install != .inStore }.sorted { $0.sizeOnDisk > $1.sizeOnDisk }
    }

    var body: some View {
        let games = self.games
        let gamesSize = games.reduce(Int64(0)) { $0 + $1.sizeOnDisk }
        Form {
            if let disk {
                Section {
                    let own = ownSize ?? 0
                    let other = max(0, disk.total - disk.free - gamesSize - own)
                    StorageBar(parts: [(gamesSize, Theme.ink.opacity(0.85)), (own, Theme.ink.opacity(0.5)), (other, Theme.ink.opacity(0.22))],
                               total: disk.total)
                    HStack(spacing: 16) {
                        legend(L10n.t("Games"), gamesSize, Theme.ink.opacity(0.85))
                        if let ownSize {
                            legend("Nightforge", ownSize, Theme.ink.opacity(0.5))
                        } else {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L10n.t("Measuring Nightforge …")) }
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        legend(L10n.t("Other"), other, Theme.ink.opacity(0.22))
                        Spacer()
                        Text(L10n.t("%@ free", Format.bytes(disk.free)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(L10n.t("“Nightforge” is the game engine, the Windows environment and Steam itself – everything besides the games."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(disk.name)
                }
            }

            Section {
                if games.isEmpty {
                    Text(L10n.t("No games on this Mac yet.")).foregroundStyle(.secondary)
                }
                ForEach(games) { game in
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(Format.bytes(game.sizeOnDisk)).monospacedDigit().foregroundStyle(.secondary)
                            Button { reveal(game) } label: { Image(systemName: "folder") }
                                .help(L10n.t("Show game folder in Finder"))
                                .accessibilityLabel(L10n.t("Show game folder in Finder"))
                                .padFocus("storage.reveal.\(game.id)", activate: { reveal(game) })
                            if model.canUninstall(game) {
                                Button(game.isInstalled ? L10n.t("Uninstall …") : L10n.t("Cancel Download")) { uninstall(game) }
                                    .padFocus("storage.uninstall.\(game.id)", activate: { uninstall(game) })
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.name).lineLimit(1)
                            Text(game.lastPlayed.map { L10n.t("Last played %@", Format.relative($0)) } ?? L10n.t("Never played"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L10n.t("Games on this Mac"))
            }
        }
        .task(id: model.allGames.count) {
            let builtIn = model.allGames.filter { $0.bottle.isBuiltIn && $0.install != .notInstalled && $0.install != .inStore }
                .reduce(Int64(0)) { $0 + $1.sizeOnDisk }
            let folder = Engine.supportDir
            let total = await Task.detached(priority: .utility) { LibraryScanner.folderSize(folder) }.value
            ownSize = max(0, total - builtIn)
        }
    }

    private func legend(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(Format.bytes(bytes))").monospacedDigit()
        }
        .font(.caption)
    }

    private func reveal(_ game: Game) {
        let folder = FileManager.default.fileExists(atPath: game.installDir.path) ? game.installDir : game.installDir.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Asks in the main window, like the game's own Uninstall button.
    private func uninstall(_ game: Game) {
        NSApp.windows.first { $0.title == "Nightforge" }?.makeKeyAndOrderFront(nil)
        model.requestUninstall(game)
    }
}

/// How a disk is used: one bar, parts left to right, the rest free.
private struct StorageBar: View {
    let parts: [(bytes: Int64, color: Color)]
    let total: Int64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle().fill(part.color)
                        .frame(width: max(0, geo.size.width * CGFloat(part.bytes) / CGFloat(max(total, 1)) - 2))
                }
                Spacer(minLength: 0)
            }
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - About

private struct AboutSettings: View {
    private struct Credit: Identifiable {
        let name: String
        let version: String?
        let role: String
        let license: String
        var id: String { name }
    }

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("No account. No telemetry. No background service."))
                            .fontWeight(.semibold)
                        Text(L10n.t("Nothing leaves your Mac unless you send it – a problem report opens on GitHub, filled in, and goes nowhere until you submit it."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "lock.fill")
                }
            } header: {
                Text(L10n.t("Nightforge %@", Updater.currentVersion))
            }

            Section {
                Text(L10n.t("Nightforge is free software under the GPL-3.0. It stands on these projects – thank you to everyone behind them. Their licence files ship inside the app."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(credits) { credit in
                    LabeledContent {
                        Text(credit.license)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 220, alignment: .trailing)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(credit.name)
                                if let version = credit.version {
                                    Text(version).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            Text(credit.role).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button(L10n.t("Show Licence Files"), action: showLicences)
                    .padFocus("settings.licences", activate: showLicences)
            } header: {
                Text(L10n.t("Built on"))
            }
        }
    }

    /// From the component list at hand (the last one fetched, else the app's own) – no network.
    private var credits: [Credit] {
        let components = ComponentStore.localManifest()?.components ?? []
        return components.map { Credit(name: Self.name(of: $0), version: $0.version, role: Self.role(of: $0), license: $0.license) }
            + [Credit(name: "umu-protonfixes", version: nil, role: L10n.t("Fixes for single games"), license: "BSD-2-Clause"),
               Credit(name: "AreWeAntiCheatYet", version: nil, role: L10n.t("Which games' anti-cheat runs where"), license: "MIT")]
    }

    private static func name(of component: Component) -> String {
        switch component.id {
        case "wine": return "Wine"
        case "winecx": return "Wine (CrossOver)"
        case "d3dmetal": return "D3DMetal"
        case "dxmt": return "DXMT"
        case "dxvk-macos": return "DXVK"
        case "moltenvk": return "MoltenVK"
        case "winetricks": return "winetricks"
        case "cabextract": return "cabextract"
        case "gamepad": return L10n.t("Wine with controller support")
        case "graphics": return L10n.t("Wine with DXMT")
        default: return component.id
        }
    }

    private static func role(of component: Component) -> String {
        switch component.id {
        case "wine", "winecx", "gamepad", "graphics": return L10n.t("Runs Windows games on the Mac")
        case "d3dmetal": return L10n.t("DirectX 12 on Metal (Apple)")
        case "dxmt": return L10n.t("DirectX 10 and 11 on Metal")
        case "dxvk-macos": return L10n.t("DirectX 9 to 11 on Vulkan")
        case "moltenvk": return L10n.t("Vulkan on Metal")
        case "winetricks": return L10n.t("Installs what games need from Windows")
        case "cabextract": return L10n.t("Unpacks Windows installers")
        default:
            switch component.kind {
            case .engine: return L10n.t("Runs Windows games on the Mac")
            case .graphics: return L10n.t("Graphics")
            case .tool: return L10n.t("Tool")
            }
        }
    }

    private func showLicences() {
        let files = ["LICENSE", "LICENSE-umu-protonfixes", "LICENSE-areweanticheatyet"]
            .compactMap { Bundle.main.url(forResource: $0, withExtension: nil) }
        if files.isEmpty {
            NSWorkspace.shared.open(URL(string: "https://github.com/LordHayne/Nightforge")!)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }
}
