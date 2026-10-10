import Foundation

public struct ObservationPoint: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let intervalSeconds: Double
    public let cpuPercent: Double?
    public let memoryPressure: String?
    public let swapUsedBytes: UInt64?
    public let compressedBytes: UInt64?
    public let activity: ActivityReadings
    public let coverage: ProcessCoverage
    public let thermal: String

    public init(snapshot: SystemSnapshot, interval: Double) {
        timestamp = snapshot.timestamp; intervalSeconds = interval
        cpuPercent = snapshot.activity.unavailable.contains("CPU counters unavailable") ? nil : snapshot.cpuTotalPercent
        memoryPressure = snapshot.activity.unavailable.contains("Memory pressure unavailable") ? nil : "\(snapshot.memoryPressure)"
        swapUsedBytes = snapshot.activity.unavailable.contains("Swap occupancy unavailable") ? nil : snapshot.swapUsedBytes
        compressedBytes = snapshot.activity.unavailable.contains("VM statistics unavailable") ? nil : snapshot.memoryCompressedBytes
        activity = snapshot.activity; coverage = snapshot.processCoverage
        thermal = "\(snapshot.thermal)"
    }
}

public struct ObservationContributor: Codable, Sendable, Equatable {
    public let name: String
    public var meanCPUPercent: Double
    public var peakCPUPercent: Double
    public var residentBytes: UInt64
    public var peakResidentBytes: UInt64
    public var representative: ProcessIdentity?
    public var memoryRepresentative: ProcessIdentity? = nil
}

public struct ObservationReport: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let startedAt: Date
    public let endedAt: Date
    public let durationSeconds: Double
    public let samples: [ObservationPoint]
    public let contributors: [ObservationContributor]
    public let memoryContributors: [ObservationContributor]
    public let findings: [String]
    public let limitations: [String]
    public let meanCPUPercent: Double?
    public let peakCPUPercent: Double?

    public static func summarize(points: [ObservationPoint]) -> [String] {
        let span = points.reduce(0) { $0 + $1.intervalSeconds }
        guard span > 0 else { return ["No measured intervals"] }
        var findings: [String] = []
        func share(_ predicate: (ObservationPoint) -> Bool) -> Int {
            Int((points.filter(predicate).reduce(0) { $0 + $1.intervalSeconds } / span * 100).rounded())
        }
        let busy = share { ($0.cpuPercent ?? 0) >= 85 }
        if busy > 0 { findings.append("High system CPU during \(busy)% of the observed interval") }
        let pressure = share { $0.memoryPressure == "warning" || $0.memoryPressure == "critical" }
        if pressure > 0 { findings.append("Elevated memory pressure during \(pressure)% of the observed interval") }
        let swapping = share { ($0.activity.swapInBytesPerSecond ?? 0) + ($0.activity.swapOutBytesPerSecond ?? 0) >= 1_048_576 }
        if swapping > 0 { findings.append("Active swapping above 1 MiB/s during \(swapping)% of the interval; correlate with pressure and responsiveness") }
        let hot = share { $0.thermal == "serious" || $0.thermal == "critical" }
        if hot > 0 { findings.append("Thermal constraints during \(hot)% of the interval") }
        if points.contains(where: { !$0.activity.unavailable.isEmpty }) { findings.append("Some measurements were unavailable; review measurement limits before concluding health") }
        if findings.isEmpty { findings.append("No sustained CPU, pressure, swap-rate or thermal warning in this interval; intermittent or network causes remain possible") }
        return findings
    }
}

public enum ObservationEngine {
    private static func weightedCPU(_ points: [ObservationPoint]) -> Double? {
        let valid = points.filter { $0.cpuPercent != nil }
        let duration = valid.reduce(0) { $0 + $1.intervalSeconds }
        return duration > 0 ? valid.reduce(0) { $0 + ($1.cpuPercent ?? 0) * $1.intervalSeconds } / duration : nil
    }

    /// Explicit user observation only. No daemon, persistence, or idle polling.
    /// Cancellation throws; an incomplete report is never called complete.
    public static func observe(seconds: Int = 30, intervalSeconds: Int = 2,
        progress: (@Sendable (ObservationPoint) async -> Void)? = nil) async throws -> ObservationReport {
        guard (2...600).contains(seconds), (1...10).contains(intervalSeconds), intervalSeconds <= seconds else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let engine = PulseEngine(recordsHistory: false)
        let initial = await engine.sample(topProcessLimit: Int.max)
        let startedAt = initial.timestamp
        let start = ProcessInfo.processInfo.systemUptime
        var previous = start
        var points: [ObservationPoint] = []
        var totals: [String: ObservationContributor] = [:]
        while ProcessInfo.processInfo.systemUptime - start < Double(seconds) {
            try Task.checkCancellation()
            let remaining = Double(seconds) - (ProcessInfo.processInfo.systemUptime - start)
            try await Task.sleep(for: .seconds(min(Double(intervalSeconds), remaining)))
            let snapshot = await engine.sample(topProcessLimit: Int.max)
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - previous; previous = now
            let point = ObservationPoint(snapshot: snapshot, interval: elapsed)
            points.append(point)
            for group in ProcessGrouper.group(snapshot.topProcesses) {
                var row = totals[group.name] ?? ObservationContributor(name: group.name, meanCPUPercent: 0,
                    peakCPUPercent: 0, residentBytes: 0, peakResidentBytes: 0, representative: nil)
                row.meanCPUPercent += group.cpuPercent * elapsed
                row.peakCPUPercent = max(row.peakCPUPercent, group.cpuPercent)
                row.residentBytes = group.residentBytes
                row.peakResidentBytes = max(row.peakResidentBytes, group.residentBytes)
                totals[group.name] = row
            }
            // ponytail: inspect only leading CPU/memory groups, not every argv.
            for group in ProcessGrouper.group(snapshot.topProcesses).prefix(5) {
                if let identity = ProcessIdentity.read(group.topPID) { totals[group.name]?.representative = identity }
            }
            for group in snapshot.memoryContributors.prefix(5) {
                if let identity = ProcessIdentity.read(group.topPID) { totals[group.name]?.memoryRepresentative = identity }
            }
            await progress?(point)
        }
        let duration = previous - start
        let contributors = totals.values.map { value in
            var row = value; row.meanCPUPercent /= duration; return row
        }.sorted { ($0.meanCPUPercent, $0.peakResidentBytes) > ($1.meanCPUPercent, $1.peakResidentBytes) }
        var limits = ["Readable processes only; denied processes are counted in coverage.",
            "RSS totals include shared pages and exclude compressed/swapped pages; they are not exclusive memory usage.",
            "Process CPU: 100% = one core. System CPU: 100% = all cores.",
            "Largest contributors are observations, not proof of causality. Browser tabs require the browser Task Manager.",
            "Storage I/O is aggregate device traffic, not latency or saturation; overlapping storage layers may count the same I/O."]
        limits += Set(points.flatMap { $0.activity.unavailable }).sorted()
        if points.contains(where: { $0.coverage.truncated }) { limits.append("PID enumeration reached its 8192-slot bound") }
        return ObservationReport(schemaVersion: 1, startedAt: startedAt, endedAt: points.last?.timestamp ?? startedAt,
            durationSeconds: duration, samples: points, contributors: Array(contributors.prefix(20)),
            memoryContributors: Array(contributors.sorted { $0.peakResidentBytes > $1.peakResidentBytes }.prefix(10)),
            findings: ObservationReport.summarize(points: points), limitations: limits,
            meanCPUPercent: weightedCPU(points), peakCPUPercent: points.compactMap(\.cpuPercent).max())
    }
}
