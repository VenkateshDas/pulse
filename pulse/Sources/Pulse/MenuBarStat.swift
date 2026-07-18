import Foundation
import PulseKit

/// Tint state for one menu-bar stat. Anything above `.nominal` switches the
/// label out of template rendering so it can carry color.
enum MenuBarSeverity: Equatable {
    case nominal, charging, warning, critical
}

/// One stat's menu-bar display state: rounded value, state-specific SF
/// symbol, and tint severity. Equatable so the status item re-renders only
/// when something visible actually changes.
struct MenuBarReading: Equatable {
    let value: Int
    let symbol: String
    let severity: MenuBarSeverity
}

/// Which stat the menu-bar label shows. Raw value persisted in UserDefaults
/// (key `PulseMenuBarStat`); `.cpu` is the historical default.
enum MenuBarStat: String, CaseIterable, Identifiable {
    case cpu, memory, cpuTemp, battery

    var id: String { rawValue }

    /// Picker label in Settings.
    var label: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .cpuTemp: "CPU Temp"
        case .battery: "Battery"
        }
    }

    /// Menu-bar icon shown next to the value; the state-neutral fallback used
    /// when no reading is available (source missing → "--").
    var symbol: String {
        switch self {
        case .cpu: "waveform.path.ecg"
        case .memory: "memorychip"
        case .cpuTemp: "thermometer.medium"
        case .battery: "battery.100percent"
        }
    }

    #if DEBUG
        /// Debug hook to preview colored rendering without draining the battery:
        /// `defaults write com.pulse.app PulseMenuBarDebugSeverity warning|critical|charging`
        /// forces every stat's tint; prefix with a stat to target one
        /// (`battery:warning` tints only the battery group, the realistic case).
        /// `defaults delete` to clear. Debug builds only.
        private func debugSeverity() -> MenuBarSeverity? {
            guard let raw = UserDefaults.standard.string(forKey: "PulseMenuBarDebugSeverity")
            else { return nil }
            // Keep empty components so "battery:" and "a:b:warning" are
            // rejected instead of silently mis-targeting.
            let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { return nil }
            if parts.count == 2, parts[0] != Substring(rawValue) { return nil }
            switch parts.last.map(String.init) {
            case "charging": return .charging
            case "warning": return .warning
            case "critical": return .critical
            default: return nil
            }
        }
    #endif

    /// Full display state for the menu bar: value plus a state-dependent
    /// symbol and tint. nil when the source is unavailable.
    func reading(from snapshot: SystemSnapshot) -> MenuBarReading? {
        guard let live = liveReading(from: snapshot) else { return nil }
        #if DEBUG
            // Debug tint override colors the label but keeps the live symbol.
            if let forced = debugSeverity() {
                return MenuBarReading(value: live.value, symbol: live.symbol, severity: forced)
            }
        #endif
        return live
    }

    private func liveReading(from snapshot: SystemSnapshot) -> MenuBarReading? {
        guard let value = value(from: snapshot) else { return nil }
        switch self {
        case .cpu:
            return MenuBarReading(
                value: value, symbol: symbol, severity: Self.loadSeverity(value))
        case .memory:
            // No leveled memorychip symbol exists; .fill marks pressure.
            return MenuBarReading(
                value: value, symbol: value >= 85 ? "memorychip.fill" : "memorychip",
                severity: Self.loadSeverity(value))
        case .cpuTemp:
            let symbol =
                value < 60
                ? "thermometer.low" : value < 80 ? "thermometer.medium" : "thermometer.high"
            // Apple Silicon die temps sit at 90–105° under ordinary sustained
            // load; tint only when the SoC is genuinely near its limit.
            let severity: MenuBarSeverity =
                value >= 100 ? .critical : value >= 90 ? .warning : .nominal
            return MenuBarReading(value: value, symbol: symbol, severity: severity)
        case .battery:
            // SF Symbols only ship 0/25/50/75/100 fills; round to nearest.
            let level = min(100, max(0, (value + 12) / 25 * 25))
            let symbol = "battery.\(level)percent"
            // Charging: keep the true fill level (no leveled .bolt symbols
            // exist) and let the green tint carry the "charging" signal. The
            // colored period is bounded — IOKit reports IsCharging=false once
            // full or held by Optimized Charging.
            if snapshot.battery?.isCharging == true {
                return MenuBarReading(value: value, symbol: symbol, severity: .charging)
            }
            let severity: MenuBarSeverity =
                value <= AlertsEngine.batteryLowThreshold
                ? .critical : value <= 20 ? .warning : .nominal
            return MenuBarReading(value: value, symbol: symbol, severity: severity)
        }
    }

    /// Shared tint thresholds for CPU % and memory %. Deliberately quieter
    /// than the dashboard's `Halo.statusColor` bands (60/85): the menu bar is
    /// always visible, so it colors only when action is likely needed, while
    /// the dashboard rings grade continuously.
    private static func loadSeverity(_ percent: Int) -> MenuBarSeverity {
        percent >= 95 ? .critical : percent >= 85 ? .warning : .nominal
    }

    /// Integer for the label; nil when the source is unavailable (no battery
    /// on desktops, SMC temp not readable) — rendered as "--".
    func value(from snapshot: SystemSnapshot) -> Int? {
        switch self {
        case .cpu: Int(snapshot.cpuTotalPercent.rounded())
        case .memory: Int((snapshot.memoryUsedFraction * 100).rounded())
        case .cpuTemp: snapshot.sensors.cpuTempC.map { Int($0.rounded()) }
        case .battery: snapshot.battery?.currentChargePercent
        }
    }

    /// Fixed-width label text — menu bar items must not jiggle as values change.
    /// Pads with U+2007 figure space (digit-width in tabular-digit fonts).
    func text(for value: Int?) -> String {
        let figureSpace = "\u{2007}"
        guard let value else { return figureSpace + figureSpace + "--" }
        let digits = String(value)
        let padded = String(repeating: figureSpace, count: max(0, 3 - digits.count)) + digits
        return padded + (self == .cpuTemp ? "°" : "%")
    }
}
