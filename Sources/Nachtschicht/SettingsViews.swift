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

            Toggle(isOn: $options.metalHUD) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("Performance HUD in game"))
                    Text(L10n.t("Shows the Metal HUD with FPS, frame time and GPU load."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

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

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
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
                Text(L10n.t("Leave empty for CrossOver. For Whisky or your own Wine, enter the path to the wine binary; the bottle is then passed as WINEPREFIX. “Quit launcher” makes sure nothing from Nachtschicht keeps running while you play."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
    }
}
