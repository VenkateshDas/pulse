import AppKit
import SwiftUI

/// Task navigation and the currently selected page.
struct RootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DashboardModel.self) private var model
    @Environment(MonitorModel.self) private var monitorModel
    @Environment(HealthModel.self) private var healthModel
    @Environment(UninstallModel.self) private var uninstall
    @Environment(CleanModel.self) private var clean
    @Environment(StorageModel.self) private var storage
    @Environment(TimelineModel.self) private var timeline
    @Environment(AgentModel.self) private var agentModel
    @State private var selection: SidebarItem = .agent
    /// Mirrors NSWindow occlusion so a hidden/locked-screen window stops
    /// driving SwiftUI updates (measured ~12% CPU when occluded otherwise).
    @State private var windowVisible = true
    @State private var screenLocked = false
    @State private var showPalette = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var showOnboarding = PermissionsGate.shouldPromptOnLaunch()
    @State private var homeAssistant = HomeAssistantState()
    @FocusState private var launcherFocused: Bool
    @FocusedValue(\.homeControlFocused) private var homeControlFocused

    private var assistantVisible: Bool {
        HomeAssistantState.isVisible(selection: selection, homeOpen: homeAssistant.isOpen,
            windowVisible: windowVisible, screenLocked: screenLocked, onboarding: showOnboarding)
    }

    private func openHomeAssistant() {
        launcherFocused = false
        agentModel.openPage("conversation")
        selection = .dashboard
        homeAssistant.open(runID: agentModel.activeRunId)
    }

    private func minimizeAssistant() {
        homeAssistant.minimize()
        VoiceInput.shared.stop()
        Task { @MainActor in
            await Task.yield()
            if selection == .dashboard && !homeAssistant.isOpen { launcherFocused = true }
        }
    }

    private func applyPendingNavigation() {
        guard let route = PulseNavigation.takePending() else { return }
        if let tab = route.diskTab { storage.pendingDiskTab = tab }
        selection = route.destination
    }

    var body: some View {
        // Registers an Observation dependency on the current theme so the
        // whole subtree re-renders (picking up fresh `Halo.*` values) when
        // the user switches presets in Settings.
        let _ = ThemeManager.shared.selected
        let _ = ThemeManager.shared.largerText
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(selection: $selection, agent: agentModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            GeometryReader { geometry in
            ZStack {
                switch selection {
                case .agent: Color.clear
                case .storage: DiskView()
                case .timeline: TimelineView()
                case .optimize: OptimizeView()
                case .uninstall: UninstallView()
                case .monitor: MonitorView()
                case .network: NetworkView()
                case .displays: DisplaysView()
                case .health: HealthView()
                case .startup: HealthView(scope: .startup)
                case .benchmark: HealthView(scope: .benchmark)
                case .settings: SettingsView(selection: $selection)
                case .diagnostics: DevModeView()
                default: DashboardView(bottomClearance: 72)
                    .focusedValue(\.homeControlFocused, true)
                    .disabled(homeAssistant.isOpen && HomeAssistantState.usesFullDetail(width: geometry.size.width, height: geometry.size.height))
                    .accessibilityHidden(homeAssistant.isOpen && HomeAssistantState.usesFullDetail(width: geometry.size.width, height: geometry.size.height))
                    .allowsHitTesting(!(homeAssistant.isOpen && HomeAssistantState.usesFullDetail(width: geometry.size.width, height: geometry.size.height)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Halo.void)
            .overlay(alignment: .bottomTrailing) {
                assistantSurface(size: geometry.size)
            }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 600)
        .tint(Halo.interactive)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if selection == .settings && homeAssistant.returnFromSettings {
                    Button("Back to Home chat", action: openHomeAssistant)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showPalette = true } label: { Label("Search tasks", systemImage: "magnifyingglass") }
                    .help("Search tasks (⌘K)")
            }
        }
        .background {
            // Hidden hotkeys (no visible chrome): ⌘K palette, ⌘1–9 sections,
            // ⌘, Settings.
            Group {
                Button("") { showPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                    if index < 9 {
                        Button("") { withAnimation(Halo.Motion.snappy) { selection = item } }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                }
                Button("") { withAnimation(Halo.Motion.snappy) { selection = .settings } }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .overlay { commandPaletteOverlay }
        // One owner drives lifecycle for both presentations. Transferring to the
        // workspace only resizes the same mounted renderer; it never starts a run.
        .task(id: assistantVisible) {
            agentModel.visibilityChanged(assistantVisible)
            if assistantVisible { await agentModel.start() }
        }
        .onDisappear { agentModel.visibilityChanged(false) }
        .onChange(of: homeControlFocused) { _, focused in
            if focused == true && !AgentWebView.hasKeyboardFocus && selection == .dashboard && homeAssistant.isOpen {
                homeAssistant.minimize()
                VoiceInput.shared.stop()
            }
        }
        .onChange(of: selection) { _, destination in
            if destination != .dashboard { homeAssistant.minimize() }
            if destination == .agent && agentModel.page == "conversation" { homeAssistant.markRead(runID: agentModel.activeRunId) }
            if destination != .dashboard && destination != .settings { homeAssistant.returnFromSettings = false }
        }
        .onChange(of: agentModel.state) { _, state in
            homeAssistant.runChanged(state, runID: agentModel.activeRunId,
                visible: assistantVisible && agentModel.page == "conversation")
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onAppear {
            applyPendingNavigation()
            KeybindingActions.openReview = { destination, tab in
                PulseNavigation.open(destination, diskTab: tab)
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
            clean.start()
            // Record this build so a post-update re-prompt fires at most once.
            PermissionsGate.markPrompted()
        }
        // Every finished scan updates today's timeline snapshot, so growth
        // attribution has category data even when Timeline is never opened
        // that day. RootView outlives every pane, so no completion is missed.
        .onChange(of: storage.scanState) { _, state in
            if case .done = state { timeline.recordToday(scan: storage.scan) }
        }
        .onReceive(NotificationCenter.default.publisher(for: PulseNavigation.notification)) { note in
            applyPendingNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: TimelineView.navigateToClean)) { _ in
            storage.pendingDiskTab = 1
            selection = .storage
        }
        .onReceive(NotificationCenter.default.publisher(for: DashboardView.navigateToMonitor)) { note in
            // Carries the culprit PID when tapped from the diagnosis chip, so
            // Monitor opens with that process already selected.
            if let pid = note.object as? Int32 { monitorModel.select(pid) }
            selection = .monitor
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsLocked"))) { _ in screenLocked = true }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init("com.apple.screenIsUnlocked"))) { _ in screenLocked = false }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSWindow.didChangeOcclusionStateNotification)
        ) { note in
            guard let window = note.object as? NSWindow,
                window.title == "Pulse"
            else { return }
            let visible = window.occlusionState.contains(.visible)
            windowVisible = visible
            model.windowVisibilityChanged(visible)
            monitorModel.windowVisibilityChanged(visible)
            healthModel.windowVisibilityChanged(visible)
        }
    }

    @ViewBuilder
    private func assistantSurface(size: CGSize) -> some View {
        let onHome = selection == .dashboard
        let fullDetail = HomeAssistantState.usesFullDetail(width: size.width, height: size.height)
        let inset: CGFloat = onHome && !fullDetail ? 24 : 0
        VStack(alignment: .trailing, spacing: 12) {
            if assistantVisible {
                VStack(spacing: 0) {
                    if onHome {
                        HomeAssistantHeader(model: agentModel, fullDetail: fullDetail, expand: {
                            agentModel.openPage("conversation")
                            selection = .agent
                        }, minimize: minimizeAssistant)
                    }
                    AgentView(model: agentModel, compact: onHome, minimize: minimizeAssistant, openSettings: {
                        homeAssistant.returnFromSettings = onHome
                        selection = .settings
                    })
                }
                .frame(width: onHome && !fullDetail ? min(400, size.width - 48) : size.width,
                       height: onHome && !fullDetail ? min(540, size.height - 104) : size.height)
                .clipShape(RoundedRectangle(cornerRadius: onHome && !fullDetail ? 12 : 0))
                .overlay {
                    if onHome && !fullDetail {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Halo.border, lineWidth: 1)
                    }
                }
                .shadow(color: onHome && !fullDetail ? Halo.Shadow.elevatedColor : .clear,
                        radius: Halo.Shadow.elevatedRadius, y: Halo.Shadow.elevatedY)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(onHome ? "Ask Pulse on Home" : "Ask Pulse workspace")
                .accessibilityIdentifier("pulse-home-assistant")
                .focusedValue(\.homeControlFocused, false)
            }
            if onHome && !(homeAssistant.isOpen && fullDetail) {
                HomeAssistantLauncher(model: agentModel, presentation: homeAssistant,
                    open: {
                        if homeAssistant.isOpen { minimizeAssistant() }
                        else { openHomeAssistant() }
                    }, focused: $launcherFocused)
                .padding(onHome && fullDetail ? 16 : 0)
            }
        }
        .padding(inset)
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if showPalette {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { showPalette = false }
                CommandPaletteView(isPresented: $showPalette, selection: $selection, openHomeAssistant: openHomeAssistant)
                    .padding(.top, 80)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .onExitCommand { showPalette = false }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}
