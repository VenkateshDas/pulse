import Foundation

/// Free/total capacity of the boot volume.
/// Uses `volumeAvailableCapacityForImportantUsage` so the number matches
/// Finder (counts purgeable space as available).
final class DiskSampler {
    // The ImportantUsage key is an XPC round trip to the CacheDelete daemon
    // on every read — at the 3–5s sample cadence that was ~20k daemon wakes
    // and ~1.9M unified-log lines per day. Free space doesn't move on that
    // timescale; cache the reading for 60s.
    private var cached: (freeBytes: UInt64, totalBytes: UInt64) = (0, 0)
    private var lastRead: Date = .distantPast

    func sample() -> (freeBytes: UInt64, totalBytes: UInt64) {
        if cached.totalBytes > 0, Date().timeIntervalSince(lastRead) < 60 {
            return cached
        }
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
        cached = (free, total)
        lastRead = Date()
        return (free, total)
    }
}
