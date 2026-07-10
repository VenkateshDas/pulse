import AppKit
import SwiftUI

/// Command Center shell: custom HALO sidebar + selected section.
struct RootView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(MonitorModel.self) private var monitorModel
    @Environment(HealthModel.self) private var healthModel
    @Environment(UninstallModel.self) private var uninstall
    @Environment(CleanModel.self) private var clean
    @Environment(StorageModel.self) private var storage
    @Environment(TimelineModel.self) private var timeline
    @State private var selection: SidebarItem = .dashboard
    /// Mirrors NSWindow occlusion so a hidden/locked-screen window stops
    /// driving SwiftUI updates (measured ~12% CPU when occluded otherwise).
    @State private var windowVisible = true
    @State private var showPalette = false
    @State private var showOnboarding = PermissionsGate.shouldPromptOnLaunch()

    var body: some View {
        // Registers an Observation dependency on the current theme so the
        // whole subtree re-renders (picking up fresh `Halo.*` values) when
        // the user switches presets in Settings.
        let _ = ThemeManager.shared.selected
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
            Group {
                switch selection {
                case .storage: DiskView()
                case .timeline: TimelineView()
                case .optimize: OptimizeView()
                case .uninstall: UninstallView()
                case .monitor: MonitorView()
                case .displays: DisplaysView()
                case .health: HealthView()
                case .settings: SettingsView(selection: $selection)
                case .diagnostics: DevModeView()
                default: DashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Halo.void)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .frame(minWidth: 1080, minHeight: 720)
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
        }
        .overlay { commandPaletteOverlay }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onAppear {
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
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSWindow.didChangeOcclusionStateNotification)
        ) { note in
            guard let window = note.object as? NSWindow,
                window.title == "Pulse — Command Center"
            else { return }
            let visible = window.occlusionState.contains(.visible)
            windowVisible = visible
            visible ? model.viewAppeared() : model.viewDisappeared()
            monitorModel.windowVisibilityChanged(visible)
            healthModel.windowVisibilityChanged(visible)
        }
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if showPalette {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { showPalette = false }
                CommandPaletteView(isPresented: $showPalette, selection: $selection)
                    .padding(.top, 80)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .onExitCommand { showPalette = false }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}
