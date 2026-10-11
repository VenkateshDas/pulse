import Darwin
import Foundation
import IOKit

/// Interval rates; nil means unavailable or no baseline, never idle.
public struct ActivityReadings: Codable, Sendable, Equatable {
    public var swapInBytesPerSecond: Double?
    public var swapOutBytesPerSecond: Double?
    public var compressionBytesPerSecond: Double?
    public var decompressionBytesPerSecond: Double?
    public var diskReadBytesPerSecond: Double?
    public var diskWriteBytesPerSecond: Double?
    public var unavailable: [String] = []
    public init() {}
}

final class DiskActivitySampler {
    private var previous: [UInt64: (read: UInt64, write: UInt64)] = [:]
    private var previousAt: TimeInterval?

    func sample() -> (read: Double?, write: Double?, error: String?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            previous = [:]; previousAt = nil
            return (nil, nil, "Storage I/O counters unavailable")
        }
        defer { IOObjectRelease(iterator) }
        var counters: [UInt64: (read: UInt64, write: UInt64)] = [:]
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
                let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                let read = stats["Bytes (Read)"] as? NSNumber,
                let write = stats["Bytes (Write)"] as? NSNumber else { continue }
            counters[id] = (read.uint64Value, write.uint64Value)
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = counters; previousAt = now }
        guard !counters.isEmpty else { return (nil, nil, "Storage I/O counters unavailable") }
        guard let before = previousAt, now > before, Set(previous.keys) == Set(counters.keys) else { return (nil, nil, nil) }
        var read: Double = 0, write: Double = 0
        for (id, current) in counters {
            guard let old = previous[id], current.read >= old.read, current.write >= old.write else { return (nil, nil, nil) }
            read += Double(current.read - old.read) / (now - before)
            write += Double(current.write - old.write) / (now - before)
        }
        return (read, write, nil)
    }
}
