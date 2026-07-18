import Foundation

/// The complete, closed set of operations Pulse will run as root. Each maps to
/// hard-coded absolute-path commands — there is no arbitrary-command path, so
/// the privileged surface is exactly these cases and nothing else. New
/// privileged work means a new case here, reviewed deliberately.
public enum PrivilegedOperation: String, Sendable, CaseIterable {
    case purgeMemory
    case flushNetworkStack
    case rebuildSpotlightIndex
    case clearUpdateDownloads
    case thinLocalSnapshots

    public var label: String {
        switch self {
        case .purgeMemory: "Free inactive memory"
        case .flushNetworkStack: "Optimize network stack"
        case .rebuildSpotlightIndex: "Rebuild Spotlight index"
        case .clearUpdateDownloads: "Delete macOS update downloads"
        case .thinLocalSnapshots: "Thin Time Machine snapshots"
        }
    }

    /// Fixed command(s) for this operation. Hard-coded absolute paths and
    /// literal arguments — nothing here is derived from caller input.
    public var commands: [(path: String, args: [String])] {
        switch self {
        case .purgeMemory:
            return [("/usr/sbin/purge", [])]
        case .flushNetworkStack:
            return [("/sbin/route", ["-n", "flush"]),
                    ("/usr/sbin/arp", ["-a", "-d"])]
        case .rebuildSpotlightIndex:
            return [("/usr/bin/mdutil", ["-E", "/"])]
        case .clearUpdateDownloads:
            // Only the download subfolders — index.plist/ProductMetadata.plist
            // stay so Software Update's bookkeeping remains intact.
            return [("/usr/bin/find",
                     ["/Library/Updates", "-mindepth", "1", "-maxdepth", "1",
                      "-type", "d", "-exec", "/bin/rm", "-rf", "{}", "+"])]
        case .thinLocalSnapshots:
            // Apple's own reclaim path: purge Time Machine local snapshots
            // down to the requested bytes (huge value = thin them all).
            // Urgency 4 = most aggressive. os.update snapshots untouched.
            return [("/usr/bin/tmutil",
                     ["thinlocalsnapshots", "/", "999999999999999", "4"])]
        }
    }

    /// The single root shell command run under one admin prompt. Built purely
    /// from `commands` (fixed paths + literal args), each token single-quoted.
    /// None of those literals contain quotes, so this is injection-free by
    /// construction — and there is no place for caller input to enter.
    public var shellScript: String {
        commands.map { cmd in
            ([cmd.path] + cmd.args).map { "'\($0)'" }.joined(separator: " ")
        }.joined(separator: " ; ")
    }
}
