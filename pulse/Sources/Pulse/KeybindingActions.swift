import AppKit
import PulseKit
import SwiftUI
import UserNotifications

/// AppKit-side implementations the 5 global hotkeys dispatch to. Each mirrors
/// the same call the equivalent popover button already makes; only the
/// trigger and feedback (system notification instead of inline text) differ.
@MainActor
enum KeybindingActions {
    /// Set once at launch (PulseApp) — hotkeys are static handlers, but the
    /// speed test must run through the app's single NetworkModel so the
    /// popover, dashboard card, and Network page all see the result.
    static weak var networkModel: NetworkModel?
    static var openReview: ((SidebarItem, Int?) -> Void)?

    static func registerHandlers() {
        let hk = HotKeyManager.shared
        hk.setHandler(runOptimize, for: .optimize)
        hk.setHandler(confirmAndEmptyTrash, for: .emptyTrash)
        hk.setHandler(syncBrightness, for: .syncBrightness)
        hk.setHandler(toggleKeepAwake, for: .toggleKeepAwake)
        hk.setHandler({ MenuBarManager.shared.toggle() }, for: .toggleMenuBarChevron)
        hk.setHandler(runSpeedTest, for: .runSpeedTest)
        hk.reregisterAll()
    }

    private static func runOptimize() { openReview?(.optimize, nil) }

    private static func confirmAndEmptyTrash() { openReview?(.storage, 2) }

    private static func syncBrightness() {
        let engine = BrightnessEngine.shared
        engine.isAdaptiveModeEnabled.toggle()
        postNotification(
            title: "Sync Brightness",
            body: engine.isAdaptiveModeEnabled ? "Adaptive sync turned on." : "Adaptive sync turned off.")
    }

    /// Flash the gauge in the menu bar while the ~20 s test runs, then
    /// notify with the numbers. The long flash acts as the "in progress"
    /// indicator; the completion flash restarts the timer so the icon
    /// reverts a couple of seconds after the result lands.
    private static func runSpeedTest() { openReview?(.network, nil) }

    private static func toggleKeepAwake() {
        let awake = KeepAwakeController.shared
        if awake.isActive {
            awake.deactivate()
        } else {
            awake.activate()
        }
    }

    /// UNUserNotificationCenter traps when the process has no bundle (bare
    /// SwiftPM `make run`) — same guard used elsewhere in the app.
    private static func postNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "hotkey-\(title)-\(UUID())", content: content, trigger: nil))
    }
}
