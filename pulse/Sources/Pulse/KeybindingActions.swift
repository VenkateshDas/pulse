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

    private static func runOptimize() {
        Task {
            let report = await OptimizeEngine.runSafeTasks()
            postNotification(title: "Optimize", body: report)
        }
    }

    private static func confirmAndEmptyTrash() {
        NSApp.activate(ignoringOtherApps: true)
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let entries = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        guard !entries.isEmpty else {
            postNotification(title: "Empty Trash", body: "Trash is already empty.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "Permanently erases \(entries.count) item\(entries.count == 1 ? "" : "s"). This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        MenuBarFlash.shared.flash("trash")
        var count = 0
        for url in entries {
            if (try? FileManager.default.removeItem(at: url)) != nil { count += 1 }
        }
        postNotification(title: "Empty Trash", body: count > 0 ? "Emptied \(count) items from Trash" : "Failed to empty Trash")
    }

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
    private static func runSpeedTest() {
        guard let network = networkModel else { return }
        guard network.speedTestState != .running else {
            postNotification(title: "Speed Test", body: "A speed test is already running.")
            return
        }
        MenuBarFlash.shared.flash(PulseAction.runSpeedTest.symbolName, for: 40)
        Task {
            if let result = await network.runSpeedTestAwaiting() {
                var parts = [
                    String(format: "%.0f ↓ / %.0f ↑ Mbps", result.downloadMbps, result.uploadMbps)
                ]
                if let rtt = result.baseRTTMillis { parts.append(String(format: "%.0f ms latency", rtt)) }
                if let rpm = result.responsivenessRPM { parts.append("\(rpm) RPM") }
                postNotification(title: "Speed Test", body: parts.joined(separator: " · "))
            } else {
                postNotification(title: "Speed Test", body: "Speed test failed — check your connection.")
            }
            MenuBarFlash.shared.flash(PulseAction.runSpeedTest.symbolName, for: 2)
        }
    }

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
