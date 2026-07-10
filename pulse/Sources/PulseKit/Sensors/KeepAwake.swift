import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac awake via an IOKit power assertion — same mechanism as
/// KeepingYouAwake/caffeinate. `PreventUserIdleDisplaySleep` stops both the
/// display and idle system sleep; the assertion dies with the process, so a
/// crash or quit can never leave the Mac stuck awake.
@MainActor @Observable
public final class KeepAwakeController {
    public static let shared = KeepAwakeController()

    /// The assertion ID is the single source of truth; 0 = inactive.
    public var isActive: Bool { assertionID != 0 }
    /// When a timed activation ends; nil while inactive or indefinite.
    public private(set) var expiresAt: Date?
    /// True when the last activate() failed to create the assertion.
    public private(set) var lastActivationFailed = false

    private var assertionID: IOPMAssertionID = 0
    private var expiryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// Bumped on every activate/deactivate so a stale expiry fire can't
    /// kill a freshly re-activated session.
    private var session = 0

    /// Menu choices. nil duration = indefinitely.
    public static let durations: [(label: String, seconds: TimeInterval?)] = [
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
    public func activate(for duration: TimeInterval? = nil) {
        deactivate()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Pulse — Keep Awake" as CFString,
            &id)
        guard result == kIOReturnSuccess else {
            lastActivationFailed = true
            return
        }
        lastActivationFailed = false
        assertionID = id
        MenuBarFlash.shared.flash("cup.and.saucer.fill")
        guard let duration else { return }

        expiresAt = Date().addingTimeInterval(duration)
        let expiringSession = session
        // .common modes so expiry still fires while a menu is being tracked.
        let timer = Timer(timeInterval: duration, repeats: false) { _ in
            Task { @MainActor in
                let shared = KeepAwakeController.shared
                if shared.session == expiringSession { shared.deactivate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer

        // NSTimer pauses during manual sleep (lid close) while the wall-clock
        // deadline keeps running — end overdue sessions right on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let shared = KeepAwakeController.shared
                if let expiry = shared.expiresAt, expiry <= Date() { shared.deactivate() }
            }
        }
    }

    public func deactivate() {
        session &+= 1
        expiryTimer?.invalidate()
        expiryTimer = nil
        expiresAt = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            // Outline cup = turned off. activate() re-flashes filled right
            // after when this deactivate was just a re-activation reset.
            MenuBarFlash.shared.flash("cup.and.saucer")
        }
    }

    private static let remainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// "42m left" / "1h 5m left" for the popover row.
    public var remainingText: String? {
        guard let expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSinceNow
        guard remaining >= 60 else { return "<1 min left" }
        return Self.remainingFormatter.string(from: remaining).map { "\($0) left" }
    }
}
