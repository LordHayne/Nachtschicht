import Foundation

/// Whether an installed game can be played without internet, as far as Nightforge can tell:
/// Steam's offline mode needs an account it remembers, and the game must not need anything online.
enum OfflineReadiness: Equatable {
    case ready
    /// Never started here: many games set themselves up online the first time.
    case startOnlineOnce
    /// An update is waiting, and Steam won't start the game offline until it's done.
    case updateFirst
    /// Steam lists no single-player mode.
    case onlineOnly
    /// It starts through another launcher that signs in online.
    case launcher(String)
    /// Steam doesn't remember the account, so it can't start offline at all.
    case signInRemembered

    static func of(_ game: Game, analysis: GameAnalysis?, accountRemembered: Bool) -> OfflineReadiness {
        if !accountRemembered { return .signInRemembered }
        if game.onlineOnly { return .onlineOnly }
        if let launcher = analysis?.launcher { return .launcher(launcher) }
        if game.pendingUpdate != nil { return .updateFirst }
        if game.lastPlayed == nil { return .startOnlineOnce }
        return .ready
    }

    var label: String {
        switch self {
        case .ready: return L10n.t("Ready")
        case .startOnlineOnce: return L10n.t("Start online once")
        case .updateFirst: return L10n.t("Update first")
        case .onlineOnly, .launcher: return L10n.t("Needs internet")
        case .signInRemembered: return L10n.t("Not yet")
        }
    }

    var help: String {
        switch self {
        case .ready: return L10n.t("Plays without internet: Steam remembers your account and nothing in the game needs to be online.")
        case .startOnlineOnce: return L10n.t("Start it once while online – many games set themselves up the first time. After that it plays offline.")
        case .updateFirst: return L10n.t("An update is waiting; Steam won't start the game offline until it's downloaded.")
        case .onlineOnly: return L10n.t("Steam lists no single-player mode for it – it needs internet.")
        case .launcher(let name): return L10n.t("It starts through %@, which signs in online.", name)
        case .signInRemembered: return L10n.t("Steam doesn't remember your account: sign in once with “Remember me” so it can start offline.")
        }
    }

    /// Steam remembers an account in this Steam (loginusers.vdf: "RememberPassword" 1).
    static func accountRemembered(steamRoot: URL) -> Bool {
        guard let users = VDF.parse(contentsOf: steamRoot.appendingPathComponent("config/loginusers.vdf"))?["users"]?.object
        else { return false }
        return users.values.contains { $0["rememberpassword"]?.string == "1" }
    }
}
