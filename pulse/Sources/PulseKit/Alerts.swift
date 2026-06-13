import Foundation

/// One "Needs Attention" card: what's wrong, the evidence, and the fix.
public struct PulseAlert: Sendable, Equatable, Identifiable {
    public enum Severity: Sendable, Equatable {
        case info, warning, critical
    }

    public enum Action: Sendable, Equatable {
        /// Offer to terminate the offending process.
        case quitProcess(pid: Int32, name: String)
        /// Show explanatory detail text.
        case showDetails(String)
    }

    /// Stable rule identifier — keeps SwiftUI from tearing cards down when
    /// only the numbers inside them change.
    public let id: String
    public let severity: Severity
    public let symbol: String  // SF Symbol name
    public let title: String
    public let subtitle: String
    public let actions: [Action]

    public init(
        id: String, severity: Severity, symbol: String,
        title: String, subtitle: String, actions: [Action]
    ) {
        self.id = id
        self.severity = severity
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
    }
}

/// Pure rules: snapshot in, alert cards out. No side effects, fully testable.
public enum AlertsEngine {
    static let cpuHogThreshold = 80.0
    static let lowDiskThreshold: UInt64 = 20_000_000_000
    static let heavySwapThreshold: UInt64 = 4_000_000_000
    /// Apple flags a battery for service below this maximum-capacity ratio.
    static let batteryDegradedThreshold = 80
    /// Charge level (on battery) that warrants a low-battery nudge.
    static let batteryLowThreshold = 10

    /// Processes that legitimately hold sleep assertions all day.
    static let sleepAssertionAllowlist: Set<String> = [
        "powerd", "bluetoothd", "coreaudiod", "apsd", "backupd", "cloudd",
    ]

    public static func evaluate(_ snapshot: SystemSnapshot, ownPID: Int32 = -1) -> [PulseAlert] {
        var alerts: [PulseAlert] = []

        if let hog = snapshot.topProcesses.first,
            hog.cpuPercent >= cpuHogThreshold, hog.pid != ownPID
        {
            let share =
                snapshot.cpuTotalPercent > 0
                ? Int(
                    min(
                        100,
                        hog.cpuPercent / (snapshot.cpuTotalPercent * Double(max(snapshot.cpuPerCore.count, 1)))
                            * 100
                    ))
                : 0
            alerts.append(
                PulseAlert(
                    id: "cpu-hog",
                    severity: .warning,
                    symbol: "thermometer.high",
                    title: "\(hog.name) is using \(Int(hog.cpuPercent))% CPU — \(share)% of total load",
                    subtitle:
                        "pid \(hog.pid) · \(ByteFormat.string(hog.residentBytes)) resident · sustained over the last sample",
                    actions: [.quitProcess(pid: hog.pid, name: hog.name)]
                ))
        }

        if snapshot.diskFreeBytes > 0, snapshot.diskFreeBytes < lowDiskThreshold {
            alerts.append(
                PulseAlert(
                    id: "low-disk",
                    severity: .critical,
                    symbol: "externaldrive.fill.badge.exclamationmark",
                    title: "Only \(ByteFormat.string(snapshot.diskFreeBytes)) free on the startup disk",
                    subtitle: "macOS slows down and updates fail below ~20 GB free",
                    actions: [
                        .showDetails(
                            "Free space includes purgeable storage. The Clean module (coming in M3) will find safe space here."
                        )
                    ]
                ))
        }

        if snapshot.memoryPressure != .normal || snapshot.swapUsedBytes >= heavySwapThreshold {
            let level = snapshot.memoryPressure == .critical ? "critical" : "elevated"
            alerts.append(
                PulseAlert(
                    id: "memory-pressure",
                    severity: snapshot.memoryPressure == .critical ? .critical : .warning,
                    symbol: "memorychip",
                    title: "Memory pressure is \(level)",
                    subtitle:
                        "swap \(ByteFormat.string(snapshot.swapUsedBytes)) · \(ByteFormat.string(snapshot.memoryUsedBytes)) of \(ByteFormat.string(snapshot.memoryTotalBytes)) used",
                    actions: [
                        .showDetails(
                            "macOS is compressing and swapping memory. Closing the biggest apps in Top Processes relieves it fastest."
                        )
                    ]
                ))
        }

        if snapshot.thermal >= .serious {
            alerts.append(
                PulseAlert(
                    id: "thermal",
                    severity: .critical,
                    symbol: "flame.fill",
                    title: "Your Mac is running hot — performance is being throttled",
                    subtitle: "macOS thermal state: \(snapshot.thermal == .critical ? "critical" : "serious")",
                    actions: [
                        .showDetails(
                            "Check Top Processes for the heaviest CPU user, improve airflow, and unplug unused peripherals."
                        )
                    ]
                ))
        }

        if let battery = snapshot.battery {
            if battery.capacityPercent > 0, battery.capacityPercent < batteryDegradedThreshold {
                alerts.append(
                    PulseAlert(
                        id: "battery-degraded",
                        severity: .warning,
                        symbol: "battery.25",
                        title: "Battery health is at \(battery.capacityPercent)% of original capacity",
                        subtitle:
                            "\(battery.cycleCount) cycles · condition: \(battery.condition) — Apple recommends service below 80%",
                        actions: [
                            .showDetails(
                                "Maximum capacity has dropped below 80%. Runtime per charge is reduced; a battery replacement restores it."
                            )
                        ]
                    ))
            }
            if !battery.isOnAC, battery.currentChargePercent > 0,
                battery.currentChargePercent <= batteryLowThreshold
            {
                alerts.append(
                    PulseAlert(
                        id: "battery-low",
                        severity: .warning,
                        symbol: "battery.0",
                        title: "Battery low — \(battery.currentChargePercent)% remaining",
                        subtitle: "Running on battery — connect power to avoid an unexpected shutdown",
                        actions: [
                            .showDetails(
                                "Close heavy apps in Top Processes to extend the remaining runtime until you can charge."
                            )
                        ]
                    ))
            }
        }

        let blockers = snapshot.sleepAssertions.filter {
            !sleepAssertionAllowlist.contains($0.processName)
        }
        if !blockers.isEmpty {
            let names = Array(Set(blockers.map(\.processName))).sorted().joined(separator: ", ")
            let detail = blockers.map { "\($0.processName): \($0.assertionName)" }
                .joined(separator: "\n")
            alerts.append(
                PulseAlert(
                    id: "sleep-blockers",
                    severity: .info,
                    symbol: "moon.zzz.fill",
                    title: "\(names) \(blockers.count == 1 ? "is" : "are") preventing sleep",
                    subtitle: "assertion: PreventUserIdleSystemSleep — battery drains while idle",
                    actions: [.showDetails(detail)]
                ))
        }

        return alerts
    }
}
