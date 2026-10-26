import SwiftUI

/// How a game ran for the player, from the "Welcome back" sheet. Kept on this Mac only; it beats
/// the profile list in the compatibility rating – your own experience counts most.
struct GameRating: Codable, Equatable {
    enum Issue: String, Codable, CaseIterable {
        case stutters, crashed, lowFrameRate, glitches, controller, sound

        var label: String {
            switch self {
            case .stutters: return L10n.t("Stutters")
            case .crashed: return L10n.t("Crashed")
            case .lowFrameRate: return L10n.t("Low frame rate")
            case .glitches: return L10n.t("Graphics glitches")
            case .controller: return L10n.t("Controller")
            case .sound: return L10n.t("Sound")
            }
        }
    }

    var good: Bool
    var issues: [Issue] = []
    var date = Date()
}

enum GameRatings {
    private static func key(_ appID: Int) -> String { "rating.\(appID)" }

    static func load(_ appID: Int, from defaults: UserDefaults = .standard) -> GameRating? {
        defaults.data(forKey: key(appID)).flatMap { try? JSONDecoder().decode(GameRating.self, from: $0) }
    }

    static func save(_ rating: GameRating, for appID: Int, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(rating) { defaults.set(data, forKey: key(appID)) }
    }
}

/// A game Nightforge started has ended after a real session: how long, and how it ran.
struct SessionSummary: Identifiable {
    let game: Game
    let minutes: Int
    /// Play time Steam had counted before this session.
    let totalBefore: Int
    /// When the game's processes were gone: Steam's cloud record has to be newer than that.
    var endedAt = Date()
    var id: String { game.id }
}

struct SessionSummarySheet: View {
    let summary: SessionSummary
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Bool?
    @State private var issues: Set<GameRating.Issue> = []
    @State private var saved = false
    @State private var cloud: CloudSaves.State?
    /// Steam took longer than a minute to confirm the upload: say it carries on by itself.
    @State private var cloudTookLong = false

    /// Steam may already have added this session when the library was read again.
    private var total: Int {
        let now = model.allGames.first { $0.id == summary.game.id }?.playtimeMinutes ?? 0
        return max(now, summary.totalBefore + summary.minutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("Welcome back"))
                .font(Theme.display(22))
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.game.name)
                    .font(.headline)
                Text(L10n.t("%@ this time · %@ in total", Format.playtime(summary.minutes), Format.playtime(total)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let cloud {
                saveLine(cloud)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("How did it run?"))
                    .font(.subheadline.weight(.semibold))
                if saved {
                    Label(L10n.t("Thanks – noted on this Mac. It shapes how Nightforge rates the game for you."),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.runsGreat)
                        .fixedSize(horizontal: false, vertical: true)
                } else if rating == false {
                    issueButtons
                    Button(L10n.t("Save")) { save(good: false) }
                        .padFocus("session.saveIssues", activate: { save(good: false) })
                } else {
                    HStack(spacing: 10) {
                        Button { save(good: true) } label: {
                            Label(L10n.t("Well"), systemImage: "hand.thumbsup").frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .padFocus("session.good", activate: { save(good: true) })
                        Button { rating = false } label: {
                            Label(L10n.t("Not well"), systemImage: "hand.thumbsdown").frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .padFocus("session.bad", activate: { rating = false })
                    }
                }
            }

            HStack {
                Button { playAgain() } label: { Label(L10n.t("Play Again"), systemImage: "play.fill") }
                    .padFocus("session.again", activate: playAgain)
                Spacer()
                Button(L10n.t("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .padFocus("session.done", activate: { dismiss() })
            }
        }
        .padding(24)
        .frame(width: 480)
        .task { await followCloud() }
    }

    @ViewBuilder private func saveLine(_ state: CloudSaves.State) -> some View {
        switch state {
        case .synced:
            Label(L10n.t("Your save is in the Steam Cloud. You can close your Mac."), systemImage: "checkmark.icloud")
                .foregroundStyle(Theme.runsGreat)
        case .syncing where cloudTookLong:
            Label(L10n.t("Steam syncs your save in the background."), systemImage: "icloud")
                .foregroundStyle(.secondary)
        case .syncing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Steam is syncing your save with the Steam Cloud …")).foregroundStyle(.secondary)
            }
        case .noCloud:
            Label(L10n.t("No Steam Cloud for this game – its saves are on this Mac."), systemImage: "internaldrive")
                .foregroundStyle(.secondary)
        }
    }

    /// Asks Steam's cloud record every two seconds for a minute, until it confirms.
    private func followCloud() async {
        for _ in 0..<30 {
            let game = summary.game, ended = summary.endedAt
            let state = await Task.detached(priority: .utility) {
                CloudSaves.state(appID: game.appID, steamRoot: game.steamRoot, endedAt: ended)
            }.value
            cloud = state
            if state != .syncing { return }
            try? await Task.sleep(for: .seconds(2))
        }
        cloudTookLong = true
    }

    private var issueButtons: some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(GameRating.Issue.allCases, id: \.self) { issue in
                let on = issues.contains(issue)
                FilterToggle(title: issue.label, symbol: on ? "checkmark" : "circle", on: on, id: "session.issue.\(issue.rawValue)") {
                    if on { issues.remove(issue) } else { issues.insert(issue) }
                }
            }
        }
    }

    private func save(good: Bool) {
        GameRatings.save(GameRating(good: good, issues: good ? [] : GameRating.Issue.allCases.filter(issues.contains)), for: summary.game.appID)
        rating = good
        saved = true
    }

    private func playAgain() {
        dismiss()
        model.play(summary.game)
    }
}
