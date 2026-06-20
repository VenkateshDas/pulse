import PulseKit
import SwiftUI

/// "Needs Attention — Cause → Fix" card stack. Every alert names the cause
/// and ends in an action; the empty state says so explicitly.
struct AlertsSection: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: Halo.Radius.large)
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
                Circle().fill(Halo.pulseGreen).frame(width: 5, height: 5)
                    .shadow(color: Halo.pulseGreen.opacity(0.5), radius: 4)
                Text("LIVE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.pulseGreen)
            }
        }
    }

    private var allClear: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Halo.pulseGreen)
            Text("All systems nominal — nothing needs attention")
                .font(.system(size: 12))
                .foregroundStyle(Halo.textPrimary.opacity(0.85))
        }
        .padding(.vertical, 10)
    }
}

private struct AlertCard: View {
    @Environment(DashboardModel.self) private var model
    let alert: PulseAlert

    @State private var expandedDetails: String?
    @State private var confirmQuit: (pid: Int32, name: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                        .fill(severityColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: alert.symbol)
                        .font(.system(size: 13))
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Halo.textDim)
                        .frame(width: 22, height: 22)
                        .background(Halo.surface2, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss — hides until this condition clears and recurs")
            }
            if let details = expandedDetails {
                Text(details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Halo.void, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Halo.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(severityColor)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
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
        HStack(spacing: 8) {
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
                        withAnimation(.spring(duration: 0.25)) {
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
