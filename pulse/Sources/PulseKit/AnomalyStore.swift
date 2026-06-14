import Foundation

/// One logged "process stayed hot" event — the memory mole lacks. Lets the
/// Timeline answer "when did Spotlight peg a core?" after the fact.
public struct AnomalyRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let processName: String
    public let pid: Int32
    public let cpuPercent: Double
    public let date: Date
    public let sustainedSeconds: TimeInterval

    public init(id: UUID = UUID(), processName: String, pid: Int32,
                cpuPercent: Double, date: Date = .now, sustainedSeconds: TimeInterval) {
        self.id = id
        self.processName = processName
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.date = date
        self.sustainedSeconds = sustainedSeconds
    }
}

/// Persists sustained-anomaly events (JSON in Application Support, same pattern
/// as DiskHistoryStore). Newest first; trimmed by age and count.
public final class AnomalyStore {
    public static let maxAge: TimeInterval = 30 * 24 * 3600
    public static let maxCount = 200

    public private(set) var records: [AnomalyRecord]
    private let fileURL: URL?

    public init(fileURL: URL? = AnomalyStore.defaultFileURL(), now: Date = .now) {
        self.fileURL = fileURL
        if let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([AnomalyRecord].self, from: data) {
            records = stored.filter { now.timeIntervalSince($0.date) <= Self.maxAge }
        } else {
            records = []
        }
    }

    public func record(_ entry: AnomalyRecord) {
        records.insert(entry, at: 0)
        records.removeAll { entry.date.timeIntervalSince($0.date) > Self.maxAge }
        if records.count > Self.maxCount { records.removeLast(records.count - Self.maxCount) }
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse/anomalies.json")
    }
}
