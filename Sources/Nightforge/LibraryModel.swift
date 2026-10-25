import AppKit
import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    /// Everything the scan found.
    @Published private(set) var allGames: [Game] = []
    /// What's shown and navigated: `allGames` narrowed by the search.
    @Published private(set) var games: [Game] = []
    @Published var selectedIndex = 0 {
        didSet { loadStoreDetailsIfNeeded() }
    }
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            applyFilter(selectBestMatch: true)
            searchStore()
        }
    }
    /// Steam store hits for the current search, games the account doesn't own yet.
    @Published private(set) var storeResults: [Game] = []
    private var storeSearch: Task<Void, Never>?
    /// Bumped to move keyboard focus into the search field (⌘F).
    @Published private(set) var searchFocusRequest = 0
    /// The full-library grid instead of the single game with its cover rail.
    @Published var showingLibrary = false
    /// Covers per row in the grid, reported by the grid so ↑/↓ can jump a row.
    var gridColumns = 1
    @Published private(set) var isScanning = false
    @Published private(set) var launchingID: String?
    /// Steam is showing a question (licence, setup) for the game being launched.
    @Published private(set) var launchNeedsConfirmation = false
    /// The game's profile is installing runtimes (winetricks) before its first start.
    @Published private(set) var launchPreparing = false
    @Published var showingOptions = false
    /// Waiting for the user to confirm removing this game (or its download).
    @Published var pendingUninstall: Game?
    @Published private(set) var uninstallingID: String?
    /// Games whose Windows process is running right now, with that process's pid.
    @Published private(set) var running: [String: pid_t] = [:]
    @Published var errorMessage: String?
    @Published var controllerConnected = false
    /// A newer Nightforge release, offered with one click in the top bar.
    @Published private(set) var availableUpdate: AppUpdate?
    @Published private(set) var updating = false
    /// macOS Low Power Mode: CPU and graphics run much slower, and so do games.
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// First-run "Connect Steam" flow for Nightforge's own engine.
    let setup = SetupModel()

    private lazy var input = InputRouter()
    private var inputStarted = false

    init() {
        setup.onFinished = { [weak self] in self?.reload() }
    }

    /// Nothing to show and Nightforge's own Steam isn't ready yet.
    var needsSetup: Bool { allGames.isEmpty && !SetupModel.isComplete }

    var selected: Game? {
        games.indices.contains(selectedIndex) ? games[selectedIndex] : nil
    }

    func startInput() {
        guard !inputStarted else { return }
        inputStarted = true
        input.start(model: self)
        watchRunningGames()
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        Task {
            try? await Task.sleep(for: .seconds(3))  // after the window and Steam got going
            availableUpdate = await Updater.check()
        }
        // Back from buying in the browser (or from Steam): pick up newly owned games.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload(quiet: true) }
        }
    }

    // MARK: - Running games

    /// Wine shows each game process with its Windows path, e.g.
    /// "C:\…\steamapps\common\Oxygen Train\Oxygen Train.exe" – match that against the install folders.
    private func watchRunningGames() {
        Task {
            while !Task.isCancelled {
                let folders = Dictionary(
                    allGames.filter(\.isInstalled).map { ("\\steamapps\\common\\\($0.installDirName.lowercased())\\", $0.id) },
                    uniquingKeysWith: { first, _ in first }
                )
                let found = await Task.detached(priority: .utility) { Self.runningGames(folders) }.value
                if found != running { running = found }
                if restartSteamWhenIdle && found.isEmpty && launchingID == nil {
                    restartSteamWhenIdle = false
                    if let wine = await Engine.installedWine() { try? await Engine.restartSteamInBackground(wine) }
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    nonisolated private static func runningGames(_ folders: [String: String]) -> [String: pid_t] {
        guard !folders.isEmpty else { return [:] }
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,command="]
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [:] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()

        var result: [String: pid_t] = [:]
        for line in output.split(separator: "\n") {
            let lower = line.lowercased()
            // Steam's crash handler and similar helpers live in the same folder; the game's
            // own process is the first .exe there that isn't one of those.
            guard lower.contains(".exe"), !lower.contains("crashhandler"), !lower.contains("unitycrash") else { continue }
            for (folder, id) in folders where result[id] == nil && lower.contains(folder) {
                let fields = line.split(separator: " ", maxSplits: 1)
                if let pid = fields.first.flatMap({ pid_t($0) }) { result[id] = pid }
            }
        }
        return result
    }

    func isRunning(_ game: Game) -> Bool { running[game.id] != nil }

    /// Brings the running game's window to the front.
    func switchToGame(_ game: Game) {
        guard let pid = running[game.id] else { return }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
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
            allGames = found
            applyFilter()
            isScanning = false
            watchDownloads()
        }
    }

    private var downloadWatcher: Task<Void, Never>?

    /// While Steam downloads something, re-read the manifests every few seconds for progress.
    private func watchDownloads() {
        let downloading = allGames.contains { if case .downloading = $0.install { return true } else { return false } }
        guard downloading, downloadWatcher == nil else { return }
        downloadWatcher = Task {
            try? await Task.sleep(for: .seconds(3))
            downloadWatcher = nil
            reload(quiet: true)
        }
    }

    /// After a setting games get from Steam changed: restart it now if no game would be cut off.
    func applySteamSettings() {
        guard SetupModel.isComplete else { return }
        // Queued behind any start still in progress: two Steam starts at once end up as two
        // Steam instances fighting over the same prefix, and games no longer start.
        let previous = steamStartup
        steamStartup = Task {
            await previous?.value
            guard let wine = await Engine.installedWine() else { return }
            Engine.applyGameEnvironment(wine: wine)
            try? await Engine.ensureSteamRunning(wine, busy: !running.isEmpty)
        }
    }

    /// Keeps Nightforge's own Steam running hidden once it's set up.
    /// The engine check and Steam (re)start at app launch; game launches wait for it so a pending
    /// Steam restart can't cut off a game that was just started.
    private var steamStartup: Task<Void, Never>?

    func startBackgroundSteam() {
        // onAppear can fire more than once; one start per app run is enough.
        guard SetupModel.isComplete, steamStartup == nil else { return }
        Task { await ProfileStore.shared.refresh() }
        steamStartup = Task {
            guard let wine = try? await Engine.ensureEngine() else { return }
            // Let the running-game check see the processes before deciding on a restart.
            try? await Task.sleep(for: .seconds(4))
            try? await Engine.ensureSteamRunning(wine, busy: !running.isEmpty)
        }
    }

    /// The big button: play when installed, otherwise ask Steam to download it.
    func primaryAction() {
        guard let game = selected, uninstallingID != game.id else { return }
        if launchingID == game.id {
            if launchNeedsConfirmation && game.bottle.isBuiltIn { showSteamWindow() }
            return
        }
        if isRunning(game) {
            switchToGame(game)
            return
        }
        switch game.install {
        case .installed: launchSelected()
        case .notInstalled: if !game.isVROnly { download(game) }
        case .downloading: break
        case .inStore: openStorePage(game)
        }
    }

    /// Buying happens on Steam's own store page in the browser; Nightforge never sees payment data.
    /// Once Steam has the new licence, the game shows up in the library with its Download button.
    func openStorePage(_ game: Game) {
        guard let url = URL(string: "https://store.steampowered.com/app/\(game.appID)") else { return }
        NSWorkspace.shared.open(url)
    }

    func installUpdate() {
        guard let update = availableUpdate, !updating else { return }
        updating = true
        Task {
            do {
                try await Updater.install(update)  // quits and restarts Nightforge when done
            } catch {
                updating = false
                if case Updater.Failure.notWritable = error { NSWorkspace.shared.open(update.page) }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Steam store search

    /// Waits for a pause in typing, then asks the store; owned games are left out.
    private func searchStore() {
        storeSearch?.cancel()
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            if !storeResults.isEmpty { storeResults = []; applyFilter() }
            return
        }
        storeSearch = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let hits = await StoreSearch.shared.search(term)
            guard !Task.isCancelled, term == searchText.trimmingCharacters(in: .whitespaces) else { return }
            storeResults = hits.map(Self.storeGame)
            applyFilter()
        }
    }

    private static func storeGame(_ hit: StoreSearch.Hit) -> Game {
        var game = Game(
            appID: hit.appID, name: hit.name, bottle: Engine.bottle, steamRoot: Engine.steamRoot,
            steamExeWindowsPath: Engine.steamExeWindowsPath,
            installDir: Engine.steamRoot.appendingPathComponent("steamapps/common", isDirectory: true),
            sizeOnDisk: 0
        )
        game.install = .inStore
        game.macNative = hit.macNative ?? false
        game.storePrice = hit.price
        game.metascore = hit.metascore
        return game
    }

    /// Hits from the games-only search can lack price and platforms; fetch them once it's selected.
    private var storeDetailsRequested: Set<Int> = []

    private func loadStoreDetailsIfNeeded() {
        guard let game = selected, game.install == .inStore, game.storePrice == nil,
              storeDetailsRequested.insert(game.appID).inserted  // once: some games have no price at all
        else { return }
        Task {
            guard let hit = await StoreSearch.shared.details(for: game.appID),
                  let index = storeResults.firstIndex(where: { $0.appID == game.appID })
            else { return }
            var updated = Self.storeGame(hit)
            updated.metascore = hit.metascore ?? storeResults[index].metascore
            storeResults[index] = updated
            applyFilter()
        }
    }

    /// A download Steam only picks up after a restart, which waits while a game runs: restarting
    /// Steam then would end the game too.
    private var restartSteamWhenIdle = false

    private func download(_ game: Game) {
        Task {
            do {
                guard let wine = await Engine.installedWine() else { return }
                try Engine.requestDownload(appID: game.appID, name: game.name, installDir: game.installDirName)
                reload(quiet: true)
                if running.isEmpty && launchingID == nil {
                    try await Engine.restartSteamInBackground(wine)
                } else {
                    restartSteamWhenIdle = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Search & views

    /// Matches ignoring case, accents and punctuation, so "baldurs" finds "Baldur's Gate 3".
    private static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(String.init).joined()
    }

    /// `selectBestMatch`: while typing, jump to the first hit instead of keeping the old selection.
    private func applyFilter(selectBestMatch: Bool = false) {
        let previous = selected?.id
        let words = Self.searchKey(searchText).split(separator: " ").map(String.init)
        if words.isEmpty {
            games = allGames
        } else {
            let matches = allGames.filter { game in
                let name = Self.searchKey(game.name)
                return words.allSatisfy { name.contains($0) }
            }
            // Names where a word starts with the search ("ark" → ARK, Arkham) before mid-word hits
            // (Amnesia: The Dark Descent); otherwise keep the library order.
            func startsWord(_ game: Game) -> Bool {
                let nameWords = Self.searchKey(game.name).split(separator: " ")
                return words.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } }
            }
            let owned = Set(allGames.map(\.appID))
            games = matches.filter(startsWord) + matches.filter { !startsWord($0) }
                + storeResults.filter { !owned.contains($0.appID) }
        }
        selectedIndex = selectBestMatch && !words.isEmpty ? 0 : games.firstIndex(where: { $0.id == previous }) ?? 0
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    func toggleLibrary() {
        showingLibrary.toggle()
    }

    /// From the grid: show the chosen game in the big view, where its button is.
    func showSelectedGame() {
        showingLibrary = false
    }

    /// ↑/↓ in the grid move a whole row.
    func moveRow(_ delta: Int) {
        guard showingLibrary else { return }
        move(delta * max(gridColumns, 1))
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
            if game.bottle.isBuiltIn { await steamStartup?.value }
            let runner = game.bottle.isBuiltIn ? await Engine.installedWine()?.path : Prefs.runnerPath
            // Known fixes for this game (profiles/profiles.json); runtimes it needs come first.
            let profile = game.bottle.isBuiltIn ? await ProfileStore.shared.profile(for: game.appID) : nil
            let missing = Engine.missingWinetricks(profile?.winetricks ?? [])
            if !missing.isEmpty, let runner {
                launchPreparing = true
                await Engine.installWinetricks(missing, wine: URL(fileURLWithPath: runner))
                launchPreparing = false
            }
            var watcher = LaunchWatcher(steamRoot: game.steamRoot, appID: game.appID)
            var options = GameOptionsStore.load(game.appID)
            if game.bottle.isBuiltIn && options.graphics == .automatic
                && (profile?.graphics ?? Engine.defaultGraphics) == .dxmt {
                // Self-healing: did the last start with DXMT end within seconds? Then DXVK from now on.
                _ = GraphicsHealth.reviewLastDXMTLaunch(game.appID, steamRoot: game.steamRoot)
                if GraphicsHealth.dxmtFailed(game.appID) {
                    options.graphics = .dxvk
                } else {
                    GraphicsHealth.recordDXMTLaunch(game.appID)
                }
            }
            let refreshRate = NSScreen.main?.maximumFramesPerSecond ?? 60  // the game opens on the main display
            do {
                // Off the main thread: it reads Steam's app catalog and writes the registry, which
                // would freeze the window for a moment.
                try await Task.detached(priority: .userInitiated) {
                    try Launcher.launch(game, runnerPath: runner ?? "", options: options, profile: profile,
                                        displayRefreshRate: refreshRate)
                }.value
            } catch {
                launchingID = nil
                errorMessage = error.localizedDescription
                return
            }

            // Only get out of the way once the game is really running. A question from Steam can
            // take as long as the player needs; a launch that shows no sign of life ends after 2 min.
            var quietSeconds = 0
            var totalSeconds = 0
            var started = false
            var askingSince: Int?
            while quietSeconds < 120 && totalSeconds < 900 {
                try? await Task.sleep(for: .seconds(1))
                totalSeconds += 1
                switch watcher.poll() {
                case .running?:
                    started = true
                case .needsConfirmation?:
                    launchNeedsConfirmation = true
                    askingSince = askingSince ?? totalSeconds
                    quietSeconds = 0
                    continue
                case .continued?:
                    launchNeedsConfirmation = false
                    askingSince = nil
                    quietSeconds = 0
                    continue
                case .cancelled?:
                    break
                case .failed?:
                    errorMessage = L10n.t("Steam couldn't start %@.", game.name)
                case nil:
                    if !launchNeedsConfirmation { quietSeconds += 1 }
                    // Routine steps are answered within a second; a real question waits for the
                    // player in Steam's window, which runs hidden – so show it.
                    if let since = askingSince, totalSeconds - since == 3, game.bottle.isBuiltIn {
                        showSteamWindow()
                    }
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

    /// Brings Steam's main window, with the question it's waiting on, in front of Nightforge.
    func showSteamWindow() {
        Task {
            guard let wine = await Engine.installedWine() else { return }
            let windows = Engine.showSteamWindow(wine)
            try? await Task.sleep(for: .seconds(2))  // the window needs a moment to appear
            for pid in windows {
                NSRunningApplication(processIdentifier: pid)?.activate(options: .activateAllWindows)
            }
        }
    }

    // MARK: - Uninstall

    /// Only games in Nightforge's own Steam; CrossOver bottles are managed by their own Steam.
    /// Uninstalling stops Steam for a moment, so not while any game runs or starts – it would go too.
    func canUninstall(_ game: Game) -> Bool {
        guard game.isInstalled || { if case .downloading = game.install { return true } else { return false } }()
        else { return false }
        return game.bottle.isBuiltIn && uninstallingID == nil && launchingID == nil && running.isEmpty
    }

    func requestUninstall(_ game: Game? = nil) {
        guard let game = game ?? selected, canUninstall(game) else { return }
        pendingUninstall = game
    }

    func confirmUninstall() {
        guard let game = pendingUninstall else { return }
        pendingUninstall = nil
        uninstallingID = game.id
        Task {
            defer {
                uninstallingID = nil
                reload(quiet: true)
            }
            do {
                guard let wine = await Engine.installedWine() else { return }
                try await Engine.uninstall(appID: game.appID, installDirName: game.installDirName, wine: wine)
            } catch {
                errorMessage = L10n.t("%@ could not be uninstalled: %@", game.name, error.localizedDescription)
            }
        }
    }

    /// Opens Steam in Nightforge's prefix, e.g. to install a game.
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
