import Foundation

/// Runs a `PrivilegedOperation` as root via Authorization Services — the GUI
/// equivalent of `sudo`. `osascript … with administrator privileges` shows the
/// native macOS password dialog, then runs the command as root.
///
/// Why not SMAppService/SMJobBless: a privileged daemon requires a Developer-ID
/// *Team* identifier for macOS's same-team trust check, so it can't work with a
/// self-signed local cert. Authorization Services works with any signing
/// (including unsigned dev builds), which keeps the admin tasks testable
/// locally — matching how the CLI tools this is modeled on just use sudo.
///
/// Security: the command string comes entirely from `PrivilegedOperation`
/// (fixed paths + literal args). No caller input is interpolated, so there is
/// no injection surface; the trust boundary is the Pulse binary itself.
public enum PrivilegedRunner {
    /// AppleScript reports user cancellation of the auth dialog as error -128.
    static let userCancelledCode = "-128"

    public static func run(_ op: PrivilegedOperation) async -> OptimizeResult {
        // op.shellScript contains no double quotes, so embedding it in the
        // double-quoted AppleScript string needs no further escaping.
        let appleScript =
            "do shell script \"\(op.shellScript)\" with administrator privileges"
        do {
            let out = try await Shell.run("/usr/bin/osascript", ["-e", appleScript])
            if out.ok {
                return OptimizeResult(success: true, summary: "\(op.label): done")
            }
            if out.stderr.contains(userCancelledCode) {
                return OptimizeResult(success: false, summary: "Cancelled — no password entered")
            }
            let detail = out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return OptimizeResult(success: false,
                                  summary: "\(op.label) failed\(detail.isEmpty ? "" : ": \(detail)")")
        } catch {
            return OptimizeResult(success: false, summary: "Couldn't request admin privileges")
        }
    }
}
