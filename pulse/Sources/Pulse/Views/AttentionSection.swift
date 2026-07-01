import PulseKit
import SwiftUI

/// Guided-focus hero: up to 3 ranked "here's the one thing worth doing"
/// cards below the health ring. Complements — doesn't replace — the
/// "Needs Attention" cause→fix list further down the Dashboard.
struct AttentionSection: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        Group {
            if model.attentionItems.isEmpty {
                allGood
            } else {
                VStack(spacing: Halo.Space.sm) {
                    ForEach(model.attentionItems) { item in
                        AttentionCard(item: item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allGood: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Halo.pulseGreen)
            Text("All good — nothing worth a look right now")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Halo.textPrimary.opacity(0.85))
            Spacer()
        }
        .padding(14)
        .background(Halo.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AttentionCard: View {
    @Environment(DashboardModel.self) private var model
    @Environment(CleanModel.self) private var clean
    let item: AttentionItem

    @State private var confirmQuit: (pid: Int32, name: String)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                    .fill(severityColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(severityColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(item.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer(minLength: 12)
            actionButton
            snoozeMenu
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var actionButton: some View {
        switch item.action {
        case .quitProcess(let pid, let name):
            Button("Quit") { confirmQuit = (pid, name) }
                .buttonStyle(.borderedProminent)
                .tint(Halo.ion.opacity(0.85))
                .controlSize(.small)
        case .cleanJunk:
            Button("Clean") { clean.runNow() }
                .buttonStyle(.borderedProminent)
                .tint(Halo.amber.opacity(0.85))
                .controlSize(.small)
        case .openPane(let target):
            Button("Review") { navigate(to: target) }
                .buttonStyle(.bordered)
                .tint(Halo.textDim)
                .controlSize(.small)
        case nil:
            EmptyView()
        }
    }

    private var snoozeMenu: some View {
        Menu {
            Button("Snooze \(defaultSnoozeLabel)") {
                model.snoozeAttentionItem(
                    item.id, until: Date.now.addingTimeInterval(AttentionPreferences.defaultSnoozeDuration))
            }
            Button("Snooze until dismissed") {
                model.snoozeAttentionItem(item.id, until: .distantFuture)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Halo.textDim)
                .frame(width: 22, height: 22)
                .background(Halo.surface2, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .help("Snooze — hides until it recurs or the snooze expires")
        .accessibilityLabel("Snooze options")
    }

    private var defaultSnoozeLabel: String {
        let hours = Int(AttentionPreferences.defaultSnoozeDuration / 3600)
        return hours >= 24 ? "\(hours / 24)d" : "\(hours)h"
    }

    private func navigate(to target: AttentionTarget) {
        switch target {
        case .monitor:
            NotificationCenter.default.post(name: DashboardView.navigateToMonitor, object: nil)
        case .storage:
            NotificationCenter.default.post(name: .navigateToOptimize, object: nil)
        }
    }

    private var symbol: String {
        switch item.action {
        case .quitProcess: return "bolt.slash.fill"
        case .cleanJunk: return "trash.fill"
        case .openPane: return "arrow.right.circle.fill"
        case nil: return "info.circle.fill"
        }
    }

    private var severityColor: Color {
        switch item.severity {
        case .info: Halo.ion
        case .warn: Halo.amber
        case .critical: Halo.flare
        }
    }
}
