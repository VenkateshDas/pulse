import Foundation
import PulseKit

public enum DisplayCmd {
    @MainActor public static func run(parser: CLIParser, output: CLIOutput) async {
        do {
            let action = parser.positional.first ?? "get"
            let value = parser.positional.dropFirst().first.flatMap(Double.init)
            let reply = try await AppControl.send(.init(action: "display.\(action)", value: value, displayID: parser.stringOption("display").flatMap(UInt32.init)))
            if let error = reply.error { throw CLIUsageError(error) }
            if output.isJSON { output.emitJSON(reply.displays ?? []) }
            else {
                output.printHeader("Displays (Pulse app state)")
                for display in reply.displays ?? [] {
                    output.printRow(label: "\(display.name) [\(display.id)]", value: String(format: "%.0f%%", display.brightness * 100))
                }
            }
        } catch { output.printError(error.localizedDescription); exit(1) }
    }
}
