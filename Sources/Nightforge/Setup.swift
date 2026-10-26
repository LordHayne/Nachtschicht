import AppKit
import Foundation

/// The one-button "Connect Steam" flow: every step checks whether it's already done, so pressing
/// the button again after a failure (or on a second Mac start) just carries on where it stopped.
@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case rosetta, engine, environment, steam, signIn

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .rosetta: return L10n.t("Preparing your Mac")
            case .engine: return L10n.t("Downloading the game engine")
            case .environment: return L10n.t("Setting up Windows environment")
            case .steam: return L10n.t("Installing Steam")
            case .signIn: return L10n.t("Signing in to Steam")
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case running(Step)
        case needsRosetta
        case waitingForSignIn
        case done
        case failed(Step, String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Download progress of the current step, when it has one.
    @Published private(set) var progress: Double?

    var onFinished: (() -> Void)?
    private var signInWatcher: Task<Void, Never>?

    /// Nothing left to do: Steam is installed and someone has signed in.
    static var isComplete: Bool { Engine.isSteamInstalled && Engine.isSteamSignedIn }

    func currentStep() -> Step? {
        switch phase {
        case .running(let step), .failed(let step, _): return step
        case .needsRosetta: return .rosetta
        case .waitingForSignIn: return .signIn
        case .idle, .done: return nil
        }
    }

    func isFinished(_ step: Step) -> Bool {
        if phase == .done { return true }
        guard let current = currentStep() else { return false }
        return step.rawValue < current.rawValue
    }

    func start() {
        guard phase == .idle || phase == .needsRosetta || { if case .failed = phase { return true } else { return false } }() else { return }
        Task { await run() }
    }

    private func run() async {
        var step = Step.rosetta
        do {
            phase = .running(.rosetta)
            guard Engine.isRosettaInstalled else {
                phase = .needsRosetta
                return
            }

            step = .engine
            phase = .running(.engine)
            let manifest = try await ComponentStore.shared.manifest()
            guard let engineComponent = manifest.component(Engine.engineID),
                  let graphicsComponent = Engine.graphicsComponent(in: manifest)
            else { throw ComponentError.noManifest }

            let total = Double(engineComponent.size + graphicsComponent.size)
            let engineShare = Double(engineComponent.size) / total
            let engineDir = try await ComponentStore.shared.install(engineComponent) { value in
                Task { @MainActor in self.progress = value * engineShare }
            }
            let graphicsDir = try await ComponentStore.shared.install(graphicsComponent) { value in
                Task { @MainActor in self.progress = engineShare + value * (1 - engineShare) }
            }
            progress = nil
            guard let wine = Engine.wineBinary(in: engineDir) else { throw SetupError.engineBroken }
            let matchesEngine = graphicsComponent.version.hasPrefix(engineComponent.version + "-")
            try await Engine.offMain { try Engine.installGraphics(graphicsDir, into: wine, matchesEngine: matchesEngine) }

            step = .environment
            phase = .running(.environment)
            if !FileManager.default.fileExists(atPath: Engine.prefix.appendingPathComponent("drive_c").path) {
                try FileManager.default.createDirectory(at: Engine.prefix, withIntermediateDirectories: true)
                guard try await Engine.run(wine, ["wineboot", "--init"]) == 0 else { throw SetupError.environmentFailed }
            }
            await Engine.offMain {
                Engine.installGameBundle(wine: wine)
                Engine.detachUserFolders()
            }

            if let dxvk = manifest.component(Engine.dxvkID) {
                let dxvkDir = try await ComponentStore.shared.install(dxvk)
                try await Engine.offMain { try Engine.installDXVK(dxvkDir, wine: wine) }
            }
            await Engine.offMain { Engine.applyGameEnvironment(wine: wine) }  // games started from the first Steam need it too

            step = .steam
            phase = .running(.steam)
            if !Engine.isSteamInstalled {
                let installer = try await downloadSteamSetup()
                defer { try? FileManager.default.removeItem(at: installer) }
                _ = try await Engine.run(wine, [installer.path, "/S"])
                guard Engine.isSteamInstalled else { throw SetupError.steamInstallFailed }
            }

            step = .signIn
            if Engine.isSteamSignedIn {
                finish()
            } else {
                try await firstSteamStart(wine)
            }
        } catch {
            progress = nil
            phase = .failed(step, error.localizedDescription)
        }
    }

    /// Opens the password prompt macOS uses for system installs; Rosetta itself comes from Apple.
    func installRosetta() {
        let script = #"do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges"#
        Task {
            let ok = await Task.detached { () -> Bool in
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                return error == nil
            }.value
            if ok {
                phase = .idle
                start()
            } else {
                phase = .needsRosetta
            }
        }
    }

    /// Brings the Steam window back if someone closed it before signing in.
    func reopenSteam() {
        Task {
            guard let wine = await Engine.installedWine() else { return }
            try? Engine.startSteam(wine)
        }
    }

    /// Steam updates itself twice on first start and restarts in between; under Wine the second round
    /// sometimes stalls or the restart doesn't come back. Watch it and restart Steam when that happens.
    private func firstSteamStart(_ wine: URL) async throws {
        // Already up (e.g. setup was restarted while the login window is open): just wait for the sign-in.
        if Engine.isSteamRunning {
            phase = .waitingForSignIn
            watchForSignIn()
            return
        }

        let start = Date()
        var restarts = 0
        var lastRestart = Date()
        phase = .running(.steam)
        try Engine.startSteam(wine)

        while true {
            try await Task.sleep(for: .seconds(2))
            if Engine.isSteamSignedIn {
                progress = nil
                finish()
                return
            }
            // Steam unpacks its browser during the first update and starts it right away – still
            // unwrapped, i.e. black. Wrap it and restart Steam once that happens.
            if Engine.installWebHelperWrapper() {
                await Engine.offMain { Engine.stopAll(wine) }
                try Engine.startSteam(wine)
                lastRestart = Date()
                continue
            }
            if Engine.isSteamWaitingForSignIn(since: start) {
                progress = nil
                phase = .waitingForSignIn
                watchForSignIn()
                return
            }

            let update = Engine.steamUpdateStatus()
            progress = update.fraction
            let stalled = (update.lastChange.map { Date().timeIntervalSince($0) > 90 } ?? false)
                && Date().timeIntervalSince(lastRestart) > 90
            let gone = !Engine.isSteamRunning && Date().timeIntervalSince(lastRestart) > 15

            if stalled || gone {
                restarts += 1
                guard restarts <= 5 else { throw SetupError.steamWontStart }
                if stalled { await Engine.offMain { Engine.stopAll(wine) } }
                try Engine.startSteam(wine)
                lastRestart = Date()
            }
        }
    }

    private func watchForSignIn() {
        signInWatcher?.cancel()
        signInWatcher = Task {
            while !Task.isCancelled {
                if Engine.isSteamSignedIn {
                    finish()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func finish() {
        signInWatcher?.cancel()
        phase = .done
        onFinished?()
        // Steam opens its big main window after sign-in; from now on it only works in the background.
        Task {
            guard let wine = await Engine.installedWine() else { return }
            try? await Engine.restartSteamInBackground(wine)
        }
    }

    private func downloadSteamSetup() async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: Engine.steamSetupURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SetupError.steamDownloadFailed }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("SteamSetup-\(UUID().uuidString).exe")
        try FileManager.default.moveItem(at: temp, to: target)
        return target
    }
}

enum SetupError: LocalizedError {
    case engineBroken, environmentFailed, steamDownloadFailed, steamInstallFailed, steamWontStart

    var errorDescription: String? {
        switch self {
        case .engineBroken: return L10n.t("The game engine is incomplete. Please try again.")
        case .environmentFailed: return L10n.t("The Windows environment could not be created.")
        case .steamDownloadFailed: return L10n.t("Steam could not be downloaded. Check your internet connection.")
        case .steamInstallFailed: return L10n.t("Steam could not be installed.")
        case .steamWontStart: return L10n.t("Steam keeps stopping during its first start. Please try again.")
        }
    }
}
