import Foundation

/// What the library grid shows and in which order. Kept while you open a game's page and come
/// back, and while you're on Home; only the library applies it.
struct LibraryFilters: Equatable {
    enum Status: CaseIterable {
        case all, onMac, notDownloaded

        var label: String {
            switch self {
            case .all: return L10n.t("All")
            case .onMac: return L10n.t("On this Mac")
            case .notDownloaded: return L10n.t("Not downloaded")
            }
        }
    }

    enum Sort: CaseIterable {
        case recent, name, size

        var label: String {
            switch self {
            case .recent: return L10n.t("Recently played")
            case .name: return L10n.t("Name")
            case .size: return L10n.t("Disk space")
            }
        }
    }

    var status = Status.all
    /// Only games rated "Runs great".
    var great = false
    /// Only games with full controller support.
    var controller = false
    /// Only games that run as their Mac version.
    var mac = false
    var sort = Sort.recent

    /// Something leaves games out.
    var narrows: Bool { status != .all || great || controller || mac }

    /// Without what leaves games out (the order stays).
    var cleared: LibraryFilters { LibraryFilters(sort: sort) }

    func admits(_ game: Game, level: (Game) -> Compatibility.Level) -> Bool {
        let onMac: Bool
        switch game.install {
        case .installed, .downloading: onMac = true
        case .notInstalled, .inStore: onMac = false
        }
        switch status {
        case .all: break
        case .onMac where !onMac: return false
        case .notDownloaded where onMac || game.install == .inStore: return false
        default: break
        }
        if controller && game.controller != .full { return false }
        if mac && game.platform != .mac { return false }
        if great && level(game) != .great { return false }
        return true
    }

    /// Owned games in the order `sort` asks for; the library's own order is "recently played".
    func sorted(_ games: [Game]) -> [Game] {
        switch sort {
        case .recent:
            return games
        case .name:
            return games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return games.sorted { $0.sizeOnDisk != $1.sizeOnDisk ? $0.sizeOnDisk > $1.sizeOnDisk
                                                                : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

/// One titled group of the grid; each starts a row of its own.
struct LibrarySection: Equatable {
    let id: String
    let title: String
    /// Indices into the games, in the order shown.
    let items: [Int]

    /// The grid's sections for `games` (already filtered and sorted): a search's hits in one list,
    /// best first; the hidden games by name; "recently played" grouped into installed /
    /// downloading / the rest; by name or size one list. Store hits always come last.
    static func make(_ games: [Game], sort: LibraryFilters.Sort, searching: Bool, hidden: Bool) -> [LibrarySection] {
        let owned = games.indices.filter { games[$0].install != .inStore }
        let store = games.indices.filter { games[$0].install == .inStore }
        var sections: [LibrarySection]
        if searching {
            sections = [LibrarySection(id: "results", title: L10n.t("Your games"), items: owned)]
        } else if hidden {
            sections = [LibrarySection(id: "hidden", title: L10n.t("Hidden games"), items: owned)]
        } else if sort == .recent {
            sections = GridGroup.allCases.filter { $0 != .store }.map { group in
                LibrarySection(id: "\(group)", title: group.title, items: owned.filter { group.contains(games[$0].install) })
            }
        } else {
            sections = [LibrarySection(id: "all", title: sort == .name ? L10n.t("A – Z") : L10n.t("Largest first"), items: owned)]
        }
        sections.append(LibrarySection(id: "store", title: GridGroup.store.title, items: store))
        return sections.filter { !$0.items.isEmpty }
    }
}
