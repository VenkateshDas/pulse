import Foundation
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac awake via an IOKit power assertion — same mechanism as
/// KeepingYouAwake/caffeinate. `PreventUserIdleDisplaySleep` stops both the
/// display and idle system sleep; the assertion dies with the process, so a
/// crash or quit can never leave the Mac stuck awake.
@MainActor @Observable
final class KeepAwakeController {
    static let shared = KeepAwakeController()

    private(set) var isActive = false
    /// When a timed activation ends; nil while inactive or indefinite.
    private(set) var expiresAt: Date?

    private var assertionID: IOPMAssertionID = 0
    private var expiryTimer: Timer?

    /// Menu choices. nil duration = indefinitely.
    static let durations: [(label: String, seconds: TimeInterval?)] = [
        ("Indefinitely", nil),
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour", 3600),
        ("2 hours", 2 * 3600),
        ("4 hours", 4 * 3600),
        ("8 hours", 8 * 3600),
    ]

    private init() {}

    /// Activate (or re-activate with a new duration).
    func activate(for duration: TimeInterval? = nil) {
        deactivate()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Pulse — Keep Awake" as CFString,
            &id)
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isActive = true
        if let duration {
            expiresAt = Date().addingTimeInterval(duration)
            expiryTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                Task { @MainActor in KeepAwakeController.shared.deactivate() }
            }
        }
    }

    func deactivate() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        expiresAt = nil
        if isActive {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isActive = false
        }
    }

    /// "42 min left" / "1 h 05 min left" for the popover row.
    var remainingText: String? {
        guard let expiresAt else { return nil }
        let remaining = max(0, expiresAt.timeIntervalSinceNow)
        let minutes = Int(remaining.rounded(.up) / 60)
        if minutes >= 60 {
            return String(format: "%d h %02d min left", minutes / 60, minutes % 60)
        }
        return "\(max(minutes, 1)) min left"
    }
}
