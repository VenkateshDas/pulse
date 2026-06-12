import CPulse
import Darwin
import Foundation

public struct SysctlProperty: Identifiable, Sendable {
    public let id: String
    public let value: String
}

public struct ProcessFDSample: Identifiable, Sendable {
    public let id: Int32
    public let name: String
    public let fdCount: Int
    public let threadCount: Int
}

public actor DevModeSampler {
    private let smc = SMCSensors()

    public init() {}

    public func sampleSMC() -> [String: String] {
        return smc?.dumpAll() ?? [:]
    }

    public func sampleSysctls() -> [SysctlProperty] {
        let keys = [
            "hw.machine", "hw.model", "hw.logicalcpu", "hw.physicalcpu", "hw.memsize",
            "kern.version", "kern.osproductversion", "kern.osversion", "kern.hostname",
            "machdep.cpu.brand_string", "machdep.cpu.core_count", "machdep.cpu.thread_count"
        ]
        
        var properties = [SysctlProperty]()
        for key in keys {
            if let val = sysctlString(key) {
                properties.append(SysctlProperty(id: key, value: val))
            } else if let valInt = sysctlInt(key) {
                properties.append(SysctlProperty(id: key, value: "\(valInt)"))
            } else if let valInt64 = sysctlInt64(key) {
                properties.append(SysctlProperty(id: key, value: "\(valInt64)"))
            }
        }
        return properties
    }

    public func sampleProcessFDs() -> [ProcessFDSample] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let pidCount = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard pidCount > 0 else { return [] }

        var samples = [ProcessFDSample]()
        samples.reserveCapacity(Int(pidCount))

        for pid in pids[0..<Int(pidCount)] where pid > 0 {
            var info = proc_taskinfo()
            let size = proc_pidinfo(
                pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)
            )
            guard size == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }

            let fdBufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            let fdCount: Int
            if fdBufferSize > 0 {
                fdCount = Int(fdBufferSize) / MemoryLayout<proc_fdinfo>.size
            } else {
                fdCount = 0
            }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = nameLength > 0 ? String(nullTerminated: nameBuffer) : "pid \(pid)"

            samples.append(ProcessFDSample(
                id: pid,
                name: name,
                fdCount: fdCount,
                threadCount: Int(info.pti_threadnum)
            ))
        }
        
        return samples.sorted { $0.fdCount > $1.fdCount }
    }

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(nullTerminated: buffer)
    }

    private func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private func sysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
