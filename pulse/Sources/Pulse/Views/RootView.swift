import AppKit
import SwiftUI

/// Command Center shell: custom HALO sidebar + selected section.
struct RootView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(MonitorModel.self) private var monitorModel
    @Environment(HealthModel.self) private var healthModel
    @State private var selection: SidebarItem = .dashboard
    /// Mirrors NSWindow occlusion so a hidden/locked-screen window stops
    /// driving SwiftUI updates (measured ~12% CPU when occluded otherwise).
    @State private var windowVisible = true

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
            switch selection {
            case .storage: StorageView()
            case .clean: CleanView()
            case .monitor: MonitorView()
            case .health: HealthView()
            case .vault: VaultView()
            case .devMode: DevModeView()
            default: DashboardView()
            }
        }
        .frame(minWidth: 1080, minHeight: 720)
        .background(Halo.void)
        .preferredColorScheme(.dark)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSWindow.didChangeOcclusionStateNotification)
        ) { note in
            // SwiftUI doesn't expose the scene id on NSWindow reliably;
            // the title is stable and unique to this window.
            guard let window = note.object as? NSWindow,
                window.title.hasPrefix("Pulse")
            else { return }
            let visible = window.occlusionState.contains(.visible)
            guard visible != windowVisible else { return }
            windowVisible = visible
            visible ? model.viewAppeared() : model.viewDisappeared()
            monitorModel.windowVisibilityChanged(visible)
            healthModel.windowVisibilityChanged(visible)
        }
    }
}
