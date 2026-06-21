import AppKit
import PulseKit

/// Manages menu bar item hiding via the NSStatusItem width-inflation trick.
/// Two status items: an inflatable separator (pushes items off-screen) and a
/// tiny chevron toggle (always visible, 1-click expand/collapse).
@MainActor
final class MenuBarManager {
    static let shared = MenuBarManager()

    private(set) var state = MenuBarState()

    private var separator: NSStatusItem?
    private var chevron: NSStatusItem?
    private var autoHideTimer: Timer?
    private var screenObserver: Any?

    private static let enabledKey = "PulseMenuBarManagementEnabled"
    private static let autoHideKey = "PulseMenuBarAutoHideDelay"
    private static let showSeparatorKey = "PulseMenuBarShowSeparator"
    // V3: bumped alongside the versioned autosave names so the refreshed
    // onboarding (with the new layout) shows once after this change.
    private static let onboardedKey = "PulseMenuBarManagerOnboardedV3"

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

    var showSeparator: Bool {
        get { state.showSeparator }
        set {
            state.showSeparator = newValue
            UserDefaults.standard.set(newValue, forKey: Self.showSeparatorKey)
            applySeparatorLength()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        state.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        state.autoHideDelay = defaults.object(forKey: Self.autoHideKey) as? TimeInterval ?? 10
        state.showSeparator = defaults.object(forKey: Self.showSeparatorKey) as? Bool ?? true
        updateScreenWidth()
    }

    func start() {
        guard state.isEnabled else { return }
        setUp()
    }

    // MARK: - Toggle

    func toggle() {
        if state.isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func collapse() {
        guard state.isExpanded else { return }
        // Refuse to collapse if the user dragged the separator to the wrong
        // side of the chevron — collapsing then would hide the chevron and the
        // visible items instead of the intended ones.
        guard isSeparatorValidPosition else {
            warnInvalidPosition()
            return
        }
        state.collapse()
        applySeparatorLength()
        updateChevronImage()
        cancelAutoHideTimer()
    }

    func expand() {
        guard state.isCollapsed else { return }
        state.expand()
        applySeparatorLength()
        updateChevronImage()
        resetAutoHideTimer()
    }

    // MARK: - Setup / Teardown

    private func setUp() {
        guard separator == nil else { return }

        // macOS inserts each new status item at the LEFTMOST slot. Create the
        // chevron FIRST so the separator (created second) lands to its LEFT:
        //   [...items to hide...] [divider ┃] [chevron «] [...] [Pulse]
        // Collapsing inflates the divider, pushing everything to its LEFT
        // off-screen; the chevron stays visible because it is to its RIGHT.
        //
        // autosaveName is versioned (V3) so saved positions from earlier builds
        // — which could leave the divider on the wrong side of the chevron —
        // are discarded and the items start fresh in the order above.
        let chev = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        chev.autosaveName = "PulseMenuBarChevronV3"
        chev.button?.target = self
        chev.button?.action = #selector(chevronClicked(_:))
        chev.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        chevron = chev

        // Divider drawn as a bold box-drawing glyph (┃). A drawn NSImage proved
        // invisible in testing; a text glyph renders reliably and is unmissable.
        let sep = NSStatusBar.system.statusItem(withLength: MenuBarState.separatorWidth)
        sep.autosaveName = "PulseMenuBarSeparatorV3"
        sep.button?.title = "┃"
        sep.button?.font = .systemFont(ofSize: 15, weight: .bold)
        sep.button?.sendAction(on: [])
        separator = sep

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }

        // Start expanded so the user sees the divider and can drag items
        // across it before collapsing.
        state.expand()
        applySeparatorLength()
        updateChevronImage()
        resetAutoHideTimer()
    }

    private func tearDown() {
        cancelAutoHideTimer()
        if let sep = separator {
            NSStatusBar.system.removeStatusItem(sep)
            separator = nil
        }
        if let chev = chevron {
            NSStatusBar.system.removeStatusItem(chev)
            chevron = nil
        }
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }

    // MARK: - Private

    private func applySeparatorLength() {
        separator?.length = state.separatorLength
    }

    /// True when the chevron sits to the right of (or level with) the separator
    /// — the only arrangement where collapsing hides the intended items rather
    /// than the chevron itself. Mirrors HiddenBar's `isBtnSeparateValidPosition`.
    /// Returns true if either window isn't laid out yet (don't block first use).
    private var isSeparatorValidPosition: Bool {
        guard let chevronX = chevron?.button?.window?.frame.origin.x,
              let separatorX = separator?.button?.window?.frame.origin.x
        else { return true }
        return chevronX >= separatorX
    }

    private func updateChevronImage() {
        chevron?.button?.image = NSImage(
            systemSymbolName: state.chevronSymbol,
            accessibilityDescription: state.isCollapsed ? "Show menu bar items" : "Hide menu bar items"
        )
    }

    @objc private func chevronClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { toggle(); return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else if event.modifierFlags.contains(.option) {
            showSeparator.toggle()
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

        let sepItem = NSMenuItem(
            title: "Show Separator",
            action: #selector(toggleSeparatorVisibility),
            keyEquivalent: ""
        )
        sepItem.target = self
        sepItem.state = state.showSeparator ? .on : .off
        menu.addItem(sepItem)

        menu.addItem(.separator())

        let disableItem = NSMenuItem(
            title: "Disable Menu Bar Manager",
            action: #selector(disableFeature),
            keyEquivalent: ""
        )
        disableItem.target = self
        menu.addItem(disableItem)

        chevron?.menu = menu
        chevron?.button?.performClick(nil)
        chevron?.menu = nil
    }

    @objc private func setAutoHideDelay(_ sender: NSMenuItem) {
        autoHideDelay = TimeInterval(sender.tag)
    }

    @objc private func toggleSeparatorVisibility() {
        showSeparator.toggle()
    }

    @objc private func disableFeature() {
        isEnabled = false
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.onboardedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)

        let alert = NSAlert()
        alert.messageText = "Menu Bar Manager is on"
        alert.informativeText = """
        Look for a bold divider and a chevron in your menu bar:  ┃ «

        Everything to the LEFT of the chevron is the "hidden" zone.

        How to use it:
        1. Hold ⌘ and drag any menu bar icon so it sits to the LEFT of the ┃ divider.
        2. Click the « chevron — those icons collapse out of sight.
        3. Click it again ( » ) to bring them back.

        Only icons left of the divider hide. The clock, Control Center, and anything to the right always stay visible.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.icon = NSImage(systemSymbolName: "menubar.rectangle",
                             accessibilityDescription: nil)

        // Run on next tick so the status items are visible before the alert.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// The separator was dragged to the right of the chevron — collapsing would
    /// hide the wrong items. Tell the user how to fix it instead of doing nothing.
    private func warnInvalidPosition() {
        let alert = NSAlert()
        alert.messageText = "Move the divider first"
        alert.informativeText = """
        The « chevron is currently to the LEFT of the ▏ divider, so collapsing \
        would hide the wrong icons.

        Hold ⌘ and drag the chevron back to the right of the divider, then try again.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
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
        if state.isCollapsed {
            applySeparatorLength()
        }
    }

    private func updateScreenWidth() {
        let maxWidth = NSScreen.screens.map(\.frame.width).max() ?? 1920
        state.updateScreenWidth(maxWidth)
    }
}
