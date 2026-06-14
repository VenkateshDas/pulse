import Foundation

// Shared contract between the Pulse app and the privileged helper daemon.
// Both targets import PulseKit, so the protocol, the operation whitelist, and
// the service identifiers live here in one place.

/// launchd label / Mach service name for the helper. Must match the
/// LaunchDaemon plist embedded in the app bundle (see scripts/bundle.sh).
public let pulseHelperMachServiceName = "com.pulse.helper"
public let pulseHelperPlistName = "com.pulse.helper.plist"

/// Bundle identifiers used to pin the XPC peer's code signature. The helper
/// only talks to a client with this identifier, and the client only talks to
/// a helper with the helper identifier. Production builds add an Apple anchor
/// + team check on top (see scripts/bundle.sh signing notes).
public let pulseAppBundleIdentifier = "com.pulse.app"
public let pulseHelperBundleIdentifier = "com.pulse.helper"

/// The complete, closed set of operations the root daemon will perform.
/// The helper executes ONLY these — there is no arbitrary-command path over
/// the wire, which is the whole point: a root daemon must not be a generic
/// shell. New privileged work means a new case here, reviewed deliberately.
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
}

/// XPC interface. Objective-C-compatible types only (reply blocks with
/// BOOL/NSString) so it can cross the NSXPCConnection boundary.
@objc public protocol PulseHelperProtocol {
    /// Runs the operation identified by its `PrivilegedOperation` raw value.
    /// Unknown ids are rejected. Replies (success, human-readable summary).
    func perform(operationID: String, reply: @escaping (Bool, String) -> Void)
    /// Liveness + version probe used to confirm the connection works.
    func ping(reply: @escaping (String) -> Void)
}

/// Designated-requirement string pinning a peer to a bundle identifier.
/// Used by both ends via `NSXPCConnection.setCodeSigningRequirement`.
public func pulseCodeSignRequirement(identifier: String) -> String {
    "identifier \"\(identifier)\""
}
