import Foundation

/// Which build of a game Nightforge runs.
enum Platform: String, Codable {
    /// The Windows version, through Wine and Nightforge's (or a bottle's) Windows Steam.
    case windows
    /// Steam's native macOS version, through Steam for Mac (MacSteam).
    case mac
}

/// The version picked in a game's options; "Automatic" leaves it to `VersionChoice`.
enum GameVersion: String, Codable, CaseIterable, Identifiable {
    case automatic, mac, windows

    var id: String { rawValue }
}

/// Picks the version of a game to run. A native Mac version needs no Windows translation and
/// draws with Metal the way its makers meant, so "Automatic" takes it whenever it still runs on
/// current Macs – 64-bit, since macOS dropped 32-bit apps. A profile can say the Windows version
/// runs better (`GameProfile.preferWindows`, old OpenGL ports), and a Mac version that ended in
/// its first seconds hands over to Windows for good (`MacHealth`).
enum VersionChoice {
    struct Facts {
        var macNative = false
        var mac64 = false
        /// Steam has a Windows version Nightforge can run (a scanned Windows Steam knows the game).
        var windows = true
        var macInstalled = false
        var windowsInstalled = false
    }

    /// Why a game runs the version it does, for the note under its name.
    enum Reason: String, Equatable {
        /// Only one version exists.
        case only
        /// The player picked it in the game's options.
        case chosen
        /// Automatic: the Mac version runs on current Macs.
        case macRuns
        /// Automatic: the player installed the Mac version themselves and not the Windows one.
        case macInstalled
        /// Automatic: Steam's Mac version is 32-bit or doesn't say otherwise.
        case macTooOld
        /// Automatic: the game's profile says the Windows version runs better.
        case windowsBetter
        /// Automatic: the Mac version ended right after starting.
        case macFailed
    }

    static func decide(_ facts: Facts, choice: GameVersion, preferWindows: Bool, macFailed: Bool) -> (Platform, Reason) {
        guard facts.macNative else { return (.windows, .only) }
        guard facts.windows else { return (.mac, .only) }
        switch choice {
        case .mac: return (.mac, .chosen)
        case .windows: return (.windows, .chosen)
        case .automatic: break
        }
        if macFailed { return (.windows, .macFailed) }
        if preferWindows { return (.windows, .windowsBetter) }
        if facts.mac64 { return (.mac, .macRuns) }
        // Unknown age, but it's what's on the Mac; if it doesn't start, MacHealth switches over.
        if facts.macInstalled && !facts.windowsInstalled { return (.mac, .macInstalled) }
        return (.windows, .macTooOld)
    }
}

/// The first start of a game's Mac version is watched like a new launch way (LaunchHealth): one
/// that ends within `LaunchHealth.failureWindow` makes "Automatic" use the Windows version.
enum MacHealth {
    private static func key(_ appID: Int) -> String { "macVersion.\(appID)" }

    private enum State: String {
        case confirmed, failed
    }

    private static func state(_ appID: Int) -> State? {
        UserDefaults.standard.string(forKey: key(appID)).flatMap(State.init(rawValue:))
    }

    static func failed(_ appID: Int) -> Bool { state(appID) == .failed }
    static func confirmed(_ appID: Int) -> Bool { state(appID) == .confirmed }

    static func confirm(_ appID: Int) { UserDefaults.standard.set(State.confirmed.rawValue, forKey: key(appID)) }
    static func fail(_ appID: Int) { UserDefaults.standard.set(State.failed.rawValue, forKey: key(appID)) }

    /// Picking a version by hand starts over.
    static func reset(_ appID: Int) { UserDefaults.standard.removeObject(forKey: key(appID)) }
}
