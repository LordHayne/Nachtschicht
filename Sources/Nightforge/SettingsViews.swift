import AppKit
import SwiftUI

struct GameOptionsSheet: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @State private var options: GameOptions

    init(game: Game) {
        self.game = game
        _options = State(initialValue: GameOptionsStore.load(game.appID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(game.name)
                .font(Theme.display(22))
                .lineLimit(2)

            if !game.bottle.isBuiltIn {
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
                    Picker(L10n.t("Graphics"), selection: $options.graphics) {
                        ForEach(GraphicsLayer.allCases) { Text($0.label).tag($0) }
                    }
                    Text(L10n.t("How DirectX 10/11 reaches the Mac's graphics. DXMT translates straight to Metal and is usually faster; DXVK takes a detour through Vulkan and works with more games."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("Save")) {
                    GameOptionsStore.save(options, for: game.appID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 470)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: LibraryModel
    @AppStorage(Prefs.Keys.bottlesRoot) private var bottlesRoot = ""
    @AppStorage(Prefs.Keys.runnerPath) private var runnerPath = ""
    @AppStorage(Prefs.Keys.afterLaunch) private var afterLaunch = AfterLaunch.quit.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @AppStorage(Prefs.Keys.performanceHUD) private var performanceHUD = false
    @AppStorage(Prefs.Keys.gameMode) private var gameMode = true

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
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
            } header: {
                Text(L10n.t("General"))
            }

            Section {
                LabeledContent(L10n.t("Bottles Folder")) {
                    HStack {
                        TextField("", text: $bottlesRoot, prompt: Text(LibraryScanner.defaultBottlesRoot().path))
                            .labelsHidden()
                        Button(L10n.t("Choose …")) { model.chooseBottlesFolder() }
                    }
                }
                Button(L10n.t("Rescan Library")) { model.reload() }
            } header: {
                Text(L10n.t("Library"))
            } footer: {
                Text(L10n.t("Leave empty to use the default CrossOver folder."))
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Wine") {
                    TextField("", text: $runnerPath, prompt: Text(Launcher.detectRunner()))
                        .labelsHidden()
                }
                Picker(L10n.t("After Launch"), selection: $afterLaunch) {
                    ForEach(AfterLaunch.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
            } header: {
                Text(L10n.t("Launching"))
            } footer: {
                Text(L10n.t("Leave empty for CrossOver. For Whisky or your own Wine, enter the path to the wine binary; the bottle is then passed as WINEPREFIX. “Quit launcher” makes sure nothing from Nightforge keeps running while you play."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
    }
}
