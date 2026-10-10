import CPulse
import Darwin
import Foundation

public struct ProcessIdentity: Codable, Sendable, Equatable {
    public let pid: Int32
    public let parentPID: Int32
    public let name: String
    public let executable: String
    public let startedAt: Date
    public let startToken: String
    public let appName: String?
    public let role: String
    public let footprintBytes: UInt64?
    public let diskReadBytes: UInt64?
    public let diskWriteBytes: UInt64?

    public static func read(_ pid: Int32, includeRole: Bool = true) -> ProcessIdentity? {
        var bsd = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout.size(ofValue: bsd))) == MemoryLayout.size(ofValue: bsd) else { return nil }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = String(nullTerminated: path)
        var name = [CChar](repeating: 0, count: 128)
        _ = proc_name(pid, &name, UInt32(name.count))
        var usage = rusage_info_v2()
        let readable = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0
            }
        }
        return ProcessIdentity(pid: pid, parentPID: Int32(bsd.pbi_ppid), name: String(nullTerminated: name), executable: executable,
            startedAt: Date(timeIntervalSince1970: Double(bsd.pbi_start_tvsec) + Double(bsd.pbi_start_tvusec) / 1_000_000),
            startToken: "\(bsd.pbi_start_tvsec):\(bsd.pbi_start_tvusec)",
            appName: ProcessGrouper.appName(fromPath: executable),
            role: includeRole ? role(arguments: arguments(pid), executable: executable) : "Process",
            footprintBytes: readable ? usage.ri_phys_footprint : nil,
            diskReadBytes: readable ? usage.ri_diskio_bytesread : nil,
            diskWriteBytes: readable ? usage.ri_diskio_byteswritten : nil)
    }

    static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        var size = bytes.count
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0, size > 4 else { return [] }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc <= 4096 else { return [] }
        var offset = 4
        while offset < size, bytes[offset] != 0 { offset += 1 }
        while offset < size, bytes[offset] == 0 { offset += 1 }
        var args: [String] = []
        for _ in 0..<argc {
            let start = offset
            while offset < size, bytes[offset] != 0 { offset += 1 }
            guard offset < size else { break }
            args.append(String(decoding: bytes[start..<offset], as: UTF8.self)); offset += 1
        }
        return args
    }

    static func role(arguments: [String], executable: String) -> String {
        if arguments.contains("--type=gpu-process") { return "GPU" }
        if arguments.contains("--type=renderer") { return arguments.contains("--extension-process") ? "Extension renderer" : "Web renderer" }
        if arguments.contains(where: { $0.contains("network.mojom.NetworkService") }) { return "Network service" }
        if arguments.contains(where: { $0.contains("media.mojom") }) { return "Media service" }
        if arguments.contains("--type=utility") { return "Utility" }
        return executable.contains(".app/") ? "Application / helper" : "Process"
    }
}

public struct ProcessCoverage: Codable, Sendable, Equatable {
    public var enumerated = 0
    public var readable = 0
    public var truncated = false
    public var unavailable: String?
    public init() {}
}

// ponytail: share one native PID walk, no process registry.
enum NativeProcesses {
    static func list() -> (pids: [Int32], coverage: ProcessCoverage) {
        var slots = [pid_t](repeating: 0, count: 8192)
        let count = slots.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        var coverage = ProcessCoverage()
        guard count > 0 else { coverage.unavailable = "PID enumeration failed"; return ([], coverage) }
        coverage.truncated = count >= slots.count
        let pids = slots.prefix(min(Int(count), slots.count)).filter { $0 > 0 }
        coverage.enumerated = pids.count
        return (pids, coverage)
    }

    static func startToken(_ pid: Int32) -> String? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info) else { return nil }
        return "\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
    }

    /// Native task totals and mach_absolute_time use mach ticks; independent POSIX workload check covers units.
    static func cpuPercent(taskDelta: UInt64, wallTicks: UInt64) -> Double {
        wallTicks == 0 ? 0 : Double(taskDelta) / Double(wallTicks) * 100
    }
}
