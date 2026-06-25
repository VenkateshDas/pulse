import Foundation
import CoreGraphics
import Cocoa
import MediaKeyTap

// 1/16 — matches macOS's native 16-step brightness granularity.
private let kBrightnessStep: Double = 0.0625

/// Intercepts physical brightness media keys and routes them through
/// ``BrightnessEngine`` instead of macOS's built-in handler.
///
/// Uses `MediaKeyTap` (alin23) which internally creates an
/// `IOHIDManager` when `observeBuiltIn: true`.  This is the only
/// reliable way to catch brightness keys on Apple Silicon — they are
/// processed at the IOKit HID layer, below CGEvents.
///
/// An `NSEvent.addGlobalMonitorForEvents` fallback is always installed
/// for the case where Accessibility is not granted.
public final class MediaKeyManager: @unchecked Sendable, MediaKeyTapDelegate {
    public static let shared = MediaKeyManager()

    private var tap: MediaKeyTap?
    private var globalMonitor: Any?
    private var accessibilityPollTimer: Timer?

    private init() {}

    // MARK: - Public

    @MainActor
    public func isTrusted(prompt: Bool = false) -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    @MainActor
    public func start() {
        // Tier 1: MediaKeyTap (IOHIDManager + CGEvent tap — needs Accessibility)
        if isTrusted(prompt: false) {
            startMediaKeyTap()
        } else {
            print("[MediaKeys] No Accessibility — MediaKeyTap skipped, fallback only.")
            startAccessibilityPoll()
        }

        // Tier 2: NSEvent global monitor (always works, no permissions)
        startGlobalMonitor()
    }

    /// Polls every 2s until Accessibility is granted, then starts Tier 1.
    @MainActor
    private func startAccessibilityPoll() {
        guard accessibilityPollTimer == nil else { return }
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.isTrusted(prompt: false) else { return }
                self.accessibilityPollTimer?.invalidate()
                self.accessibilityPollTimer = nil
                self.startMediaKeyTap()
                print("[MediaKeys] Accessibility granted — MediaKeyTap started.")
            }
        }
    }

    public func stop() {
        tap?.stop()
        tap = nil
        if let mon = globalMonitor {
            NSEvent.removeMonitor(mon)
            globalMonitor = nil
        }
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
    }

    // MARK: - Tier 1: MediaKeyTap

    @MainActor
    private func startMediaKeyTap() {
        guard tap == nil else { return }
        tap = MediaKeyTap(
            delegate: self,
            on: .keyDown,
            for: [.brightnessUp, .brightnessDown],
            observeBuiltIn: true               // ← IOHIDManager path
        )
        tap?.start()
        print("[MediaKeys] MediaKeyTap active — brightness keys intercepted (IOHIDManager + CGEvent tap).")
    }

    // MARK: - MediaKeyTapDelegate

    public func handle(
        mediaKey: MediaKey,
        event: KeyEvent?,
        modifiers: NSEvent.ModifierFlags?,
        event cgEvent: CGEvent
    ) -> CGEvent? {
        guard mediaKey == .brightnessUp || mediaKey == .brightnessDown else {
            return cgEvent
        }

        let delta = mediaKey == .brightnessUp ? kBrightnessStep : -kBrightnessStep

        guard let mouseLoc = CGEvent(source: nil)?.location else { return nil }
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(mouseLoc, 1, &displayID, &count) == .success,
              count > 0 else { return nil }

        Task { @MainActor in
            let engine = BrightnessEngine.shared
            guard let monitor = engine.monitors.first(where: { $0.id == displayID }) else { return }
            engine.adjustBrightness(for: monitor, delta: delta)
        }

        return nil   // consume — blocks macOS OSD
    }

    // MARK: - Tier 2: NSEvent global monitor (fallback)

    @MainActor
    private func startGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { event in
            guard event.subtype.rawValue == 8 else { return }
            let data1    = event.data1
            let keyCode  = (data1 & 0xFFFF_0000) >> 16
            let keyState = (data1 & 0x0000_FF00) >> 8
            guard (keyCode == 2 || keyCode == 3), keyState == 0x0A else { return }

            let isUp = keyCode == 2
            Task { @MainActor in
                Self.handleFallbackBrightness(isUp: isUp)
            }
        }
        print("[MediaKeys] NSEvent global monitor active (fallback).")
    }

    /// Fallback path — macOS already changed the hardware, so for
    /// built-in displays we just sync our map.  For external monitors
    /// macOS doesn't touch them, so we apply our own DDC delta.
    @MainActor
    private static func handleFallbackBrightness(isUp: Bool) {
        guard let mouseLoc = CGEvent(source: nil)?.location else { return }
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(mouseLoc, 1, &displayID, &count) == .success,
              count > 0 else { return }

        let engine = BrightnessEngine.shared
        guard let monitor = engine.monitors.first(where: { $0.id == displayID }) else { return }

        if monitor.isBuiltIn {
            // macOS already adjusted hardware — read back & sync map.
            let hw = engine.getBrightness(for: monitor)
            engine.brightnessMap[monitor.id] = hw
            engine.saveBrightnessMap()
        } else {
            let delta = isUp ? kBrightnessStep : -kBrightnessStep
            engine.adjustBrightness(for: monitor, delta: delta)
        }
    }
}
