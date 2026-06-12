import Foundation

/// Persists periodic disk-usage readings so "disk grew X this week" can be
/// computed across launches. JSON file in Application Support; one entry
/// per `recordInterval`, capped at `maxEntries`.
final class DiskHistoryStore {
    struct Entry: Codable, Equatable {
        let date: Date
        let usedBytes: UInt64
    }

    static let recordInterval: TimeInterval = 6 * 3600
    static let maxEntries = 120  // ~30 days at 6h cadence
    static let minimumSpan: TimeInterval = 24 * 3600

    private(set) var entries: [Entry]
    private let fileURL: URL?

    init(fileURL: URL? = DiskHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([Entry].self, from: data)
        {
            entries = stored
        } else {
            entries = []
        }
    }

    /// Appends a reading if the last one is older than `recordInterval`.
    func record(usedBytes: UInt64, at date: Date = .now) {
        if let last = entries.last, date.timeIntervalSince(last.date) < Self.recordInterval {
            return
        }
        entries.append(Entry(date: date, usedBytes: usedBytes))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        persist()
    }

    /// Used-space change over the trailing week, scaled from the oldest entry
    /// within the window. nil until at least `minimumSpan` of history exists.
    func weeklyGrowth(currentUsedBytes: UInt64, at date: Date = .now) -> Int64? {
        let weekAgo = date.addingTimeInterval(-7 * 24 * 3600)
        guard let baseline = entries.first(where: { $0.date >= weekAgo }) ?? entries.last else {
            return nil
        }
        let span = date.timeIntervalSince(baseline.date)
        guard span >= Self.minimumSpan else { return nil }
        let delta = Int64(bitPattern: currentUsedBytes &- baseline.usedBytes)
        // Scale partial windows up to a weekly rate, but never extrapolate
        // beyond the actual window once we have a full week.
        let scale = min(7 * 24 * 3600 / span, 7.0)
        return Int64(Double(delta) * scale)
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

    private static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse/disk-history.json")
    }
}
