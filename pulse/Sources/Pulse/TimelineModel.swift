import Foundation
import Observation
import PulseKit

/// Owns the Storage Timeline: a daily disk-usage history with per-category
/// breakdown. Records one snapshot per day (latest scan wins) and exposes the
/// series + day-over-day deltas for the stacked chart and spike drill.
@MainActor
@Observable
final class TimelineModel {
    private(set) var snapshots: [TimelineSnapshot] = []

    @ObservationIgnored private let store = TimelineStore()

    init() {
        snapshots = store.snapshots
    }

    /// Records today's snapshot from the current disk usage and, when a full
    /// scan is available, its top-folder + cleanable-category breakdown.
    func recordToday(scan: StorageScan?) {
        let used = Self.diskUsedBytes()
        guard used > 0 else { return }
        var categories: [String: UInt64] = [:]
        if let scan {
            for folder in scan.topFolders.prefix(8) {
                categories[folder.name, default: 0] += folder.sizeBytes
            }
            for item in scan.items {
                categories[item.category, default: 0] += item.sizeBytes
            }
        }
        store.record(totalUsedBytes: used, categories: categories)
        snapshots = store.snapshots
    }

    /// Day-over-day used-space change, oldest first.
    var deltas: [(date: Date, deltaBytes: Int64)] { store.dailyDeltas() }

    /// Total used-space change across the recorded window.
    var weeklyDeltaBytes: Int64 {
        let cutoff = Calendar.current.startOfDay(for: Date.now.addingTimeInterval(-7 * 86400))
        let recent = snapshots.filter { $0.date >= cutoff }
        guard let first = recent.first, let last = recent.last, recent.count >= 2 else { return 0 }
        return Int64(bitPattern: last.totalUsedBytes) - Int64(bitPattern: first.totalUsedBytes)
    }

    /// A daily jump this large flags as a spike worth investigating.
    static let spikeThreshold: Int64 = 2_000_000_000

    private nonisolated static func diskUsedBytes() -> UInt64 {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
            let total = values.volumeTotalCapacity,
            let free = values.volumeAvailableCapacityForImportantUsage,
            Int64(total) > free
        else { return 0 }
        return UInt64(Int64(total) - free)
    }
}
