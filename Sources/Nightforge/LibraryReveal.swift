import SwiftUI

/// After the first start (and from Settings › About): how many of your games run on this Mac,
/// in one bar, with what each part means.
struct LibraryReveal: Identifiable, Equatable {
    var great = 0, tweaks = 0, untested = 0, no = 0
    /// Of the games that don't run, the ones GeForce Now streams, and the VR-only ones.
    var cloud = 0
    var vr = 0
    let id = UUID()

    var total: Int { great + tweaks + untested + no }
    /// "Run here": rated great or with tweaks.
    var running: Int { great + tweaks }

    init(great: Int = 0, tweaks: Int = 0, untested: Int = 0, no: Int = 0, cloud: Int = 0, vr: Int = 0) {
        (self.great, self.tweaks, self.untested, self.no, self.cloud, self.vr) = (great, tweaks, untested, no, cloud, vr)
    }

    /// The owned games' levels (store hits aren't yours).
    init(_ rated: [(game: Game, level: Compatibility.Level)]) {
        for (game, level) in rated where game.install != .inStore {
            switch level {
            case .great: great += 1
            case .tweaks: tweaks += 1
            case .untested: untested += 1
            case .no:
                no += 1
                if game.isVROnly { vr += 1 } else if game.playsInCloud { cloud += 1 }
            }
        }
    }

    static func == (a: LibraryReveal, b: LibraryReveal) -> Bool {
        (a.great, a.tweaks, a.untested, a.no, a.cloud, a.vr) == (b.great, b.tweaks, b.untested, b.no, b.cloud, b.vr)
    }
}

struct LibraryRevealSheet: View {
    let reveal: LibraryReveal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("Your library on this Mac"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(reveal.total == 1 ? L10n.t("%ld of your 1 game runs here", reveal.running)
                 : L10n.t("%ld of your %ld games run here", reveal.running, reveal.total))
                .font(Theme.display(28))
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.level) { part in
                        Rectangle().fill(part.level.color)
                            .frame(width: max(0, geo.size.width * CGFloat(part.count) / CGFloat(max(reveal.total, 1)) - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                row(.great, reveal.great, L10n.t("Tested by Nightforge, a Mac version, or it started fine here."))
                if reveal.tweaks > 0 {
                    row(.tweaks, reveal.tweaks, L10n.t("Nightforge applies what they need by itself, at every start."))
                }
                if reveal.untested > 0 {
                    row(.untested, reveal.untested, L10n.t("Nobody has tried them on a Mac with Nightforge yet – most still run. The first start tells, and Nightforge remembers what works."))
                }
                if reveal.no > 0 {
                    row(.no, reveal.no, notRunning)
                }
            }

            HStack {
                Spacer()
                Button(L10n.t("Let's Play")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .padFocus("reveal.play", activate: { dismiss() })
            }
        }
        .padding(26)
        .frame(width: 520)
    }

    /// Why: anti-cheat (some on GeForce Now instead) and VR headsets.
    private var notRunning: String {
        var reasons: [String] = []
        if reveal.no > reveal.vr {
            reasons.append(reveal.cloud > 0
                ? L10n.t("Their anti-cheat needs Windows itself – %ld of them play on GeForce Now instead.", reveal.cloud)
                : L10n.t("Their anti-cheat needs Windows itself."))
        }
        if reveal.vr > 0 {
            reasons.append(reveal.vr == 1 ? L10n.t("1 needs a VR headset.") : L10n.t("%ld need a VR headset.", reveal.vr))
        }
        return reasons.joined(separator: " ")
    }

    private var parts: [(level: Compatibility.Level, count: Int)] {
        [(.great, reveal.great), (.tweaks, reveal.tweaks), (.untested, reveal.untested), (.no, reveal.no)].filter { $0.count > 0 }
    }

    private func row(_ level: Compatibility.Level, _ count: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: level.symbol).foregroundStyle(level.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) · \(level.label)").fontWeight(.semibold)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
