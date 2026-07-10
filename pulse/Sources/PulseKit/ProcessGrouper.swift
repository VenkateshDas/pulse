import Foundation

/// Helper processes rolled up under their owning app — users think in apps,
/// not in "Google Chrome Helper (Renderer)" pids.
public struct ProcessGroup: Sendable, Identifiable, Equatable {
    /// App name, or the lone process's own name when not app-hosted.
    public let name: String
    public let count: Int
    /// Sum over members.
    public let cpuPercent: Double
    /// Sum over members.
    public let residentBytes: UInt64
    /// Hottest member — culprit for tap-through to Monitor.
    public let topPID: Int32

    public var id: String { name }

    public init(name: String, count: Int, cpuPercent: Double,
                residentBytes: UInt64, topPID: Int32) {
        self.name = name
        self.count = count
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.topPID = topPID
    }
}

public enum ProcessGrouper {
    /// "/Applications/Google Chrome.app/Contents/…/Google Chrome Helper" →
    /// "Google Chrome". First "*.app" path component wins (helpers nested in
    /// sub-bundles still group under the outermost app); nil if none.
    public static func appName(fromPath path: String) -> String? {
        path.split(separator: "/")
            .first { $0.hasSuffix(".app") }
            .map { String($0.dropLast(4)) }
    }

    /// Groups by `appName ?? name`; sorted (cpuPercent, residentBytes) desc to
    /// match ProcessSampler's ordering.
    public static func group(_ procs: [ProcessSample]) -> [ProcessGroup] {
        Dictionary(grouping: procs, by: { $0.appName ?? $0.name })
            .map { name, members in
                ProcessGroup(
                    name: name,
                    count: members.count,
                    cpuPercent: members.reduce(0) { $0 + $1.cpuPercent },
                    residentBytes: members.reduce(0) { $0 + $1.residentBytes },
                    topPID: members.max {
                        ($0.cpuPercent, $0.residentBytes) < ($1.cpuPercent, $1.residentBytes)
                    }!.pid)
            }
            .sorted { ($0.cpuPercent, $0.residentBytes) > ($1.cpuPercent, $1.residentBytes) }
    }
}
