import IOKit.pwr_mgt
import SwiftUI

/// Keeps the Mac awake while games download: an idle Mac would otherwise sleep and stop Steam.
/// The display may still turn off; only system sleep waits.
@MainActor
enum KeepAwake {
    private static var assertion: IOPMAssertionID = 0
    private static var holding = false

    static func update(downloading names: [String]) {
        if names.isEmpty {
            guard holding else { return }
            IOPMAssertionRelease(assertion)
            holding = false
        } else if !holding {
            let reason = L10n.t("Nightforge is downloading %@", names.joined(separator: ", ")) as CFString
            holding = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                  IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess
        }
    }
}

/// The top bar's download ring: how far the downloads have got and how many there are (D).
struct DownloadsButton: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        let downloads = model.downloads
        Button { model.showingDownloads.toggle() } label: {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.03, Self.progress(downloads)))
                    .stroke(Theme.sodium, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(downloads.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(GlassGroupButtonStyle())
        .help(downloads.count == 1 ? L10n.t("1 download (D)") : L10n.t("%ld downloads (D)", downloads.count))
        .accessibilityLabel(downloads.count == 1 ? L10n.t("1 download") : L10n.t("%ld downloads", downloads.count))
        .padFocus("top.downloads", cornerRadius: 15, activate: { model.showingDownloads.toggle() })
        .popover(isPresented: $model.showingDownloads, arrowEdge: .bottom) {
            DownloadsPanel()
                .environmentObject(model)
        }
    }

    static func progress(_ downloads: [Game]) -> Double {
        let fractions = downloads.map { game -> Double in
            if case .downloading(let fraction) = game.install { return fraction ?? 0 }
            return 0
        }
        return fractions.isEmpty ? 0 : fractions.reduce(0, +) / Double(fractions.count)
    }
}

/// What's downloading, how far, and a way to stop each one.
struct DownloadsPanel: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("Downloads"))
                .font(.headline)
            if model.downloads.isEmpty {
                Text(L10n.t("Nothing is downloading."))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.downloads) { game in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(game.name).lineLimit(1)
                        Spacer()
                        Text(status(game))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        if case .downloading(let fraction?) = game.install {
                            ProgressView(value: fraction).tint(Theme.sodium)
                        } else {
                            ProgressView().progressViewStyle(.linear).tint(Theme.sodium)
                        }
                        if model.canUninstall(game) {
                            Button(L10n.t("Cancel")) { model.requestUninstall(game) }
                                .controlSize(.small)
                                .padFocus("downloads.cancel.\(game.id)", activate: { model.requestUninstall(game) })
                        }
                    }
                }
            }
            if !model.downloads.isEmpty {
                Label(L10n.t("Your Mac stays awake while games download. The display can still turn off."),
                      systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func status(_ game: Game) -> String {
        if game.downloadNeedsSpace != nil { return L10n.t("Paused – not enough space") }
        if case .downloading(let fraction?) = game.install {
            return game.sizeOnDisk > 0
                ? L10n.t("%ld %% of %@", Int(fraction * 100), Format.bytes(game.sizeOnDisk))
                : "\(Int(fraction * 100)) %"
        }
        return L10n.t("Preparing …")
    }
}
