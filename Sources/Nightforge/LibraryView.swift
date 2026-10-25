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
        }
        .animation(.easeOut(duration: 0.28), value: model.selected?.id)
        .animation(.easeOut(duration: 0.22), value: model.showingLibrary)
        .sheet(isPresented: $model.showingOptions) {
            if let game = model.selected {
                GameOptionsSheet(game: game)
            }
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
                Button(L10n.t("Keep"), role: .cancel) {}
            },
            message: { game in
                Text(game.isInstalled
                     ? L10n.t("This removes the game from your Mac and frees %@. It stays in your Steam library, so you can download it again any time. Saves in the Steam Cloud are kept.", Format.bytes(game.sizeOnDisk))
                     : L10n.t("The part downloaded so far is deleted. You can start the download again any time."))
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

            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
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
        return L10n.t("%ld of %ld games", matches, total)
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
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 230, height: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.sodium.opacity(focused ? 0.8 : 0), lineWidth: 1.5))
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
        }
    }
}

// MARK: - Selected game

private struct GameDetail: View {
    let game: Game
    @EnvironmentObject private var model: LibraryModel
    @State private var logo: NSImage?

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
                case .notInstalled:
                    Stat(label: L10n.t("Download"), value: game.sizeOnDisk > 0
                         ? L10n.t("up to %@", Format.bytes(game.sizeOnDisk)) : "–")
                case .downloading:
                    Stat(label: L10n.t("Download"), value: Format.bytes(game.sizeOnDisk))
                }
                if !game.bottle.isBuiltIn {  // only means something with several CrossOver bottles
                    Stat(label: "Bottle", value: game.bottle.name)
                }
            }

            if game.isVROnly {
                Label(L10n.t("Needs a VR headset – this game can't be played on a Mac."), systemImage: "visionpro")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            if game.bottle.isBuiltIn && GraphicsHealth.dxmtFailed(game.appID)
                && GameOptionsStore.load(game.appID).graphics == .automatic {
                Label(L10n.t("This game didn't start with DXMT, so Nightforge uses DXVK for it automatically."),
                      systemImage: "wand.and.stars")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            if model.lowPowerMode && game.install != .inStore {
                HStack(spacing: 10) {
                    Label(L10n.t("Low Power Mode is on – games run much slower with it."), systemImage: "battery.25percent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.sodium)
                    Button(L10n.t("Battery Settings")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if game.macNative {
                Label(L10n.t("Steam also has a Mac version of this game. It often runs better than the Windows version, but older Mac versions sometimes don't start on current Macs."),
                      systemImage: "laptopcomputer")
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
                           isPreparing: model.launchPreparing,
                           vrOnly: game.isVROnly && game.install == .notInstalled) {
                    model.primaryAction()
                }
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
    var isPreparing = false
    /// VR-only and not downloaded: nothing useful to do on a Mac.
    var vrOnly = false
    let action: () -> Void
    @State private var hovering = false

    private var busy: Bool {
        if isLaunching || vrOnly || isUninstalling { return true }
        if case .downloading = install { return true }
        return false
    }

    private var title: String {
        if isLaunching && isPreparing { return L10n.t("Setting up the game …") }
        if isLaunching { return needsConfirmation ? L10n.t("Confirm in the Steam window") : L10n.t("Launching …") }
        if isUninstalling { return L10n.t("Uninstalling …") }
        if isRunning { return L10n.t("Running – switch to game") }
        if vrOnly { return L10n.t("VR only") }
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
                } else if vrOnly {
                    Image(systemName: "visionpro")
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
                    if case .downloading(let fraction?) = install {
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
    }
}

// MARK: - Cover rail

private struct CoverRail: View {
    @EnvironmentObject private var model: LibraryModel

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
                withAnimation(.easeOut(duration: 0.22)) {
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
            case .installed:
                Button(model.isRunning(game) ? L10n.t("Switch to Game") : L10n.t("Play")) { select(); model.primaryAction() }
            case .notInstalled where !game.isVROnly:
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
            if game.macNative {
                Text("MAC")
                    .font(.system(size: 9.5, weight: .heavy).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.night.opacity(0.78), in: Capsule())
                    .padding(7)
                    .help(L10n.t("Steam also has a Mac version"))
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
        .scaleEffect(isSelected ? 1.08 : 1)
        .opacity(isSelected ? 1 : 0.6)
        .shadow(color: .black.opacity(isSelected ? 0.55 : 0.25), radius: isSelected ? 22 : 8, y: isSelected ? 12 : 4)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
        .help(game.name)
        .task(id: game.id) {
            cover = await ArtworkStore.shared.image(for: game, kind: .cover)
        }
    }

    @ViewBuilder private var installBadge: some View {
        switch game.install {
        case .installed:
            EmptyView()
        case .notInstalled, .inStore:
            HStack {
                Spacer()
                Image(systemName: game.install == .inStore ? "cart.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink, Theme.night.opacity(0.7))
                    .padding(8)
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

    var body: some View {
        HStack(spacing: 22) {
            Spacer()
            if model.showingLibrary {
                Hint(symbol: model.controllerConnected ? "a.circle.fill" : "return", text: L10n.t("Open"))
                Hint(symbol: "arrow.up.and.down.and.arrow.left.and.right", text: L10n.t("Select"))
                Hint(symbol: model.controllerConnected ? "b.circle.fill" : "escape", text: L10n.t("Back"))
            } else if model.controllerConnected {
                Hint(symbol: "a.circle.fill", text: L10n.t("Play"))
                Hint(symbol: "y.circle.fill", text: L10n.t("Options"))
                Hint(symbol: "x.circle.fill", text: L10n.t("Library"))
                Hint(symbol: "arrow.left.and.right", text: L10n.t("Select"))
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
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.sodium)
                    .foregroundStyle(Theme.night)
                Button(L10n.t("Rescan")) { model.reload() }
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
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.sodium)
                    .foregroundStyle(Theme.night)
                Button(L10n.t("Choose Another Folder …")) { model.chooseBottlesFolder() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }
}
