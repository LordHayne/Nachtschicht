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

            if let game = model.heroGame {
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

                ZStack(alignment: .topLeading) {
                    // The grid stays behind a game's page opened from it, so going back finds it
                    // scrolled to where it was.
                    if keepsLibrary {
                        LibraryLevel()
                            .opacity(model.showingLibrary ? 1 : 0)
                            .allowsHitTesting(model.showingLibrary)
                            .accessibilityHidden(!model.showingLibrary)
                    }
                    switch model.route {
                    case .home:
                        HomeLevel()
                            .transition(.opacity)
                    case .detail:
                        if let game = model.selected {
                            DetailLevel(game: game)
                                .transition(.opacity)
                        }
                    case .library:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HintBar()
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 22)
            }

            ToastHost()
        }
        .animation(.easeOut(duration: 0.28), value: model.heroGame?.id)
        .animation(.easeOut(duration: 0.22), value: model.route)
        // A changed version moves the game to another Steam: scan again.
        .sheet(isPresented: $model.showingOptions, onDismiss: { model.reload(quiet: true) }) {
            if let game = model.selected {
                GameOptionsSheet(game: game, insight: model.insights[game.appID]) { model.reportProblem(for: game) }
            }
        }
        .sheet(item: $model.pendingSpace) { request in
            SpaceSheet(request: request)
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
        .sheet(item: $model.sessionSummary) { summary in
            SessionSummarySheet(summary: summary)
        }
        .sheet(item: $model.failedLaunch) { failed in
            FailedLaunchSheet(failed: failed)
        }
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

    private var keepsLibrary: Bool { model.route.level == .library }
}

// MARK: - The three levels

/// Level 1 – what you play: the selected game big, the rail of what's next, and the way to the rest.
private struct HomeLevel: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)

            if let game = model.heroGame {
                GameDetail(game: game, compact: true)
                    .id(game.id)
                    .transition(.opacity)
                    .padding(.horizontal, Theme.gutter)
            } else if model.needsSetup {
                SetupView(setup: model.setup)
                    .padding(.horizontal, Theme.gutter)
            } else if !model.allGames.isEmpty {
                AllGamesHero()
                    .transition(.opacity)
                    .padding(.horizontal, Theme.gutter)
            } else if !model.isScanning {
                EmptyLibrary()
                    .padding(.horizontal, Theme.gutter)
            }

            Spacer(minLength: 28)

            if !model.allGames.isEmpty {
                CoverRail()
            }
        }
    }
}

/// Level 2 – every game, in the grid, with its filters; a search's hits show here.
private struct LibraryLevel: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryToolbar()
            if model.games.isEmpty {
                VStack(alignment: .leading) {
                    Spacer()
                    if !model.searchText.isEmpty {
                        NoResults()
                    } else if model.filters.narrows {
                        NoFilterMatches()
                    } else if !model.isScanning {
                        EmptyLibrary()
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LibraryGrid()
                    .padding(.top, 4)
            }
        }
    }
}

private struct NoFilterMatches: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("No games match these filters"))
                .font(Theme.display(30))
                .foregroundStyle(Theme.ink)
            Button(L10n.t("Clear filters")) { model.filters = model.filters.cleared }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padFocus("noResults.clearFilters", activate: { model.filters = model.filters.cleared })
        }
    }
}

/// Level 3 – one game's page: everything Nightforge knows about it, and the one button.
private struct DetailLevel: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackPill(to: model.route.level)
                .padding(.top, 18)
            Spacer(minLength: 24)
            GameDetail(game: game, compact: false)
                .id(game.id)
            Spacer(minLength: 28)
        }
        .padding(.horizontal, Theme.gutter)
    }
}

/// "‹ Home" / "‹ Library": where Esc and B go from a game's page.
private struct BackPill: View {
    let to: Route.Level
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        Button { model.back() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                Text(to == .home ? L10n.t("Home") : L10n.t("Library"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.ink.opacity(0.9))
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: 34)
            .background(.ultraThinMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L10n.t("Back (Esc)"))
        .accessibilityLabel(to == .home ? L10n.t("Back to Home") : L10n.t("Back to the library"))
        .padFocus("detail.back", cornerRadius: 17, activate: { model.back() })
    }
}

/// Home with the rail's last tile selected: the way to every game.
private struct AllGamesHero: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("Library").uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(1.8)
                .foregroundStyle(Theme.muted)
            Text(model.visibleCount == 1 ? L10n.t("Your game") : L10n.t("All %ld games", model.visibleCount))
                .font(Theme.display(54))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            Text(L10n.t("Everything in your library – installed or not – in one place."))
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 320, maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.goLibrary() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(L10n.t("Open Library"))
                        .font(Theme.display(17))
                }
                .foregroundStyle(Theme.night)
                .padding(.horizontal, 32)
                .frame(height: 52)
                .background(Theme.sodium, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(L10n.t("Whole library (L)"))
            .padFocus("play", cornerRadius: 34, activate: { model.goLibrary() })
        }
        .frame(height: 340, alignment: .bottomLeading)
    }
}

// MARK: - Didn't start

/// A game that ended right after starting with every way Nightforge knows: what was tried, and
/// what's left to do – start over, choose by hand, or report it.
struct FailedLaunchSheet: View {
    let failed: FailedLaunch
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("%@ didn't start", failed.game.name))
                .font(Theme.display(20))
                .lineLimit(2)
            Label(L10n.t("It ended right after starting, with every way Nightforge knows to start it."),
                  systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
            if !failed.tried.isEmpty {
                Text(L10n.t("Tried: %@", failed.tried.joined(separator: " · ")))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                // A on a controller is Return: the first way out, not a browser.
                Button(action: startOver) {
                    Label(L10n.t("Try Again From the First Way"), systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padFocus("failed.again", activate: startOver)
                Text(L10n.t("Helps when something got in the way the first time – Steam updating, a window asking something."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if hasLayers {
                    Button(action: chooseByHand) {
                        Label(L10n.t("Choose Graphics by Hand …"), systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .padFocus("failed.options", activate: chooseByHand)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t("Still no luck? A problem report opens on GitHub, filled in with what Nightforge tried – nothing is sent until you submit it there."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(L10n.t("Report problem"), action: report)
                    .padFocus("failed.report", activate: report)
            }
            HStack {
                Spacer()
                Button(L10n.t("Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padFocus("failed.close", activate: { dismiss() })
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    /// Vulkan, OpenGL and DirectX 12 have one way each: nothing to pick by hand.
    private var hasLayers: Bool {
        guard failed.game.bottle.isBuiltIn, failed.game.platform == .windows else { return false }
        guard let analysis = model.insights[failed.game.appID]?.analysis else { return true }
        return analysis.usesD3D11 || analysis.usesD3D9 || analysis.apis.isEmpty
    }

    private func startOver() { model.startOver(failed) }
    private func chooseByHand() { model.chooseGraphicsByHand(failed) }
    private func report() { model.reportProblem(for: failed.game, tried: failed.tried) }
}

// MARK: - Not enough space

/// A download that wouldn't fit: how much is missing, and long unplayed games to make room with.
struct SpaceSheet: View {
    let request: SpaceRequest
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String>

    init(request: SpaceRequest) {
        self.request = request
        _picked = State(initialValue: SpaceCheck.preselect(request.candidates, shortfall: request.shortfall))
    }

    private var freed: Int64 { request.candidates.filter { picked.contains($0.id) }.reduce(0) { $0 + $1.sizeOnDisk } }
    private var enough: Bool { freed >= request.shortfall }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("%@ needs up to %@", request.game.name, Format.bytes(request.game.sizeOnDisk)))
                .font(Theme.display(20))
                .lineLimit(2)
            Label(L10n.t("Your Mac has %@ free – %@ short. Nothing is downloaded until there's room, so nothing stops halfway.",
                         Format.bytes(request.free), Format.bytes(request.shortfall)),
                  systemImage: "externaldrive.badge.exclamationmark")
                .fixedSize(horizontal: false, vertical: true)
            if request.candidates.isEmpty {
                Text(L10n.t("No game here has gone unplayed for a month. Remove games or other files you don't need, then try again."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.t("Make room – these haven't been played for a while. They stay in your Steam library, and saves in the Steam Cloud are kept."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(request.candidates) { game in
                        let on = Binding(get: { picked.contains(game.id) },
                                         set: { if $0 { picked.insert(game.id) } else { picked.remove(game.id) } })
                        Toggle(isOn: on) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(game.name).lineLimit(1)
                                    Text(game.lastPlayed.map { L10n.t("Last played %@", Format.relative($0)) } ?? L10n.t("Never played"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Format.bytes(game.sizeOnDisk)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padFocus("space.\(game.id)", toggle: on)
                    }
                }
                Text(enough ? L10n.t("Frees %@ – enough", Format.bytes(freed)) : L10n.t("Frees %@ of %@", Format.bytes(freed), Format.bytes(request.shortfall)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(enough ? Theme.runsGreat : .secondary)
            }
            HStack {
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padFocus("space.cancel", activate: { dismiss() })
                if !request.candidates.isEmpty {
                    Button(L10n.t("Uninstall %ld & Download", picked.count)) { model.freeUpAndDownload(picked) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!enough)
                        .padFocus("space.confirm", enabled: enough, activate: { model.freeUpAndDownload(picked) })
                }
            }
        }
        .padding(24)
        .frame(width: 520)
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
                SectionSwitch()
                    .fixedSize()
                    .padding(.leading, 6)
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
                            .lineLimit(1)
                    }
                    .fixedSize()
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
            }

            if !model.downloads.isEmpty {
                DownloadsButton()
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

}

/// "Home | Library 104": the two levels, the one you're on filled in.
private struct SectionSwitch: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        HStack(spacing: 0) {
            segment(.home, L10n.t("Home"), count: nil) { model.goHome() }
            segment(.library, L10n.t("Library"), count: model.visibleCount) { model.goLibrary() }
        }
        .padding(3)
        .frame(height: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Sections"))
    }

    private func segment(_ level: Route.Level, _ title: String, count: Int?, action: @escaping () -> Void) -> some View {
        let on = model.route.level == level
        return Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(on ? Theme.night.opacity(0.6) : Theme.muted)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? Theme.night : Theme.ink.opacity(0.8))
            .padding(.horizontal, 13)
            .frame(maxHeight: .infinity)
            .background(on ? Theme.ink : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(level == .home ? L10n.t("Home – what you play (L)") : L10n.t("Whole library (L)"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .padFocus("top.\(level == .home ? "home" : "library")", cornerRadius: 14, activate: action)
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
        .frame(minWidth: 120, idealWidth: 230, maxWidth: 230)
        .frame(height: 34)
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

/// The selected game big: on Home what you need to press Play (`compact`), on its page everything.
private struct GameDetail: View {
    let game: Game
    var compact = false
    @EnvironmentObject private var model: LibraryModel
    @State private var logo: NSImage?

    static func openBatterySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 24) {
            VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CompatibilityLine(compatibility: model.compatibility(of: game), detailed: !compact)
                if model.isHidden(game) {
                    Label(L10n.t("Hidden"), systemImage: "eye.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
            }

            Group {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 480, maxHeight: compact ? 150 : 170, alignment: .bottomLeading)
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
            .frame(height: compact ? 150 : 170, alignment: .bottomLeading)
            .accessibilityLabel(game.name)
            }

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
            if !compact, let insight = model.insights[game.appID] {
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
            if !compact {
                VersionNotes(game: game)
            }
            if let needed = game.downloadNeedsSpace {
                Label(L10n.t("Not enough space: Steam needs %@ to download this game, your Mac has %@ free. Make some room, then continue.",
                             Format.bytes(needed), Format.bytes(LibraryModel.freeSpace(at: game.installDir.deletingLastPathComponent()))),
                      systemImage: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                PlayButton(install: game.install, isLaunching: model.launchingID == game.id,
                           isUninstalling: model.uninstallingID == game.id,
                           isRunning: model.isRunning(game),
                           needsConfirmation: model.launchNeedsConfirmation,
                           status: model.launchPhase?.title,
                           unavailable: unavailable, cloud: game.playsInCloud,
                           noSpace: game.downloadNeedsSpace != nil,
                           update: game.pendingUpdate) {
                    model.primaryAction()
                }
                .padFocus("play", cornerRadius: 34, activate: { model.primaryAction() })
                if compact {
                    RoundIconButton(symbol: "info", help: L10n.t("Details (I)")) {
                        model.openDetail()
                    }
                }
                if game.install != .inStore {
                    RoundIconButton(symbol: "slider.horizontal.3", help: L10n.t("Options for this game (O)")) {
                        model.showingOptions = true
                    }
                }
                if !compact && game.install != .inStore {
                    RoundIconButton(symbol: "folder", help: L10n.t("Show game folder in Finder")) {
                        model.revealSelected()
                    }
                }
                if !compact && model.canUninstall(game) {
                    RoundIconButton(
                        symbol: game.isInstalled ? "trash" : "xmark",
                        help: game.isInstalled ? L10n.t("Uninstall (⌘⌫)") : L10n.t("Cancel Download")
                    ) {
                        model.requestUninstall(game)
                    }
                }
                if !compact && game.install != .inStore {
                    let hidden = model.isHidden(game)
                    RoundIconButton(symbol: hidden ? "eye" : "eye.slash",
                                    help: hidden ? L10n.t("Show in library again (H)") : L10n.t("Hide from library (H)"),
                                    focusID: "detail.hide") {
                        model.toggleHidden(game)
                    }
                }
                if !compact && game.isInstalled {
                    let added = model.shortcutsChanged >= 0 && GameShortcut.exists(for: game)
                    RoundIconButton(symbol: added ? "app.badge.checkmark" : "app.badge",
                                    help: added ? L10n.t("In Applications – show it") : L10n.t("Add to Applications – Spotlight and Launchpad find it"),
                                    focusID: "detail.shortcut") {
                        if added {
                            NSWorkspace.shared.activateFileViewerSelecting([GameShortcut.appURL(for: game)])
                        } else {
                            model.addShortcut(for: game)
                        }
                    }
                }
                if !compact && (model.canPin(game) || model.isPinned(game)) {
                    let pinned = model.isPinned(game)
                    RoundIconButton(symbol: pinned ? "pin.fill" : "pin",
                                    help: pinned ? L10n.t("Unpin from Home (P)") : L10n.t("Pin to Home – stays on the rail (P)"),
                                    focusID: "detail.pin") {
                        model.togglePinned(game)
                    }
                }
            }
            if model.launchingID == game.id, let hint = model.launchHint {
                Text(hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
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

/// How well it runs on a Mac: the badge, and on a game's page what it means for this game.
private struct CompatibilityLine: View {
    let compatibility: Compatibility
    var detailed = false

    var body: some View {
        HStack(spacing: 12) {
            CompatibilityBadge(compatibility: compatibility)
            if detailed, let note = compatibility.note {
                Text(note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .frame(minWidth: 320, maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if detailed, !compatibility.testedOn.isEmpty {
                Text(L10n.t("Tested on %@", compatibility.testedOn.joined(separator: ", ")))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
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
        .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
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
    /// An update Steam downloads first: its size, 0 when not known yet.
    var update: Int64?
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
        case .installed where update != nil:
            return update! > 0 ? L10n.t("Update & Play · %@", Format.bytes(update!)) : L10n.t("Update & Play")
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
                } else if install == .installed && update != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .bold))
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
    /// For a button whose symbol changes (hide/show): keeps the pad's highlight on it.
    var focusID: String?
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
        .padFocus(focusID ?? "round.\(symbol)", cornerRadius: size / 2, activate: action)
    }
}

// MARK: - Cover rail

/// Home's rail, "Continue playing": pinned games, downloads and what you played lately, then a tile
/// to all the others. A click selects, a second one opens the game's page – it never starts or
/// downloads anything.
private struct CoverRail: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.reduceMotion) private var reduceMotion

    private static let allGamesID = "rail.allGames"

    private var railItems: [(place: Int, index: Int, game: Game)] {
        model.homeRail.enumerated().map { (place: $0.offset, index: $0.element, game: model.games[$0.element]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L10n.t("Continue playing"))
                    .font(Theme.display(15))
                    .foregroundStyle(Theme.ink)
                Text(L10n.t("Pinned, then what you played lately"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, Theme.gutter)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            rail
        }
    }

    private var rail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(railItems, id: \.game.id) { place, index, game in
                        let isSelected = !model.homeOnAllGames && index == model.selectedIndex
                        CoverCard(game: game, isSelected: isSelected, isRunning: model.isRunning(game), isPinned: model.isPinned(game))
                            .id(game.id)
                            .modifier(GameContextMenu(game: game, index: index))
                            .onTapGesture {
                                if isSelected {
                                    model.openDetail()
                                } else {
                                    model.selectOnHome(place: place)
                                }
                            }
                            .help(isSelected ? L10n.t("%@ – click again for details", game.name) : game.name)
                    }
                    AllGamesTile(count: model.visibleCount, isSelected: model.homeOnAllGames)
                        .id(Self.allGamesID)
                        .onTapGesture {
                            if model.homeOnAllGames {
                                model.goLibrary()
                            } else {
                                model.selectOnHome(place: model.homeRail.count)
                            }
                        }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 22)
            }
            .frame(height: 290)
            .onChange(of: model.homePlace) { _, _ in
                let id = model.homeOnAllGames ? Self.allGamesID : model.selected?.id
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0.3, y: 0.5))
                }
            }
        }
    }
}

/// The rail's last tile: every game, one step away.
private struct AllGamesTile: View {
    let count: Int
    let isSelected: Bool
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.ink.opacity(0.85))
            Spacer()
            Text(L10n.t("All games"))
                .font(Theme.display(19))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 4) {
                Text(count == 1 ? L10n.t("1 in your library") : L10n.t("%ld in your library", count))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 154, height: 231, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Theme.sodium : Color.white.opacity(0.15), lineWidth: isSelected ? 3 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1)
        .opacity(isSelected ? 1 : 0.6)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
        .help(L10n.t("Whole library (L)"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("All games, %ld in your library", count))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
        model.select(index)
    }
}

struct CoverCard: View {
    let game: Game
    let isSelected: Bool
    var isRunning = false
    var isPinned = false
    @State private var cover: NSImage?
    @Environment(\.reduceMotion) private var reduceMotion

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
            if isPinned && !isRunning {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Theme.night.opacity(0.78), in: Capsule())
                    .padding(7)
                    .help(L10n.t("Pinned to Home"))
            }
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
        case .installed: parts.append(game.pendingUpdate != nil ? L10n.t("Installed, update waiting") : L10n.t("Installed"))
        case .downloading: parts.append(L10n.t("Downloading"))
        case .notInstalled: parts.append(L10n.t("In your library"))
        case .inStore: parts.append(L10n.t("In the Steam Store"))
        }
        if game.platform == .mac { parts.append(L10n.t("Uses the Mac version")) }
        if isPinned { parts.append(L10n.t("Pinned to Home")) }
        if game.controller != .none { parts.append(game.controller.help) }
        if isRunning { parts.append(L10n.t("Running")) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var installBadge: some View {
        switch game.install {
        case .installed where game.pendingUpdate != nil:
            HStack {
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink, Theme.night.opacity(0.7))
                    .padding(8)
                    .help(L10n.t("An update is waiting – Steam downloads it before the game starts"))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
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
            let controller = model.controllerConnected
            if controller && focus.focused != nil {
                Hint(symbol: pad.confirm, text: L10n.t("Select"))
                Hint(symbol: pad.stick, text: L10n.t("Move"))
                Hint(symbol: pad.back, text: L10n.t("Back"))
            } else {
                switch model.route {
                case .home:
                    if model.heroGame != nil {
                        Hint(symbol: controller ? pad.confirm : "return", text: L10n.t("Play"))
                        Hint(symbol: controller ? pad.library : "i.square", text: L10n.t("Details"))
                    } else {
                        Hint(symbol: controller ? pad.confirm : "return", text: L10n.t("Open"))
                    }
                    Hint(symbol: controller ? "line.3.horizontal.circle.fill" : "l.square", text: L10n.t("Library"))
                    Hint(symbol: controller ? pad.stick : "arrow.left.and.right", text: L10n.t("Select"))
                case .library:
                    Hint(symbol: controller ? pad.confirm : "return", text: L10n.t("Open"))
                    Hint(symbol: controller ? pad.stick : "arrow.up.and.down.and.arrow.left.and.right",
                         text: L10n.t("Select"))
                    Hint(symbol: controller ? pad.back : "escape",
                         text: !model.searchText.isEmpty ? L10n.t("Clear search") : model.showingHidden ? L10n.t("All games") : L10n.t("Home"))
                case .detail(_, let from):
                    if let game = model.selected, game.install != .inStore {
                        // What Return does here: the big button's word, short.
                        Hint(symbol: controller ? pad.confirm : "return",
                             text: game.install == .notInstalled && !game.playsInCloud ? L10n.t("Download") : L10n.t("Play"))
                        Hint(symbol: controller ? pad.options : "o.square", text: L10n.t("Options"))
                        if !controller {
                            Hint(symbol: "h.square", text: model.isHidden(game) ? L10n.t("Show") : L10n.t("Hide"))
                        }
                    }
                    Hint(symbol: controller ? pad.back : "escape", text: from == .home ? L10n.t("Home") : L10n.t("Library"))
                }
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
                .frame(minWidth: 320, maxWidth: 560, alignment: .leading)
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
                .frame(minWidth: 320, maxWidth: 560, alignment: .leading)
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
            .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
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
            .frame(minWidth: 320, maxWidth: 620, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
