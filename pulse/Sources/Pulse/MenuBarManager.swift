import AppKit
import PulseKit

/// Hides menu bar items using the NSStatusItem width-inflation trick, with
/// two status items: a chevron (the click target) and a separator. When
/// collapsed, the separator's width balloons to ~2× the screen, pushing
/// everything to its LEFT off-screen; the chevron stays right of it and
/// remains clickable.
@MainActor
final class MenuBarManager {
    static let shared = MenuBarManager()

    private(set) var state = MenuBarState()

    private var btnExpandCollapse: NSStatusItem?
    private var btnSeparate: NSStatusItem?
    private var autoHideTimer: Timer?
    private var heartbeatTimer: Timer?
    private var screenObserver: Any?
    private var wakeObservers: [Any] = []
    private var pendingReconcile: DispatchWorkItem?
    /// Consecutive reconciles that found the chevron's button window missing.
    private var deadButtonStrikes = 0

    private var isToggle = false

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
        if isToggle { return }
        isToggle = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isToggle = false
            }
        }
        if state.isExpanded { collapse() } else { expand() }
    }

    func collapse(userInitiated: Bool = true) {
        guard state.isExpanded else { return }
        guard isBtnSeparateValidPosition else {
            // If the user dragged them into an invalid order, auto-hide is
            // still allowed to fire but we refuse to collapse to prevent trapping.
            // Only warn on an explicit user click — the passive auto-hide timer
            // must not pop a focus-stealing modal with no user action.
            if userInitiated {
                NSSound.beep()
                showOrderWarningAlert()
            }
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

        createStatusItems()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }

        // Status-item button windows go transiently nil across App Nap and
        // sleep/wake — reconcile the visible chevron with `state` on wake so
        // a click that landed during the gap isn't stranded. Both notifications
        // are needed: screensDidWake covers display power-saving (idle dims/
        // blanks the screen without the Mac actually sleeping), didWake covers
        // full system sleep (lid closed, or idle sleep) — the more common
        // "left it backgrounded for a while" case.
        let wakeCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            let obs = wakeCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reconcile() }
            }
            wakeObservers.append(obs)
        }

        // Start expanded so the user can arrange icons before collapsing.
        state.expand()
        applyControl()
        resetAutoHideTimer()
        startHeartbeat()
    }

    private func createStatusItems() {
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
            // Right-click context menu
            separateItem.menu = getContextMenu()
        }
        btnSeparate = separateItem

        // Self-Healing UI: Cmd-dragging a status item off the bar is persisted
        // by macOS. Force visibility so the user is never permanently locked out.
        btnExpandCollapse?.isVisible = true
        btnSeparate?.isVisible = true
    }

    private func tearDown() {
        cancelAutoHideTimer()
        stopHeartbeat()
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
        let wakeCenter = NSWorkspace.shared.notificationCenter
        wakeObservers.forEach { wakeCenter.removeObserver($0) }
        wakeObservers.removeAll()
        pendingReconcile?.cancel()
        pendingReconcile = nil
    }

    // MARK: - Rendering

    private func applyControl() {
        guard let chevron = btnExpandCollapse, let sep = btnSeparate else { return }
        guard let cBtn = chevron.button else {
            // Button window is transiently nil (App Nap / display sleep /
            // monitor hot-plug). Silently giving up here used to leave
            // `state` and the on-screen chevron permanently desynced — the
            // next click would flip `state` again with no visible effect,
            // looking completely dead. Retry until the button is back.
            scheduleReconcile()
            return
        }
        pendingReconcile?.cancel()
        pendingReconcile = nil

        // Write-only-on-change: the heartbeat calls this every few seconds,
        // and rewriting NSStatusItem.length/title unconditionally forces a
        // menu bar relayout each time.
        let length = state.isExpanded ? btnHiddenLength : state.collapseWidth
        let glyph = state.isExpanded ? Self.expandedGlyph : Self.collapsedGlyph
        let tip = state.isExpanded
            ? "Hide the menu bar icons on the left"
            : "Show the hidden menu bar icons"
        if sep.length != length { sep.length = length }
        if cBtn.title != glyph { cBtn.title = glyph }
        if cBtn.toolTip != tip { cBtn.toolTip = tip }
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

    private func showOrderWarningAlert() {
        let alert = NSAlert()
        alert.messageText = "Menu Bar Order Error"
        alert.informativeText = """
        The chevron ( ‹ ) must be to the RIGHT of the separator ( | ).

        If it is to the left, collapsing the menu bar would hide the chevron itself and trap you!

        Please hold ⌘ (Command) and drag the chevron to the right of the separator in your menu bar.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Got it")
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
            collapse(userInitiated: false)
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
        reconcile()
    }

    /// Re-asserts visibility and re-applies `state` to the actual status
    /// items. Called after events known to transiently break the chevron —
    /// display/monitor reconfiguration and screen wake — and every few
    /// seconds by the heartbeat, so a stale visual (or a system-demoted,
    /// overflow-hidden item) doesn't strand the user.
    private func reconcile() {
        guard let chevron = btnExpandCollapse else { return }
        if chevron.isVisible == false { chevron.isVisible = true }
        if let sep = btnSeparate, sep.isVisible == false { sep.isVisible = true }

        // A button whose backing window stays gone is a dead status item —
        // clicks land nowhere and no amount of re-applying state revives it.
        // Three consecutive strikes (heartbeat-spaced, so screens had time to
        // wake) → rebuild both items from scratch. autosaveName preserves
        // their menu bar positions.
        if chevron.button?.window == nil {
            // Don't count strikes while the display itself is asleep — the
            // window is legitimately gone then, and rebuilding in that state
            // would churn items every heartbeat for the whole nap.
            if CGDisplayIsAsleep(CGMainDisplayID()) == 0 {
                deadButtonStrikes += 1
            }
            if deadButtonStrikes >= 3 {
                deadButtonStrikes = 0
                rebuildStatusItems()
                return
            }
        } else {
            deadButtonStrikes = 0
        }

        applyControl()
    }

    /// Tears down and recreates the two status items, preserving `state`.
    private func rebuildStatusItems() {
        if let item = btnExpandCollapse { NSStatusBar.system.removeStatusItem(item) }
        if let item = btnSeparate { NSStatusBar.system.removeStatusItem(item) }
        btnExpandCollapse = nil
        btnSeparate = nil
        createStatusItems()
        applyControl()
    }

    // MARK: - Heartbeat

    /// Periodic self-heal. Wake/screen-change notifications miss some of the
    /// ways macOS breaks status items (App Nap, spaces, overflow demotion) —
    /// the reported symptom was a chevron that randomly stops responding.
    /// The reconcile is cheap and write-only-on-change, so polling is safe.
    private func startHeartbeat() {
        stopHeartbeat()
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in MenuBarManager.shared.reconcile() }
        }
        timer.tolerance = 2
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func scheduleReconcile() {
        guard pendingReconcile == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingReconcile = nil
            self?.reconcile()
        }
        pendingReconcile = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func updateScreenWidth() {
        let maxWidth = NSScreen.screens.map(\.frame.width).max() ?? 1920
        state.updateScreenWidth(maxWidth)
    }
}
