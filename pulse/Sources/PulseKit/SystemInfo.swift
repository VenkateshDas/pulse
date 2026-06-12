import Darwin
import Foundation

/// Static hardware facts, read once.
public enum SystemInfo {
    /// e.g. "Apple M2" — from the CPU brand string.
    public static let chipName: String = sysctlString("machdep.cpu.brand_string") ?? "Mac"

    /// Logical efficiency-core count (perflevel1). 0 on Intel Macs.
    public static let efficiencyCoreCount: Int = sysctlInt("hw.perflevel1.logicalcpu") ?? 0

    /// Logical performance-core count (perflevel0). 0 when unknown.
    public static let performanceCoreCount: Int = sysctlInt("hw.perflevel0.logicalcpu") ?? 0

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(nullTerminated: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
