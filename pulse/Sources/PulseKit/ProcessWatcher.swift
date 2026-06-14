import Foundation

/// A process that has stayed above the CPU threshold for the full window.
public struct ProcessAlert: Sendable, Equatable, Identifiable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    /// How long it has been continuously above the threshold.
    public let sustainedSeconds: TimeInterval
    /// True only on the tick it first crosses the window — drives notify/log.
    public let isNewlySustained: Bool

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double,
                sustainedSeconds: TimeInterval, isNewlySustained: Bool) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.sustainedSeconds = sustainedSeconds
        self.isNewlySustained = isNewlySustained
    }
}

/// Sustained-threshold detector: a process must stay hot for `window` before it
/// alerts, which kills the false alarms a momentary spike would trigger. Identity
/// is (pid, name) — a respawned PID with a different name resets its clock
/// (`ppid` isn't carried in ProcessSample, so the name guards against reuse).
///
/// A value type with `mutating ingest`, driven from the MainActor sampling loop
/// — no actor hop needed, and trivially testable by advancing `now` by hand.
public struct ProcessWatcher: Sendable {
    public var cpuThreshold: Double
    public var window: TimeInterval

    struct Key: Hashable { let pid: Int32; let name: String }
    struct Track { var firstAbove: Date; var triggered: Bool }
    private var tracks: [Key: Track] = [:]

    public init(cpuThreshold: Double = 50, window: TimeInterval = 60) {
        self.cpuThreshold = cpuThreshold
        self.window = window
    }

    /// Updates tracking and returns every process currently sustained past the
    /// window. Processes that drop below threshold (or vanish) lose their track,
    /// so the next time they cross they start the clock fresh.
    public mutating func ingest(_ procs: [ProcessSample], now: Date) -> [ProcessAlert] {
        var live: [Key: Track] = [:]
        var alerts: [ProcessAlert] = []

        for proc in procs where proc.cpuPercent >= cpuThreshold {
            let key = Key(pid: proc.pid, name: proc.name)
            var track = tracks[key] ?? Track(firstAbove: now, triggered: false)
            let sustained = now.timeIntervalSince(track.firstAbove)
            if sustained >= window {
                let isNew = !track.triggered
                track.triggered = true
                alerts.append(ProcessAlert(
                    pid: proc.pid, name: proc.name, cpuPercent: proc.cpuPercent,
                    sustainedSeconds: sustained, isNewlySustained: isNew))
            }
            live[key] = track
        }

        tracks = live   // drop everyone who cooled off → resets their clock
        return alerts.sorted { $0.cpuPercent > $1.cpuPercent }
    }
}
