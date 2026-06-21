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
    private static let onboardedKey = "PulseMenuBarManagerOnboarded"

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
        state.toggle()
        applySeparatorLength()
        updateChevronImage()
        resetAutoHideTimer()
    }

    func collapse() {
        guard state.isExpanded else { return }
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

        // Create chevron FIRST — macOS inserts new items at the leftmost
        // position, so the chevron lands further left. Then the separator is
        // created and appears to the LEFT of the chevron. This gives us:
        //   [...hidden...] [separator] [chevron ‹›] [...visible...] [Pulse]
        let chev = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        chev.autosaveName = "PulseMenuBarChevron"
        chev.button?.target = self
        chev.button?.action = #selector(chevronClicked(_:))
        chev.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        chevron = chev

        let sep = NSStatusBar.system.statusItem(withLength: MenuBarState.separatorWidth)
        sep.autosaveName = "PulseMenuBarSeparator"
        sep.button?.sendAction(on: [])
        separator = sep

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }

        // Start expanded so user sees the separator and understands the layout.
        state.expand()
        applySeparatorLength()
        updateSeparatorAppearance()
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
        updateSeparatorAppearance()
    }

    private func updateSeparatorAppearance() {
        guard let btn = separator?.button else { return }
        if state.isExpanded && state.showSeparator {
            btn.image = NSImage(
                systemSymbolName: "line.diagonal",
                accessibilityDescription: "Menu bar section divider"
            )
            btn.image?.isTemplate = true
            btn.title = ""
        } else {
            btn.image = nil
            btn.title = ""
        }
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
        alert.messageText = "Menu Bar Manager"
        alert.informativeText = """
        Two new icons appeared in your menu bar:

        ≡  Separator — the divider between visible and hidden items
        «  Chevron — click to hide/show items

        To choose which items to hide:
        ⌘ + drag menu bar icons to the LEFT of the ≡ separator.

        Then click the « chevron to collapse — items left of the separator will be hidden.

        Right-click the chevron for auto-hide settings.
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
