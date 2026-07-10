import Foundation
import Observation

/// Transient menu-bar icon feedback: when an action fires (hotkey or UI),
/// the main status-item icon swaps to the action's symbol for a few seconds
/// so otherwise-silent actions are visible, then reverts.
@MainActor @Observable
public final class MenuBarFlash {
    public static let shared = MenuBarFlash()

    /// Symbol to show instead of the default menu-bar icon; nil = default.
    public private(set) var symbol: String?

    private var clearTask: Task<Void, Never>?

    private init() {}

    public func flash(_ symbol: String, for seconds: TimeInterval = 3) {
        self.symbol = symbol
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.symbol = nil
        }
    }
}
