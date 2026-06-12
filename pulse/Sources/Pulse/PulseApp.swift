import AppKit
import SwiftUI

@main
struct PulseApp: App {
    @State private var model = DashboardModel()
    @State private var storageModel = StorageModel()
    @State private var cleanModel = CleanModel()
    @State private var monitorModel = MonitorModel()
    @State private var healthModel = HealthModel()

    init() {
        // Allow running as a bare SwiftPM executable during development:
        // give the process a real app presence (dock icon, key windows).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Pulse — Command Center", id: "dashboard") {
            RootView()
                .environment(model)
                .environment(storageModel)
                .environment(cleanModel)
                .environment(monitorModel)
                .environment(healthModel)
                .onAppear {
                    model.start()
                    cleanModel.start()
                    model.viewAppeared()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear { model.viewDisappeared() }
        }
        .defaultSize(width: 1220, height: 840)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        // Static-width label: menu bar items must not jiggle as values change.
        // Reads only menuBarCPUPercent so it re-renders only when the
        // displayed integer changes, not on every sample.
        HStack(spacing: 3) {
            Image(systemName: "waveform.path.ecg")
            Text(String(format: "%3d%%", model.menuBarCPUPercent))
                .font(.system(size: 12, design: .monospaced))
        }
    }
}
