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
    static var navigationOrder: [SidebarItem] { everyday + advanced + [.settings] }

    static func adjacent(to item: SidebarItem, offset: Int) -> SidebarItem {
        let items = navigationOrder
        let index = items.firstIndex(of: item) ?? 0
        return items[min(max(index + offset, 0), items.count - 1)]
    }
}

struct SidebarView: View {
    @Environment(DashboardModel.self) private var model
    @Binding var selection: SidebarItem
    @FocusState private var focusedItem: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("p")
                    .font(Halo.font(size: 25, weight: .medium, design: .rounded))
                    .foregroundStyle(Halo.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Halo.interactive, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                Text("Pulse")
                    .font(Halo.font(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Halo.textPrimary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            // ponytail: native buttons plus move commands keep the short list accessible.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(SidebarItem.navigationOrder) { item in row(item) }
                    }
                    .padding(.horizontal, 12)
                }
                .onMoveCommand { direction in
                    guard direction == .up || direction == .down else { return }
                    let next = SidebarItem.adjacent(to: focusedItem ?? selection,
                                                   offset: direction == .down ? 1 : -1)
                    selection = next
                    focusedItem = next
                    proxy.scrollTo(next)
                }
            }
            .font(Halo.font(size: 14))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Navigation")

            Label(statusText, systemImage: statusSymbol)
                .font(Halo.font(size: 12))
                .foregroundStyle(Halo.textSecondary)
                .padding(16)
                .accessibilityElement(children: .combine)
        }
        .background(Halo.sidebar)
    }

    private func row(_ item: SidebarItem) -> some View {
        Button {
            selection = item
            focusedItem = item
        } label: {
            Label(item.title, systemImage: item.symbol)
                .foregroundStyle(selection == item ? Halo.interactive : Halo.textPrimary)
                .fontWeight(selection == item ? .medium : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .background(selection == item ? Halo.tealSoft : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedItem, equals: item)
        .id(item)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selection == item ? .isSelected : [])
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
