import Foundation

/// Minimal async wrapper around `Process` for the in-process (non-privileged)
/// optimize tasks. Same detached-Process pattern as BatteryHistoryStore.
/// Privileged commands do NOT go through here — they route to the (future)
/// SMAppService helper.
public enum Shell {
    public struct Output: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
        public var ok: Bool { exitCode == 0 }
    }

    /// Runs `executable` with `args`, capturing output. Never throws for a
    /// non-zero exit — inspect `exitCode`. Throws only if the binary can't launch.
    @discardableResult
    public static func run(_ executable: String, _ args: [String]) async throws -> Output {
        try await Task.detached(priority: .userInitiated) { () throws -> Output in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let outPipe = Pipe(), errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            try process.run()
            let outData = try outPipe.fileHandleForReading.readToEnd() ?? Data()
            let errData = try errPipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            return Output(
                exitCode: process.terminationStatus,
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self))
        }.value
    }
}
