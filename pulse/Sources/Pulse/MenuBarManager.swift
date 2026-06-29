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

    private var btnExpandCollapse: NSStatusItem?
    private var btnSeparate: NSStatusItem?
    private var autoHideTimer: Timer?
    private var screenObserver: Any?

    private static let enabledKey = "PulseMenuBarManagementEnabled"
    private static let autoHideKey = "PulseMenuBarAutoHideDelay"
    private static let onboardedKey = "PulseMenuBarManagerOnboardedV5"
    private static let expandCollapseAutosaveName = "PulseMenuBarExpandCollapse"
    private static let separateAutosaveName = "PulseMenuBarSeparate"
    private static let v4LegacyAutosaveName = "PulseMenuBarControlV4"

    /// Chevron shown while expanded
    private static let expandedGlyph = "‹"
    /// Chevron shown while collapsed
    private static let collapsedGlyph = "›"
    
    private let btnHiddenLength: CGFloat = 20

    /// Safety check: if the chevron is placed to the left of the separator, collapsing
    /// would push the chevron itself off-screen, trapping the user.
    private var isBtnSeparateValidPosition: Bool {
        // ponytail: best-effort trap check. Status-item button windows can be
        // transiently nil after App Nap / display sleep while backgrounded; if
        // we can't read positions, ALLOW the collapse rather than dead-locking
        // the chevron (the only failure this guards — a ⌘-dragged-left chevron —
        // is rare, and expand() always works to recover).
        guard let chevronX = btnExpandCollapse?.button?.window?.frame.origin.x,
              let separateX = btnSeparate?.button?.window?.frame.origin.x else {
            return true
        }
        if NSApp.userInterfaceLayoutDirection == .rightToLeft {
            return chevronX <= separateX
        } else {
            return chevronX >= separateX
        }
    }

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
        upgradeFromV4()
    }

    private func upgradeFromV4() {
        // macOS persists status items by autosave name. Since we changed to a 2-item 
        // architecture, the old invisible 10,000pt item remains permanently stuck in 
        // the user's menubar. We claim its name and remove it.
        let orphanedItem = NSStatusBar.system.statusItem(withLength: 1)
        orphanedItem.autosaveName = Self.v4LegacyAutosaveName
        NSStatusBar.system.removeStatusItem(orphanedItem)
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
        guard isBtnSeparateValidPosition else {
            // If the user dragged them into an invalid order, auto-hide is 
            // still allowed to fire but we refuse to collapse to prevent trapping.
            return
        }
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
        guard btnExpandCollapse == nil else { return }

        // Expand/Collapse Chevron
        let expandItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        expandItem.autosaveName = Self.expandCollapseAutosaveName
        if let button = expandItem.button {
            button.target = self
            button.action = #selector(controlClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = .systemFont(ofSize: 15, weight: .bold)
            button.alignment = .right
        }
        btnExpandCollapse = expandItem

        // Separator Line
        let separateItem = NSStatusBar.system.statusItem(withLength: btnHiddenLength)
        separateItem.autosaveName = Self.separateAutosaveName
        if let button = separateItem.button {
            button.title = "|"
            // Optionally set image if we had ic_line, but title "|" works
            // Right-click context menu
            let menu = getContextMenu()
            separateItem.menu = menu
        }
        btnSeparate = separateItem

        // Self-Healing UI: Cmd-dragging a status item off the bar is persisted 
        // by macOS. Force visibility so the user is never permanently locked out.
        btnExpandCollapse?.isVisible = true
        btnSeparate?.isVisible = true

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
        if let item = btnExpandCollapse {
            NSStatusBar.system.removeStatusItem(item)
            btnExpandCollapse = nil
        }
        if let item = btnSeparate {
            NSStatusBar.system.removeStatusItem(item)
            btnSeparate = nil
        }
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }

    // MARK: - Rendering

    private func applyControl() {
        guard let chevron = btnExpandCollapse, let cBtn = chevron.button else { return }
        guard let sep = btnSeparate else { return }
        
        if state.isExpanded {
            sep.length = btnHiddenLength
            cBtn.title = Self.expandedGlyph
            cBtn.toolTip = "Hide the menu bar icons on the left"
        } else {
            sep.length = state.collapseWidth
            cBtn.title = Self.collapsedGlyph
            cBtn.toolTip = "Show the hidden menu bar icons"
        }
    }

    @objc private func controlClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { toggle(); return }
        if event.type == .rightMouseUp {
            showContextMenuFromChevron()
        } else {
            toggle()
        }
    }

    private func showContextMenuFromChevron() {
        guard let btn = btnExpandCollapse?.button else { return }
        let menu = getContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: btn.bounds.maxY + 5), in: btn)
    }

    private func getContextMenu() -> NSMenu {
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

        return menu
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
        A separator ( | ) and a chevron ( ‹ ) were added to your menu bar.

        Everything to the LEFT of the separator ( | ) is your "hidden" zone.

        • Click the chevron to collapse — every icon left of the separator disappears.
        • To bring them back, click the chevron again.

        To configure what hides, hold ⌘ and drag the separator ( | ). Anything \
        left of it hides; anything right of it always stays visible.
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
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            // Dynamic check accommodates notched displays instead of hardcoded 24pt
            if mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX &&
               mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY {
                return true
            }
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
