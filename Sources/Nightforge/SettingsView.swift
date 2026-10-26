import AppKit
import SwiftUI

/// Settings in tabs: where the games come from and how they run. The tabs are a row of
/// buttons, so the pad reaches them too.
struct SettingsView: View {
    enum Tab: CaseIterable {
        case stores, general

        var label: String {
            switch self {
            case .stores: return L10n.t("Stores")
            case .general: return L10n.t("General")
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
