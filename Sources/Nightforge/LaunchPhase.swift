import Foundation

/// What a start is busy with, for the Play button, with a line underneath that says why it takes
/// a moment: no wait without an explanation.
enum LaunchPhase: Equatable {
    case startingSteam
    case startingSteamForMac
    case signingIn
    case signInInSteamWindow
    case settingUp
    case settingUpDotNet
    case restartingSteam
    /// It ended at once: the next way, by its name.
    case retrying(String)

    var title: String {
        switch self {
        case .startingSteam: return L10n.t("Starting Steam …")
        case .startingSteamForMac: return L10n.t("Starting Steam for Mac …")
        case .signingIn: return L10n.t("Signing in to Steam …")
        case .signInInSteamWindow: return L10n.t("Sign in in the Steam window")
        case .settingUp: return L10n.t("Setting up the game …")
        case .settingUpDotNet: return L10n.t("Setting up .NET for the game …")
        case .restartingSteam: return L10n.t("Restarting Steam …")
        case .retrying(let way): return L10n.t("Starting again with %@ …", way)
        }
    }

    var hint: String {
        switch self {
        case .startingSteam: return L10n.t("Steam runs invisibly in the background – it only has to start once.")
        case .startingSteamForMac: return L10n.t("The Mac version starts through Steam for Mac, which runs in the background.")
        case .signingIn: return L10n.t("Steam signs in again, so your cloud saves come along.")
        case .signInInSteamWindow: return L10n.t("Steam needs you to sign in – its window is open.")
        case .settingUp: return L10n.t("Installing what the game needs from Windows. Only the first time.")
        case .settingUpDotNet: return L10n.t("Installing .NET, which this game needs. Only the first time.")
        case .restartingSteam: return L10n.t("Steam got stuck while starting – a fresh start fixes that.")
        case .retrying: return L10n.t("It closed right away – Nightforge starts it the next way and remembers what works.")
        }
    }

    /// While Steam starts the game itself, the first time with new graphics: shaders are built then.
    static var shaderHint: String { L10n.t("First start with this graphics version: shaders are prepared, so it can take a minute. Next time it's quicker.") }
    static var confirmHint: String { L10n.t("Steam asks something before the game starts – answer it in its window.") }

    // MARK: - First start with new graphics

    private static func shaderKey(_ appID: Int) -> String { "shaders.\(appID)" }

    /// What the shaders depend on: the engine, the layer and the graphics builds in the component list.
    static func graphicsSignature(runner: String?, layer: GraphicsLayer, components: [Component]) -> String {
        let builds = components.filter { $0.kind == .graphics }.map { "\($0.id)@\($0.version)" }.sorted()
        return ([runner ?? "", layer.rawValue] + builds).joined(separator: "|")
    }

    static func isFirstStart(_ appID: Int, signature: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: shaderKey(appID)) != signature
    }

    static func recordStart(_ appID: Int, signature: String, defaults: UserDefaults = .standard) {
        defaults.set(signature, forKey: shaderKey(appID))
    }
}
