import Foundation

/// One daily disk-usage snapshot: total used plus a per-category breakdown
/// (the top home folders / cleanable groups). Powers the Storage Timeline's
/// stacked area chart and "what ate my disk this week?" spike drill.
public struct TimelineSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let date: Date
    public let totalUsedBytes: UInt64
    /// Category name → bytes (e.g. "Documents", "App caches"). May be empty on
    /// days the user never opened a full scan — the total line still records.
    public let categories: [String: UInt64]
    public var id: Date { date }

    public init(date: Date, totalUsedBytes: UInt64, categories: [String: UInt64]) {
        self.date = Calendar.current.startOfDay(for: date)
        self.totalUsedBytes = totalUsedBytes
        self.categories = categories
    }
}

/// Persists one TimelineSnapshot per day (JSON in Application Support, same
/// pattern as DiskHistoryStore — no SQLite dependency, identical guarantees:
/// gap-honest, survives launches). Latest reading per day wins.
public final class TimelineStore {
    public static let maxAge: TimeInterval = 90 * 24 * 3600

    public private(set) var snapshots: [TimelineSnapshot]
    private let fileURL: URL?

    public init(fileURL: URL? = TimelineStore.defaultFileURL(), now: Date = .now) {
        self.fileURL = fileURL
        if let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([TimelineSnapshot].self, from: data)
        {
            snapshots = stored.filter { now.timeIntervalSince($0.date) <= Self.maxAge }
        } else {
            snapshots = []
        }
    }

    /// Records (or overwrites) today's snapshot. No-op if the same total and
    /// categories were already recorded today — keeps writes to once per change.
    public func record(
        totalUsedBytes: UInt64, categories: [String: UInt64], at date: Date = .now
    ) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let snapshot = TimelineSnapshot(
            date: startOfDay, totalUsedBytes: totalUsedBytes, categories: categories)
        if let index = snapshots.firstIndex(where: { $0.date == startOfDay }) {
            guard snapshots[index] != snapshot else { return }
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
            snapshots.sort { $0.date < $1.date }
        }
        snapshots.removeAll { date.timeIntervalSince($0.date) > Self.maxAge }
        persist()
    }

    /// Day-over-day change in total used bytes (signed), oldest first.
    public func dailyDeltas() -> [(date: Date, deltaBytes: Int64)] {
        guard snapshots.count >= 2 else { return [] }
        var out: [(Date, Int64)] = []
        for index in 1..<snapshots.count {
            let prev = Int64(bitPattern: snapshots[index - 1].totalUsedBytes)
            let curr = Int64(bitPattern: snapshots[index].totalUsedBytes)
            out.append((snapshots[index].date, curr - prev))
        }
        return out
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse/storage-timeline.json")
    }
}
