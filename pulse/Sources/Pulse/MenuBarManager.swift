import AppKit
import PulseKit

/// Hides menu bar items using the NSStatusItem width-inflation trick, with a
/// SINGLE status item that is both the visible chevron and the inflating
/// element. When collapsed, the item's width balloons to ~2× the screen,
/// pushing everything to its LEFT off-screen; the chevron glyph stays pinned
/// to the item's right edge (right-aligned title) so it remains clickable.
///
/// A single item is deliberate: two independent status items proved unable to
/// stay adjacent — macOS scattered them to opposite ends of the bar (separator
/// at x=0, chevron at x=3879), so inflating the separator hid nothing. One
/// item has no position to coordinate, so "everything left of the chevron
/// hides" always holds.
@MainActor
final class MenuBarManager {
    static let shared = MenuBarManager()

    private(set) var state = MenuBarState()

    private var control: NSStatusItem?
    private var autoHideTimer: Timer?
    private var screenObserver: Any?

    private static let enabledKey = "PulseMenuBarManagementEnabled"
    private static let autoHideKey = "PulseMenuBarAutoHideDelay"
    private static let onboardedKey = "PulseMenuBarManagerOnboardedV4"
    private static let autosaveName = "PulseMenuBarControlV4"

    /// Chevron shown while expanded — points left ("click to hide to the left").
    private static let expandedGlyph = "‹"

    /// Whether the menu bar is currently collapsed (icons hidden).
    var isCollapsed: Bool { state.isCollapsed }

    var isEnabled: Bool {
        get { state.isEnabled }
        set {
            state.isEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                setUp()
                showOnboardingIfNeeded()
            } else {
                tearDown()
            }
        }
    }

    var autoHideDelay: TimeInterval {
        get { state.autoHideDelay }
        set {
            state.autoHideDelay = newValue
            UserDefaults.standard.set(newValue, forKey: Self.autoHideKey)
            resetAutoHideTimer()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        state.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        state.autoHideDelay = defaults.object(forKey: Self.autoHideKey) as? TimeInterval ?? 10
        updateScreenWidth()
    }

    func start() {
        guard state.isEnabled else { return }
        setUp()
    }

    // MARK: - Toggle

    func toggle() {
        if state.isExpanded { collapse() } else { expand() }
    }

    func collapse() {
        guard state.isExpanded else { return }
        state.collapse()
        applyControl()
        cancelAutoHideTimer()
    }

    func expand() {
        guard state.isCollapsed else { return }
        state.expand()
        applyControl()
        resetAutoHideTimer()
    }

    // MARK: - Setup / Teardown

    private func setUp() {
        guard control == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        if let button = item.button {
            button.target = self
            button.action = #selector(controlClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = .systemFont(ofSize: 15, weight: .bold)
            // Right-align so the glyph stays pinned to the item's right edge
            // even when the item is inflated thousands of points wide.
            button.alignment = .right
        }
        control = item

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }

        // Start expanded so the user can arrange icons before collapsing.
        state.expand()
        applyControl()
        resetAutoHideTimer()
    }

    private func tearDown() {
        cancelAutoHideTimer()
        if let item = control {
            NSStatusBar.system.removeStatusItem(item)
            control = nil
        }
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }

    // MARK: - Rendering

    private func applyControl() {
        guard let item = control, let button = item.button else { return }
        if state.isExpanded {
            // Small, normal-sized item showing the chevron. Click to collapse.
            item.length = NSStatusItem.variableLength
            button.title = Self.expandedGlyph
            button.toolTip = "Hide the menu bar icons on the left"
        } else {
            // Inflate to push everything on the item's left off-screen. An
            // inflated status item does not render its own button content (an
            // AppKit limit at large widths), so there is no glyph here — the
            // whole emptied strip is one big click target that expands again.
            item.length = state.collapseWidth
            button.title = ""
            button.toolTip = "Show the hidden menu bar icons"
        }
    }

    @objc private func controlClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { toggle(); return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let autoHideItem = NSMenuItem(
            title: state.autoHideDelay > 0 ? "Auto-hide (\(Int(state.autoHideDelay))s)" : "Auto-hide (off)",
            action: nil, keyEquivalent: ""
        )
        let autoHideMenu = NSMenu()
        for seconds in [0, 5, 10, 15, 30] {
            let item = NSMenuItem(
                title: seconds == 0 ? "Disabled" : "\(seconds) seconds",
                action: #selector(setAutoHideDelay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = seconds
            item.state = Int(state.autoHideDelay) == seconds ? .on : .off
            autoHideMenu.addItem(item)
        }
        autoHideItem.submenu = autoHideMenu
        menu.addItem(autoHideItem)

        let helpItem = NSMenuItem(title: "How it works…", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(.separator())

        let disableItem = NSMenuItem(title: "Disable Menu Bar Manager", action: #selector(disableFeature), keyEquivalent: "")
        disableItem.target = self
        menu.addItem(disableItem)

        control?.menu = menu
        control?.button?.performClick(nil)
        control?.menu = nil
    }

    @objc private func setAutoHideDelay(_ sender: NSMenuItem) {
        autoHideDelay = TimeInterval(sender.tag)
    }

    @objc private func showHelp() {
        showHelpAlert()
    }

    @objc private func disableFeature() {
        isEnabled = false
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.onboardedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        showHelpAlert()
    }

    private func showHelpAlert() {
        let alert = NSAlert()
        alert.messageText = "Menu Bar Manager"
        alert.informativeText = """
        A small chevron ( ‹ ) was added to your menu bar. Everything to its \
        LEFT is the "hidden" zone.

        • Click the ‹ chevron to collapse — every icon to its left disappears.
        • To bring them back, click the empty strip where they were, or use \
        the Show/Hide button in Pulse's menu bar popover.

        To keep an icon always visible, hold ⌘ and drag it to the RIGHT of the \
        chevron. Anything left of the chevron hides; anything right of it \
        (including the clock and Control Center) always stays.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.icon = NSImage(systemSymbolName: "menubar.rectangle",
                             accessibilityDescription: nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - Auto-hide Timer

    private func resetAutoHideTimer() {
        cancelAutoHideTimer()
        guard state.shouldAutoHide else { return }
        autoHideTimer = Timer.scheduledTimer(
            withTimeInterval: state.autoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoHideTimerFired()
            }
        }
    }

    private func cancelAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func autoHideTimerFired() {
        guard state.isExpanded else { return }
        if isMouseInMenuBar() {
            resetAutoHideTimer()
        } else {
            collapse()
        }
    }

    private func isMouseInMenuBar() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let menuBarRect = CGRect(
                x: screen.frame.origin.x,
                y: screen.frame.maxY - 24,
                width: screen.frame.width,
                height: 24
            )
            if menuBarRect.contains(mouseLocation) { return true }
        }
        return false
    }

    // MARK: - Screen Changes

    private func handleScreenChange() {
        updateScreenWidth()
        if state.isCollapsed { applyControl() }
    }

    private func updateScreenWidth() {
        let maxWidth = NSScreen.screens.map(\.frame.width).max() ?? 1920
        state.updateScreenWidth(maxWidth)
    }
}
