import PulseKit
import SwiftUI

/// "Needs Attention — Cause → Fix" card stack. Every alert names the cause
/// and ends in an action; the empty state says so explicitly.
struct AlertsSection: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Halo.Space.md) {
            header
            if model.alerts.isEmpty {
                allClear
            } else {
                ForEach(model.alerts) { alert in
                    AlertCard(alert: alert)
                }
            }
            if let feedback = model.actionFeedback {
                Text(feedback)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.ion)
            }
        }
        .premiumCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                Text("NEEDS ATTENTION")
                    .sectionLabel()
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .help("System alerts that require your attention to fix performance or safety issues")
            }
            .foregroundStyle(Halo.textDim)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(Halo.pulseGreen)
                    .frame(width: 6, height: 6)
                    .shadow(color: Halo.pulseGreen.opacity(0.5), radius: 4)
                Text("LIVE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.pulseGreen)
            }
        }
    }

    private var allClear: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Halo.pulseGreen.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Halo.pulseGreen)
            }
            Text("All systems nominal — nothing needs attention")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Halo.textSecondary)
        }
        .padding(.vertical, Halo.Space.sm)
    }
}

private struct AlertCard: View {
    @Environment(DashboardModel.self) private var model
    let alert: PulseAlert

    @State private var expandedDetails: String?
    @State private var confirmQuit: (pid: Int32, name: String)?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Halo.Space.sm) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(severityColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: alert.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(severityColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                    Text(alert.subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                }
                Spacer(minLength: 12)
                actions
                Button {
                    model.dismissAlert(id: alert.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Halo.textDim)
                        .frame(width: 22, height: 22)
                        .background(Halo.surface2.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss — hides until this condition clears and recurs")
            }
            if let details = expandedDetails {
                Text(details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .padding(Halo.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Halo.void, in: RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous))
            }
        }
        .padding(Halo.Space.md)
        .background {
            RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous)
                .fill(isHovered ? Halo.surface2.opacity(0.7) : Halo.surface2.opacity(0.4))
        }
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: Halo.Radius.medium,
                bottomLeadingRadius: Halo.Radius.medium,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(severityColor)
            .frame(width: 3)
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .confirmationDialog(
            "Quit \(confirmQuit?.name ?? "")?",
            isPresented: Binding(
                get: { confirmQuit != nil },
                set: { if !$0 { confirmQuit = nil } }
            )
        ) {
            Button("Quit \(confirmQuit?.name ?? "")", role: .destructive) {
                if let target = confirmQuit {
                    model.quitProcess(pid: target.pid, name: target.name)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends a normal Quit signal. Unsaved work in that app may be lost.")
        }
    }

    private var actions: some View {
        HStack(spacing: Halo.Space.sm) {
            ForEach(Array(alert.actions.enumerated()), id: \.offset) { _, action in
                switch action {
                case .quitProcess(let pid, let name):
                    Button("Quit \(name)") {
                        confirmQuit = (pid, name)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Halo.ion.opacity(0.85))
                    .controlSize(.small)
                case .showDetails(let text):
                    Button(expandedDetails == nil ? "Details" : "Hide") {
                        withAnimation(Halo.Motion.snappy) {
                            expandedDetails = expandedDetails == nil ? text : nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Halo.textDim)
                }
            }
        }
    }

    private var severityColor: Color {
        switch alert.severity {
        case .info: Halo.ion
        case .warning: Halo.amber
        case .critical: Halo.flare
        }
    }
}
