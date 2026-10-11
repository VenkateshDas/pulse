import Foundation

/// Legacy shell-backed operations have no supported native implementation.
/// Keep a truthful failure result for existing callers without starting a shell
/// or requesting a password. Finder Trash actions use their separate native path.
public enum PrivilegedRunner {
    static let userCancelledCode = "-128"
    public static func run(_ op: PrivilegedOperation) async -> OptimizeResult {
        OptimizeResult(success: false, summary: "\(op.label) was not run: no supported native operation in Pulse. Review the relevant macOS settings instead.")
    }
}
