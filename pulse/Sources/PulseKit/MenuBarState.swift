import Foundation

/// Pure state machine for menu bar item hiding. Separates logic from AppKit
/// so it can be unit-tested without NSStatusItem.
public struct MenuBarState: Sendable {
    public enum Phase: Sendable { case collapsed, expanded }

    public private(set) var phase: Phase
    public var isEnabled: Bool
    public var autoHideDelay: TimeInterval
    public var showSeparator: Bool

    public var isCollapsed: Bool { phase == .collapsed }
    public var isExpanded: Bool { phase == .expanded }

    /// Width to inflate separator to push items off-screen.
    public var collapseWidth: CGFloat {
        // 2x widest connected screen, capped at 10_000.
        min(screenWidth * 2, 10_000)
    }

    /// Normal separator width (visible divider).
    public static let separatorWidth: CGFloat = 20

    /// Chevron symbol for current state.
    public var chevronSymbol: String {
        isCollapsed ? "chevron.right.2" : "chevron.left.2"
    }

    private var screenWidth: CGFloat

    public init(
        isEnabled: Bool = true,
        autoHideDelay: TimeInterval = 10,
        showSeparator: Bool = true,
        screenWidth: CGFloat = 1920
    ) {
        self.phase = .collapsed
        self.isEnabled = isEnabled
        self.autoHideDelay = autoHideDelay
        self.showSeparator = showSeparator
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

    /// The length to set on the separator NSStatusItem.
    public var separatorLength: CGFloat {
        switch phase {
        case .collapsed: collapseWidth
        case .expanded: showSeparator ? Self.separatorWidth : 0
        }
    }

    /// Whether auto-hide timer should be active (expanded + delay > 0).
    public var shouldAutoHide: Bool {
        isExpanded && autoHideDelay > 0
    }
}
