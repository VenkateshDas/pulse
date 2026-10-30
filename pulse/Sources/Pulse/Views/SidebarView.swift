import PulseKit
import SwiftUI

/// Stable identifiers are retained for existing shortcuts and stored routes.
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case storage = "Storage"
    case timeline = "Timeline"
    case optimize = "Optimize"
    case uninstall = "Uninstall"
    case monitor = "Monitor"
    case network = "Network"
    case displays = "Displays"
    case health = "Health"
    case settings = "Settings"
    case diagnostics = "Diagnostics"
    case startup = "Startup"
    case benchmark = "Benchmark"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Home"
        case .storage: "Free up space"
        case .timeline: "Activity"
        case .optimize: "Maintenance"
        case .uninstall: "Apps"
        case .monitor: "App activity"
        case .network: "Internet"
        case .displays: "Displays"
        case .health: "Battery & energy"
        case .settings: "Settings"
        case .diagnostics: "Diagnostics"
        case .startup: "Startup helpers"
        case .benchmark: "Performance test"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "house"
        case .storage: "internaldrive"
        case .timeline: "clock.arrow.circlepath"
        case .optimize: "wrench.and.screwdriver"
        case .uninstall: "square.grid.2x2"
        case .monitor: "waveform.path.ecg"
        case .network: "wifi"
        case .displays: "display"
        case .health: "battery.75percent"
        case .settings: "gearshape"
        case .diagnostics: "stethoscope"
        case .startup: "power"
        case .benchmark: "gauge.with.needle"
        }
    }

    var isAvailable: Bool { true }
    static let everyday: [SidebarItem] = [.dashboard, .storage, .uninstall, .health, .network, .displays, .timeline]
    static let advanced: [SidebarItem] = [.monitor, .optimize, .startup, .benchmark, .diagnostics]
}

struct SidebarView: View {
    @Environment(DashboardModel.self) private var model
    @Binding var selection: SidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "circle.inset.filled")
                    .foregroundStyle(Halo.interactive)
                    .accessibilityHidden(true)
                Text("Pulse")
                    .font(Halo.font(size: 22, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            List(selection: Binding<SidebarItem?>(
                get: { selection }, set: { if let item = $0 { selection = item } }
            )) {
                ForEach(SidebarItem.everyday) { item in row(item) }
                ForEach(SidebarItem.advanced) { item in row(item) }
                row(.settings)
            }
            .listStyle(.sidebar)
            .font(Halo.font(size: 14))
            .accessibilityLabel("Navigation")

            Label(statusText, systemImage: statusSymbol)
                .font(Halo.font(size: 12))
                .foregroundStyle(Halo.textSecondary)
                .padding(16)
                .accessibilityElement(children: .combine)
        }
        .foregroundStyle(Halo.textPrimary)
        .background(Halo.void)
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .padding(.vertical, 4)
            .tag(item)
            .accessibilityLabel(item.title)
    }

    private var statusText: String {
        guard model.snapshot != nil else { return "Checking your Mac…" }
        return Self.statusText(mode: .simple,
                              hasCritical: model.diagnosis.severity == .critical,
                              hasWarning: model.diagnosis.severity == .warn || !model.attentionItems.isEmpty)
    }

    private var statusSymbol: String {
        model.snapshot == nil ? "clock" : (model.diagnosis.severity >= .warn ? "exclamationmark.circle" : "checkmark.circle")
    }

    static func statusText(mode: DisplayMode, hasCritical: Bool, hasWarning: Bool) -> String {
        if hasCritical { return "Needs attention" }
        if hasWarning { return "Something to review" }
        return "No urgent issues detected"
    }
}

/// Used by Home, search and contextual links. Navigation never executes an action.
@MainActor
enum PulseNavigation {
    private(set) static var pending: (destination: SidebarItem, diskTab: Int?)?
    static func takePending() -> (destination: SidebarItem, diskTab: Int?)? {
        defer { pending = nil }
        return pending
    }
    static let notification = Notification.Name("PulseNavigateToDestination")
    static func open(_ item: SidebarItem, diskTab: Int? = nil) {
        pending = (item, diskTab)
        var info: [String: Any] = ["destination": item.rawValue]
        if let diskTab { info["diskTab"] = diskTab }
        NotificationCenter.default.post(name: notification, object: nil, userInfo: info)
    }
}
