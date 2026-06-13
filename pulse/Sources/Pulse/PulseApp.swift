import AppKit
import SwiftUI
import UserNotifications

@main
struct PulseApp: App {
    @State private var model = DashboardModel()
    @State private var storageModel = StorageModel()
    @State private var cleanModel = CleanModel()
    @State private var monitorModel = MonitorModel()
    @State private var healthModel = HealthModel()
    @State private var timelineModel = TimelineModel()

    init() {
        #if DEBUG
        // Dev (`make run`, bare SwiftPM exe): give the process a real app
        // presence — dock icon and key windows — so the window can be focused.
        NSApplication.shared.setActivationPolicy(.regular)
        #else
        // Production: menu-bar-primary app, no dock icon (LSUIElement in the
        // bundle Info.plist mirrors this). The Command Center opens from the
        // menu bar popover.
        NSApplication.shared.setActivationPolicy(.accessory)
        #endif
    }

    var body: some Scene {
        Window("Pulse — Command Center", id: "dashboard") {
            RootView()
                .environment(model)
                .environment(storageModel)
                .environment(cleanModel)
                .environment(monitorModel)
                .environment(healthModel)
                .environment(timelineModel)
                .onAppear {
                    model.start()
                    cleanModel.start()
                    model.viewAppeared()
                    Self.scheduleWeeklyReport()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear { model.viewDisappeared() }
        }
        .defaultSize(width: 1220, height: 840)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .environment(cleanModel)
                .environment(storageModel)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// Schedules a recurring Monday-morning Weekly Pulse notification. Guarded
    /// behind a bundle id — UNUserNotificationCenter traps in bare SwiftPM runs.
    private static func scheduleWeeklyReport() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let id = "com.pulse.weekly-report"
        let content = UNMutableNotificationContent()
        content.title = "Your Weekly Pulse is ready"
        content.body = "See how much space you reclaimed this week and your Mac's current health."
        var when = DateComponents()
        when.weekday = 2  // Monday
        when.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private var menuBarLabel: some View {
        // Static-width label: menu bar items must not jiggle as values change.
        // Reads only the gated integer properties, so it re-renders only when
        // a displayed value actually changes, not on every sample.
        let metrics = MenuBarMetric.allCases.filter { model.menuBarMetrics.contains($0) }
        return HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
            if metrics.isEmpty {
                Text(String(format: "%3d%%", model.menuBarCPUPercent))
                    .font(.system(size: 12, design: .monospaced))
            } else {
                ForEach(metrics) { metric in
                    Text(menuBarText(for: metric))
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        }
    }

    private func menuBarText(for metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu: String(format: "%3d%%", model.menuBarCPUPercent)
        case .memory: String(format: "M%2d%%", model.menuBarMemPercent)
        case .diskFree: "\(model.menuBarDiskFreeGB)G"
        case .temperature: model.menuBarTempC > 0 ? "\(model.menuBarTempC)°" : "—°"
        case .battery: "\(model.menuBarBatteryPercent)%🔋"
        }
    }
}
