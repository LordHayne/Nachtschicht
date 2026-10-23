import AppKit
import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var selectedIndex = 0
    @Published private(set) var isScanning = false
    @Published private(set) var launchingID: String?
    /// Steam is showing a question (licence, setup) for the game being launched.
    @Published private(set) var launchNeedsConfirmation = false
    @Published var showingOptions = false
    @Published var errorMessage: String?
    @Published var controllerConnected = false

    /// First-run "Connect Steam" flow for Nachtschicht's own engine.
    let setup = SetupModel()

    private lazy var input = InputRouter()
    private var inputStarted = false

    init() {
        setup.onFinished = { [weak self] in self?.reload() }
    }

    /// Nothing to show and Nachtschicht's own Steam isn't ready yet.
    var needsSetup: Bool { games.isEmpty && !SetupModel.isComplete }

    var selected: Game? {
        games.indices.contains(selectedIndex) ? games[selectedIndex] : nil
    }

    func startInput() {
        guard !inputStarted else { return }
        inputStarted = true
        input.start(model: self)
    }

    /// `quiet` refreshes without the scanning indicator (used for download progress).
    func reload(quiet: Bool = false) {
        guard !isScanning else { return }
        isScanning = !quiet
        let root = Prefs.bottlesRoot
        let builtIn = Engine.isSteamInstalled ? [Engine.bottle] : []
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                LibraryScanner.scan(bottlesRoot: root, extraBottles: builtIn)
            }.value
            let previous = selected?.id
            games = found
            selectedIndex = found.firstIndex(where: { $0.id == previous }) ?? 0
            isScanning = false
            watchDownloads()
        }
    }

    private var downloadWatcher: Task<Void, Never>?

    /// While Steam downloads something, re-read the manifests every few seconds for progress.
    private func watchDownloads() {
        let downloading = games.contains { if case .downloading = $0.install { return true } else { return false } }
        guard downloading, downloadWatcher == nil else { return }
        downloadWatcher = Task {
            try? await Task.sleep(for: .seconds(3))
            downloadWatcher = nil
            reload(quiet: true)
        }
    }

    /// Keeps Nachtschicht's own Steam running hidden once it's set up.
    func startBackgroundSteam() {
        guard SetupModel.isComplete else { return }
        Task {
            guard let wine = try? await Engine.ensureEngine() else { return }
            try? Engine.ensureSteamRunning(wine)
        }
    }

    /// The big button: play when installed, otherwise ask Steam to download it.
    func primaryAction() {
        guard let game = selected else { return }
        switch game.install {
        case .installed: launchSelected()
        case .notInstalled: if !game.isVROnly { download(game) }
        case .downloading: break
        }
    }

    private func download(_ game: Game) {
        Task {
            do {
                guard let wine = await Engine.installedWine() else { return }
                try Engine.requestDownload(appID: game.appID, name: game.name, installDir: game.installDirName)
                reload(quiet: true)
                try await Engine.restartSteamInBackground(wine)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func move(_ delta: Int) {
        guard !games.isEmpty else { return }
        selectedIndex = max(0, min(games.count - 1, selectedIndex + delta))
    }

    func jump(toStart: Bool) {
        guard !games.isEmpty else { return }
        selectedIndex = toStart ? 0 : games.count - 1
    }

    func launchSelected() {
        guard let game = selected, game.isInstalled, launchingID == nil else { return }
        launchingID = game.id
        launchNeedsConfirmation = false
        let behavior = Prefs.afterLaunch
        Task {
            let runner = game.bottle.isBuiltIn ? await Engine.installedWine()?.path : Prefs.runnerPath
            var watcher = LaunchWatcher(steamRoot: game.steamRoot, appID: game.appID)
            do {
                try Launcher.launch(game, runnerPath: runner ?? "", options: GameOptionsStore.load(game.appID))
            } catch {
                launchingID = nil
                errorMessage = error.localizedDescription
                return
            }

            // Only get out of the way once the game is really running. A question from Steam can
            // take as long as the player needs; a launch that shows no sign of life ends after 2 min.
            var quietSeconds = 0
            var started = false
            while quietSeconds < 120 {
                try? await Task.sleep(for: .seconds(1))
                switch watcher.poll() {
                case .running?:
                    started = true
                case .needsConfirmation?:
                    launchNeedsConfirmation = true
                    quietSeconds = 0
                    continue
                case .failed?:
                    errorMessage = L10n.t("Steam couldn't start %@.", game.name)
                case nil:
                    if !launchNeedsConfirmation { quietSeconds += 1 }
                    continue
                }
                break
            }
            launchingID = nil
            launchNeedsConfirmation = false
            guard started else { return }

            switch behavior {
            case .quit: NSApp.terminate(nil)
            case .hide: NSApp.hide(nil)
            case .stay: break
            }
        }
    }

    /// Opens Steam in Nachtschicht's prefix, e.g. to install a game.
    func openSteam() {
        Task {
            guard let wine = await Engine.installedWine() else { return }
            do {
                try Engine.startSteam(wine)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func revealSelected() {
        guard let game = selected else { return }
        let fm = FileManager.default
        let target = fm.fileExists(atPath: game.installDir.path) ? game.installDir : game.steamRoot
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func chooseBottlesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = Prefs.bottlesRoot
        panel.prompt = L10n.t("Use This Folder")
        panel.message = L10n.t("Choose the folder that contains your bottles, or a single bottle.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Prefs.Keys.bottlesRoot)
        reload()
    }
}
