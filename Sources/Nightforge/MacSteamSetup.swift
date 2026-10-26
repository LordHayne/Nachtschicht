import AppKit
import SwiftUI

/// Sets up Steam for Mac the first time a game's Mac version is wanted: one button, Valve's
/// installer, then the player signs in in Steam's own window. Afterwards Nightforge carries on
/// with what the player pressed (`next`).
@MainActor
final class MacSteamSetup: ObservableObject, Identifiable {
    enum Next { case download, play }

    enum Phase: Equatable {
        case intro
        case installing
        case signingIn
        case failed(String)
    }

    let id = UUID()
    let game: Game
    let next: Next
    @Published private(set) var phase = Phase.intro
    /// Steam's self-update on its first start, while it has one.
    @Published private(set) var progress: Double?

    /// Called once Steam for Mac is signed in.
    var onReady: ((MacSteamSetup) -> Void)?
    private var task: Task<Void, Never>?

    init(game: Game, next: Next) {
        self.game = game
        self.next = next
    }

    func start() {
        switch phase {
        case .intro, .failed: task = Task { await run() }
        case .installing, .signingIn: break
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func run() async {
        do {
            phase = .installing
            try await MacSteam.install()
            // Asked for before Steam's first start, the download begins right after the sign-in.
            if game.install == .notInstalled {
                try? Engine.requestDownload(appID: game.appID, name: game.name, installDir: game.installDirName,
                                            steamapps: MacSteam.steamapps)
            }
            phase = .signingIn
            let started = Date()
            MacSteam.start(visible: true)
            while !Task.isCancelled {
                if MacSteam.signedIn || signedInSince(started) { break }
                let update = Engine.steamUpdateStatus(steamRoot: MacSteam.root)
                progress = (update.lastChange ?? .distantPast) >= started ? update.fraction : nil
                try await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled else { return }
            progress = nil
            // Steam opens its library after the sign-in; from now on it works in the background.
            NSApp.activate()
            onReady?(self)
            MacSteam.hide()
        } catch is CancellationError {
            return
        } catch {
            progress = nil
            phase = .failed(error.localizedDescription)
        }
    }

    /// Steam writes its list of accounts when someone signs in.
    private func signedInSince(_ start: Date) -> Bool {
        let users = MacSteam.root.appendingPathComponent("config/loginusers.vdf")
        let modified = (try? users.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return MacSteam.hasSignedIn && (modified ?? .distantPast) >= start
    }
}

struct MacSteamSetupView: View {
    @ObservedObject var setup: MacSteamSetup
    /// Plays (or downloads) the Windows version instead, for good.
    let useWindows: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("Steam for Mac"))
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink)
                Text(L10n.t("%@ has a Mac version. It runs without any Windows translation, so it usually looks and runs better. To get it, Nightforge sets up Valve's Steam for Mac – once, in a few minutes.", setup.game.name))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if setup.phase != .intro {
                VStack(alignment: .leading, spacing: 14) {
                    StepRow(title: L10n.t("Downloading Steam for Mac"),
                            state: setup.phase == .installing ? .active : isFailed ? .failed : .done, progress: nil)
                    StepRow(title: L10n.t("Signing in to Steam"),
                            state: setup.phase == .signingIn ? .waiting : .pending, progress: setup.progress)
                }
            }

            switch setup.phase {
            case .intro:
                Note(L10n.t("You sign in in Steam's own window – Nightforge never sees your login. By installing you accept Valve's Steam Subscriber Agreement."))
            case .installing:
                EmptyView()
            case .signingIn:
                Note(L10n.t("Steam updates itself first, then asks you to sign in – with the QR code from the Steam app on your phone or with your password. Nightforge never sees your login."))
            case .failed(let message):
                Note(message, isError: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                switch setup.phase {
                case .intro:
                    SetupButton(title: L10n.t("Set Up Steam for Mac"), symbol: "arrow.down.circle") { setup.start() }
                case .failed:
                    SetupButton(title: L10n.t("Try again"), symbol: "arrow.clockwise") { setup.start() }
                case .signingIn:
                    Button(L10n.t("Show Steam window again")) { MacSteam.show(keepFor: 600) }
                        .buttonStyle(.bordered)
                case .installing:
                    EmptyView()
                }
                HStack(spacing: 12) {
                    if let useWindows, setup.phase == .intro || isFailed {
                        Button(L10n.t("Use the Windows Version"), action: useWindows)
                            .buttonStyle(.bordered)
                    }
                    Button(L10n.t("Cancel"), action: close)
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 560)
        .background(Theme.night)
        .animation(.easeOut(duration: 0.25), value: setup.phase)
    }

    private var isFailed: Bool {
        if case .failed = setup.phase { return true }
        return false
    }
}
