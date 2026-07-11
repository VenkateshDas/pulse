import Foundation

/// Persists speed-test results (JSON in Application Support, same pattern as
/// `AnomalyStore`) so the Network page has a cached result to show
/// immediately on launch, before the next auto-test runs.
public final class SpeedTestStore {
    public static let maxAge: TimeInterval = 30 * 24 * 3600
    public static let maxCount = 50

    public private(set) var results: [SpeedTestResult]
    private let fileURL: URL?

    public init(fileURL: URL? = SpeedTestStore.defaultFileURL(), now: Date = .now) {
        self.fileURL = fileURL
        if let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([SpeedTestResult].self, from: data)
        {
            results = stored.filter { now.timeIntervalSince($0.date) <= Self.maxAge }
        } else {
            results = []
        }
    }

    public func record(_ result: SpeedTestResult) {
        results.insert(result, at: 0)
        if results.count > Self.maxCount { results.removeLast(results.count - Self.maxCount) }
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(results) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse/speed-tests.json")
    }
}
