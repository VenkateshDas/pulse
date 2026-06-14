import Foundation
import ServiceManagement

/// App-side client for the privileged helper daemon. Registers it via
/// SMAppService, manages the XPC connection, and runs `PrivilegedOperation`s.
///
/// Degrades gracefully everywhere it can't work: a bare `swift run` with no
/// bundle id, an unregistered/unapproved daemon, or a signature mismatch all
/// resolve to a non-`.enabled` status and a failed (never crashing) `perform`.
public actor PrivilegedHelperClient {
    public static let shared = PrivilegedHelperClient()

    public enum Status: String, Sendable {
        case enabled            // registered + approved, ready to call
        case requiresApproval   // user must approve in Settings → Login Items
        case notRegistered      // never registered, or unregistered
        case unavailable        // no bundle / daemon plist not found
    }

    private var connection: NSXPCConnection?

    private var service: SMAppService {
        SMAppService.daemon(plistName: pulseHelperPlistName)
    }

    public init() {}

    public func status() -> Status {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    /// Registers the daemon and returns the resulting status. After first
    /// registration macOS usually reports `.requiresApproval` until the user
    /// enables it in System Settings.
    @discardableResult
    public func register() -> Status {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        // A second register() on an already-registered service throws; that's
        // fine — we only care about the resulting status.
        try? service.register()
        return status()
    }

    public func unregister() async {
        try? await service.unregister()
        connection?.invalidate()
        connection = nil
    }

    public func perform(_ op: PrivilegedOperation) async -> OptimizeResult {
        guard status() == .enabled else {
            return OptimizeResult(success: false, summary: "Privileged helper not enabled")
        }
        let conn = makeConnection()
        let once = ResumeOnce()
        return await withCheckedContinuation { (cont: CheckedContinuation<OptimizeResult, Never>) in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                once.fire { cont.resume(returning: OptimizeResult(
                    success: false, summary: "Helper error: \(error.localizedDescription)")) }
            } as? PulseHelperProtocol
            guard let proxy else {
                once.fire { cont.resume(returning: OptimizeResult(
                    success: false, summary: "Helper unavailable")) }
                return
            }
            proxy.perform(operationID: op.rawValue) { ok, summary in
                once.fire { cont.resume(returning: OptimizeResult(success: ok, summary: summary)) }
            }
        }
    }

    private func makeConnection() -> NSXPCConnection {
        if let connection { return connection }
        let conn = NSXPCConnection(
            machServiceName: pulseHelperMachServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: PulseHelperProtocol.self)
        // Only talk to a helper signed as our helper identifier.
        conn.setCodeSigningRequirement(
            pulseCodeSignRequirement(identifier: pulseHelperBundleIdentifier))
        conn.invalidationHandler = { [weak self] in
            Task { await self?.clearConnection() }
        }
        conn.resume()
        connection = conn
        return conn
    }

    private func clearConnection() { connection = nil }
}

/// Guards an XPC continuation so it resumes exactly once, even though both the
/// reply block and the error handler are wired up. Double-resume would trap.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func fire(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
