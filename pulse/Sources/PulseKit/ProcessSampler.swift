import CPulse
import Darwin
import Foundation

/// Top processes by CPU, via libproc — no subprocesses spawned.
/// CPU% is computed from the delta of per-process task time between
/// consecutive samples, so the first call returns 0% for every process.
final class ProcessSampler {
    // proc_taskinfo's pti_total_user/system and mach_absolute_time() are BOTH
    // in mach-absolute time units, so the busy/wall ratio is unit-free — no
    // timebase conversion is needed (and applying one to only the wall delta
    // inflated it ~42× on Apple Silicon, crushing every process's CPU% by that
    // same factor). Compare the raw deltas directly.
    private(set) var coverage = ProcessCoverage()
    private var previousStarts: [pid_t: String] = [:]
    private var previousTaskTime: [pid_t: UInt64] = [:]
    private var previousSampleAt: UInt64 = 0
    private var nameCache: [pid_t: String] = [:]
    // Owning-app name per pid; nil cached too so failed lookups aren't retried.
    private var appCache: [pid_t: String?] = [:]

    func sample(limit: Int) -> [ProcessSample] {
        let now = mach_absolute_time()
        let wallDelta = now &- previousSampleAt
        let firstSample = previousSampleAt == 0
        defer { previousSampleAt = now }

        let enumeration = NativeProcesses.list()
        let pids = enumeration.pids
        coverage = enumeration.coverage
        let pidCount = pids.count

        var nextStarts: [pid_t: String] = [:]
        var nextTaskTime: [pid_t: UInt64] = [:]
        nextTaskTime.reserveCapacity(pidCount)
        var samples: [ProcessSample] = []
        samples.reserveCapacity(pidCount)

        for pid in pids[0..<pidCount] where pid > 0 {
            var info = proc_taskinfo()
            let size = proc_pidinfo(
                pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)
            )
            guard size == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }

            let startToken = NativeProcesses.startToken(pid)
            if let startToken { nextStarts[pid] = startToken }
            let taskTime = info.pti_total_user &+ info.pti_total_system
            nextTaskTime[pid] = taskTime

            var cpuPercent = 0.0
            if !firstSample, wallDelta > 0, let startToken, previousStarts[pid] == startToken, let prev = previousTaskTime[pid], taskTime >= prev {
                cpuPercent = NativeProcesses.cpuPercent(taskDelta: taskTime - prev, wallTicks: wallDelta)
            }

            if previousStarts[pid] != startToken {
                nameCache.removeValue(forKey: pid); appCache.removeValue(forKey: pid)
            }
            let name: String
            if let cached = nameCache[pid] {
                name = cached
            } else {
                var nameBuffer = [CChar](repeating: 0, count: 128)
                let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                let resolved = nameLength > 0 ? String(nullTerminated: nameBuffer) : "pid \(pid)"
                nameCache[pid] = resolved
                name = resolved
            }

            let appName: String?
            if let cached = appCache[pid] {
                appName = cached
            } else {
                var pathBuffer = [CChar](repeating: 0, count: 4096)
                let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
                appName = pathLength > 0
                    ? ProcessGrouper.appName(fromPath: String(nullTerminated: pathBuffer))
                    : nil
                appCache[pid] = appName
            }

            samples.append(
                ProcessSample(
                    pid: pid,
                    name: name,
                    cpuPercent: cpuPercent,
                    residentBytes: info.pti_resident_size,
                    appName: appName, startToken: startToken
                )
            )
        }

        coverage.readable = samples.count
        previousStarts = nextStarts
        previousTaskTime = nextTaskTime
        let livePIDs = Set(nextTaskTime.keys)
        do {
            nameCache = nameCache.filter { livePIDs.contains($0.key) }
            appCache = appCache.filter { livePIDs.contains($0.key) }
        }
        return Array(
            samples
                .sorted { ($0.cpuPercent, $0.residentBytes) > ($1.cpuPercent, $1.residentBytes) }
                .prefix(limit)
        )
    }
}
