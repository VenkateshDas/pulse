import PulseKit
import SwiftUI

/// Navigation destinations. Only `.dashboard` is built in v0.2; the rest
/// render dimmed with a "soon" tag — no dead UI pretending to work.
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case storage = "Storage"
    case timeline = "Timeline"
    case optimize = "Optimize"
    case uninstall = "Uninstall"
    case monitor = "Monitor"
    case displays = "Displays"
    case health = "Health"
    case settings = "Settings"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: "heart.fill"
        case .storage: "internaldrive.fill"
        case .timeline: "chart.xyaxis.line"
        case .optimize: "sparkles"
        case .uninstall: "trash.slash.fill"
        case .monitor: "waveform.path.ecg"
        case .displays: "display"
        case .health: "stethoscope"
        case .settings: "gearshape.fill"
        case .diagnostics: "wrench.and.screwdriver.fill"
        }
    }

    var isAvailable: Bool { true }
}

enum SidebarSection: String, CaseIterable {
    case overview = "OVERVIEW"
    case insights = "INSIGHTS"
    case system = "SYSTEM"
    case tools = "TOOLS"

    var items: [SidebarItem] {
        switch self {
        case .overview: [.dashboard]
        case .insights: [.storage, .timeline]
        case .system: [.monitor, .displays, .health]
        case .tools: [.optimize, .uninstall, .settings, .diagnostics]
        }
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

            ForEach(SidebarSection.allCases, id: \.self) { section in
                Text(section.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.textDim.opacity(0.6))
                    .padding(.leading, 10)
                    .padding(.top, section == .overview ? 0 : Halo.Space.lg)
                    .padding(.bottom, Halo.Space.xs)
                ForEach(section.items) { item in
                    row(item)
                }
            }

            Spacer()
            Divider().overlay(Halo.borderSubtle).padding(.bottom, Halo.Space.sm)
            footer
        }
        .padding(Halo.Space.lg)
        .frame(width: 216)
        .background { GlassLayer(material: .ultraThinMaterial, tint: Halo.void.opacity(0.7)) }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Halo.borderSubtle).frame(width: 1)
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let image = Bundle.module.image(forResource: "Logo") ?? NSImage(named: "Logo") {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 160, height: 56, alignment: .center)
                .clipped()
                .padding(.leading, -8) // slight shift to align the dot nicely with the layout
        } else {
            // Fallback if logo not found
            Text("PULSE")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .tracking(3)
                .foregroundStyle(Halo.textPrimary)
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        let isSelected = selection == item
        let isHover = hoveredItem == item && !isSelected
        return Button {
            if item.isAvailable {
                withAnimation(Halo.Motion.snappy) { selection = item }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(item.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
                badge(item)
            }
            .foregroundStyle(rowColor(item))
            .padding(.horizontal, 10)
            .padding(.vertical, Halo.Space.sm)
            .background(
                isSelected
                    ? Halo.interactive.opacity(0.10)
                    : (isHover ? Halo.surface2.opacity(0.6) : .clear),
                in: RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredItem = hovering ? item : nil }
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
        } else if !item.isAvailable {
            Text("soon")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Halo.textDim.opacity(0.7))
        }
    }

    private func rowColor(_ item: SidebarItem) -> Color {
        if selection == item { return Halo.interactive }
        return item.isAvailable ? Halo.textPrimary.opacity(0.8) : Halo.textDim.opacity(0.6)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Halo.Space.xs) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 6)
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
