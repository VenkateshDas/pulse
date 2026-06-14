import Foundation

/// The complete, closed set of operations Pulse will run as root. Each maps to
/// hard-coded absolute-path commands — there is no arbitrary-command path, so
/// the privileged surface is exactly these cases and nothing else. New
/// privileged work means a new case here, reviewed deliberately.
public enum PrivilegedOperation: String, Sendable, CaseIterable {
    case purgeMemory
    case flushNetworkStack
    case rebuildSpotlightIndex

    public var label: String {
        switch self {
        case .purgeMemory: "Free inactive memory"
        case .flushNetworkStack: "Optimize network stack"
        case .rebuildSpotlightIndex: "Rebuild Spotlight index"
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
