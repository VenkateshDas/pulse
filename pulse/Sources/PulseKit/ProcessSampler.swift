import CPulse
import Darwin
import Foundation

/// Top processes by CPU, via libproc — no subprocesses spawned.
/// CPU% is computed from the delta of per-process task time between
/// consecutive samples, so the first call returns 0% for every process.
final class ProcessSampler {
    // pti_total_* and mach_absolute_time share mach time units,
    // so the busy/wall ratio needs no timebase conversion.
    private var previousTaskTime: [pid_t: UInt64] = [:]
    private var previousSampleAt: UInt64 = 0

    func sample(limit: Int) -> [ProcessSample] {
        let now = mach_absolute_time()
        let wallDelta = now &- previousSampleAt
        let firstSample = previousSampleAt == 0
        defer { previousSampleAt = now }

        var pids = [pid_t](repeating: 0, count: 8192)
        let pidCount = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard pidCount > 0 else { return [] }

        var nextTaskTime: [pid_t: UInt64] = [:]
        nextTaskTime.reserveCapacity(Int(pidCount))
        var samples: [ProcessSample] = []
        samples.reserveCapacity(Int(pidCount))

        for pid in pids[0..<Int(pidCount)] where pid > 0 {
            var info = proc_taskinfo()
            let size = proc_pidinfo(
                pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)
            )
            guard size == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }

            let taskTime = info.pti_total_user &+ info.pti_total_system
            nextTaskTime[pid] = taskTime

            var cpuPercent = 0.0
            if !firstSample, wallDelta > 0, let prev = previousTaskTime[pid], taskTime >= prev {
                cpuPercent = Double(taskTime - prev) / Double(wallDelta) * 100
            }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = nameLength > 0 ? String(nullTerminated: nameBuffer) : "pid \(pid)"

            samples.append(
                ProcessSample(
                    pid: pid,
                    name: name,
                    cpuPercent: cpuPercent,
                    residentBytes: info.pti_resident_size
                )
            )
        }

        previousTaskTime = nextTaskTime
        return Array(
            samples
                .sorted { ($0.cpuPercent, $0.residentBytes) > ($1.cpuPercent, $1.residentBytes) }
                .prefix(limit)
        )
    }
}
