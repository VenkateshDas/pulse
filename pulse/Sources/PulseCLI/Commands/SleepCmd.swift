import Foundation
import PulseKit

public enum SleepCmd {
    @MainActor public static func run(parser: CLIParser, output: CLIOutput) async {
        do {
            let action = parser.positional.first ?? "status"
            let reply = try await AppControl.send(.init(action: "sleep.\(action)", value: parser.doubleOption("until")))
            if let error = reply.error { throw CLIUsageError(error) }
            struct Assertion: Encodable { let pid: Int32; let processName: String; let assertionName: String }
            struct Status: Encodable { let isKeepAwakeActive: Bool; let expiresAt: Date?; let activeAssertions: [Assertion] }
            let snapshot = await PulseEngine(recordsHistory: false).sampleLite()
            let status = Status(isKeepAwakeActive: reply.isKeepAwakeActive ?? false, expiresAt: reply.expiresAt, activeAssertions: snapshot.sleepAssertions.map { Assertion(pid: $0.pid, processName: $0.processName, assertionName: $0.assertionName) })
            if output.isJSON { output.emitJSON(status) }
            else {
                output.printHeader("Sleep")
                output.printRow(label: "Pulse keep awake", value: status.isKeepAwakeActive ? "Active" : "Inactive")
                if let expiry = status.expiresAt { output.printRow(label: "Expires", value: expiry.description) }
                for item in status.activeAssertions { output.printRow(label: "\(item.processName) [\(item.pid)]", value: item.assertionName) }
            }
        } catch { output.printError(error.localizedDescription); exit(1) }
    }
}
