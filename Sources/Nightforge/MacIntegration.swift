import AppKit
import UserNotifications

/// Nightforge outside its window: the Dock menu with the last games played, and a macOS
/// notification when a download finishes while Nightforge isn't in front.
@MainActor
enum MacIntegration {
    /// The library the Dock menu and notifications act on (set when the window starts).
    static weak var model: LibraryModel?

    // MARK: - Dock menu

    nonisolated static let dockLimit = 5

    /// Installed games, the last played first; never played ones aren't "recent".
    nonisolated static func recentGames(_ games: [Game], hidden: Set<Int> = []) -> [Game] {
        let played = games.filter { $0.isInstalled && $0.lastPlayed != nil && !hidden.contains($0.appID) }
        return Array(played.sorted { $0.lastPlayed! > $1.lastPlayed! }.prefix(dockLimit))
    }

    static func dockMenu(target: AnyObject, action: Selector) -> NSMenu? {
        guard let model else { return nil }
        let games = recentGames(model.allGames, hidden: model.hiddenGames)
        guard !games.isEmpty else { return nil }
        let menu = NSMenu()
        for game in games {
            let item = NSMenuItem(title: game.name, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = game.id
            menu.addItem(item)
        }
        return menu
    }

    /// From the Dock menu, a notification's Play button or a game's link: Nightforge comes to the
    /// front and plays the game – or shows its page when it isn't installed (a link never downloads).
    static func open(id: String? = nil, appID: Int? = nil, play: Bool) {
        guard let model, let game = model.allGames.first(where: { $0.id == id || (appID != nil && $0.appID == appID) }) else { return }
        NSApp.activate()
        if play && game.isInstalled {
            model.play(game)
        } else if model.reveal(game), play {
            model.openDetail()
        }
    }

    /// A link that came before the library was read: opened once it is.
    private static var pendingLink: GameShortcut.Action?

    static func open(_ url: URL) {
        guard let action = GameShortcut.action(from: url) else { return }
        guard let model, !model.allGames.isEmpty else {
            pendingLink = action
            return
        }
        switch action {
        case .play(let appID): open(appID: appID, play: true)
        case .show(let appID): open(appID: appID, play: false)
        }
    }

    /// After a scan: a link that waited for the library.
    static func libraryLoaded() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        switch link {
        case .play(let appID): open(appID: appID, play: true)
        case .show(let appID): open(appID: appID, play: false)
        }
    }

    // MARK: - Notifications

    private static let category = "download.finished"
    private static let playAction = "play"

    /// Notifications need a real app bundle (not a test run).
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func setUp(delegate: UNUserNotificationCenterDelegate) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let play = UNNotificationAction(identifier: playAction, title: L10n.t("Play"), options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: category, actions: [play], intentIdentifiers: [])])
    }

    /// "<Game> is ready to play" with a Play button – only when Nightforge isn't in front (then a
    /// toast says it) and the player hasn't turned it off. macOS asks once whether that's all right.
    static func announceFinished(_ games: [Game]) {
        guard available, Prefs.notifyDownloads, !NSApp.isActive, let game = games.first else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = games.count == 1 ? L10n.t("%@ is ready to play", game.name) : L10n.t("%ld games are ready to play", games.count)
        content.body = games.count == 1 ? L10n.t("The download is done.") : games.map(\.name).joined(separator: ", ")
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["appID": game.appID]
        let request = UNNotificationRequest(identifier: "download.\(game.appID)", content: content, trigger: nil)
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }

    /// A click on the notification or its Play button.
    nonisolated static func handle(_ response: UNNotificationResponse) {
        let appID = response.notification.request.content.userInfo["appID"] as? Int
        let action = response.actionIdentifier
        Task { @MainActor in
            if action == playAction {
                open(appID: appID, play: true)
            } else if action == UNNotificationDefaultActionIdentifier {
                open(appID: appID, play: false)
            }
        }
    }
}
