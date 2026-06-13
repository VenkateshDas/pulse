import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// Sparkle auto-updater wrapper. Compiles with OR without the Sparkle SPM
/// dependency via `#if canImport(Sparkle)`: when Sparkle isn't linked,
/// `checkForUpdates()` is a no-op and `isAvailable` is false, so the patched-CLT
/// offline build keeps working and the UI hides the menu item.
///
/// To enable updates:
///   1. Add the Sparkle dependency in Package.swift (see the commented block).
///   2. Set `SUFeedURL` (appcast XML) + `SUPublicEDKey` in the bundle Info.plist
///      (bundle.sh already seeds the keys).
///   3. Rebuild — this controller wires up automatically.
@MainActor
final class Updater {
    static let shared = Updater()

    #if canImport(Sparkle)
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    /// True only when the Sparkle framework is linked into this build.
    var isAvailable: Bool {
        #if canImport(Sparkle)
        return true
        #else
        return false
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        controller.updater.checkForUpdates()
        #endif
    }
}
