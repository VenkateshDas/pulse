import PulseKit
import SwiftUI

/// Navigation destinations. Only `.dashboard` is built in v0.2; the rest
/// render dimmed with a "soon" tag — no dead UI pretending to work.
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case storage = "Storage"
    case timeline = "Timeline"
    case uninstall = "Uninstall"
    case monitor = "Monitor"
    case health = "Health"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .storage: "internaldrive.fill"
        case .timeline: "chart.xyaxis.line"
        case .uninstall: "trash.slash.fill"
        case .monitor: "waveform.path.ecg"
        case .health: "heart.fill"
        case .diagnostics: "stethoscope"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .dashboard, .storage, .timeline, .uninstall, .monitor, .health,
            .diagnostics:
            true
        }
    }

    var section: SidebarSection {
        switch self {
        case .dashboard: .overview
        case .storage, .timeline: .insights
        case .monitor, .health, .diagnostics: .system
        case .uninstall: .tools
        }
    }
}

enum SidebarSection: String, CaseIterable {
    case overview = "OVERVIEW"
    case insights = "INSIGHTS"
    case system = "SYSTEM"
    case tools = "TOOLS"

    var items: [SidebarItem] {
        SidebarItem.allCases.filter { $0.section == self }
    }
}

struct SidebarView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(StorageModel.self) private var storage
    @Binding var selection: SidebarItem
    @State private var hoveredItem: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logo
                .padding(.bottom, Halo.Space.xxl)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Halo.Space.xl) {
                    ForEach(SidebarSection.allCases, id: \.self) { section in
                        sectionGroup(section)
                    }
                }
            }

            Spacer(minLength: Halo.Space.lg)
            footer
        }
        .padding(.horizontal, Halo.Space.lg)
        .padding(.vertical, Halo.Space.xl)
        .frame(width: 220)
        .background {
            ZStack {
                Halo.void
                Halo.meshBackground
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Halo.borderSubtle).frame(width: 1)
        }
    }

    private var logo: some View {
        HStack(spacing: 10) {
            if let image = Bundle.module.image(forResource: "Logo") ?? NSImage(named: "Logo") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Halo.interactive, Halo.volt],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(color: Halo.interactive.opacity(0.3), radius: 8, y: 2)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("PULSE")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Halo.textPrimary)
                Text("Command Center")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Halo.textDim)
            }
        }
    }

    private func sectionGroup(_ section: SidebarSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim.opacity(0.7))
                .padding(.leading, 8)
                .padding(.bottom, Halo.Space.xs)

            ForEach(section.items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Button {
            if item.isAvailable {
                withAnimation(Halo.Motion.snappy) {
                    selection = item
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        selection == item
                            ? Halo.interactive
                            : (hoveredItem == item ? Halo.textPrimary : Halo.textDim)
                    )
                    .frame(width: 20)

                Text(item.rawValue)
                    .font(.system(size: 13, weight: selection == item ? .semibold : .regular))
                    .foregroundStyle(rowColor(item))

                Spacer(minLength: 0)
                badge(item)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if selection == item {
                    RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                        .fill(Halo.interactive.opacity(0.10))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Halo.interactive)
                                .frame(width: 3, height: 16)
                                .padding(.leading, -1)
                        }
                } else if hoveredItem == item {
                    RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                        .fill(Halo.surface2.opacity(0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredItem = hovering ? item : nil
            }
        }
    }

    @ViewBuilder
    private func badge(_ item: SidebarItem) -> some View {
        if item == .storage, let snapshot = model.snapshot {
            let fraction = snapshot.diskUsedFraction
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.statusColor(fraction))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Halo.statusColor(fraction).opacity(0.12),
                    in: Capsule()
                )
        } else if !item.isAvailable {
            Text("soon")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Halo.textDim.opacity(0.5))
        }
    }

    private func rowColor(_ item: SidebarItem) -> Color {
        if selection == item { return Halo.textPrimary }
        if hoveredItem == item { return Halo.textPrimary.opacity(0.9) }
        return item.isAvailable ? Halo.textSecondary : Halo.textDim.opacity(0.5)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Halo.Space.sm) {
            Divider().overlay(Halo.borderSubtle)
                .padding(.bottom, Halo.Space.xs)

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(statusColor)
                    Text("\(SystemInfo.chipName) · up \(uptimeText)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                }
            }
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
