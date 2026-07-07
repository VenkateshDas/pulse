import Foundation

/// Free/total capacity of the boot volume.
/// Uses `volumeAvailableCapacityForImportantUsage` so the number matches
/// Finder (counts purgeable space as available).
final class DiskSampler {
    func sample() -> (freeBytes: UInt64, totalBytes: UInt64) {
        // NSURL caches resource values per URL instance — a stored URL froze
        // free space at its first read for the app's whole lifetime (values
        // only refreshed on relaunch). A fresh URL per sample reads live.
        let rootURL = URL(fileURLWithPath: "/")
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
