import Foundation

/// Pure state machine for menu bar item hiding. Separates logic from AppKit
/// so it can be unit-tested without NSStatusItem. Drives a single status item
/// that inflates to `collapseWidth` when collapsed (pushing items off-screen)
/// and auto-sizes when expanded.
public struct MenuBarState: Sendable {
    public enum Phase: Sendable { case collapsed, expanded }

    public private(set) var phase: Phase
    public var isEnabled: Bool
    public var autoHideDelay: TimeInterval

    public var isCollapsed: Bool { phase == .collapsed }
    public var isExpanded: Bool { phase == .expanded }

    /// Width to inflate the control to so everything on its left is pushed
    /// off-screen: 2× the widest screen, capped at the macOS 10,000pt ceiling.
    public var collapseWidth: CGFloat {
        min(screenWidth * 2, 10_000)
    }

    /// Whether the auto-hide timer should be active (expanded + delay > 0).
    public var shouldAutoHide: Bool {
        isExpanded && autoHideDelay > 0
    }

    private var screenWidth: CGFloat

    public init(
        isEnabled: Bool = true,
        autoHideDelay: TimeInterval = 10,
        screenWidth: CGFloat = 1920
    ) {
        self.phase = .collapsed
        self.isEnabled = isEnabled
        self.autoHideDelay = autoHideDelay
        self.screenWidth = screenWidth
    }

    public mutating func toggle() {
        phase = isCollapsed ? .expanded : .collapsed
    }

    public mutating func collapse() { phase = .collapsed }
    public mutating func expand() { phase = .expanded }

    /// Recompute collapse width when displays change.
    public mutating func updateScreenWidth(_ width: CGFloat) {
        screenWidth = width
    }
}
