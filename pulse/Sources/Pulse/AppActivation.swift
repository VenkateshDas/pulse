import AppKit
import ServiceManagement
import SwiftUI
import PulseKit

/// Governs Pulse's Dock presence. Pulse is fundamentally a menu-bar app: it
/// samples and serves its popover from the background with no Dock tile. The
/// Command Center window temporarily promotes the app to `.regular` (Dock icon
/// + Cmd-Tab + focusable window) while it is open; closing it drops Pulse back
/// to the menu bar (`.accessory`). The user may pin a permanent Dock icon.
///
/// Policy is always *computed* from current state, never toggled blindly, so the
/// window-open signal and the preference compose without drift.
@MainActor
final class AppActivation {
    static let shared = AppActivation()

    private static let dockKey = "PulseShowDockIcon"

    /// User preference: keep a permanent Dock icon. Default `false` — Pulse
    /// lives in the menu bar and only shows a Dock icon while a window is open.
    var showDockIcon: Bool {
        didSet {
            guard showDockIcon != oldValue else { return }
            UserDefaults.standard.set(showDockIcon, forKey: Self.dockKey)
            apply()
        }
    }

    /// Whether Pulse registers itself as a login item via `SMAppService`.
    /// Read/write hits the launchd registry directly — there's nothing to
    /// cache, `.status` is already a fast local check.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Best-effort: SMAppService has no user-facing recovery path
                // here beyond retrying, so the toggle simply won't have moved.
            }
        }
    }

    /// Open Command Center windows. Policy is `.regular` while > 0. Reference
    /// counted so a re-opened or second window can't strand us in `.accessory`.
    private var openWindowCount = 0

    /// Set by the popover's "Quit Pulse" so `applicationShouldTerminate` knows
    /// the user really means to exit. Cmd-Q / the app menu's Quit are otherwise
    /// reinterpreted as "close the Command Center, stay in the menu bar".
    private(set) var userRequestedQuit = false

    /// The one true exit: actually terminate Pulse (popover "Quit Pulse").
    func quit() {
        userRequestedQuit = true
        NSApp.terminate(nil)
    }

    private init() {
        showDockIcon = UserDefaults.standard.bool(forKey: Self.dockKey)
    }

    /// Applies the launch-time policy. Call once after the app finishes
    /// launching so background mode is correct even before any window appears.
    func applyInitialPolicy() { apply() }

    func windowDidAppear() {
        openWindowCount += 1
        apply()
        // Accessory apps don't auto-activate; bring the freshly promoted window
        // to the front so it doesn't open behind other apps.
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidDisappear() {
        openWindowCount = max(0, openWindowCount - 1)
        apply()
    }

    /// `.regular` while a window is open or the user pinned a Dock icon;
    /// otherwise `.accessory` (menu-bar only, no Dock).
    private func apply() {
        let policy: NSApplication.ActivationPolicy =
            (showDockIcon || openWindowCount > 0) ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Policy flips strand existing status items click-dead in the
        // menu bar compositor — let the Menu Bar Manager re-register its
        // items (see handleActivationPolicyChange).
        MenuBarManager.shared.handleActivationPolicyChange()
    }
}

/// Keeps Pulse resident in the menu bar after the last window closes, and sets
/// the initial activation policy once AppKit is ready.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivation.shared.applyInitialPolicy()
        MenuBarManager.shared.start()
        
        // Brightness media-key interception.
        // Never prompt here — the Permissions onboarding handles that.
        // start() installs a global-monitor fallback that works without
        // Accessibility; a poll upgrades to the CGEvent tap once granted.
        MediaKeyManager.shared.start()

        // BrightnessEngine is otherwise lazily created by the first view that
        // reads it, so its hardware brightness-change observer wouldn't exist
        // until the popover first opens — media-key / Control Center changes
        // made before that were never reflected in the sliders. Touch it now.
        _ = BrightnessEngine.shared

        // Resident usage observation: folder-level "last seen in use" log
        // (FSEvents writes + sparse open-handle samples) feeding the storage
        // verdict card. Must run from launch — its value IS the watching time.
        UsageObserver.shared.start()
    }

    /// Closing the Command Center must not quit Pulse — it returns to the menu
    /// bar. Only the popover's "Quit Pulse" terminates.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Cmd-Q / the app menu's Quit reach here too, but for Pulse they should
    /// mean "close the Command Center and stay in the menu bar" — not exit.
    /// Only the popover's "Quit Pulse" (which sets `userRequestedQuit`) really
    /// terminates. If no Command Center window is open there's nothing to close
    /// to, so we allow termination (covers logout/shutdown while backgrounded).
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if AppActivation.shared.userRequestedQuit { return .terminateNow }
        let commandCenter = sender.windows.filter {
            $0.isVisible && $0.title.hasPrefix("Pulse")
        }
        guard !commandCenter.isEmpty else { return .terminateNow }
        commandCenter.forEach { $0.close() }
        return .terminateCancel
    }
}
