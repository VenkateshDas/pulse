import Foundation

/// Free/total capacity of the boot volume.
/// Uses `volumeAvailableCapacityForImportantUsage` so the number matches
/// Finder (counts purgeable space as available).
final class DiskSampler {
    private let rootURL = URL(fileURLWithPath: "/")

    func sample() -> (freeBytes: UInt64, totalBytes: UInt64) {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]
        guard let values = try? rootURL.resourceValues(forKeys: keys) else {
            return (0, 0)
        }
        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        return (free, total)
    }
}
