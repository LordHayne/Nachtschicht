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

    init(games: [Game], columns: Int) {
        let columns = max(columns, 1)
        rows = GridGroup.allCases.flatMap { group -> [[Int]] in
            let members = games.indices.filter { group.contains(games[$0].install) }
            return stride(from: 0, to: members.count, by: columns).map { Array(members[$0..<min($0 + columns, members.count)]) }
        }
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
        GridGroup.allCases.compactMap { group in
            let items = model.games.indices.filter { group.contains(model.games[$0].install) }
                .map { (index: $0, game: model.games[$0]) }
            return items.isEmpty ? nil : Section(id: "\(group)", title: group.title, items: items)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let columnCount = max(1, Int((geo.size.width - 2 * Theme.gutter + Self.spacing) / (Self.cardWidth + Self.spacing)))
            let columns = Array(repeating: GridItem(.fixed(Self.cardWidth), spacing: Self.spacing), count: columnCount)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 34) {
                        LibraryFilterBar()
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

/// Above the grid: what the library shows. Only there when it has something to offer.
private struct LibraryFilterBar: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if !model.hiddenGames.isEmpty || model.showingHidden {
            HStack(spacing: 12) {
                if model.showingHidden {
                    Text(L10n.t("Hidden games"))
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.ink)
                    Text(L10n.t("Open a game to bring it back."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                FilterToggle(title: L10n.t("Hidden"), symbol: "eye.slash", count: model.hiddenGames.count,
                             on: model.showingHidden, id: "library.hidden") { model.toggleShowingHidden() }
            }
        }
    }
}

/// A filter switch: filled in while it's on.
struct FilterToggle: View {
    let title: String
    let symbol: String
    var count: Int?
    let on: Bool
    let id: String
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
        .accessibilityAddTraits(on ? .isSelected : [])
        .padFocus(id, cornerRadius: 16, activate: action)
    }
}
