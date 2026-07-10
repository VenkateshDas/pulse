import Foundation

/// Controls how much raw system detail Pulse surfaces at once. `.simple`
/// leads with plain-language verdicts and gates jargon (load average,
/// per-core splits, process tables) behind an explicit "show details" tap.
/// `.pro` shows everything today's dashboard already shows.
enum DisplayMode: String, CaseIterable, Identifiable {
    case simple = "Simple"
    case pro = "Pro"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .simple: "Plain-English overview. Full detail is always one tap away."
        case .pro: "Every metric, all the time — the full instrument panel."
        }
    }
}

/// Persists the chosen `DisplayMode` and derives a sensible default when no
/// choice has been made yet.
@MainActor
@Observable
final class DisplayModeManager {
    static let shared = DisplayModeManager()

    private static let key = "PulseDisplayMode"

    private(set) var current: DisplayMode
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.key), let saved = DisplayMode(rawValue: raw) {
            current = saved
        } else {
            current = Self.defaultMode(onboardingAlreadyComplete: defaults.bool(forKey: OnboardingView.completeKey))
        }
    }

    func set(_ mode: DisplayMode) {
        current = mode
        defaults.set(mode.rawValue, forKey: Self.key)
    }

    /// No explicit choice saved yet: an install where onboarding had already
    /// completed before this feature shipped is an existing user — default
    /// them to `.pro` so nothing changes underfoot. A fresh install (no
    /// onboarding-complete flag either) defaults to `.simple`.
    static func defaultMode(onboardingAlreadyComplete: Bool) -> DisplayMode {
        onboardingAlreadyComplete ? .pro : .simple
    }
}
