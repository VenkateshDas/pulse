import Foundation
import PulseKit

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

    /// Menu-bar icon shown next to the value.
    var symbol: String {
        switch self {
        case .cpu: "waveform.path.ecg"
        case .memory: "memorychip"
        case .cpuTemp: "thermometer.medium"
        case .battery: "battery.100percent"
        }
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
    func text(for value: Int?) -> String {
        guard let value else { return "  --" }
        switch self {
        case .cpuTemp: return String(format: "%3ld°", value)
        default: return String(format: "%3ld%%", value)
        }
    }
}
