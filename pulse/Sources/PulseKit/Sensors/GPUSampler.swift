import Foundation
import IOKit

public struct GPUUsage: Sendable, Equatable {
    public let deviceUtilization: Double
    public let rendererUtilization: Double
    public let tilerUtilization: Double
    public let inUseSystemMemory: UInt64
}

public actor GPUSampler {
    private var lastScan: Date = .distantPast
    private var cached: GPUUsage?

    public init() {}

    public func sample(now: Date = .now) -> GPUUsage? {
        if now.timeIntervalSince(lastScan) < 5 { return cached }
        cached = Self.readAccelerator()
        lastScan = now
        return cached
    }

    private static func readAccelerator() -> GPUUsage? {
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        defer { if service != 0 { IOObjectRelease(service) } }
        guard service != 0 else { return nil }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let stats = dict["PerformanceStatistics"] as? [String: Any]
        else { return nil }

        guard let device = stats["Device Utilization %"] as? Int else { return nil }

        return GPUUsage(
            deviceUtilization: Double(device),
            rendererUtilization: Double(stats["Renderer Utilization %"] as? Int ?? device),
            tilerUtilization: Double(stats["Tiler Utilization %"] as? Int ?? device),
            inUseSystemMemory: UInt64(stats["In use system memory"] as? Int ?? 0)
        )
    }
}
