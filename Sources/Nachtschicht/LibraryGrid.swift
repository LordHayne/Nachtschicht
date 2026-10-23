import SwiftUI

/// The whole library at once: covers in a grid, grouped by installed / downloading / the rest.
/// Picking a game here opens it in the big view, where its Play or Download button is.
struct LibraryGrid: View {
    @EnvironmentObject private var model: LibraryModel

    private static let cardWidth: CGFloat = 154
    private static let spacing: CGFloat = 24

    private struct Section: Identifiable {
        let id: String
        let title: String
        let items: [(index: Int, game: Game)]
    }

    private var sections: [Section] {
        let indexed = Array(model.games.enumerated()).map { (index: $0.offset, game: $0.element) }
        func items(_ match: (InstallState) -> Bool) -> [(index: Int, game: Game)] {
            indexed.filter { match($0.game.install) }
        }
        return [
            Section(id: "installed", title: L10n.t("Installed"), items: items { $0 == .installed }),
            Section(id: "downloading", title: L10n.t("Downloading"), items: items {
                if case .downloading = $0 { return true } else { return false }
            }),
            Section(id: "library", title: L10n.t("In your library"), items: items { $0 == .notInstalled }),
        ].filter { !$0.items.isEmpty }
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
                                        GridCard(game: item.game, isSelected: item.index == model.selectedIndex)
                                            .id(item.game.id)
                                            .modifier(GameContextMenu(game: item.game, index: item.index))
                                            .onTapGesture {
                                                if item.index == model.selectedIndex {
                                                    model.showSelectedGame()
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
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}

private struct GridCard: View {
    let game: Game
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverCard(game: game, isSelected: isSelected)
            Text(game.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.ink : Theme.muted)
                .lineLimit(2)
                .frame(width: 154, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
