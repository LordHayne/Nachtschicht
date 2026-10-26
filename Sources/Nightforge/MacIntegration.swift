import AppKit
import UserNotifications

/// Nightforge outside its window: a macOS notification when a download finishes while
/// Nightforge isn't in front.
@MainActor
enum MacIntegration {
    /// The library notifications act on (set when the window starts).
    static weak var model: LibraryModel?

    /// From a notification's Play button: Nightforge comes to the front and plays the game; a
    /// click on the notification itself only shows it.
    static func open(appID: Int?, play: Bool) {
        guard let model, let appID, let game = model.allGames.first(where: { $0.appID == appID }) else { return }
        NSApp.activate()
        if play { model.play(game) } else { model.reveal(game) }
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
