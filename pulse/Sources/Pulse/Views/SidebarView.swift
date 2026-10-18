import PulseKit
import SwiftUI

/// Stable identifiers are retained for existing shortcuts and stored routes.
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case agent = "Agent"
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
        case .agent: "Ask Pulse"
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
        case .agent: "bubble.left.and.text.bubble.right"
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
    static let advancedGatedItems = Set(advanced)
}

struct SidebarView: View {
    @Environment(DashboardModel.self) private var model
    @Binding var selection: SidebarItem
    @Bindable var agent: AgentModel
    @State private var showAdvanced = false
    @State private var showMac = true
    @State private var showRecents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.system(size: 21, weight: .semibold)).foregroundStyle(Halo.interactive)
                Text("Pulse").font(Halo.font(size: 23, weight: .semibold))
                Spacer()
                Text("AI").font(Halo.font(size: 11, weight: .medium)).foregroundStyle(Halo.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 3).overlay(RoundedRectangle(cornerRadius: 5).stroke(Halo.borderSubtle))
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    nav("New conversation", symbol: "plus", page: "conversation") { agent.newConversation() }
                    nav("Search", symbol: "magnifyingglass", page: "search")
                    nav("Automations", symbol: "clock", page: "automations")
                    nav("Needs attention", symbol: "tray", page: "inbox")
                    nav("Memory", symbol: "brain", page: "memory")
                    nav("Specialists", symbol: "sparkles", page: "skills")
                    if !agent.sessions.isEmpty {
                        navLabel("CONVERSATIONS")
                        let recent = showRecents ? agent.sessions : Array(agent.sessions.prefix(7))
                        ForEach(recent) { session in
                            Button {
                                selection = .agent
                                Task { await agent.openSession(session.sessionId) }
                            } label: {
                                HStack(spacing: 9) {
                                    if session.pinned == true { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Halo.textSecondary) }
                                    Text(session.name).lineLimit(1).truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(selection == .agent && agent.page == "conversation" && agent.sessionId == session.sessionId ? Halo.surface2 : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).font(Halo.font(size: 13)).disabled(agent.isBusy)
                                .help(session.name)
                                .contextMenu {
                                    Button(session.pinned == true ? "Unpin" : "Pin") { Task { await agent.updateSession(session.sessionId, pinned: session.pinned != true) } }
                                    Button("Rename…") { rename(session) }
                                    Button("Archive") { Task { await agent.updateSession(session.sessionId, archived: true) } }
                                }
                        }
                        if agent.sessions.count > 7 { Button(showRecents ? "Show fewer" : "Show more") { showRecents.toggle() }.buttonStyle(.plain).font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary).padding(10) }
                    }
                    navLabel("YOUR MAC")
                    DisclosureGroup("Mac tools", isExpanded: $showMac) {
                        ForEach(SidebarItem.everyday) { item in toolRow(item) }
                        DisclosureGroup("Advanced tools", isExpanded: $showAdvanced) {
                            ForEach(SidebarItem.advanced) { item in toolRow(item) }
                        }.font(Halo.font(size: 13)).padding(.horizontal, 10).padding(.vertical, 5)
                    }.font(Halo.font(size: 13, weight: .medium)).padding(.horizontal, 9)
                }.padding(.horizontal, 10).padding(.bottom, 16)
            }
            VStack(spacing: 8) {
                Divider().overlay(Halo.borderSubtle)
                Button { selection = .settings } label: { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(10) }.buttonStyle(.plain)
                Label(statusText, systemImage: statusSymbol).font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.bottom, 12)
            }.padding(.horizontal, 10)
        }
        .font(Halo.font(size: 14)).foregroundStyle(Halo.textPrimary).background(Halo.surface1)
        .onAppear { revealSelection() }.onChange(of: selection) { _, _ in revealSelection() }
        .accessibilityLabel("Navigation")
    }

    private func navLabel(_ title: String) -> some View {
        Text(title).font(Halo.font(size: 11, weight: .medium)).foregroundStyle(Halo.textSecondary).tracking(0.7).padding(.horizontal, 12).padding(.top, 24).padding(.bottom, 8)
    }
    private func nav(_ title: String, symbol: String, page: String, action: (() -> Void)? = nil) -> some View {
        Button {
            selection = .agent; action?(); agent.openPage(page)
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                .background(selection == .agent && agent.page == page && (page != "conversation" || agent.sessionId == nil) ? Halo.surface2 : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(page == "conversation" && agent.isBusy)
    }
    private func toolRow(_ item: SidebarItem) -> some View {
        Button { selection = item } label: {
            Label(item.title, systemImage: item.symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                .background(selection == item ? Halo.surface2 : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).font(Halo.font(size: 13))
    }
    private func rename(_ session: AgentSessionItem) {
        let alert = NSAlert(); alert.messageText = "Rename conversation"; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: session.name); field.frame = NSRect(x: 0, y: 0, width: 300, height: 25); alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn { Task { await agent.updateSession(session.sessionId, title: field.stringValue) } }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .padding(.vertical, 4)
            .tag(item)
            .accessibilityLabel(item.title)
    }

    private func revealSelection() {
        if selection != .agent && selection != .settings { showMac = true }
        if SidebarItem.advancedGatedItems.contains(selection) { showAdvanced = true }
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
