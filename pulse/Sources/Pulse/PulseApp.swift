import AppKit
import PulseKit
import SwiftUI
import UserNotifications

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = DashboardModel()
    @State private var storageModel = StorageModel()
    @State private var cleanModel = CleanModel()
    @State private var uninstallModel = UninstallModel()
    @State private var monitorModel = MonitorModel()
    @State private var healthModel = HealthModel()
    @State private var timelineModel = TimelineModel()
    @State private var optimizeModel = OptimizeModel()
    @State private var insightsModel = InsightsModel()
    @State private var networkModel = NetworkModel()

    // Activation policy is no longer pinned to `.regular` here. Pulse is a
    // menu-bar app: `AppActivation` promotes it to `.regular` (Dock + Cmd-Tab)
    // only while the Command Center window is open, and demotes it back to
    // `.accessory` (menu-bar only) when closed. See AppActivation.swift.

    var body: some Scene {
        Window("Pulse — Command Center", id: "dashboard") {
            RootView()
                .environment(model)
                .environment(storageModel)
                .environment(cleanModel)
                .environment(uninstallModel)
                .environment(monitorModel)
                .environment(healthModel)
                .environment(timelineModel)
                .environment(optimizeModel)
                .environment(insightsModel)
                .environment(networkModel)
                .environment(Updater.shared)
                .onAppear {
                    model.start()
                    cleanModel.start()
                    networkModel.start()
                    KeybindingActions.networkModel = networkModel
                    model.viewAppeared()
                    Self.scheduleWeeklyReport()
                    // Promote to a Dock-visible, focusable app while open and
                    // bring the window forward (also activates from .accessory).
                    AppActivation.shared.windowDidAppear()
                }
                .onDisappear {
                    model.viewDisappeared()
                    // Window closed — return Pulse to the menu bar (no Dock).
                    AppActivation.shared.windowDidDisappear()
                }
        }
        .defaultSize(width: 1220, height: 840)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .environment(cleanModel)
                .environment(storageModel)
                .environment(networkModel)
                .environment(Updater.shared)
                // `.window`-style popovers don't reliably propagate
                // `@Observable` changes across window boundaries — force a
                // full rebuild on theme change so the popover always shows
                // the current preset immediately.
                .id(ThemeManager.shared.selected)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// Schedules a recurring Monday-morning Weekly Pulse notification. Guarded
    /// behind a bundle id — UNUserNotificationCenter traps in bare SwiftPM runs.
    private static func scheduleWeeklyReport() {
        guard Bundle.main.bundleIdentifier != nil, NotificationPreferences.notifyWeeklyReport else { return }
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
        MenuBarLabel(model: model)
    }
}

/// Static-width label: menu bar items must not jiggle as values change.
/// Reads only the gated readings dictionary, so it re-renders only when
/// something displayed actually changes, not on every sample.
///
/// Drawn into ONE NSImage (see MenuBarLabelRenderer): MenuBarExtra flattens
/// its label, so this is the only way to get native-looking multi-stat
/// rendering in a single button.
private struct MenuBarLabel: View {
    let model: DashboardModel
    // Colored (non-template) renders bake labelColor at draw time; template
    // renders are re-tinted by macOS for free. Depending on colorScheme
    // forces a rebuild on Light/Dark flips so a colored label can't keep a
    // stale neutral color.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: MenuBarLabelRenderer.image(
            stats: model.menuBarStats,
            readings: model.menuBarReadings,
            flashSymbol: MenuBarFlash.shared.symbol))
            .id(colorScheme)
    }
}
