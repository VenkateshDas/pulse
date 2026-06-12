import Darwin
import Foundation

/// Memory and swap usage from `host_statistics64` / `sysctl`.
final class MemorySampler {
    let totalBytes: UInt64

    init() {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        totalBytes = size
    }

    /// "Used" mirrors Activity Monitor's notion: active + wired + compressed.
    func sample() -> (appBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var app: UInt64 = 0
        var wired: UInt64 = 0
        var comp: UInt64 = 0
        if result == KERN_SUCCESS {
            let pageSize = UInt64(sysconf(_SC_PAGESIZE))
            app = UInt64(stats.active_count) * pageSize
            wired = UInt64(stats.wire_count) * pageSize
            comp = UInt64(stats.compressor_page_count) * pageSize
        }

        var swap = xsw_usage()
        var swapLen = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapLen, nil, 0)

        var pressureLevel: Int32 = 1
        var pressureLen = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &pressureLen, nil, 0)

        return (app, wired, comp, swap.xsu_used, MemoryPressure(rawLevel: pressureLevel))
    }
}
