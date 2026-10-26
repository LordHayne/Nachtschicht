import AppKit
import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    /// Everything the scan found.
    @Published private(set) var allGames: [Game] = []
    /// What's shown and navigated: `allGames` narrowed by the search.
    @Published private(set) var games: [Game] = []
    @Published var selectedIndex = 0 {
        didSet {
            loadStoreDetailsIfNeeded()
            if let game = selected { Task { _ = await insight(of: game) } }
        }
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
    /// What the launch is busy with when it's more than waiting for Steam ("Restarting Steam …").
    @Published private(set) var launchStatus: String?
    /// A game that ended right after starting with every way Nightforge knows.
    @Published var failedLaunch: FailedLaunch?
    /// What Nightforge knows about installed games before starting them, by app ID.
    @Published private(set) var insights: [Int: GameInsight] = [:]
    private var analyses: [Int: GameAnalysis] = [:]
    @Published var showingOptions = false
    /// Waiting for the user to confirm removing this game (or its download).
    @Published var pendingUninstall: Game?
    /// Waiting for the user to confirm removing the Windows version of a game that now runs its Mac one.
    @Published var pendingLeftoverRemoval: Game?
    /// Steam for Mac being set up for a game whose Mac version is wanted.
    @Published var macSetup: MacSteamSetup?
    /// A game about to open in GeForce Now for the first time: what that means is said once.
    @Published var pendingCloudGame: Game?
    private var macSteamPrewarmed = false
    @Published private(set) var uninstallingID: String?
    /// Games whose Windows process is running right now, with that process's pid.
    @Published private(set) var running: [String: pid_t] = [:]
    @Published var errorMessage: String?
    @Published var controllerConnected = false
    /// The buttons of the controller in use, as that controller labels them (InputRouter).
    @Published var padSymbols = PadSymbols()
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
        // Left over from an earlier run whose Steam for Mac has ended since: a Steam the player
        // starts later isn't Nightforge's to quit.
        if !MacSteam.isRunning { MacSteam.startedByNightforge = false }
        Task { await MacSteam.guardWindows() }
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
                let loaded = libraryLoaded
                let folders = Self.processFolders(allGames)
                let found = await Task.detached(priority: .utility) { Self.runningGames(folders) }.value
                if found != running { running = found }
                if loaded { runningScanned = true }  // only a look with the games known counts
                watchForGameEnd(found)
                if restartSteamWhenIdle && found.isEmpty && launchingID == nil {
                    restartSteamWhenIdle = false
                    if let wine = await Engine.installedWine() { try? await Engine.restartSteamInBackground(wine) }
                }
                // Every few seconds while it matters (Nightforge in front, a game running or starting),
                // otherwise less often: nothing waits on it then, and the Mac stays quieter.
                let busy = NSApp.isActive || !found.isEmpty || launchingID != nil
                try? await Task.sleep(for: .seconds(busy ? 3 : 10))
            }
        }
    }

    // MARK: - Back after a game

    /// Games Nightforge started, from when their process shows up until it ends.
    private var startedHere: Set<String> = []
    private var playing: Set<String> = []
    private var goneFor = 0

    /// Once the games Nightforge started have all ended (gone for three looks, ~6–9 s, so a
    /// launcher handing over to the game doesn't count), Nightforge comes back to the front: the
    /// controller keeps working, and neither the desktop nor Steam is what the player sees.
    private func watchForGameEnd(_ found: [String: pid_t]) {
        playing.formUnion(startedHere.intersection(found.keys))
        startedHere.subtract(playing)
        guard !playing.isEmpty else { return }
        if playing.contains(where: { found[$0] != nil }) {
            goneFor = 0
            return
        }
        goneFor += 1
        guard goneFor >= 3 else { return }
        playing = []
        goneFor = 0
        comeBack()
    }

    private func comeBack() {
        MacSteam.hide()
        // Since macOS 14 an app can't push itself to the front; opening it through Launch
        // Services can, and unhides it too.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        reload(quiet: true)  // play time, last played
    }

    /// What a game's processes show in `ps`, by game: Wine's Windows path of the game folder, or
    /// for Mac versions the folder itself.
    private static func processFolders(_ games: [Game]) -> [String: String] {
        Dictionary(games.filter(\.isInstalled).map { game in
            game.platform == .mac
                ? (game.installDir.path.lowercased() + "/", game.id)
                : ("\\steamapps\\common\\\(game.installDirName.lowercased())\\", game.id)
        }, uniquingKeysWith: { first, _ in first })
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
            let fields = line.drop { $0 == " " }.split(separator: " ", maxSplits: 1)
            guard fields.count == 2, let pid = pid_t(fields[0]) else { continue }
            let command = fields[1].lowercased()
            // Steam's crash handler and similar helpers live in the same folder; the game's
            // own process is the first .exe there that isn't one of those.
            guard !command.contains("crashhandler"), !command.contains("unitycrash") else { continue }
            let windowsProgram = command.contains(".exe")
            for (folder, id) in folders where result[id] == nil {
                // Mac versions: the program itself runs from the folder ("/…/steamapps/common/Game/
                // Game.app/Contents/MacOS/Game"); a script that merely names the folder doesn't count.
                let matches = folder.hasPrefix("/") ? command.hasPrefix(folder) : windowsProgram && command.contains(folder)
                if matches { result[id] = pid }
            }
        }
        return result
    }

    /// The running-game check has looked at the processes at least once, knowing the library.
    private var runningScanned = false
    /// The first library scan has finished.
    private var libraryLoaded = false

    /// The name of the program a process runs ("No Man's Sky"), as crash reports are named.
    nonisolated private static func programName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }

    /// macOS wrote a crash report for `program` since `date` (~/Library/Logs/DiagnosticReports).
    nonisolated private static func crashed(_ program: String, since date: Date) -> Bool {
        let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.contains { file in
            ["ips", "crash"].contains(file.pathExtension) && file.lastPathComponent.hasPrefix(program)
                && ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= date
        }
    }

    func isRunning(_ game: Game) -> Bool { running[game.id] != nil }

    /// A game of this platform is running – Windows games depend on Nightforge's Wine Steam,
    /// Mac versions on Steam for Mac.
    private func anyRunning(_ platform: Platform) -> Bool { runningGame(platform) != nil }

    /// Steam for Mac is busy for a Mac version: one is running or starting. The Wine Steam stays
    /// out of the way then – signing in, it would sign Steam for Mac out (one sign-in per account),
    /// and the game's saves would no longer reach Steam Cloud.
    private var macSteamBusy: Bool {
        anyRunning(.mac) || allGames.contains { $0.id == launchingID && $0.platform == .mac }
    }

    private func runningGame(_ platform: Platform) -> Game? {
        let ids = Set(running.keys)
        return allGames.first { ids.contains($0.id) && $0.platform == platform }
    }

    /// Steam can be signed in on one client at a time, so starting the other Steam would sign out
    /// the one a running game uses. Says so and returns false while such a game runs.
    private func otherSteamFree(for platform: Platform) -> Bool {
        guard let busy = runningGame(platform == .mac ? .windows : .mac) else { return true }
        errorMessage = L10n.t("%@ is still running and needs Steam. Steam can be signed in only once at a time, so quit the game first.", busy.name)
        return false
    }

    /// Brings the running game's window to the front.
    func switchToGame(_ game: Game) {
        guard let pid = running[game.id] else { return }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
    }

    /// `quiet` refreshes without the scanning indicator (used for download progress).
    func reload(quiet: Bool = false) {
        if !quiet { isScanning = true }
        // One scan at a time: two overlapping ones could land in the wrong order and bring back an
        // uninstalled game or an older download state. A request during a scan gets one scan after it.
        guard !scanInFlight else {
            scanAgain = true
            return
        }
        scanInFlight = true
        Task { await rescan() }
    }

    private var scanInFlight = false
    private var scanAgain = false

    /// Scans the library and shows what it found.
    private func rescan() async {
        let root = Prefs.bottlesRoot
        let builtIn = Engine.isSteamInstalled ? [Engine.bottle] : []
        let preferWindows = await ProfileStore.shared.preferWindows()
        let blocks = await ProfileStore.shared.antiCheatBlocks()
        antiCheatBlocks = blocks
        let found = await Task.detached(priority: .userInitiated) {
            LibraryScanner.markAntiCheat(
                LibraryScanner.merge(LibraryScanner.scan(bottlesRoot: root, extraBottles: builtIn),
                                     mac: LibraryScanner.scanMac(), preferWindows: preferWindows),
                blocks: blocks)
        }.value
        let wasDownloading = Set(allGames.filter { Self.isDownloading($0.install) }.map(\.id))
        allGames = found
        libraryLoaded = true
        for game in found where game.isInstalled && wasDownloading.contains(game.id) { prepare(game) }
        applyFilter()
        watchDownloads()
        afterScan()
        if scanAgain {
            scanAgain = false
            Task { await rescan() }
        } else {
            scanInFlight = false
            isScanning = false
        }
    }

    /// Steam for Mac starts in the background with Nightforge while it has a Mac version to
    /// download. Not otherwise: it would sign the Wine Steam out (one sign-in per account), which
    /// most games need; Play starts it when a Mac version is played.
    private func afterScan() {
        if MacSteam.isReady { Engine.excludeGamesFromBackup(steamapps: MacSteam.steamapps) }
        let macDownload = allGames.contains { game in
            (game.platform == .mac && Self.isDownloading(game.install)) || Self.isDownloading(game.macPending)
        }
        if !macSteamPrewarmed, macDownload, MacSteam.isReady, !anyRunning(.windows), launchingID == nil {
            macSteamPrewarmed = true
            if !MacSteam.isRunning { MacSteam.start() }
        }
        takeTurnsDownloading()
    }

    /// One Steam can be signed in at a time, and a signed-out one soon gets no download servers
    /// any more ("Failed to get list of download sources"). With downloads waiting in both, the
    /// signed-in one finishes first, then the other is signed in – not while a game runs or starts.
    private var lastSignInSwitch = Date.distantPast
    /// How far the Mac downloads had got when Steam for Mac last got its turn.
    private var lastMacTurnProgress: Double?

    private func takeTurnsDownloading() {
        guard launchingID == nil, running.isEmpty, Date().timeIntervalSince(lastSignInSwitch) > 120 else { return }
        let macDownload = allGames.contains { game in
            (game.platform == .mac && Self.isDownloading(game.install)) || Self.isDownloading(game.macPending)
        }
        let windowsDownload = allGames.contains { $0.platform == .windows && $0.bottle.isBuiltIn && Self.isDownloading($0.install) }
        // A Mac download that got nowhere in its last turn (Steam for Mac finds no download
        // servers, say) doesn't get another: Steam for Mac would come up and sign the Wine Steam out
        // every few minutes for nothing. Any progress lets it take turns again.
        // What the scan measured (it asks nettop off the main thread); asking again here would block the window.
        let macProgress = allGames.compactMap { game in
            Self.downloadFraction(game.macPending) ?? (game.platform == .mac ? Self.downloadFraction(game.install) : nil)
        }.reduce(0, +)
        let macStalled = lastMacTurnProgress.map { macProgress <= $0 } ?? false
        if macDownload, MacSteam.isReady, !MacSteam.signedIn, !(windowsDownload && Engine.steamSignedIn), !macStalled {
            lastSignInSwitch = Date()
            lastMacTurnProgress = macProgress
            Task {
                if MacSteam.isRunning { await MacSteam.quit() }
                MacSteam.start()
            }
        } else if windowsDownload, Engine.isSteamRunning, Engine.sessionReplaced(), !(macDownload && MacSteam.signedIn) {
            lastSignInSwitch = Date()
            Task {
                guard let wine = await Engine.installedWine() else { return }
                try? await Engine.restartSteamInBackground(wine)
            }
        }
    }

    private static func isDownloading(_ state: InstallState?) -> Bool {
        if case .downloading? = state { return true }
        return false
    }

    /// How far a download has got (0 while Steam hasn't worked out its size); nil when it isn't one.
    private static func downloadFraction(_ state: InstallState?) -> Double? {
        if case .downloading(let fraction)? = state { return fraction ?? 0 }
        return nil
    }

    private var downloadWatcher: Task<Void, Never>?

    /// While Steam downloads something, re-read the manifests every few seconds for progress.
    private func watchDownloads() {
        let downloading = allGames.contains { Self.isDownloading($0.install) || Self.isDownloading($0.macPending) }
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
            guard let wine = await Engine.installedWine(), !macSteamBusy else { return }
            await Engine.offMain { Engine.applyGameEnvironment(wine: wine) }
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
            // Let the running-game check see the processes before deciding on a restart – or on
            // replacing the engine's files, which ends the Wine session a game would run in.
            while !runningScanned { try? await Task.sleep(for: .milliseconds(100)) }
            // A new engine that can't be fetched now (offline, broken download): Steam starts with
            // the one already installed, and the new one is tried again at the next start.
            var ensured = try? await Engine.ensureEngine(gameRunning: !running.isEmpty)
            if ensured == nil { ensured = await Engine.installedWine() }
            guard let wine = ensured else { return }
            // Signing in would sign out the Steam for Mac a running Mac game uses; Play starts it later.
            guard !macSteamBusy else { return }
            try? await Engine.ensureSteamRunning(wine, busy: !running.isEmpty)
            Task { await self.watchSteamStart(wine) }
        }
    }

    /// Steam hangs now and then while starting under Wine (see Engine.steamLooksStuck), and one
    /// restart fixes it. Watched for the first two minutes, ideally before anyone presses Play.
    private func watchSteamStart(_ wine: URL) async {
        for _ in 0..<24 {
            try? await Task.sleep(for: .seconds(5))
            if Engine.steamSignedIn { return }
            if launchingID == nil, running.isEmpty, Engine.steamLooksStuck(quietFor: 45) {
                _ = await restartStuckSteam(wine)
                return
            }
        }
    }

    /// Restarts a hung Steam, queued like any other Steam start so a launch waits for it.
    /// True once it has signed in again (up to 90 s).
    private func restartStuckSteam(_ wine: URL) async -> Bool {
        let previous = steamStartup
        let restart = Task {
            await previous?.value
            try? await Engine.restartSteamInBackground(wine)
        }
        steamStartup = restart
        await restart.value
        for _ in 0..<90 {
            if Engine.steamSignedIn { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    /// The big button: play when installed, otherwise ask Steam to download it.
    func primaryAction() {
        guard let game = selected, uninstallingID != game.id else { return }
        if launchingID == game.id {
            if launchNeedsConfirmation && game.platform == .mac {
                MacSteam.show()
            } else if launchNeedsConfirmation && game.bottle.isBuiltIn {
                showSteamWindow()
            }
            return
        }
        if isRunning(game) {
            switchToGame(game)
            return
        }
        if game.playsInCloud {
            playInCloud(game)
            return
        }
        switch game.install {
        case .installed: launchSelected()
        case .installed where game.antiCheatBlock != nil: break
        case .notInstalled where game.isVROnly || game.antiCheatBlock != nil: break
        case .notInstalled: download(game)
        case .downloading: if game.downloadNeedsSpace != nil { resumeDownload(game) }
        case .inStore: openStorePage(game)
        }
    }

    /// Anti-cheat games GeForce Now streams open there, with the copy the player owns on Steam.
    /// The first time Nightforge says what that involves (NVIDIA account, free hour) before going.
    func playInCloud(_ game: Game) {
        guard let url = game.antiCheatBlock?.geforceNowURL else { return }
        if UserDefaults.standard.bool(forKey: Prefs.Keys.geforceNowExplained) {
            NSWorkspace.shared.open(url)
        } else {
            pendingCloudGame = game
        }
    }

    func confirmCloud() {
        guard let url = pendingCloudGame?.antiCheatBlock?.geforceNowURL else { return }
        pendingCloudGame = nil
        UserDefaults.standard.set(true, forKey: Prefs.Keys.geforceNowExplained)
        NSWorkspace.shared.open(url)
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
            storeResults = hits.map(storeGame)
            applyFilter()
        }
    }

    /// Games whose anti-cheat stops them on a Mac, so the store search can say so before buying.
    private var antiCheatBlocks: [Int: AntiCheatBlock] = [:]

    private func storeGame(_ hit: StoreSearch.Hit) -> Game {
        var game = Game(
            appID: hit.appID, name: hit.name, bottle: Engine.bottle, steamRoot: Engine.steamRoot,
            steamExeWindowsPath: Engine.steamExeWindowsPath,
            installDir: Engine.steamRoot.appendingPathComponent("steamapps/common", isDirectory: true),
            sizeOnDisk: 0
        )
        game.install = .inStore
        game.macNative = hit.macNative ?? false
        game.controller = hit.controller ?? .none
        game.storePrice = hit.price
        game.metascore = hit.metascore
        // Store hits don't say whether there's single player, so only blocks that always hold.
        if hit.macNative != true, let block = antiCheatBlocks[hit.appID], !block.onlineOnly { game.antiCheatBlock = block }
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
            var updated = storeGame(hit)
            updated.metascore = hit.metascore ?? storeResults[index].metascore
            storeResults[index] = updated
            applyFilter()
        }
    }

    /// A download Steam only picks up after a restart, which waits while a game runs: restarting
    /// Steam then would end the game too.
    private var restartSteamWhenIdle = false

    private func download(_ game: Game) {
        if game.platform == .mac {
            downloadMac(game)
            return
        }
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

    /// A download Steam stopped for lack of disk space: once there's room, unpause it in Steam's
    /// manifest and restart that Steam, which then carries on – by itself it never tries again.
    func resumeDownload(_ game: Game) {
        guard let needed = game.downloadNeedsSpace else { return }
        let free = Self.freeSpace(at: game.installDir.deletingLastPathComponent())
        guard free >= needed else {
            errorMessage = L10n.t("There's still not enough space: Steam needs %@ for %@, your Mac has %@ free.",
                                  Format.bytes(needed), game.name, Format.bytes(free))
            return
        }
        let steamapps = game.installDir.deletingLastPathComponent().deletingLastPathComponent()
        Engine.unpauseDownload(appID: game.appID, steamapps: steamapps)
        Task {
            if game.platform == .mac {
                guard !anyRunning(.mac) else { return }  // it carries on at Steam for Mac's next start
                await MacSteam.quit()
                MacSteam.start()
            } else if let wine = await Engine.installedWine() {
                if running.isEmpty && launchingID == nil {
                    try? await Engine.restartSteamInBackground(wine)
                } else {
                    restartSteamWhenIdle = true
                }
            }
            reload(quiet: true)
        }
    }

    /// Space left for downloads on the volume holding `folder`.
    nonisolated static func freeSpace(at folder: URL) -> Int64 {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Mac versions

    /// Opens the Steam for Mac setup when a game's Mac version is wanted and Steam for Mac isn't
    /// ready yet; Nightforge carries on with `next` once the player has signed in.
    private func needsMacSteam(_ game: Game, then next: MacSteamSetup.Next) -> Bool {
        guard game.platform == .mac, !MacSteam.isReady else { return false }
        guard macSetup == nil else { return true }
        let setup = MacSteamSetup(game: game, next: next)
        setup.onReady = { [weak self] setup in
            guard let self else { return }
            self.macSetup = nil
            switch setup.next {
            case .download: self.downloadMac(setup.game)
            case .play: self.launch(setup.game)
            }
        }
        macSetup = setup
        return true
    }

    func closeMacSetup() {
        macSetup?.cancel()
        macSetup = nil
    }

    /// From the setup sheet: this game keeps to its Windows version.
    func useWindowsVersion(of game: Game) {
        closeMacSetup()
        var options = GameOptionsStore.load(game.appID)
        options.version = .windows
        GameOptionsStore.save(options, for: game.appID)
        MacHealth.reset(game.appID)
        reload(quiet: true)
    }

    /// For a game played through its installed Windows version: fetch its Mac version in the
    /// background; the game switches over once it's installed.
    func loadMacVersion(of game: Game) {
        downloadMac(LibraryScanner.macEntry(for: game))
    }

    /// Stops fetching the Mac version (asks first, like any download).
    func cancelMacVersion(of game: Game) {
        var entry = LibraryScanner.macEntry(for: game)
        entry.listID = game.id + "#mac"  // the Windows version stays playable meanwhile
        requestUninstall(entry)
    }

    private func downloadMac(_ game: Game) {
        guard !needsMacSteam(game, then: .download) else { return }
        guard MacSteam.signedIn || otherSteamFree(for: .mac) else { return }
        Task {
            do {
                try await MacSteam.download(appID: game.appID, name: game.name, installDir: game.installDirName,
                                            macGameRunning: anyRunning(.mac))
                reload(quiet: true)
                await watchMacDownloadStart(game)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Steam for Mac normally takes up the requested download within a minute of signing in. If it
    /// hasn't, its install dialog does the same with one click; if it hasn't signed in (an expired
    /// login), its window comes up for that.
    private func watchMacDownloadStart(_ game: Game) async {
        var signedInFor = 0
        for second in 1...180 {
            try? await Task.sleep(for: .seconds(1))
            if MacSteam.downloadStarted(appID: game.appID) { return }
            signedInFor = MacSteam.signedIn ? signedInFor + 1 : 0
            if second == 40 && signedInFor == 0 { MacSteam.show() }
            if signedInFor >= 60 {
                MacSteam.ask("install/\(game.appID)")
                return
            }
        }
    }

    /// Starts a Mac version through Steam for Mac and follows it until the game runs.
    private func launchMac(_ game: Game) {
        guard !needsMacSteam(game, then: .play) else { return }
        guard MacSteam.signedIn || otherSteamFree(for: .mac) else { return }
        launchingID = game.id
        launchNeedsConfirmation = false
        launchStatus = nil
        let behavior = Prefs.afterLaunch
        let arguments = GameOptionsStore.load(game.appID).extraArgs.trimmingCharacters(in: .whitespaces)
        Task {
            defer {
                launchingID = nil
                launchNeedsConfirmation = false
                launchStatus = nil
            }
            // A Wine Steam that is still starting would sign in after Steam for Mac and sign it out.
            if Engine.isSteamRunning, !Engine.steamSignedIn, !Engine.sessionReplaced(),
               let wine = await Engine.installedWine() {
                launchStatus = L10n.t("Starting Steam for Mac …")
                try? await Engine.stopSteam(wine)
            }
            if !MacSteam.isRunning {
                launchStatus = L10n.t("Starting Steam for Mac …")
                MacSteam.start()
            } else if MacSteam.sessionReplaced {
                // The Wine Steam signed in since; signing in again needs a fresh start. Without it
                // the game would start without its cloud saves.
                launchStatus = L10n.t("Signing in to Steam …")
                await MacSteam.quit()
                MacSteam.start()
            }
            // Steam turns commands away until it has signed in and finished starting.
            var waited = 0
            while !(MacSteam.signedIn && MacSteam.startupFinished) && waited < 90 {
                if waited == 25 {
                    launchStatus = L10n.t("Sign in in the Steam window")
                    MacSteam.show()
                }
                try? await Task.sleep(for: .seconds(1))
                waited += 1
            }
            launchStatus = nil
            // steam://run/<id>//<arguments>: the extra part goes to the game.
            let extra = arguments.isEmpty ? ""
                : "//" + (arguments.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")
            await takeSavesAlong(game, to: .mac)
            let installDir = MacSteam.steamapps.appendingPathComponent("common/\(game.installDirName)", isDirectory: true)
            await Task.detached(priority: .userInitiated) { ControllerCompatibility.prepare(installDir: installDir) }.value
            let watcher = LaunchWatcher(steamRoot: MacSteam.root, appID: game.appID)
            let launchStarted = Date()
            let run = { MacSteam.open("run/\(game.appID)" + extra) }
            run()
            let start = await waitForMacStart(game, watcher: watcher, send: run)
            switch start {
            case .failed:
                if !fallBackToWindows(game) { errorMessage = L10n.t("Steam couldn't start %@.", game.name) }
                return
            case .noSignOfLife:
                return
            case .processSeen, .steamSaysRunning:
                break
            }
            launchingID = nil
            SteamPriority.watch(game)
            startedHere.insert(game.id)
            // Steam's window may still be up from a question it asked; the game has the stage now.
            MacSteam.hide()
            await bringToFront(game)

            // The first start of a Mac version: does it run past its first seconds? Only judged
            // when its process was seen at all – Steam may know better where a game runs from.
            // Ending early alone isn't a fail (the player may have closed it, or a launcher window);
            // a crash report from macOS is.
            if start == .processSeen && !MacHealth.confirmed(game.appID) {
                let folders = Self.processFolders([game])
                let program = await Task.detached(priority: .utility) {
                    Self.runningGames(folders)[game.id].flatMap(Self.programName)
                }.value
                if await survivesFirstSeconds(game) {
                    MacHealth.confirm(game.appID)
                } else if let program, Self.crashed(program, since: launchStarted), fallBackToWindows(game) {
                    return
                }
            }
            switch behavior {
            case .quit: NSApp.terminate(nil)
            case .hide: NSApp.hide(nil)
            case .stay: break
            }
        }
    }

    /// The first start of a game's other version (SaveTransfer): its empty save folders get the
    /// saves the version played before left, so it doesn't start from scratch.
    private func takeSavesAlong(_ game: Game, to platform: Platform) async {
        guard game.macNative else { return }
        let appID = game.appID
        let installDir = game.installDirName
        let profileRules = await ProfileStore.shared.profile(for: appID)?.saves ?? []
        await Task.detached(priority: .userInitiated) {
            let macCatalog = MacSteam.root.appendingPathComponent("appcache/appinfo.vdf")
            let rules = SteamCatalog.saveRules(
                appID: appID, steamRoot: FileManager.default.fileExists(atPath: macCatalog.path) ? MacSteam.root : Engine.steamRoot)
                + profileRules
            var places = SaveTransfer.Places()
            places.windowsInstall = Engine.steamRoot.appendingPathComponent("steamapps/common/\(installDir)", isDirectory: true)
            places.macInstall = MacSteam.steamapps.appendingPathComponent("common/\(installDir)", isDirectory: true)
            SaveTransfer.beforeStart(appID: appID, platform: platform, rules: rules, places: places)
        }.value
    }

    /// A Mac version that didn't start: "Automatic" moves the game to the best alternative, its
    /// Windows version, and goes on with it at once – starts it when it's installed, else
    /// downloads it. The game's note says so; its options can switch back.
    private func fallBackToWindows(_ game: Game) -> Bool {
        guard game.switchable, GameOptionsStore.load(game.appID).version == .automatic else { return false }
        MacHealth.fail(game.appID)
        NSApp.activate()
        Task {
            await rescan()  // after the Mac launch has wound down: one launch at a time
            guard let windows = allGames.first(where: { $0.appID == game.appID && $0.platform == .windows }) else { return }
            if windows.isInstalled {
                launch(windows)
            } else if windows.install == .notInstalled {
                download(windows)
            }
        }
        return true
    }

    private enum MacStart {
        case processSeen, steamSaysRunning, failed, noSignOfLife
    }

    /// Follows the start of a Mac game until its process is there, or Steam's log says it runs.
    /// Steam's questions (licence, first-time setup) wait in its window as long as the player
    /// needs; no sign of life ends after 2 min.
    /// `send` asks Steam again: it turns the command away while it's still starting, and now and
    /// then takes it without a word.
    private func waitForMacStart(_ game: Game, watcher: LaunchWatcher, send: () -> Void) async -> MacStart {
        var watcher = watcher
        let folders = Self.processFolders([game])
        var quietSeconds = 0
        var seconds = 0
        var askingSince: Int?
        var handledRejections = 0
        var resent = 0
        while quietSeconds < 120 && seconds < 900 {
            try? await Task.sleep(for: .seconds(1))
            seconds += 1
            if await Task.detached(priority: .utility, operation: { Self.runningGames(folders) }).value[game.id] != nil {
                launchNeedsConfirmation = false
                return .processSeen
            }
            let event = watcher.poll()
            if watcher.rejectedCommands > handledRejections && resent < 5 {
                handledRejections = watcher.rejectedCommands
                resent += 1
                try? await Task.sleep(for: .seconds(2))
                send()
                quietSeconds = 0
                continue
            }
            if !watcher.steamReceivedLaunch && seconds % 15 == 0 && resent < 5 {
                resent += 1
                send()
            }
            switch event {
            case .running?:
                // Give the process a few seconds to show up before trusting the log alone.
                for _ in 0..<5 {
                    try? await Task.sleep(for: .seconds(1))
                    if await Task.detached(priority: .utility, operation: { Self.runningGames(folders) }).value[game.id] != nil {
                        launchNeedsConfirmation = false
                        return .processSeen
                    }
                }
                launchNeedsConfirmation = false
                return .steamSaysRunning
            case .needsConfirmation?:
                askingSince = askingSince ?? seconds
                quietSeconds = 0
            case .continued?:
                launchNeedsConfirmation = false
                askingSince = nil
                quietSeconds = 0
            case .cancelled?:
                return .noSignOfLife
            case .failed?:
                return .failed
            case nil:
                if let since = askingSince {
                    // Steam logs routine steps as questions too and answers them within a second.
                    if seconds - since >= 3, !launchNeedsConfirmation {
                        launchNeedsConfirmation = true
                        MacSteam.show()
                    }
                } else {
                    quietSeconds += 1
                }
            }
        }
        return .noSignOfLife
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
        guard let game = selected else { return }
        launch(game)
    }

    private func launch(_ game: Game) {
        guard game.isInstalled, launchingID == nil else { return }
        if game.platform == .mac {
            launchMac(game)
            return
        }
        if game.bottle.isBuiltIn && !Engine.steamSignedIn && !otherSteamFree(for: .windows) { return }
        launchingID = game.id
        launchNeedsConfirmation = false
        launchStatus = nil
        let behavior = Prefs.afterLaunch
        Task {
            defer {
                launchingID = nil
                launchNeedsConfirmation = false
                launchStatus = nil
            }
            if game.bottle.isBuiltIn { await steamStartup?.value }
            // Steam for Mac signed in since and signed this Steam out: sign it in again, or the
            // game starts without its cloud saves.
            if game.bottle.isBuiltIn, Engine.sessionReplaced(), let wine = await Engine.installedWine() {
                launchStatus = L10n.t("Signing in to Steam …")
                _ = await restartStuckSteam(wine)
                launchStatus = nil
            }
            // A Steam that is still signing in starts the game offline ("Steam is currently in
            // Offline Mode"): wait for it, and start it afresh if it doesn't get there.
            if game.bottle.isBuiltIn, Engine.isSteamSignedIn, !Engine.steamSignedIn, let wine = await Engine.installedWine() {
                launchStatus = L10n.t("Signing in to Steam …")
                var waited = 0
                while !Engine.steamSignedIn, waited < 45 {
                    try? await Task.sleep(for: .seconds(1))
                    waited += 1
                }
                if !Engine.steamSignedIn { _ = await restartStuckSteam(wine) }
                launchStatus = nil
            }
            if game.bottle.isBuiltIn { await takeSavesAlong(game, to: .windows) }
            let runner = game.bottle.isBuiltIn ? await Engine.installedWine()?.path : Prefs.runnerPath
            // Known fixes for this game (profiles/profiles.json) and what its files reveal.
            let profile = game.bottle.isBuiltIn ? await ProfileStore.shared.profile(for: game.appID) : nil
            let insight = await insight(of: game)
            let analysis = insight?.analysis
            var options = GameOptionsStore.load(game.appID)
            let automatic = game.bottle.isBuiltIn && options.graphics == .automatic
            let attempts = insight?.attempts ?? []
            if automatic { LaunchHealth.review(game.appID, attempts, steamRoot: game.steamRoot) }
            let refreshRate = NSScreen.main?.maximumFramesPerSecond ?? 60  // the game opens on the main display
            if game.bottle.isBuiltIn {
                // The last session's frame rates decide this one's automatic frame limit.
                await Task.detached(priority: .utility) {
                    FramePacing.learn(appID: game.appID, installDir: game.installDir)
                }.value
            }

            if let preparing = preparations[game.appID] {
                launchStatus = L10n.t("Setting up the game …")
                await preparing.value
                launchStatus = nil
            }
            while true {
                if let runner {
                    await installRuntimes(for: game, profile: profile, analysis: analysis,
                                          wine: URL(fileURLWithPath: runner), showStatus: true)
                }
                var arguments = analysis?.preferD3D11Arguments ?? []
                var watchFirstSeconds = false
                if automatic, !attempts.isEmpty {
                    let (index, confirmed) = LaunchHealth.current(game.appID, attempts)
                    options.graphics = attempts[index].graphics
                    arguments = attempts[index].arguments
                    watchFirstSeconds = !confirmed
                    if watchFirstSeconds { LaunchHealth.recordStart(game.appID, attempts) }
                }
                let logMark = GameLog.mark()
                let startedAt = Date()
                LearnedFixes.setLastLaunch(game.appID, logMark: logMark)
                let (frameLimit, learning) = FramePacing.automaticLimit(appID: game.appID, options: options,
                                                                         profile: profile, refreshRate: refreshRate)
                if game.bottle.isBuiltIn {
                    FramePacing.recordStart(appID: game.appID, options: options, profile: profile, refreshRate: refreshRate,
                                            logMark: logMark, limit: frameLimit, learning: learning)
                }
                // Settings a game only takes from the environment come with the Steam that starts it.
                let layer = options.graphics == .automatic ? (profile?.graphics ?? Engine.defaultGraphics) : options.graphics
                if game.bottle.isBuiltIn,
                   Engine.prepareLaunchEnvironment(avx: LearnedFixes.avx(game.appID, profile: profile), d3dMetal: layer == .d3dmetal,
                                                   frameLimit: frameLimit, upscaling: options.effectiveUpscaling(profile: profile)),
                   Engine.isSteamRunning, !anyRunning(.windows), let runner {
                    launchStatus = L10n.t("Signing in to Steam …")
                    _ = await restartStuckSteam(URL(fileURLWithPath: runner))
                    launchStatus = nil
                }
                guard await start(game, runner: runner, options: options, profile: profile,
                                  arguments: arguments, frameLimit: frameLimit)
                else { return }
                launchingID = nil
                if game.bottle.isBuiltIn { SteamPriority.watch(game) }
                startedHere.insert(game.id)
                await bringToFront(game)
                guard watchFirstSeconds else { break }

                // The first start with this way: is the game still there after its first seconds?
                if await survivesFirstSeconds(game, logMark: logMark) {
                    LaunchHealth.confirm(game.appID, attempts)
                    break
                }
                launchingID = game.id
                NSApp.activate()
                let needed = GameLog.missingRuntimes(since: logMark, gameFolder: game.installDirName)
                    .filter { !LearnedFixes.winetricks(game.appID).contains($0) }
                if !needed.isEmpty {
                    // Wine said what's missing: install it and try the same way again.
                    LearnedFixes.addWinetricks(needed, for: game.appID)
                    continue
                }
                if game.bottle.isBuiltIn, Engine.applyFileEdits(profile?.fileEdits ?? [], installDir: game.installDir) {
                    // The game wrote its settings file at its first start, with a setting its
                    // profile turns off: the same way again, with the file fixed.
                    continue
                }
                if game.bottle.isBuiltIn, LearnedFixes.avx(game.appID, profile: profile),
                   GameLog.illegalInstruction(since: logMark, installDir: game.installDir, startedAt: startedAt) {
                    // Rosetta's AVX hint sent it down a path Rosetta can't run: the same way without it.
                    LearnedFixes.setNoAVX(game.appID)
                    continue
                }
                if LaunchHealth.advance(game.appID, attempts) {
                    let next = attempts[LaunchHealth.current(game.appID, attempts).index]
                    launchStatus = L10n.t("Starting again with %@ …", next.label)
                    continue
                }
                // One way only (Vulkan, DirectX 12): what the game draws with says more than a layer.
                let tried = attempts.count > 1 ? attempts.map(\.label) : [analysis?.summary ?? attempts.first?.label ?? ""]
                failedLaunch = FailedLaunch(game: game, tried: tried)
                return
            }

            switch behavior {
            case .quit: NSApp.terminate(nil)
            case .hide: NSApp.hide(nil)
            case .stay: break
            }
        }
    }

    /// Runtimes the profile asks for and those an earlier start turned out to need, and Wine Mono
    /// for .NET games. `showStatus` says so on the Play button while it takes.
    private func installRuntimes(for game: Game, profile: GameProfile?, analysis: GameAnalysis?,
                                 wine: URL, showStatus: Bool) async {
        let learned = LearnedFixes.winetricks(game.appID)
        let missing = Engine.missingWinetricks((profile?.winetricks ?? []) + learned.filter { $0 != GameLog.wineMono })
            .filter(Engine.isSafeWinetricksVerb)
        if !missing.isEmpty {
            if showStatus { launchStatus = L10n.t("Setting up the game …") }
            await Engine.installWinetricks(missing, wine: wine)
            if showStatus { launchStatus = nil }
        }
        if game.bottle.isBuiltIn, analysis?.usesDotNet == true || learned.contains(GameLog.wineMono),
           !Engine.wineMonoInstalled {
            if showStatus { launchStatus = L10n.t("Setting up .NET for the game …") }
            await Engine.installWineMono(wine)
            if showStatus { launchStatus = nil }
        }
    }

    /// Games being set up in the background right after their download; Play waits for them.
    private var preparations: [Int: Task<Void, Never>] = [:]

    /// A Windows game Steam has just finished downloading gets what it needs to start (runtimes,
    /// .NET) now, while nobody waits – so its first Play starts it at once. Not while a game runs
    /// or starts: that one gets the Mac's full attention, and Play does the setup then.
    private func prepare(_ game: Game) {
        guard game.bottle.isBuiltIn, game.platform == .windows, preparations[game.appID] == nil,
              running.isEmpty, launchingID == nil
        else { return }
        preparations[game.appID] = Task {
            defer { preparations[game.appID] = nil }
            guard let wine = await Engine.installedWine() else { return }
            let profile = await ProfileStore.shared.profile(for: game.appID)
            let analysis = await insight(of: game)?.analysis
            await installRuntimes(for: game, profile: profile, analysis: analysis, wine: wine, showStatus: false)
        }
    }

    /// Hands the game to Steam and follows Steam's log until the game runs. True once it does; a
    /// question from Steam can take as long as the player needs, no sign of life ends after 2 min.
    private func start(_ game: Game, runner: String?, options: GameOptions, profile: GameProfile?,
                       arguments: [String], frameLimit: Int) async -> Bool {
        var watcher = LaunchWatcher(steamRoot: game.steamRoot, appID: game.appID)
        do {
            // Off the main thread: it reads Steam's app catalog and writes the registry, which
            // would freeze the window for a moment.
            try await Task.detached(priority: .userInitiated) {
                try Launcher.launch(game, runnerPath: runner ?? "", options: options, profile: profile,
                                    frameLimit: frameLimit, extraArguments: arguments)
            }.value
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        var quietSeconds = 0
        var totalSeconds = 0
        var askingSince: Int?
        var retriedAfterRestart = false
        var signedInSince: Int?
        var resent = false
        while quietSeconds < 120 && totalSeconds < 900 {
            try? await Task.sleep(for: .seconds(1))
            totalSeconds += 1
            switch watcher.poll() {
            case .running?:
                launchNeedsConfirmation = false
                return true
            case .needsConfirmation?:
                askingSince = askingSince ?? totalSeconds
                quietSeconds = 0
            case .continued?:
                launchNeedsConfirmation = false
                askingSince = nil
                quietSeconds = 0
            case .cancelled?:
                return false
            case .failed?:
                errorMessage = L10n.t("Steam couldn't start %@.", game.name)
                return false
            case nil:
                // A request that arrives while Steam is still starting can get lost. Once Steam has
                // signed in and still hasn't logged it, ask once more.
                if game.bottle.isBuiltIn, !watcher.steamReceivedLaunch, !resent {
                    if signedInSince == nil, Engine.steamSignedIn { signedInSince = totalSeconds }
                    if let since = signedInSince, totalSeconds - since >= 10 {
                        resent = true
                        try? await Task.detached(priority: .userInitiated) {
                            try Launcher.launch(game, runnerPath: runner ?? "", options: options, profile: profile,
                                                frameLimit: frameLimit, extraArguments: arguments)
                        }.value
                        continue
                    }
                }
                // Steam never took the request and has gone silent: it hung while starting.
                // Restart it once and ask again.
                if game.bottle.isBuiltIn, !watcher.steamReceivedLaunch, !retriedAfterRestart,
                   totalSeconds % 5 == 0, running.isEmpty, let runner, Engine.steamLooksStuck(quietFor: 30) {
                    retriedAfterRestart = true
                    launchStatus = L10n.t("Restarting Steam …")
                    if await restartStuckSteam(URL(fileURLWithPath: runner)) {
                        watcher = LaunchWatcher(steamRoot: game.steamRoot, appID: game.appID)
                        try? await Task.detached(priority: .userInitiated) {
                            try Launcher.launch(game, runnerPath: runner, options: options, profile: profile,
                                                frameLimit: frameLimit, extraArguments: arguments)
                        }.value
                    }
                    launchStatus = nil
                    quietSeconds = 0
                    continue
                }
                guard let since = askingSince else {
                    quietSeconds += 1
                    continue
                }
                // Steam logs routine steps as questions too and answers them within a second;
                // a real question waits for the player in Steam's window, which runs hidden –
                // so only then say so and show it.
                if totalSeconds - since >= 3, !launchNeedsConfirmation {
                    launchNeedsConfirmation = true
                    if game.bottle.isBuiltIn { showSteamWindow() }
                }
            }
        }
        return false
    }

    /// Whether the game is still running `LaunchHealth.failureWindow` seconds after it started.
    /// A launcher handing over to the game leaves a gap of a few seconds, so only a longer absence
    /// counts as the game having ended. A game whose Direct3D layer failed (GameLog) is ended here:
    /// it would only sit behind its own error box.
    private func survivesFirstSeconds(_ game: Game, logMark: UInt64? = nil) async -> Bool {
        let folders = Self.processFolders([game])
        let started = Date()
        var absent = 0
        while Date().timeIntervalSince(started) < LaunchHealth.failureWindow || (absent > 0 && absent < 10) {
            try? await Task.sleep(for: .seconds(1))
            let pid = await Task.detached(priority: .utility) { Self.runningGames(folders)[game.id] }.value
            absent = pid == nil ? absent + 1 : 0
            if absent >= 10 { return false }
            if let pid, let logMark, GameLog.graphicsFailed(since: logMark) {
                kill(pid, SIGTERM)
                // Steam has to see it gone before the next way can start.
                for _ in 0..<15 {
                    try? await Task.sleep(for: .seconds(1))
                    if await Task.detached(priority: .utility, operation: { Self.runningGames(folders)[game.id] }).value == nil { break }
                }
                return false
            }
        }
        return true
    }

    /// What a game's files reveal (read once per game and app run) and the ways to start it.
    private var analyzing: [Int: Task<GameAnalysis, Never>] = [:]

    func insight(of game: Game) async -> GameInsight? {
        guard game.bottle.isBuiltIn, game.isInstalled else { return nil }
        let analysis: GameAnalysis
        if let known = analyses[game.appID] {
            analysis = known
        } else {
            // Scrolling through the covers asks again before the first look is done: one look per game.
            let running = analyzing[game.appID] ?? Task.detached(priority: .utility) {
                GameAnalysis.analyze(installDir: game.installDir,
                                     launchExecutable: SteamCatalog.launchExecutable(appID: game.appID, steamRoot: game.steamRoot))
            }
            analyzing[game.appID] = running
            analysis = await running.value
            analyzing[game.appID] = nil
            analyses[game.appID] = analysis
        }
        let profile = await ProfileStore.shared.profile(for: game.appID)
        let insight = GameInsight(analysis: analysis, attempts: LaunchHealth.attempts(for: analysis, profile: profile))
        if insights[game.appID] != insight { insights[game.appID] = insight }
        return insight
    }

    /// Opens a pre-filled problem report for the game in the browser.
    func reportProblem(for game: Game) {
        Task { ProblemReport.open(game: game, insight: await insight(of: game)) }
    }

    /// Steam starts the game in the background, and since macOS 14 an app can't push itself to
    /// the front. Nightforge is the active app at this point, so it hands activation over as soon
    /// as the game shows its window (Wine makes it a regular app then) – before quitting or hiding.
    private func bringToFront(_ game: Game) async {
        let folders = Self.processFolders([game])
        var absent = 0
        for _ in 0..<60 {
            let pid = await Task.detached(priority: .utility) { Self.runningGames(folders)[game.id] }.value
            absent = pid == nil ? absent + 1 : 0
            if absent >= 10 { return }  // gone again: it crashed before showing a window
            if let pid, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                guard NSApp.isActive else { return }  // the player has moved on to something else
                NSApp.yieldActivation(to: app)
                app.activate(from: .current, options: [])
                try? await Task.sleep(for: .milliseconds(600))
                if app.isActive { return }
            }
            try? await Task.sleep(for: .seconds(1))
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

    /// Only games in Nightforge's own Steam or Steam for Mac; CrossOver bottles are managed by their
    /// own Steam. Uninstalling stops that Steam for a moment, so not while one of its games runs or
    /// anything starts – it would go too.
    func canUninstall(_ game: Game) -> Bool {
        guard game.isInstalled || { if case .downloading = game.install { return true } else { return false } }()
        else { return false }
        guard uninstallingID == nil && launchingID == nil else { return false }
        if game.platform == .mac { return !anyRunning(.mac) }
        return game.bottle.isBuiltIn && !anyRunning(.windows)
    }

    /// The Windows version a game left behind when it moved to its Mac version.
    func requestLeftoverRemoval(_ game: Game) {
        guard game.windowsLeftover != nil, uninstallingID == nil, launchingID == nil, !anyRunning(.windows) else { return }
        pendingLeftoverRemoval = game
    }

    func confirmLeftoverRemoval() {
        guard let game = pendingLeftoverRemoval else { return }
        pendingLeftoverRemoval = nil
        uninstallingID = game.id
        Task {
            defer {
                uninstallingID = nil
                reload(quiet: true)
            }
            do {
                guard let wine = await Engine.installedWine(), let leftover = game.windowsLeftoverDir else { return }
                try await Engine.uninstall(appID: game.appID, installDir: leftover, wine: wine)
            } catch {
                errorMessage = L10n.t("%@ could not be uninstalled: %@", game.name, error.localizedDescription)
            }
        }
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
                if game.platform == .mac {
                    try await MacSteam.uninstall(appID: game.appID, installDir: game.installDir)
                    return
                }
                guard let wine = await Engine.installedWine() else { return }
                try await Engine.uninstall(appID: game.appID, installDir: game.installDir, wine: wine)
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
