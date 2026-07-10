import Foundation
import PulseKit

/// Pure string-builders for the Dashboard vital cards, split out from
/// `DashboardView` so the Simple/Pro copy differences are unit-testable
/// without SwiftUI. `.pro` reproduces the original jargon-dense lines
/// unchanged; `.simple` drops load average, E/P core split, GPU%, swap, and
/// per-sensor thermal breakdown in favor of one plain sentence.
enum DashboardFormatting {

    // MARK: - CPU

    static func cpuLine1(mode: DisplayMode, efficiencyPercent: Int?, performancePercent: Int?, coreCount: Int, gpuPercent: Double?) -> String {
        switch mode {
        case .pro:
            let split: String
            if let e = efficiencyPercent, let p = performancePercent {
                split = String(format: "E %2d%% · P %2d%%", e, p)
            } else {
                split = "\(coreCount) cores"
            }
            let gpuStr = gpuPercent.map { String(format: " · GPU %1.0f%%", $0) } ?? ""
            return split + gpuStr
        case .simple:
            return "\(coreCount) core\(coreCount == 1 ? "" : "s")"
        }
    }

    /// `nil` means the line is omitted entirely (Simple mode).
    static func cpuLine2(mode: DisplayMode, loadAverage1m: Double) -> String? {
        switch mode {
        case .pro: String(format: "load %5.2f", loadAverage1m)
        case .simple: nil
        }
    }

    // MARK: - Memory

    static func memoryLine1(mode: DisplayMode, usedBytes: UInt64, freeBytes: UInt64) -> String {
        switch mode {
        case .pro: "U: \(ByteFormat.string(usedBytes)) · F: \(ByteFormat.string(freeBytes))"
        case .simple: "\(ByteFormat.string(usedBytes)) used · \(ByteFormat.string(freeBytes)) free"
        }
    }

    /// `nil` means the line is omitted entirely (Simple mode) — swap and the
    /// wired/compressed breakdown are Pro-only detail.
    static func memoryLine2(mode: DisplayMode, swapUsedBytes: UInt64, pressureSuffix: String) -> String? {
        switch mode {
        case .pro: "Swap \(ByteFormat.string(swapUsedBytes))\(pressureSuffix)"
        case .simple: nil
        }
    }

    /// Whether to pass the App/Wired/Compressed segmented breakdown + legend
    /// into the memory VitalCard at all.
    static func showsMemoryBreakdown(mode: DisplayMode) -> Bool { mode == .pro }

    // MARK: - Thermal

    static func thermalLine1(mode: DisplayMode, cpuTempC: Double?, gpuTempC: Double?) -> String {
        switch mode {
        case .pro:
            return [
                cpuTempC.map { String(format: "CPU %2.0f°", $0) },
                gpuTempC.map { String(format: "GPU %2.0f°", $0) },
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        case .simple:
            guard let hottest = [cpuTempC, gpuTempC].compactMap({ $0 }).max() else { return "" }
            if hottest < 70 { return "Running cool" }
            if hottest < 90 { return "Getting warm" }
            return "Running hot"
        }
    }

    /// `nil` means the line is omitted entirely (Simple mode) — battery
    /// temp, fan RPM and wattage are Pro-only detail.
    static func thermalLine2(mode: DisplayMode, parts: [String]) -> String? {
        switch mode {
        case .pro: parts.joined(separator: " · ")
        case .simple: nil
        }
    }

    static func showsThermalStats(mode: DisplayMode) -> Bool { mode == .pro }

    static func thermalFallbackLine2(mode: DisplayMode) -> String {
        mode == .pro ? "no SMC sensors found" : "no sensors on this Mac"
    }
}
