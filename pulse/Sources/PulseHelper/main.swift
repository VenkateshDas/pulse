import Foundation
import PulseKit

// Pulse privileged helper — a launchd daemon that runs as root and performs
// a fixed, reviewed set of maintenance operations on behalf of the app.
//
// Security model:
//   * It exposes ONE entry point (`perform`) that accepts an operation *id*,
//     not a command. The id maps to a hard-coded command via PrivilegedOperation.
//     There is no way to make this daemon run an arbitrary binary.
//   * Every inbound XPC connection must be signed as the Pulse app
//     (identifier pin via setCodeSigningRequirement). Anything else is refused.

/// Implements the XPC interface. Each call executes the operation's fixed
/// command(s) and reports a combined result.
final class HelperService: NSObject, PulseHelperProtocol {
    func ping(reply: @escaping (String) -> Void) {
        reply("pulse-helper 1")
    }

    func perform(operationID: String, reply: @escaping (Bool, String) -> Void) {
        guard let op = PrivilegedOperation(rawValue: operationID) else {
            reply(false, "Unknown operation")
            return
        }
        var allOK = true
        var notes: [String] = []
        for command in op.commands {
            let (ok, output) = Self.runRoot(command.path, command.args)
            allOK = allOK && ok
            if !output.isEmpty { notes.append(output) }
        }
        let summary = allOK
            ? "\(op.label): done"
            : "\(op.label): failed — \(notes.joined(separator: "; "))"
        reply(allOK, summary)
    }

    /// Runs a command synchronously as the daemon's (root) user.
    private static func runRoot(_ path: String, _ args: [String]) -> (Bool, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()
            let err = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus == 0, err)
        } catch {
            return (false, "\(path): \(error.localizedDescription)")
        }
    }
}

/// Listener delegate: pins every connection to the Pulse app's code signature
/// before wiring up the exported interface.
final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Refuse anyone who isn't the signed Pulse app.
        connection.setCodeSigningRequirement(
            pulseCodeSignRequirement(identifier: pulseAppBundleIdentifier))
        connection.exportedInterface = NSXPCInterface(with: PulseHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

// A Mach-service listener handed to us by launchd. Run forever.
let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: pulseHelperMachServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
