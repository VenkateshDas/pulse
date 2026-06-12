import Foundation

/// Minute-aggregated ring buffer for a single metric, persisted as JSON so
/// the 24h chart survives relaunches. Samples arriving within the same
/// wall-clock minute are averaged; a finalized entry is appended when the
/// minute rolls over. Gaps (app closed, Mac asleep) stay gaps — `series`
/// returns nil for minutes with no data instead of interpolating.
public final class MinuteHistoryStore {
    public struct Entry: Codable, Equatable {
        /// Whole minutes since the Unix epoch (timeIntervalSince1970 / 60).
        public let minute: Int
        public let value: Double
    }

    /// 24h of minutes — the chart window and the retention horizon.
    public static let capacity = 24 * 60
    /// Persist once per N finalized minutes; an atomic ~30KB write every
    /// 5 min is invisible, every sample would not be.
    static let persistEvery = 5

    private(set) var entries: [Entry]
    private let fileURL: URL?

    // Accumulator for the in-progress minute.
    private var currentMinute: Int?
    private var currentSum: Double = 0
    private var currentCount: Int = 0
    private var unpersistedMinutes = 0

    public init(fileURL: URL?, now: Date = .now) {
        self.fileURL = fileURL
        if let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([Entry].self, from: data)
        {
            // Drop anything outside the 24h window at load time.
            let cutoff = Self.minuteIndex(of: now) - Self.capacity
            entries = stored.filter { $0.minute > cutoff }
        } else {
            entries = []
        }
    }

    /// Feeds one sample. Cheap enough to call on every 2s tick.
    public func record(_ value: Double, at date: Date = .now) {
        let minute = Self.minuteIndex(of: date)
        if minute == currentMinute {
            currentSum += value
            currentCount += 1
            return
        }
        finalizeCurrentMinute()
        // Trim against the incoming minute, not the finalized one — after a
        // long gap the finalized minute is itself ancient.
        let cutoff = minute - Self.capacity
        if let oldest = entries.first?.minute, oldest <= cutoff {
            entries.removeAll { $0.minute <= cutoff }
        }
        currentMinute = minute
        currentSum = value
        currentCount = 1
    }

    /// Average of samples in the not-yet-finalized minute (the live point).
    public var currentAverage: Double? {
        currentCount > 0 ? currentSum / Double(currentCount) : nil
    }

    /// Fixed-width 24h series ending at `date`'s minute: one slot per minute,
    /// oldest first, nil where no samples exist. The last slot carries the
    /// in-progress minute so the chart's right edge is live.
    public func series(at date: Date = .now) -> [Double?] {
        let endMinute = Self.minuteIndex(of: date)
        let startMinute = endMinute - Self.capacity + 1
        var slots = [Double?](repeating: nil, count: Self.capacity)
        for entry in entries {
            let index = entry.minute - startMinute
            if index >= 0 && index < Self.capacity {
                slots[index] = entry.value
            }
        }
        if let currentMinute, let currentAverage {
            let index = currentMinute - startMinute
            if index >= 0 && index < Self.capacity {
                slots[index] = currentAverage
            }
        }
        return slots
    }

    private func finalizeCurrentMinute() {
        guard let minute = currentMinute, currentCount > 0 else { return }
        entries.append(Entry(minute: minute, value: currentSum / Double(currentCount)))
        unpersistedMinutes += 1
        if unpersistedMinutes >= Self.persistEvery {
            persist()
            unpersistedMinutes = 0
        }
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func minuteIndex(of date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    public static func defaultFileURL(metric: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse/\(metric)-history.json")
    }
}
