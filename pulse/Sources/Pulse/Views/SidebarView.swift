import PulseKit
import SwiftUI

/// Navigation destinations. Only `.dashboard` is built in v0.2; the rest
/// render dimmed with a "soon" tag — no dead UI pretending to work.
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case storage = "Storage"
    case timeline = "Timeline"
    case clean = "Clean"
    case monitor = "Monitor"
    case health = "Health"
    case vault = "Vault"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: "circle.circle"
        case .storage: "internaldrive"
        case .timeline: "chart.xyaxis.line"
        case .clean: "sparkles"
        case .monitor: "waveform.path.ecg"
        case .health: "heart"
        case .vault: "shield"
        case .diagnostics: "stethoscope"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .dashboard, .storage, .timeline, .clean, .monitor, .health, .vault, .diagnostics: true
        }
    }
}

struct SidebarView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(StorageModel.self) private var storage
    @Binding var selection: SidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logo
                .padding(.bottom, 24)

            ForEach(SidebarItem.allCases) { item in
                row(item)
            }

            Spacer()
            footer
        }
        .padding(16)
        .frame(width: 216)
        .background(Halo.void)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Halo.surface2).frame(width: 1)
        }
    }

    private var logo: some View {
        HStack(spacing: 10) {
            if let image = Bundle.module.image(forResource: "Logo") ?? NSImage(named: "Logo") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            LinearGradient(
                                colors: [Halo.ion.opacity(0.9), Halo.volt],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Halo.void)
                }
            }
            Text("PULSE")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(Halo.textPrimary)
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Button {
            if item.isAvailable { selection = item }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(item.rawValue)
                    .font(.system(size: 13, weight: selection == item ? .semibold : .regular))
                Spacer()
                badge(item)
            }
            .foregroundStyle(rowColor(item))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                selection == item ? Halo.surface2 : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(alignment: .leading) {
                if selection == item {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Halo.ion)
                        .frame(width: 2, height: 18)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badge(_ item: SidebarItem) -> some View {
        if item == .storage, let snapshot = model.snapshot {
            Text("\(Int(snapshot.diskUsedFraction * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.statusColor(snapshot.diskUsedFraction))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Halo.surface2, in: Capsule())
        } else if item == .vault, !storage.vaultSessions.isEmpty {
            Text("\(storage.vaultSessions.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.volt)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Halo.surface2, in: Capsule())
        } else if !item.isAvailable {
            Text("soon")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Halo.textDim.opacity(0.7))
        }
    }

    private func rowColor(_ item: SidebarItem) -> Color {
        if selection == item { return Halo.textPrimary }
        return item.isAvailable ? Halo.textPrimary.opacity(0.8) : Halo.textDim.opacity(0.6)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
            Text("\(SystemInfo.chipName) · up \(uptimeText)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
    }

    private var statusColor: Color {
        if model.alerts.contains(where: { $0.severity == .critical }) { return Halo.flare }
        if model.alerts.contains(where: { $0.severity == .warning }) { return Halo.amber }
        return Halo.pulseGreen
    }

    private var statusText: String {
        if model.alerts.contains(where: { $0.severity == .critical }) { return "ATTENTION NEEDED" }
        if model.alerts.contains(where: { $0.severity == .warning }) { return "MINOR ISSUES" }
        return "ALL SYSTEMS NOMINAL"
    }

    private var uptimeText: String {
        let hours = Int(model.snapshot?.uptime ?? 0) / 3600
        return hours >= 24 ? "\(hours / 24)d \(hours % 24)h" : "\(hours)h"
    }
}
