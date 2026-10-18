import Foundation
import PulseKit
import os

/// The CLI and the optional agent share these operations and safety checks.
/// JSON is captured per request: no stdout redirection, child process or shell.
public enum NativeCommandExecutor {
    public struct Result: Sendable {
        public let json: String
        public let exitCode: Int32
        public init(json: String, exitCode: Int32) { self.json = json; self.exitCode = exitCode }
    }

    public static func execute(_ arguments: [String]) async -> Result {
        let parser = CLIParser(arguments: arguments + ["--json"])
        let capture = OSAllocatedUnfairLock(initialState: (json: "", status: Int32(0)))
        let output = CLIOutput(isJSON: true, sink: { text in capture.withLock { $0.json = text } },
                               statusSink: { status in capture.withLock { $0.status = status } })
        do { try parser.validate() }
        catch { output.printError(error.localizedDescription); return .init(json: capture.withLock { $0.json }, exitCode: 2) }
        // Help/version are process-facing grammar, never agent operations.
        guard let command = parser.subcommand, CLIParser.commands.contains(command),
              !parser.hasFlag("help", "version") else {
            return .init(json: "{\"error\":\"Unsupported native operation\"}", exitCode: 2)
        }
        if Task.isCancelled { return .init(json: "{\"error\":\"Cancelled before execution\"}", exitCode: 1) }
        switch command {
        case "observe", "process", "network", "history", "startup", "quit": await InvestigateCmd.run(parser: parser, output: output)
        case "vitals": await VitalsCmd.run(parser: parser, output: output)
        case "diagnose": await DiagnoseCmd.run(parser: parser, output: output)
        case "procs": await ProcsCmd.run(parser: parser, output: output)
        case "attention": await AttentionCmd.run(parser: parser, output: output)
        case "anomalies": AnomaliesCmd.run(parser: parser, output: output)
        case "growth": await GrowthCmd.run(parser: parser, output: output)
        case "verdict": await VerdictCmd.run(parser: parser, output: output)
        case "clean": await CleanCmd.run(parser: parser, output: output)
        case "uninstall": await UninstallCmd.run(parser: parser, output: output)
        case "display": await DisplayCmd.run(parser: parser, output: output)
        case "sleep": await SleepCmd.run(parser: parser, output: output)
        case "sensors": await SensorsCmd.run(parser: parser, output: output)
        case "undo": await UndoCmd.run(parser: parser, output: output)
        case "duplicates": await DuplicatesCmd.run(parser: parser, output: output)
        case "speedtest": await SpeedTestCmd.run(parser: parser, output: output)
        default: output.printError("Unsupported native operation"); output.finish(2)
        }
        return capture.withLock { .init(json: $0.json.isEmpty ? "{\"error\":\"No native result\"}" : $0.json, exitCode: $0.status) }
    }
}

enum NativeCommandControl {
    @MainActor static func send(_ request: AppControl.Request) async throws -> AppControl.Reply {
        if Bundle.main.bundleIdentifier == "com.pulse.app" || ProcessInfo.processInfo.processName == "Pulse" {
            return await AppControlServer.handle(request)
        }
        return try await AppControl.send(request)
    }
}
