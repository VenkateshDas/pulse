import CPulse
import Darwin
import Foundation
import IOKit.pwr_mgt

/// Apps currently holding "don't sleep" power assertions — the classic
/// "Teams kept my Mac awake all night" detector. Public IOKit API, no root.
final class SleepAssertionReader {
    /// Assertion types that actually block idle system sleep.
    private static let blockingTypes: Set<String> = [
        kIOPMAssertionTypePreventUserIdleSystemSleep as String,
        "NoIdleSleepAssertion",
    ]

    func sample() -> [SleepAssertion] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
            let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        var assertions: [SleepAssertion] = []
        for (pidNumber, entries) in byProcess {
            let pid = pidNumber.int32Value
            for entry in entries {
                guard let type = entry[kIOPMAssertionTypeKey as String] as? String,
                    Self.blockingTypes.contains(type)
                else { continue }
                let name = entry[kIOPMAssertionNameKey as String] as? String ?? type
                assertions.append(
                    SleepAssertion(pid: pid, processName: processName(pid), assertionName: name)
                )
            }
        }
        return assertions.sorted { $0.pid < $1.pid }
    }

    private func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 { return String(nullTerminated: buffer) }

        // proc_name can't read processes owned by other users (root daemons
        // like powerd hold assertions constantly) — kinfo_proc can.
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        if sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 {
            let comm = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
                String(nullTerminated: raw.bindMemory(to: CChar.self).map { $0 })
            }
            if !comm.isEmpty { return comm }
        }
        return "pid \(pid)"
    }
}
