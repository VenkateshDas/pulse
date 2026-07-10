import AppKit
import Observation

/// Global theme selection, persisted across relaunch. Same singleton access
/// pattern as `AppActivation.shared` / `MenuBarManager.shared` — read
/// directly from `Halo`'s computed tokens, no environment injection needed.
@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var selected: AppTheme

    /// Mirror of `selected.palette`, kept in sync on every `select(_:)`.
    /// `Halo`'s token accessors read this directly (not `shared.selected`)
    /// so they stay `nonisolated` like every other type in the codebase that
    /// consumes them — `Halo` is a passive color lookup table, always read
    /// from UI code already confined to the main thread, and `ThemeManager`
    /// (main-actor) is the sole writer.
    nonisolated(unsafe) static var currentPalette: Palette = AppTheme.precision.palette

    private static let key = "pulse.theme"

    private init() {
        let theme = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(AppTheme.init(rawValue:)) ?? .precision
        selected = theme
        Self.currentPalette = theme.palette
        applyAppearance()
    }

    func select(_ theme: AppTheme) {
        guard theme != selected else { return }
        selected = theme
        Self.currentPalette = theme.palette
        UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
        applyAppearance()
    }

    private func applyAppearance() {
        if let name = selected.forcedAppearance {
            NSApp.appearance = NSAppearance(named: name)
        } else {
            NSApp.appearance = nil
        }
    }
}
