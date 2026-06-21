import AppKit
import SwiftUI

/// Command Center shell: custom HALO sidebar + selected section.
struct RootView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(MonitorModel.self) private var monitorModel
    @Environment(HealthModel.self) private var healthModel
    @Environment(UninstallModel.self) private var uninstall
    @Environment(CleanModel.self) private var clean
    @State private var selection: SidebarItem = .dashboard
    /// Mirrors NSWindow occlusion so a hidden/locked-screen window stops
    /// driving SwiftUI updates (measured ~12% CPU when occluded otherwise).
    @State private var windowVisible = true
    @State private var showPalette = false
    @State private var showOnboarding = PermissionsGate.shouldPromptOnLaunch()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
            Group {
                switch selection {
                case .storage: DiskView()
                case .timeline: TimelineView()
                case .uninstall: UninstallView()
                case .monitor: MonitorView()
                case .displays: DisplaysView()
                case .health: HealthView()
                case .permissions: PermissionsView()
                case .diagnostics: DevModeView()
                default: DashboardView()
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .frame(minWidth: 1080, minHeight: 720)
        .background(Halo.void)
        .background {
            // Hidden ⌘K hotkey for the command palette (no visible chrome).
            Button("") { showPalette = true }
                .keyboardShortcut("k", modifiers: .command)
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
        .onReceive(NotificationCenter.default.publisher(for: TimelineView.navigateToClean)) { _ in
            selection = .storage
        }
        .onReceive(NotificationCenter.default.publisher(for: DashboardView.navigateToMonitor)) { _ in
            selection = .monitor
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToOptimize)) { _ in
            selection = .storage
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
