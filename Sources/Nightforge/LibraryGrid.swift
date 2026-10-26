import SwiftUI

/// The grid's groups, in the order it shows them; each one starts a row of its own.
enum GridGroup: CaseIterable {
    case installed, downloading, library, store

    var title: String {
        switch self {
        case .installed: return L10n.t("Installed")
        case .downloading: return L10n.t("Downloading")
        case .library: return L10n.t("In your library")
        case .store: return L10n.t("In the Steam Store")
        }
    }

    func contains(_ state: InstallState) -> Bool {
        switch (self, state) {
        case (.installed, .installed), (.downloading, .downloading), (.library, .notInstalled), (.store, .inStore): return true
        default: return false
        }
    }
}

/// Where each game sits in the grid, so ↑/↓ and ←/→ follow what's on screen: a search orders the
/// games by match, and every group starts a new row, so neither is a plain step through the list.
struct GridLayout {
    /// Indices into the games, row by row.
    let rows: [[Int]]

    /// `sections`: each group's indices, in the order shown.
    init(sections: [[Int]], columns: Int) {
        let columns = max(columns, 1)
        rows = sections.flatMap { members -> [[Int]] in
            stride(from: 0, to: members.count, by: columns).map { Array(members[$0..<min($0 + columns, members.count)]) }
        }
    }

    /// Grouped by install state, in the list's order (the library sorted by "recently played").
    init(games: [Game], columns: Int) {
        self.init(sections: GridGroup.allCases.map { group in games.indices.filter { group.contains(games[$0].install) } },
                  columns: columns)
    }

    /// The games in reading order.
    var order: [Int] { rows.flatMap { $0 } }

    func position(of index: Int) -> (row: Int, column: Int)? {
        for (row, members) in rows.enumerated() {
            if let column = members.firstIndex(of: index) { return (row, column) }
        }
        return nil
    }

    /// The game `delta` rows up or down, in the same column or the last one of a shorter row;
    /// nil past the first or last row.
    func index(from index: Int, rows delta: Int) -> Int? {
        guard let (row, column) = position(of: index), rows.indices.contains(row + delta) else { return nil }
        let target = rows[row + delta]
        return target[min(column, target.count - 1)]
    }

    /// The game `delta` places on in reading order, stopping at either end.
    func index(from index: Int, steps delta: Int) -> Int? {
        let order = self.order
        guard let place = order.firstIndex(of: index) else { return order.first }
        return order[max(0, min(order.count - 1, place + delta))]
    }
}

/// The whole library at once: covers in a grid, grouped by installed / downloading / the rest.
/// A click selects a game, a second one (or Return, A) opens its page, where its Play or Download
/// button is.
struct LibraryGrid: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cardWidth: CGFloat = 154
    private static let spacing: CGFloat = 24

    private struct Section: Identifiable {
        let id: String
        let title: String
        let items: [(index: Int, game: Game)]
    }

    private var sections: [Section] {
        model.librarySections.map { section in
            Section(id: section.id, title: section.title, items: section.items.map { (index: $0, game: model.games[$0]) })
        }
    }

    var body: some View {
        GeometryReader { geo in
            let columnCount = max(1, Int((geo.size.width - 2 * Theme.gutter + Self.spacing) / (Self.cardWidth + Self.spacing)))
            let columns = Array(repeating: GridItem(.fixed(Self.cardWidth), spacing: Self.spacing), count: columnCount)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 34) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(section.title)
                                        .font(Theme.display(19))
                                        .foregroundStyle(Theme.ink)
                                    Text("\(section.items.count)")
                                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(Theme.muted)
                                }
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                                    ForEach(section.items, id: \.game.id) { item in
                                        GridCard(game: item.game, isSelected: item.index == model.selectedIndex,
                                                 isRunning: model.isRunning(item.game), isPinned: model.isPinned(item.game),
                                                 compatibility: model.compatibility(of: item.game))
                                            .id(item.game.id)
                                            .modifier(GameContextMenu(game: item.game, index: item.index))
                                            .onTapGesture {
                                                if item.index == model.selectedIndex {
                                                    model.openDetail()
                                                } else {
                                                    model.selectedIndex = item.index
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 20)
                }
                .onAppear {
                    model.gridColumns = columnCount
                    if let id = model.selected?.id { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: columnCount) { _, count in model.gridColumns = count }
                .onChange(of: model.selectedIndex) { _, _ in
                    guard let id = model.selected?.id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}

private struct GridCard: View {
    let game: Game
    let isSelected: Bool
    var isRunning = false
    var isPinned = false
    let compatibility: Compatibility

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverCard(game: game, isSelected: isSelected, isRunning: isRunning, isPinned: isPinned)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // The level's own icon (each has a different one), named for VoiceOver and on hover.
                Image(systemName: compatibility.level.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(compatibility.level.color)
                    .help(compatibility.level.label)
                    .accessibilityLabel(compatibility.level.label)
                Text(game.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.muted)
                    .lineLimit(2)
            }
            .frame(width: 154, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

/// Above the grid: what it shows and in which order. Every control is a button the pad reaches
/// (↑ from the grid's first row).
struct LibraryToolbar: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.showingHidden ? L10n.t("Hidden games") : L10n.t("Library"))
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink)
                Text(countText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.muted)
                if model.showingHidden {
                    Text(L10n.t("Open a game to bring it back."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if !model.hiddenGames.isEmpty {
                    FilterToggle(title: L10n.t("Hidden"), symbol: "eye.slash", count: model.hiddenGames.count,
                                 on: model.showingHidden, id: "library.hidden",
                                 help: L10n.t("Games you hid from your library")) { model.toggleShowingHidden() }
                        .padding(.trailing, model.showingHidden ? 0 : 8)
                }
                if !model.showingHidden {
                    Text(L10n.t("Sort"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Segmented(options: LibraryFilters.Sort.allCases.map { ($0, $0.label, nil) }, selection: model.filters.sort,
                              id: "library.sort") { model.filters.sort = $0 }
                }
            }
            if !model.showingHidden {
                HStack(spacing: 10) {
                    Segmented(options: LibraryFilters.Status.allCases.map { ($0, $0.label, nil) }, selection: model.filters.status,
                              id: "library.status") { model.filters.status = $0 }
                    Divider().frame(height: 18).overlay(Color.white.opacity(0.15))
                    FilterToggle(title: Compatibility.Level.great.label, symbol: Compatibility.Level.great.symbol,
                                 on: model.filters.great, id: "library.great",
                                 help: L10n.t("Only games that run great on a Mac")) { model.filters.great.toggle() }
                    FilterToggle(title: L10n.t("Controller"), symbol: "gamecontroller.fill", on: model.filters.controller,
                                 id: "library.controller", help: L10n.t("Full controller support")) { model.filters.controller.toggle() }
                    FilterToggle(title: L10n.t("Mac version"), symbol: "apple.logo", on: model.filters.mac,
                                 id: "library.mac", help: L10n.t("Runs as its Mac version")) { model.filters.mac.toggle() }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 18)
    }

    private var countText: String {
        let owned = model.games.filter { $0.install != .inStore }.count
        if model.showingHidden { return L10n.t("%ld hidden", owned) }
        let total = model.visibleCount
        if model.filters.narrows || !model.searchText.isEmpty {
            return total == 1 ? L10n.t("%ld of 1 game", owned) : L10n.t("%ld of %ld games", owned, total)
        }
        return total == 1 ? L10n.t("1 game") : L10n.t("%ld games", total)
    }
}

/// A row of choices, one filled in; each segment is a button of its own for the pad.
struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, title: String, count: Int?)]
    let selection: Value
    let id: String
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { place, option in
                let on = option.value == selection
                Button { select(option.value) } label: {
                    HStack(spacing: 6) {
                        Text(option.title)
                        if let count = option.count {
                            Text("\(count)").monospacedDigit().foregroundStyle(on ? Theme.night.opacity(0.6) : Theme.muted)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Theme.night : Theme.ink.opacity(0.8))
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .background(on ? Theme.ink : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .padFocus("\(id).\(place)", cornerRadius: 13, activate: { select(option.value) })
            }
        }
        .padding(3)
        .frame(height: 32)
        .background(.ultraThinMaterial, in: Capsule())
        .fixedSize()
    }
}

/// A filter switch: filled in while it's on.
struct FilterToggle: View {
    let title: String
    let symbol: String
    var count: Int?
    let on: Bool
    let id: String
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(on ? Theme.night.opacity(0.6) : Theme.muted)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? Theme.night : Theme.ink.opacity(0.85))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background {
                if on { Capsule().fill(Theme.ink) } else { Capsule().fill(.ultraThinMaterial) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .padFocus(id, cornerRadius: 16, activate: action)
        .fixedSize()
    }
}
