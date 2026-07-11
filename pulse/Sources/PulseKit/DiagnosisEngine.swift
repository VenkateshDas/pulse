import Foundation

/// One-line verdict on system state plus the process to blame, if any.
/// Mirrors mole's `statusDiagnosisLine` priority cascade
/// (CPU → memory pressure → disk → battery → thermal), reimplemented in Swift.
public struct Diagnosis: Sendable, Equatable {
    public enum Severity: Int, Sendable, Comparable {
        case clear, info, warn, critical
        public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
    }

    /// e.g. "Chrome high CPU", "Disk low, 12 GB free", "All clear".
    public let line: String
    public let severity: Severity
    /// PID of the culprit process for deep-linking to Monitor; nil if none.
    public let culpritPID: Int32?
    /// Which metric triggered the verdict; nil when all clear.
    public let factor: HealthFactor?

    public init(line: String, severity: Severity, culpritPID: Int32?, factor: HealthFactor?) {
        self.line = line
        self.severity = severity
        self.culpritPID = culpritPID
        self.factor = factor
    }
}

public enum DiagnosisEngine {
    /// Process is "leading" a resource if it alone exceeds this CPU share.
    static let leadingCPUFloor = 50.0

    static func shorten(_ name: String, _ max: Int = 18) -> String {
        name.count <= max ? name : String(name.prefix(max - 1)) + "…"
    }

    /// Blame is attributed to app groups, not lone helpers — five 12% Chrome
    /// helpers read as "Chrome (5)" and their sum trips the floor.
    static func leadingCPUProcess(_ procs: [ProcessSample]) -> ProcessGroup? {
        ProcessGrouper.group(procs).first.flatMap {
            $0.cpuPercent >= leadingCPUFloor ? $0 : nil
        }
    }

    static func blame(_ g: ProcessGroup) -> String {
        g.count > 1 ? "\(shorten(g.name)) (\(g.count))" : shorten(g.name)
    }

    public static func evaluate(_ s: SystemSnapshot, leak: LeakAlert? = nil) -> Diagnosis {
        // 1 · CPU
        if s.cpuTotalPercent > HealthFactor.cpu.high {
            if let p = leadingCPUProcess(s.topProcesses) {
                return Diagnosis(line: "\(blame(p)) high CPU",
                                 severity: .critical, culpritPID: p.topPID, factor: .cpu)
            }
            return Diagnosis(line: "CPU load high", severity: .critical,
                             culpritPID: nil, factor: .cpu)
        }

        // 2 · Memory pressure
        switch s.memoryPressure {
        case .critical, .warning:
            let sev: Diagnosis.Severity = s.memoryPressure == .critical ? .critical : .warn
            if let p = leadingMemoryProcess(s.topProcesses) {
                return Diagnosis(line: "\(blame(p)) memory pressure",
                                 severity: sev, culpritPID: p.topPID, factor: .memory)
            }
            return Diagnosis(line: "Memory pressure", severity: sev,
                             culpritPID: nil, factor: .memory)
        case .normal:
            break
        }

        // 2b · Confirmed memory leak — outranks a full disk, not active pressure.
        if let leak {
            return Diagnosis(line: "\(shorten(leak.name)) leaking memory",
                             severity: .warn, culpritPID: leak.pid, factor: .memory)
        }

        // 3 · Disk
        let diskPct = s.diskUsedFraction * 100
        if diskPct > HealthFactor.disk.high {
            return Diagnosis(line: "Disk low, \(ByteFormat.string(s.diskFreeBytes)) free",
                             severity: .critical, culpritPID: nil, factor: .disk)
        }

        // 4 · Battery service condition
        if let b = s.battery, b.condition != "Normal" {
            return Diagnosis(line: "Battery: \(b.condition.lowercased())",
                             severity: .warn, culpritPID: nil, factor: nil)
        }

        // 5 · Thermal
        if s.thermal >= .serious || (s.sensors.cpuTempC ?? 0) > HealthFactor.thermal.high {
            return Diagnosis(line: "Running hot", severity: .warn,
                             culpritPID: nil, factor: .thermal)
        }

        // 6 · Soft warnings (above normal but below high)
        if s.cpuTotalPercent > HealthFactor.cpu.normal,
           let p = leadingCPUProcess(s.topProcesses) {
            return Diagnosis(line: "\(blame(p)) busy", severity: .info,
                             culpritPID: p.topPID, factor: .cpu)
        }
        if diskPct > HealthFactor.disk.normal {
            return Diagnosis(line: "Disk filling up", severity: .info,
                             culpritPID: nil, factor: .disk)
        }

        return Diagnosis(line: "All clear", severity: .clear, culpritPID: nil, factor: nil)
    }

    /// Largest-resident group, used to attribute memory pressure.
    static func leadingMemoryProcess(_ procs: [ProcessSample]) -> ProcessGroup? {
        ProcessGrouper.group(procs).max(by: { $0.residentBytes < $1.residentBytes })
    }
}
