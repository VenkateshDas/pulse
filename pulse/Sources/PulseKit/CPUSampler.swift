import Darwin

/// Per-core CPU usage from `host_processor_info` tick deltas.
/// First call returns zeros (no previous ticks to diff against).
final class CPUSampler {
    private struct CoreTicks {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        var busy: UInt64 { user + system + nice }
        var total: UInt64 { busy + idle }
    }

    struct Sample {
        var total: Double = 0
        var perCore: [Double] = []
        /// E/P averages — nil when the machine has no perflevel split (Intel).
        var efficiency: Double?
        var performance: Double?
    }

    private var previous: [CoreTicks] = []
    // On Apple Silicon, host_processor_info lists efficiency cores first.
    private let efficiencyCoreCount = SystemInfo.efficiencyCoreCount

    func sample() -> Sample {
        let (total, perCore) = sampleTicks()
        var result = Sample(total: total, perCore: perCore)
        if efficiencyCoreCount > 0, perCore.count > efficiencyCoreCount {
            let eCores = perCore[..<efficiencyCoreCount]
            let pCores = perCore[efficiencyCoreCount...]
            result.efficiency = eCores.reduce(0, +) / Double(eCores.count)
            result.performance = pCores.reduce(0, +) / Double(pCores.count)
        }
        return result
    }

    private func sampleTicks() -> (total: Double, perCore: [Double]) {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return (0, []) }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        let stateCount = Int(CPU_STATE_MAX)
        var current: [CoreTicks] = []
        current.reserveCapacity(Int(coreCount))
        for core in 0..<Int(coreCount) {
            let base = core * stateCount
            var ticks = CoreTicks()
            ticks.user = UInt64(info[base + Int(CPU_STATE_USER)])
            ticks.system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            ticks.idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            ticks.nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            current.append(ticks)
        }

        defer { previous = current }
        guard previous.count == current.count else {
            return (0, Array(repeating: 0, count: current.count))
        }

        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        var busySum: UInt64 = 0
        var totalSum: UInt64 = 0
        for (prev, cur) in zip(previous, current) {
            let busy = cur.busy &- prev.busy
            let total = cur.total &- prev.total
            busySum &+= busy
            totalSum &+= total
            perCore.append(total == 0 ? 0 : Double(busy) / Double(total) * 100)
        }
        let total = totalSum == 0 ? 0 : Double(busySum) / Double(totalSum) * 100
        return (total, perCore)
    }
}
