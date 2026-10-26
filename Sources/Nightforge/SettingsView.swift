import AppKit
import SwiftUI

/// Settings in tabs: where the games come from, how they run, and what Nightforge is
/// built on. The tabs are a row of buttons, so the pad reaches them too.
struct SettingsView: View {
    enum Tab: CaseIterable {
        case stores, general, about

        var label: String {
            switch self {
            case .stores: return L10n.t("Stores")
            case .general: return L10n.t("General")
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
                        Text(L10n.t("A macOS notification with a Play button while Nightforge is in the background."))
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
        }
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
