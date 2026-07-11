import Foundation

/// Result of one `networkQuality` run.
public struct SpeedTestResult: Sendable, Equatable, Codable, Identifiable {
    public var id: Date { date }
    public let downloadMbps: Double
    public let uploadMbps: Double
    /// Round-trips per minute under working load — Apple's "Responsiveness" metric.
    public let responsivenessRPM: Int?
    public let baseRTTMillis: Double?
    public let date: Date

    public init(
        downloadMbps: Double, uploadMbps: Double, responsivenessRPM: Int?,
        baseRTTMillis: Double?, date: Date = Date()
    ) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.responsivenessRPM = responsivenessRPM
        self.baseRTTMillis = baseRTTMillis
        self.date = date
    }
}

public enum SpeedTestError: Error, Sendable {
    case toolUnavailable
    case cancelled
    case malformedOutput
    case processFailed(Int32)
}

/// Runs macOS's built-in `networkQuality` CLI (ships since Monterey) to
/// measure real throughput and responsiveness. This is the one sanctioned
/// subprocess in Pulse: user-triggered by a button tap, never polled, and
/// there's no public in-process API for RPM/responsiveness.
public actor SpeedTestRunner {
    private var runningProcess: Process?

    public init() {}

    public func run() async throws -> SpeedTestResult {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/networkQuality") else {
            throw SpeedTestError.toolUnavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.arguments = ["-c"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        runningProcess = process

        defer { runningProcess = nil }

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                // networkQuality can still emit valid JSON with a non-zero
                // exit status on partial results, so parse first and only
                // fail on malformed output below.
                let collected = outPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: collected)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SpeedTestError.malformedOutput
        }

        // networkQuality reports throughput in bits/sec.
        let dlBitsPerSec = (json["dl_throughput"] as? Double) ?? 0
        let ulBitsPerSec = (json["ul_throughput"] as? Double) ?? 0
        let rpm = (json["responsiveness"] as? Double).map { Int($0) }
        let baseRTT = json["base_rtt"] as? Double

        guard dlBitsPerSec > 0 || ulBitsPerSec > 0 else {
            throw SpeedTestError.malformedOutput
        }

        return SpeedTestResult(
            downloadMbps: dlBitsPerSec / 1_000_000,
            uploadMbps: ulBitsPerSec / 1_000_000,
            responsivenessRPM: rpm,
            baseRTTMillis: baseRTT)
    }

    public func cancel() {
        runningProcess?.terminate()
    }
}
