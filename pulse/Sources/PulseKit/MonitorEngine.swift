import CPulse
import Darwin
import Foundation

/// Per-interface network telemetry. When produced by
/// `MonitorEngine.networkDeltas()` the byte fields hold rates
/// (bytes per second since the previous call), not lifetime totals.
public struct NetworkSample: Sendable, Equatable, Identifiable {
    public let interfaceName: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public var id: String { interfaceName }

    public init(interfaceName: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.interfaceName = interfaceName
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// One process with the extended fields the Monitor page shows.
/// All fields come from proc_pidinfo — no root, no subprocesses.
public struct ProcessExtendedSample: Sendable, Identifiable, Equatable {
    public let pid: Int32
    public let name: String
    /// CPU over the last sampling interval, 0–100 (can exceed 100 on multi-core).
    public let cpuPercent: Double
    public let residentBytes: UInt64
    public let virtualBytes: UInt64
    public let threadCount: UInt32
    /// Disk pageins per second over the last interval (pti_pageins delta).
    public let pageFaultRate: Double

    public var id: Int32 { pid }

    public init(
        pid: Int32, name: String, cpuPercent: Double, residentBytes: UInt64,
        virtualBytes: UInt64, threadCount: UInt32, pageFaultRate: Double
    ) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.virtualBytes = virtualBytes
        self.threadCount = threadCount
        self.pageFaultRate = pageFaultRate
    }
}

/// Parent-child process linkage for the tree view.
public struct ProcessNode: Sendable, Identifiable {
    public let process: ProcessExtendedSample
    public let children: [ProcessNode]
    public var id: Int32 { process.pid }

    public init(process: ProcessExtendedSample, children: [ProcessNode]) {
        self.process = process
        self.children = children
    }
}

/// Process tree + per-interface network sampling for the Monitor page.
///
/// Per-process network breakdown is intentionally absent: it requires the
/// private com.apple.private.network.socket-delegate entitlement, so the
/// engine reports per-interface throughput instead (spec §3 Monitor).
///
/// One `collect()` walk serves `sample`, `tree`, and `parents` within the
/// same tick — callers in a 2s loop never pay for the pid walk twice.
public actor MonitorEngine {
    public enum SortKey: String, CaseIterable, Sendable {
        case cpu, memory, threads, pageFaults, name, pid
    }

    public init() {}

    // MARK: - Processes

    public func sample(sortKey: SortKey, ascending: Bool) -> [ProcessExtendedSample] {
        collectIfStale()
        let sorted: [ProcessExtendedSample] =
            switch sortKey {
            case .cpu: rows.sorted { ($0.cpuPercent, $0.residentBytes) > ($1.cpuPercent, $1.residentBytes) }
            case .memory: rows.sorted { $0.residentBytes > $1.residentBytes }
            case .threads: rows.sorted { $0.threadCount > $1.threadCount }
            case .pageFaults: rows.sorted { $0.pageFaultRate > $1.pageFaultRate }
            case .name:
                rows.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            case .pid: rows.sorted { $0.pid < $1.pid }
            }
        // For metric keys "ascending: false" is the natural big-first order;
        // for name/pid the natural order is already ascending.
        let natural: [ProcessExtendedSample]
        switch sortKey {
        case .name, .pid: natural = ascending ? sorted : sorted.reversed()
        default: natural = ascending ? sorted.reversed() : sorted
        }
        return natural
    }

    /// Root nodes with children attached, children sorted by CPU descending.
    /// A process whose parent isn't in the sample (or is the kernel) is a root.
    public func tree() -> [ProcessNode] {
        collectIfStale()
        let byPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        var childPIDs: [pid_t: [pid_t]] = [:]
        var roots: [pid_t] = []
        for row in rows {
            if let ppid = parentByPID[row.pid], ppid > 0, byPID[ppid] != nil, ppid != row.pid {
                childPIDs[ppid, default: []].append(row.pid)
            } else {
                roots.append(row.pid)
            }
        }

        func build(_ pid: pid_t) -> ProcessNode? {
            guard let process = byPID[pid] else { return nil }
            let children = (childPIDs[pid] ?? [])
                .compactMap(build)
                .sorted { $0.process.cpuPercent > $1.process.cpuPercent }
            return ProcessNode(process: process, children: children)
        }
        return roots.compactMap(build)
            .sorted { $0.process.cpuPercent > $1.process.cpuPercent }
    }

    /// pid → parent pid from the same collection `sample`/`tree` used.
    public func parents() -> [Int32: Int32] {
        collectIfStale()
        return parentByPID
    }

    /// pid → name for every pid proc_name resolves — a superset of the
    /// rows, so parents the task-info walk can't read (launchd, other
    /// users' processes) still get a real name in the detail card.
    public func names() -> [Int32: String] {
        collectIfStale()
        return nameByPID
    }

    // MARK: - Network

    /// Per-interface throughput (bytes/sec) since the previous call.
    /// First call returns zero rates — there is no previous reading yet.
    /// Active non-loopback en* interfaces only (WiFi/Ethernet); virtual
    /// bridge/awdl/utun interfaces would double-count tunneled traffic.
    public func networkDeltas() -> [NetworkSample] {
        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPtr) == 0 else { return [] }
        defer { freeifaddrs(ifaddrsPtr) }

        var totals: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        var ptr = ifaddrsPtr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                let dataPtr = current.pointee.ifa_data
            else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            // Idle Thunderbolt/dormant ports report zero lifetime bytes —
            // pure noise in the UI, so they're dropped entirely.
            guard data.ifi_ibytes > 0 || data.ifi_obytes > 0 else { continue }
            totals[name] = (UInt64(data.ifi_ibytes), UInt64(data.ifi_obytes))
        }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - previousNetworkAt
        var samples: [NetworkSample] = []
        for (name, total) in totals.sorted(by: { $0.key < $1.key }) {
            var inRate: UInt64 = 0
            var outRate: UInt64 = 0
            // ifi_ibytes is 32-bit and wraps; a backwards counter means
            // wrap or interface reset — report zero for that tick.
            if let prev = previousNetworkTotals[name], dt > 0,
                total.bytesIn >= prev.bytesIn, total.bytesOut >= prev.bytesOut
            {
                inRate = UInt64(Double(total.bytesIn - prev.bytesIn) / dt)
                outRate = UInt64(Double(total.bytesOut - prev.bytesOut) / dt)
            }
            samples.append(
                NetworkSample(interfaceName: name, bytesIn: inRate, bytesOut: outRate))
        }
        previousNetworkTotals = totals
        previousNetworkAt = now
        return samples
    }

    private var previousNetworkTotals: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousNetworkAt: TimeInterval = 0

    // MARK: - Collection

    private var rows: [ProcessExtendedSample] = []
    private var parentByPID: [pid_t: pid_t] = [:]
    private var nameByPID: [pid_t: String] = [:]
    private var collectedAt: UInt64 = 0  // DispatchTime ns; 0 = never

    // CPU/pagein deltas need previous per-pid readings, like ProcessSampler.
    private var previousTaskTime: [pid_t: UInt64] = [:]
    private var previousPageins: [pid_t: Int32] = [:]
    private var previousSampleAt: UInt64 = 0  // mach ticks; convert to ns before ratio
    // pti_total_* are nanoseconds; mach_absolute_time() is mach ticks (≈24MHz on
    // Apple Silicon), so the wall delta needs timebase conversion to ns.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    private var previousSampleUptime: TimeInterval = 0

    /// Re-walks the pid list at most twice per second so `sample`, `tree`,
    /// and `parents` called within one UI tick share a single collection.
    private func collectIfStale() {
        let nowNS = DispatchTime.now().uptimeNanoseconds
        if collectedAt != 0, nowNS - collectedAt < 500_000_000 { return }
        collectedAt = nowNS
        collect()
    }

    private func collect() {
        let now = mach_absolute_time()
        let wallDelta =
            (now &- previousSampleAt) &* UInt64(Self.timebase.numer)
            / UInt64(Self.timebase.denom)
        let firstSample = previousSampleAt == 0
        let uptime = ProcessInfo.processInfo.systemUptime
        let seconds = uptime - previousSampleUptime
        previousSampleAt = now
        previousSampleUptime = uptime

        var pids = [pid_t](repeating: 0, count: 8192)
        let pidCount = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard pidCount > 0 else { return }

        var nextTaskTime: [pid_t: UInt64] = [:]
        var nextPageins: [pid_t: Int32] = [:]
        var nextParents: [pid_t: pid_t] = [:]
        var nextNames: [pid_t: String] = [:]
        nextTaskTime.reserveCapacity(Int(pidCount))
        var samples: [ProcessExtendedSample] = []
        samples.reserveCapacity(Int(pidCount))

        for pid in pids[0..<Int(pidCount)] where pid > 0 {
            // Name first, with a path fallback: proc_name is denied for
            // other users' processes (launchd included) but proc_pidpath
            // isn't — keeps parent lookups real in the detail card.
            var nameBuffer = [CChar](repeating: 0, count: 128)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            var name = nameLength > 0 ? String(nullTerminated: nameBuffer) : "pid \(pid)"
            if nameLength <= 0 {
                var pathBuffer = [CChar](repeating: 0, count: 4096)
                if proc_pidpath(pid, &pathBuffer, 4096) > 0 {
                    let path = String(nullTerminated: pathBuffer)
                    if let base = path.split(separator: "/").last { name = String(base) }
                }
            }
            if name != "pid \(pid)" { nextNames[pid] = name }

            var info = proc_taskinfo()
            let size = proc_pidinfo(
                pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
            guard size == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }

            let taskTime = info.pti_total_user &+ info.pti_total_system
            nextTaskTime[pid] = taskTime
            nextPageins[pid] = info.pti_pageins

            var cpuPercent = 0.0
            if !firstSample, wallDelta > 0, let prev = previousTaskTime[pid], taskTime >= prev {
                cpuPercent = Double(taskTime - prev) / Double(wallDelta) * 100
            }
            var pageFaultRate = 0.0
            if !firstSample, seconds > 0, let prev = previousPageins[pid],
                info.pti_pageins >= prev
            {
                pageFaultRate = Double(info.pti_pageins - prev) / seconds
            }

            var bsd = proc_bsdinfo()
            let bsdSize = proc_pidinfo(
                pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size))
            if bsdSize == Int32(MemoryLayout<proc_bsdinfo>.size) {
                nextParents[pid] = pid_t(bsd.pbi_ppid)
            }

            samples.append(
                ProcessExtendedSample(
                    pid: pid,
                    name: name,
                    cpuPercent: cpuPercent,
                    residentBytes: info.pti_resident_size,
                    virtualBytes: info.pti_virtual_size,
                    threadCount: UInt32(max(info.pti_threadnum, 0)),
                    pageFaultRate: pageFaultRate
                ))
        }

        previousTaskTime = nextTaskTime
        previousPageins = nextPageins
        rows = samples
        parentByPID = nextParents
        nameByPID = nextNames
    }
}
