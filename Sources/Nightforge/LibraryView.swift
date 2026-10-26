import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: LibraryModel

    private var uninstallTitle: String {
        guard let game = model.pendingUninstall else { return "" }
        return game.isInstalled ? L10n.t("Uninstall %@?", game.name) : L10n.t("Cancel the download of %@?", game.name)
    }

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()

            if let game = model.selected {
                Backdrop(game: game)
                    .id(game.id)
                    .transition(.opacity)
            }
            if model.showingLibrary {
                Theme.night.opacity(0.86).ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 0) {
                TopBar()

                if model.showingLibrary && !model.games.isEmpty {
                    LibraryGrid()
                        .padding(.top, 16)
                        .transition(.opacity)
                } else {
                Spacer(minLength: 24)

                if let game = model.selected {
                    GameDetail(game: game)
                        .id(game.id)
                        .transition(.opacity)
                        .padding(.horizontal, Theme.gutter)
                } else if model.needsSetup {
                    SetupView(setup: model.setup)
                        .padding(.horizontal, Theme.gutter)
                } else if !model.searchText.isEmpty && !model.allGames.isEmpty {
                    NoResults()
                        .padding(.horizontal, Theme.gutter)
                } else if !model.isScanning {
                    EmptyLibrary()
                        .padding(.horizontal, Theme.gutter)
                }

                Spacer(minLength: 28)

                if !model.games.isEmpty {
                    CoverRail()
                }
                }
                HintBar()
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 22)
            }

            ToastHost()
        }
        .animation(.easeOut(duration: 0.28), value: model.selected?.id)
        .animation(.easeOut(duration: 0.22), value: model.showingLibrary)
        // A changed version moves the game to another Steam: scan again.
        .sheet(isPresented: $model.showingOptions, onDismiss: { model.reload(quiet: true) }) {
            if let game = model.selected {
                GameOptionsSheet(game: game, insight: model.insights[game.appID]) { model.reportProblem(for: game) }
            }
        }
        // Esc closes it like Cancel: the setup stops.
        .sheet(item: Binding(get: { model.macSetup }, set: { if $0 == nil { model.closeMacSetup() } })) { setup in
            MacSteamSetupView(
                setup: setup,
                useWindows: setup.game.switchable ? { model.useWindowsVersion(of: setup.game) } : nil,
                close: { model.closeMacSetup() }
            )
        }
        .alert(
            L10n.t("Something went wrong"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: { Button("OK") {} },
            message: { Text(model.errorMessage ?? "") }
        )
        .alert(
            L10n.t("%@ didn't start", model.failedLaunch?.game.name ?? ""),
            isPresented: Binding(
                get: { model.failedLaunch != nil },
                set: { if !$0 { model.failedLaunch = nil } }
            ),
            presenting: model.failedLaunch,
            actions: { failed in
                Button(L10n.t("Report problem")) { model.reportProblem(for: failed.game, tried: failed.tried) }
                // A on a controller is Return: it closes the box rather than opening a browser.
                Button("OK", role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            },
            message: { failed in
                // The ways it tried (graphics layers, launch options) go into the report, not into this box.
                Text(L10n.t("It ended right after starting, with every way Nightforge knows to start it. A problem report helps get it running – it opens on GitHub, filled in with what Nightforge found."))
            }
        )
        .alert(
            L10n.t("Play %@ on GeForce Now?", model.pendingCloudGame?.name ?? ""),
            isPresented: Binding(
                get: { model.pendingCloudGame != nil },
                set: { if !$0 { model.pendingCloudGame = nil } }
            ),
            presenting: model.pendingCloudGame,
            actions: { _ in
                Button(L10n.t("Continue to GeForce Now")) { model.confirmCloud() }
                Button(L10n.t("Cancel"), role: .cancel) {}
            },
            message: { _ in
                Text(L10n.t("Its anti-cheat doesn't run on a Mac, so it runs on NVIDIA's servers and streams to your Mac – with the copy you own on Steam. The first time, sign in to GeForce Now with an NVIDIA account and link Steam there. Free play lasts an hour at a time, with ads and a queue; GeForce Now's paid plans lift that. GeForce Now forgets the game while you sign in: afterwards, press Play on GeForce Now here once more."))
            }
        )
        .alert(
            uninstallTitle,
            isPresented: Binding(
                get: { model.pendingUninstall != nil },
                set: { if !$0 { model.pendingUninstall = nil } }
            ),
            presenting: model.pendingUninstall,
            actions: { game in
                Button(game.isInstalled ? L10n.t("Uninstall") : L10n.t("Cancel Download"), role: .destructive) {
                    model.confirmUninstall()
                }
                // Return (and A) keeps the game; uninstalling takes a deliberate click or a pad move first.
                Button(L10n.t("Keep"), role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            },
            message: { game in
                Text(game.isInstalled
                     ? L10n.t("This removes the game from your Mac and frees %@. It stays in your Steam library, so you can download it again any time. Saves in the Steam Cloud are kept.", Format.bytes(game.sizeOnDisk))
                     : L10n.t("The part downloaded so far is deleted. You can start the download again any time."))
            }
        )
        .alert(
            L10n.t("Remove the Windows version of %@?", model.pendingLeftoverRemoval?.name ?? ""),
            isPresented: Binding(
                get: { model.pendingLeftoverRemoval != nil },
                set: { if !$0 { model.pendingLeftoverRemoval = nil } }
            ),
            presenting: model.pendingLeftoverRemoval,
            actions: { _ in
                Button(L10n.t("Remove"), role: .destructive) { model.confirmLeftoverRemoval() }
                Button(L10n.t("Keep"), role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            },
            message: { game in
                Text(L10n.t("Nightforge uses the Mac version of this game now. Removing the Windows version frees %@; you can switch back and download it again any time.",
                            Format.bytes(game.windowsLeftover ?? 0)))
            }
        )
        .onAppear {
            model.startInput()
            if model.games.isEmpty { model.reload() }
            model.startBackgroundSteam()
        }
    }
}

// MARK: - Backdrop

private struct Backdrop: View {
    let game: Game
    @State private var hero: NSImage?
    @State private var cover: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let hero {
                    Image(nsImage: hero)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if let cover {
                    // No hero art: use the cover as a soft light source instead.
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 70)
                        .opacity(0.55)
                        .clipped()
                }

                LinearGradient(
                    stops: [
                        .init(color: Theme.night.opacity(0.10), location: 0),
                        .init(color: Theme.night.opacity(0.50), location: 0.45),
                        .init(color: Theme.night.opacity(0.94), location: 0.78),
                        .init(color: Theme.night, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                LinearGradient(
                    colors: [Theme.night.opacity(0.85), Theme.night.opacity(0)],
                    startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5)
                )
            }
        }
        .ignoresSafeArea()
        .task(id: game.id) {
            hero = await ArtworkStore.shared.image(for: game, kind: .hero)
            if hero == nil {
                cover = await ArtworkStore.shared.image(for: game, kind: .cover)
            }
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 16) {
            Text("Nightforge")
                .font(Theme.display(15))
                .foregroundStyle(Theme.ink)
            if !model.allGames.isEmpty {
                Text(countText)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            if let update = model.availableUpdate {
                Button {
                    model.installUpdate()
                } label: {
                    HStack(spacing: 7) {
                        if model.updating {
                            ProgressView().controlSize(.small).environment(\.colorScheme, .light)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(model.updating ? L10n.t("Updating …") : L10n.t("Update to %@", update.version))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.night)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.sodium, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.updating)
                .padFocus("top.update", enabled: !model.updating, cornerRadius: 17, activate: { model.installUpdate() })
                .help(L10n.t("Installs the new version and restarts Nightforge. Your games and settings stay."))
            }

            if !model.allGames.isEmpty {
                SearchField()
                RoundIconButton(
                    symbol: model.showingLibrary ? "rectangle.inset.filled" : "square.grid.3x3",
                    help: model.showingLibrary ? L10n.t("Back to the game (L)") : L10n.t("Whole library (L)"),
                    size: 34
                ) {
                    model.toggleLibrary()
                }
            }

            if model.isScanning {
                ProgressView().controlSize(.small)
            }
            RoundIconButton(symbol: "arrow.clockwise", help: L10n.t("Rescan library (⌘R)"), size: 34) {
                model.reload()
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("Settings (⌘,)"))
            .accessibilityLabel(L10n.t("Settings"))
            .padFocus("top.settings", cornerRadius: 17, activate: { openSettings() })

            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute().locale(L10n.locale))  // the app's language, not the Mac's
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            .padding(.leading, 6)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 36)
    }

    private var countText: String {
        let total = model.allGames.count
        if model.searchText.isEmpty {
            return total == 1 ? L10n.t("1 game") : L10n.t("%ld games", total)
        }
        let matches = model.games.filter { $0.install != .inStore }.count  // store hits aren't yours
        return total == 1 ? L10n.t("%ld of 1 game", matches) : L10n.t("%ld of %ld games", matches, total)
    }
}

/// Search as you type; ⌘F or / jumps here, Return goes back to the results, Esc clears.
private struct SearchField: View {
    @EnvironmentObject private var model: LibraryModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
            TextField("", text: $model.searchText, prompt: Text(L10n.t("Search")).foregroundStyle(Theme.muted))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit { focused = false }
                .onExitCommand {
                    model.searchText = ""
                    focused = false
                }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Clear search"))
                .accessibilityLabel(L10n.t("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 230, height: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.sodium.opacity(focused ? 0.8 : 0), lineWidth: 1.5))
        .padFocus("top.search", cornerRadius: 17, activate: { focused = true })
        .onChange(of: model.searchFocusRequest) { _, _ in focused = true }
        .help(L10n.t("Search (⌘F)"))
    }
}

private struct NoResults: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("No games match “%@”", model.searchText))
                .font(Theme.display(30))
                .foregroundStyle(Theme.ink)
            Button(L10n.t("Clear search")) { model.searchText = "" }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padFocus("noResults.clear", activate: { model.searchText = "" })
        }
    }
}

// MARK: - Selected game

private struct GameDetail: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel
    @State private var logo: NSImage?

    static func openBatterySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Group {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 480, maxHeight: 170, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                } else {
                    Text(game.name)
                        .font(Theme.display(54))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: 760, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                }
            }
            .frame(height: 170, alignment: .bottomLeading)
            .accessibilityLabel(game.name)

            HStack(alignment: .top, spacing: 34) {
                if game.install != .inStore {
                    Stat(label: L10n.t("Last played"), value: game.lastPlayed.map(Format.relative) ?? L10n.t("Never"))
                }
                if let minutes = game.playtimeMinutes, minutes > 0 {
                    Stat(label: L10n.t("Play time"), value: Format.playtime(minutes))
                }
                switch game.install {
                case .inStore:
                    Stat(label: L10n.t("Price"), value: game.storePrice ?? "–")
                    if let score = game.metascore {
                        Stat(label: "Metascore", value: "\(score)")
                    }
                case .installed:
                    Stat(label: L10n.t("Size"), value: Format.bytes(game.sizeOnDisk))
                case .notInstalled where game.playsInCloud:
                    Stat(label: L10n.t("Plays on"), value: "GeForce Now")
                case .notInstalled:
                    Stat(label: L10n.t("Download"), value: game.sizeOnDisk > 0
                         ? L10n.t("up to %@", Format.bytes(game.sizeOnDisk)) : "–")
                case .downloading:
                    Stat(label: L10n.t("Download"), value: Format.bytes(game.sizeOnDisk))
                }
                if game.switchable {
                    Stat(label: L10n.t("Version"), value: game.platform == .mac ? "Mac" : "Windows")
                }
                if game.install != .inStore || game.controller != .none {
                    Stat(label: L10n.t("Controller"), value: game.controller.label)
                }
                if !game.bottle.isBuiltIn && game.platform == .windows {  // only means something with several CrossOver bottles
                    Stat(label: L10n.t("Bottle"), value: game.bottle.name)
                }
            }

            if game.isVROnly {
                Label(L10n.t("Needs a VR headset – this game can't be played on a Mac."), systemImage: "visionpro")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            if let block = game.antiCheatBlock {
                AntiCheatNote(block: block)
            }
            if let insight = model.insights[game.appID] {
                GameInsightNotes(game: game, insight: insight)
            }
            if model.lowPowerMode && game.install != .inStore {
                HStack(spacing: 10) {
                    Label(L10n.t("Low Power Mode is on – games run much slower with it."), systemImage: "battery.25percent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.sodium)
                    Button(L10n.t("Battery Settings"), action: Self.openBatterySettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padFocus("detail.battery", activate: Self.openBatterySettings)
                }
            }
            VersionNotes(game: game)
            if let needed = game.downloadNeedsSpace {
                Label(L10n.t("Not enough space: Steam needs %@ to download this game, your Mac has %@ free. Make some room, then continue.",
                             Format.bytes(needed), Format.bytes(LibraryModel.freeSpace(at: game.installDir.deletingLastPathComponent()))),
                      systemImage: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                PlayButton(install: game.install, isLaunching: model.launchingID == game.id,
                           isUninstalling: model.uninstallingID == game.id,
                           isRunning: model.isRunning(game),
                           needsConfirmation: model.launchNeedsConfirmation,
                           status: model.launchStatus,
                           unavailable: unavailable, cloud: game.playsInCloud,
                           noSpace: game.downloadNeedsSpace != nil) {
                    model.primaryAction()
                }
                .padFocus("play", cornerRadius: 34, activate: { model.primaryAction() })
                if game.install != .inStore {
                    RoundIconButton(symbol: "slider.horizontal.3", help: L10n.t("Options for this game (O)")) {
                        model.showingOptions = true
                    }
                    RoundIconButton(symbol: "folder", help: L10n.t("Show game folder in Finder")) {
                        model.revealSelected()
                    }
                }
                if model.canUninstall(game) {
                    RoundIconButton(
                        symbol: game.isInstalled ? "trash" : "xmark",
                        help: game.isInstalled ? L10n.t("Uninstall (⌘⌫)") : L10n.t("Cancel Download")
                    ) {
                        model.requestUninstall(game)
                    }
                }
            }
        }
        .task(id: game.id) {
            logo = await ArtworkStore.shared.image(for: game, kind: .logo)
        }
    }

    /// Nothing a Mac can run (VR only, anti-cheat): the button says why instead.
    private var unavailable: PlayButton.Unavailable? {
        guard game.install == .notInstalled || game.install == .installed, !model.isRunning(game) else { return nil }
        if game.isVROnly && game.install == .notInstalled { return .init(title: L10n.t("VR only"), symbol: "visionpro") }
        if game.antiCheatBlock != nil && !game.playsInCloud {
            return .init(title: L10n.t("Doesn't run on a Mac"), symbol: "shield.slash")
        }
        return nil
    }
}

/// Why a game with anti-cheat can't be played on a Mac, and where it can be streamed instead.
private struct AntiCheatNote: View {
    let block: AntiCheatBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.t("This game's anti-cheat (%@) stops it on a Mac: it needs Windows itself, and getting around it would get your account banned.",
                         block.antiCheat.joined(separator: ", ")),
                  systemImage: "shield.slash")
            if block.geforceNow != nil {
                Label(L10n.t("Nightforge plays it on GeForce Now, NVIDIA's cloud gaming, with your Steam copy (own NVIDIA account; free sessions last an hour)."),
                      systemImage: "cloud")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: 620, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
    }
}

/// The one big button: Download → Downloading … % → Play.
private struct PlayButton: View {
    let install: InstallState
    let isLaunching: Bool
    var isUninstalling = false
    var isRunning = false
    var needsConfirmation = false
    /// What the launch is busy with, when it's more than waiting for Steam.
    var status: String?
    /// Nothing a Mac can run (VR only, anti-cheat): what the button says instead.
    var unavailable: Unavailable?
    /// Streams from GeForce Now instead (anti-cheat games it carries).
    var cloud = false
    /// Steam stopped the download for lack of disk space: the button carries on with it.
    var noSpace = false
    let action: () -> Void
    @State private var hovering = false

    private var busy: Bool {
        if isLaunching || unavailable != nil || isUninstalling { return true }
        if case .downloading = install, !noSpace { return true }
        return false
    }

    private var title: String {
        if isLaunching, let status { return status }
        if isLaunching { return needsConfirmation ? L10n.t("Confirm in the Steam window") : L10n.t("Launching …") }
        if isUninstalling { return L10n.t("Uninstalling …") }
        if isRunning { return L10n.t("Running – switch to game") }
        if let unavailable { return unavailable.title }
        if cloud { return L10n.t("Play on GeForce Now") }
        if noSpace { return L10n.t("Continue Download") }
        switch install {
        case .installed: return L10n.t("Play")
        case .notInstalled: return L10n.t("Download")
        case .downloading(let fraction?): return L10n.t("Downloading … %ld %%", Int(fraction * 100))
        case .downloading(nil): return L10n.t("Preparing download …")
        case .inStore: return L10n.t("View in Steam Store")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isRunning && !busy {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                } else if let unavailable {
                    Image(systemName: unavailable.symbol)
                        .font(.system(size: 15, weight: .bold))
                } else if cloud {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 15, weight: .bold))
                } else if noSpace {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                } else if busy {
                    ProgressView()
                        .controlSize(.small)
                        .environment(\.colorScheme, .light)
                } else {
                    Image(systemName: install == .notInstalled ? "arrow.down" : install == .inStore ? "cart" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(title)
                    .font(Theme.display(17))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.night)
            .padding(.horizontal, 32)
            .frame(height: 52)
            .background(
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.sodium.opacity(busy ? 0.55 : 1))
                    if case .downloading(let fraction?) = install, !noSpace {
                        GeometryReader { geo in
                            Capsule().fill(Theme.sodium).frame(width: max(52, geo.size.width * fraction))
                        }
                    }
                }
            )
            .clipShape(Capsule())
            .shadow(color: Theme.sodium.opacity(hovering ? 0.55 : 0.3), radius: hovering ? 24 : 14)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.4), value: install)
        }
        .buttonStyle(.plain)
        .disabled(busy && !(isLaunching && needsConfirmation))  // then it brings Steam's window up
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    struct Unavailable {
        let title: String
        let symbol: String
    }
}

struct RoundIconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        // Spoken without the shortcut in brackets ("Rescan library", not "arrow.clockwise").
        .accessibilityLabel(help.replacingOccurrences(of: #" \(.*\)$"#, with: "", options: .regularExpression))
        .padFocus("round.\(symbol)", cornerRadius: size / 2, activate: action)
    }
}

// MARK: - Cover rail

private struct CoverRail: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(Array(model.games.enumerated()), id: \.element.id) { index, game in
                        CoverCard(game: game, isSelected: index == model.selectedIndex, isRunning: model.isRunning(game))
                            .id(game.id)
                            .modifier(GameContextMenu(game: game, index: index))
                            .onTapGesture {
                                if index == model.selectedIndex {
                                    model.primaryAction()
                                } else {
                                    model.selectedIndex = index
                                }
                            }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 22)
            }
            .frame(height: 290)
            .onChange(of: model.selectedIndex) { _, _ in
                guard let id = model.selected?.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0.3, y: 0.5))
                }
            }
        }
    }
}

/// Right-click on a cover: the same actions as the big view, without selecting first.
struct GameContextMenu: ViewModifier {
    let game: Game
    let index: Int
    @EnvironmentObject private var model: LibraryModel

    func body(content: Content) -> some View {
        content.contextMenu {
            switch game.install {
            case _ where game.playsInCloud:
                Button(L10n.t("Play on GeForce Now")) { select(); model.primaryAction() }
            case .installed where game.antiCheatBlock == nil || model.isRunning(game):
                Button(model.isRunning(game) ? L10n.t("Switch to Game") : L10n.t("Play")) { select(); model.primaryAction() }
            case .notInstalled where !game.isVROnly && game.antiCheatBlock == nil:
                Button(L10n.t("Download")) { select(); model.primaryAction() }
            case .inStore:
                Button(L10n.t("View in Steam Store")) { model.openStorePage(game) }
            default:
                EmptyView()
            }
            if game.install != .inStore {
                Button(L10n.t("Show game folder in Finder")) { select(); model.revealSelected() }
            }
            if model.canUninstall(game) {
                Divider()
                Button(game.isInstalled ? L10n.t("Uninstall …") : L10n.t("Cancel Download"), role: .destructive) {
                    model.requestUninstall(game)
                }
            }
        }
    }

    private func select() {
        model.selectedIndex = index
    }
}

struct CoverCard: View {
    let game: Game
    let isSelected: Bool
    var isRunning = false
    @State private var cover: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.slate, Theme.night], startPoint: .top, endPoint: .bottom)
                Text(game.name)
                    .font(.system(size: 15, weight: .bold).width(.expanded))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(14)
            }
        }
        .frame(width: 154, height: 231)
        .saturation(game.install == .notInstalled || game.install == .inStore ? 0.15 : 1)
        .overlay(alignment: .bottom) { installBadge }
        .overlay(alignment: .topTrailing) {
            // The version in use; in the store, that Steam has one.
            if game.platform == .mac || (game.install == .inStore && game.macNative) {
                Text("MAC")
                    .font(.system(size: 9.5, weight: .heavy).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.night.opacity(0.78), in: Capsule())
                    .padding(7)
                    .help(game.platform == .mac ? L10n.t("Uses the Mac version") : L10n.t("Steam also has a Mac version"))
            }
        }
        .overlay(alignment: .bottomLeading) {
            // From the couch: which games play with a controller, at a glance.
            // Full support in the accent colour, so it reads across the room; partial in outline.
            if game.controller != .none {
                Image(systemName: game.controller == .full ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(game.controller == .full ? Theme.sodium : Theme.ink.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.night.opacity(0.82), in: Capsule())
                    .padding(7)
                    .help(game.controller.help)
            }
        }
        .overlay(alignment: .topLeading) {
            if isRunning {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text(L10n.t("Running")).font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.night.opacity(0.75), in: Capsule())
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.sodium, lineWidth: isSelected ? 3 : 0)
        )
        .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1)
        .opacity(isSelected ? 1 : 0.6)
        .shadow(color: .black.opacity(isSelected ? 0.55 : 0.25), radius: isSelected ? 22 : 8, y: isSelected ? 12 : 4)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
        .help(game.name)
        // VoiceOver reads a cover as one button: the game and what its badges show.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .task(id: game.id) {
            cover = await ArtworkStore.shared.image(for: game, kind: .cover)
        }
    }

    private var spokenDescription: String {
        var parts = [game.name]
        switch game.install {
        case .installed: parts.append(L10n.t("Installed"))
        case .downloading: parts.append(L10n.t("Downloading"))
        case .notInstalled: parts.append(L10n.t("In your library"))
        case .inStore: parts.append(L10n.t("In the Steam Store"))
        }
        if game.platform == .mac { parts.append(L10n.t("Uses the Mac version")) }
        if game.controller != .none { parts.append(game.controller.help) }
        if isRunning { parts.append(L10n.t("Running")) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var installBadge: some View {
        switch game.install {
        case .installed:
            EmptyView()
        case .notInstalled, .inStore:
            HStack {
                Spacer()
                if let block = game.antiCheatBlock {
                    // Instead of the download sign: this one won't run here, or only in the cloud.
                    Image(systemName: block.geforceNow != nil ? "cloud" : "shield.slash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Theme.night.opacity(0.82), in: Capsule())
                        .padding(7)
                        .help(block.geforceNow != nil ? L10n.t("Plays on GeForce Now – its anti-cheat doesn't run on a Mac")
                              : L10n.t("Anti-cheat stops this game on a Mac"))
                } else {
                    Image(systemName: game.install == .inStore ? "cart.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.ink, Theme.night.opacity(0.7))
                        .padding(8)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        case .downloading(let fraction):
            VStack(spacing: 0) {
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.night.opacity(0.75))
                        Rectangle().fill(Theme.sodium).frame(width: geo.size.width * (fraction ?? 0))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

// MARK: - Hints & empty state

private struct HintBar: View {
    @EnvironmentObject private var model: LibraryModel
    @ObservedObject private var focus = PadFocus.shared
    @ObservedObject private var toasts = Toasts.shared

    var body: some View {
        HStack(spacing: 22) {
            Spacer()
            let pad = model.padSymbols
            if let action = toasts.current?.action, focus.focused != Toasts.padID {
                Hint(symbol: model.controllerConnected ? pad.stick : "command", text: model.controllerConnected ? action.label : "↩ " + action.label)
            }
            if model.controllerConnected && focus.focused != nil {
                Hint(symbol: pad.confirm, text: L10n.t("Select"))
                Hint(symbol: pad.stick, text: L10n.t("Move"))
                Hint(symbol: pad.back, text: L10n.t("Back"))
            } else if model.showingLibrary {
                Hint(symbol: model.controllerConnected ? pad.confirm : "return", text: L10n.t("Open"))
                Hint(symbol: model.controllerConnected ? pad.stick : "arrow.up.and.down.and.arrow.left.and.right",
                     text: L10n.t("Select"))
                Hint(symbol: model.controllerConnected ? pad.back : "escape", text: L10n.t("Back"))
            } else if model.controllerConnected {
                Hint(symbol: pad.confirm, text: L10n.t("Play"))
                Hint(symbol: pad.options, text: L10n.t("Options"))
                Hint(symbol: pad.library, text: L10n.t("Library"))
                Hint(symbol: pad.stick, text: L10n.t("Select"))
            } else {
                Hint(symbol: "return", text: L10n.t("Play"))
                Hint(symbol: "o.square", text: L10n.t("Options"))
                Hint(symbol: "l.square", text: L10n.t("Library"))
                Hint(symbol: "arrow.left.and.right", text: L10n.t("Select"))
            }
        }
        .opacity(model.games.isEmpty ? 0 : 1)
    }
}

private struct Hint: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Theme.muted)
    }
}

private struct EmptyLibrary: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if Engine.isSteamInstalled {
            connected
        } else {
            bottles
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("Steam is connected"))
                .font(Theme.display(36))
                .foregroundStyle(Theme.ink)
            Text(L10n.t("Install a game in Steam – it shows up here as soon as it's on your Mac."))
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(L10n.t("Open Steam")) { model.openSteam() }
                    .padFocus("empty.openSteam", activate: { model.openSteam() })
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.sodium)
                    .foregroundStyle(Theme.night)
                Button(L10n.t("Rescan")) { model.reload() }
                    .padFocus("empty.rescan", activate: { model.reload() })
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    private var bottles: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("No games here yet"))
                .font(Theme.display(36))
                .foregroundStyle(Theme.ink)
            Text(L10n.t("Nightforge shows the Steam games installed in your CrossOver bottles. Install Steam in a bottle, download a game there, then rescan your library."))
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("Scanned: %@", Prefs.bottlesRoot.path))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted.opacity(0.8))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button(L10n.t("Rescan")) { model.reload() }
                    .padFocus("empty.rescan", activate: { model.reload() })
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.sodium)
                    .foregroundStyle(Theme.night)
                Button(L10n.t("Choose Another Folder …")) { model.chooseBottlesFolder() }
                    .padFocus("empty.chooseFolder", activate: { model.chooseBottlesFolder() })
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }
}

extension ControllerSupport {
    var label: String {
        switch self {
        case .full: return L10n.t("Full")
        case .partial: return L10n.t("Partial")
        case .none: return L10n.t("Mouse & keyboard")
        }
    }

    var help: String {
        switch self {
        case .full: return L10n.t("Full controller support – playable from the couch")
        case .partial: return L10n.t("Partial controller support – some menus need a mouse or keyboard")
        case .none: return L10n.t("Made for mouse and keyboard")
        }
    }
}

/// Which version of the game Nightforge runs, and why – when Steam has both.
private struct VersionNotes: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pending = game.macPending {
                note(L10n.t("There's a Mac version of this game that runs without any Windows translation. Nightforge switches to it as soon as it's on your Mac – until then you play the Windows version."),
                     systemImage: "apple.logo")
                HStack(spacing: 10) {
                    if case .downloading(let fraction) = pending {
                        if let fraction {
                            ProgressView(value: fraction)
                                .tint(Theme.sodium)
                                .frame(width: 200)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Text(fraction.map { L10n.t("Loading the Mac version … %ld %%", Int($0 * 100)) }
                             ?? L10n.t("Preparing the Mac version …"))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                        Button(L10n.t("Cancel")) { model.cancelMacVersion(of: game) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padFocus("detail.cancelMac", enabled: model.uninstallingID == nil,
                                      activate: { model.cancelMacVersion(of: game) })
                    } else {
                        Button(game.macSize > 0 ? L10n.t("Load Mac Version (%@)", Format.bytes(game.macSize)) : L10n.t("Load Mac Version")) {
                            model.loadMacVersion(of: game)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padFocus("detail.loadMac", enabled: model.uninstallingID == nil,
                                  activate: { model.loadMacVersion(of: game) })
                    }
                }
                .padding(.leading, 26)
                .disabled(model.uninstallingID != nil)
            } else if let text {
                note(text, systemImage: game.platform == .mac ? "apple.logo" : "laptopcomputer")
            }
            if let leftover = game.windowsLeftover {
                HStack(spacing: 10) {
                    Label(L10n.t("The Windows version is still installed and takes %@.", Format.bytes(leftover)),
                          systemImage: "externaldrive")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Button(L10n.t("Remove …")) { model.requestLeftoverRemoval(game) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.uninstallingID != nil || model.launchingID != nil)
                        .padFocus("detail.removeLeftover", enabled: model.uninstallingID == nil && model.launchingID == nil,
                                  activate: { model.requestLeftoverRemoval(game) })
                }
            }
        }
    }

    private var text: String? {
        if game.install == .inStore {
            return game.macNative ? L10n.t("Steam also has a Mac version of this game. Nightforge uses it once you own the game, if it runs on current Macs.") : nil
        }
        guard let reason = game.versionReason else { return nil }
        if game.platform == .mac {
            return game.macAppleSilicon
                ? L10n.t("Nightforge uses the Mac version of this game, made for Apple silicon – no Windows translation needed.")
                : L10n.t("Nightforge uses the Mac version of this game – no Windows translation needed. It's made for Intel Macs, so Rosetta runs it.")
        }
        switch reason {
        case .windowsBetter:
            return L10n.t("Steam also has a Mac version, but the Windows version runs better, so Nightforge uses that.")
        case .macTooOld:
            return L10n.t("Steam's Mac version of this game is too old for current Macs, so Nightforge uses the Windows version.")
        case .macFailed:
            return L10n.t("The Mac version didn't start, so Nightforge uses the Windows version. You can switch back in the game's options.")
        case .only, .chosen, .macRuns, .macInstalled:
            return nil
        }
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: 620, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What Nightforge found out about a game that the player should know before pressing Play.
private struct GameInsightNotes: View {
    let game: Game
    let insight: GameInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if GameOptionsStore.load(game.appID).graphics == .automatic,
               let healed = LaunchHealth.note(game.appID, insight.attempts) {
                note(healed, systemImage: "wand.and.stars")
            }
            if insight.analysis.onlyD3D12, !insight.attempts.contains(where: { $0.graphics == .d3dmetal }) {
                note(L10n.t("This game uses DirectX 12 only, which runs on a Mac in part at best."), systemImage: "exclamationmark.triangle")
            }
            if let launcher = insight.analysis.launcher {
                note(L10n.t("Starts through another launcher: %@. Under Wine its window can stay empty or fail to sign in; if the game doesn't come up, a problem report helps.", launcher),
                     systemImage: "arrow.triangle.branch")
            } else if insight.analysis.usesWebView2 {
                note(L10n.t("Draws some windows (sign-in, news) with Microsoft WebView2, which can stay empty on a Mac."),
                     systemImage: "rectangle.dashed")
            }
            if !insight.analysis.antiCheat.isEmpty && game.antiCheatBlock == nil {
                note(L10n.t("Uses %@: online play with it doesn't work on a Mac, single player usually does.",
                            insight.analysis.antiCheat.joined(separator: ", ")),
                     systemImage: "shield.lefthalf.filled")
            }
        }
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: 620, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
