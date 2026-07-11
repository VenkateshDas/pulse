import Foundation

/// A process whose resident memory has grown steadily across the full window.
public struct LeakAlert: Sendable, Equatable, Identifiable {
    public let pid: Int32
    public let name: String
    /// RSS at the oldest point still inside the window.
    public let startBytes: UInt64
    public let currentBytes: UInt64
    /// Actual span covered by the tracked points (≥ the configured window).
    public let windowSeconds: TimeInterval
    /// True only on the tick it first qualifies — drives notify/log.
    public let isNewlySustained: Bool

    public var id: Int32 { pid }
    public var growthBytes: Int64 { Int64(bitPattern: currentBytes &- startBytes) }

    public init(pid: Int32, name: String, startBytes: UInt64, currentBytes: UInt64,
                windowSeconds: TimeInterval, isNewlySustained: Bool) {
        self.pid = pid
        self.name = name
        self.startBytes = startBytes
        self.currentBytes = currentBytes
        self.windowSeconds = windowSeconds
        self.isNewlySustained = isNewlySustained
    }
}

/// Memory-leak detector: flags a process whose RSS climbs near-monotonically
/// for the whole window. Same shape as ProcessWatcher (value type, `mutating
/// ingest`, hand-advanced `now`), but it keeps a per-PID *series* rather than a
/// crossing timestamp, because a leak is a trend, not a threshold.
///
/// Default thresholds: **+1 GiB over 30 min** — normal apps take step jumps
/// (open a project, load a tab) but rarely add a full gigabyte over half an
/// hour without ever releasing; absolute rather than relative avoids flagging
/// small daemons doubling from 40 → 80 MB. **≥90 % non-negative minute
/// deltas** — a real leak essentially never shrinks; caches and GC-style apps
/// free memory in bursts, so a few negative deltas mark them clean while
/// tolerating RSS jitter.
///
/// Input is `topProcesses` (30 pids sorted cpu-then-rss). A CPU-idle leaker
/// still surfaces: at idle most processes tie near 0 % CPU and the RSS
/// tiebreak floats big-memory processes into the 30. Unlike ProcessWatcher,
/// vanishing from one batch does NOT reset the clock — the top-30 churns, so
/// tracks are only dropped after `staleAfter` unseen.
public struct LeakWatcher: Sendable {
    /// The series must span at least this long before a verdict.
    public var window: TimeInterval = 30 * 60
    /// Minimum absolute RSS growth across the window.
    public var growthThresholdBytes: Int64 = 1 << 30
    /// Minimum fraction of non-negative consecutive deltas.
    public var monotonicFraction: Double = 0.9
    /// At most one stored point per pid per this interval.
    public var sampleInterval: TimeInterval = 60
    /// Tracks unseen this long are evicted (their clock resets).
    public var staleAfter: TimeInterval = 5 * 60

    struct Key: Hashable { let pid: Int32; let name: String }
    struct Point { let at: Date; let bytes: UInt64 }
    struct Track {
        var points: [Point]
        var lastSeen: Date
        var triggered: Bool
    }
    private var tracks: [Key: Track] = [:]

    public init() {}

    /// Updates tracking and returns every process currently judged leaking.
    public mutating func ingest(_ procs: [ProcessSample], now: Date) -> [LeakAlert] {
        var alerts: [LeakAlert] = []

        for proc in procs {
            let key = Key(pid: proc.pid, name: proc.name)
            // A pid unseen past staleAfter starts fresh — its old points are a
            // different era (e.g. it left the top-30 for 20 min), not a window.
            let existing = tracks[key].flatMap {
                now.timeIntervalSince($0.lastSeen) <= staleAfter ? $0 : nil
            }
            var track = existing
                ?? Track(points: [Point(at: now, bytes: proc.residentBytes)],
                         lastSeen: now, triggered: false)
            track.lastSeen = now

            if let last = track.points.last, now.timeIntervalSince(last.at) >= sampleInterval {
                track.points.append(Point(at: now, bytes: proc.residentBytes))
            }
            // Trim to the window, but keep one point at/beyond the edge so the
            // span check can still cover the full window.
            while track.points.count > 1,
                  now.timeIntervalSince(track.points[1].at) >= window {
                track.points.removeFirst()
            }

            if let alert = evaluate(track, key: key, now: now) {
                let isNew = !track.triggered
                track.triggered = true
                alerts.append(LeakAlert(
                    pid: alert.pid, name: alert.name, startBytes: alert.startBytes,
                    currentBytes: alert.currentBytes, windowSeconds: alert.windowSeconds,
                    isNewlySustained: isNew))
            }
            // `triggered` stays sticky until the track is evicted — growth
            // hovering around the threshold must not re-notify every flicker.
            tracks[key] = track
        }

        // Evict only stale tracks — absence from one batch (top-30 churn) must
        // not reset a 30-minute clock.
        tracks = tracks.filter { now.timeIntervalSince($0.value.lastSeen) <= staleAfter }

        return alerts.sorted { $0.growthBytes > $1.growthBytes }
    }

    private func evaluate(_ track: Track, key: Key, now: Date) -> LeakAlert? {
        guard let first = track.points.first, let last = track.points.last else { return nil }
        let span = last.at.timeIntervalSince(first.at)
        guard span >= window else { return nil }

        let growth = Int64(bitPattern: last.bytes &- first.bytes)
        guard growth >= growthThresholdBytes else { return nil }

        var nonNegative = 0
        for i in 1..<track.points.count where track.points[i].bytes >= track.points[i - 1].bytes {
            nonNegative += 1
        }
        let deltas = track.points.count - 1
        guard deltas > 0, Double(nonNegative) / Double(deltas) >= monotonicFraction else { return nil }

        return LeakAlert(pid: key.pid, name: key.name, startBytes: first.bytes,
                         currentBytes: last.bytes, windowSeconds: span,
                         isNewlySustained: false)
    }
}
