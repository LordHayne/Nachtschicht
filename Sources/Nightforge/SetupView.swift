import SwiftUI

/// First-run screen: one button, then a short checklist that fills itself in.
struct SetupView: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 14) {
                Text(setup.phase == .idle ? L10n.t("Welcome to Nightforge") : L10n.t("Connecting Steam"))
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.ink)
                Text(L10n.t("Nightforge sets up everything your Windows games need – free, in the background, in a few minutes. You only sign in to Steam."))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if setup.phase != .idle {
                StepList(setup: setup)
            }

            actions
        }
        .animation(.easeOut(duration: 0.25), value: setup.phase)
    }

    @ViewBuilder private var actions: some View {
        switch setup.phase {
        case .idle:
            SetupButton(title: L10n.t("Connect Steam"), symbol: "link") { setup.start() }

        case .running:
            EmptyView()

        case .needsRosetta:
            Note(L10n.t("Windows games need Rosetta from Apple. macOS asks for your password once to install it; by installing you accept Apple's Rosetta license."))
            SetupButton(title: L10n.t("Install Rosetta"), symbol: "arrow.down.circle") { setup.installRosetta() }

        case .waitingForSignIn:
            Note(L10n.t("Sign in in the Steam window – with the QR code from the Steam app on your phone or with your password. Nightforge never sees your login."))
            Button(L10n.t("Show Steam window again")) { setup.reopenSteam() }
                .buttonStyle(.bordered)
                .controlSize(.large)

        case .failed(_, let message):
            Note(message, isError: true)
            SetupButton(title: L10n.t("Try again"), symbol: "arrow.clockwise") { setup.start() }

        case .done:
            EmptyView()
        }
    }
}

private struct StepList: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(SetupModel.Step.allCases) { step in
                StepRow(
                    title: step.title,
                    state: state(of: step),
                    progress: setup.currentStep() == step ? setup.progress : nil
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func state(of step: SetupModel.Step) -> StepRow.State {
        if setup.isFinished(step) { return .done }
        guard setup.currentStep() == step else { return .pending }
        switch setup.phase {
        case .failed: return .failed
        case .needsRosetta, .waitingForSignIn: return .waiting
        default: return .active
        }
    }
}

private struct StepRow: View {
    enum State { case pending, active, waiting, done, failed }

    let title: String
    let state: State
    let progress: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                switch state {
                case .pending:
                    Circle().strokeBorder(Theme.muted.opacity(0.5), lineWidth: 1.5)
                case .active:
                    ProgressView().controlSize(.small)
                case .waiting:
                    Image(systemName: "hand.point.right.fill").foregroundStyle(Theme.sodium)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sodium)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: state == .pending ? .regular : .semibold))
                    .foregroundStyle(state == .pending ? Theme.muted : Theme.ink)
                if let progress {
                    ProgressView(value: progress)
                        .tint(Theme.sodium)
                        .frame(width: 320)
                    Text("\(Int(progress * 100)) %")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

private struct Note: View {
    let text: String
    var isError = false

    init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(isError ? Color(red: 1, green: 0.62, blue: 0.58) : Theme.ink.opacity(0.85))
            .frame(maxWidth: 560, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SetupButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                Text(title).font(Theme.display(17))
            }
            .foregroundStyle(Theme.night)
            .padding(.horizontal, 32)
            .frame(height: 52)
            .background(Capsule().fill(Theme.sodium))
            .shadow(color: Theme.sodium.opacity(hovering ? 0.55 : 0.3), radius: hovering ? 24 : 14)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .keyboardShortcut(.defaultAction)
    }
}
