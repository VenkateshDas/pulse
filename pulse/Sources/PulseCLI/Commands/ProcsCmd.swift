import Foundation
import PulseKit

public struct ProcessDTO: Codable, Sendable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let residentBytes: UInt64
    public let residentFormatted: String
    public let appName: String?

    public init(sample: ProcessSample) {
        self.pid = sample.pid
        self.name = sample.name
        self.cpuPercent = (sample.cpuPercent * 10).rounded() / 10
        self.residentBytes = sample.residentBytes
        self.residentFormatted = CLIOutput.bytes(Int64(sample.residentBytes))
        self.appName = sample.appName
    }
}

public enum ProcsCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let limit = parser.intOption("limit", "n", default: 10) ?? 10
        let sortBy = parser.stringOption("by", "sort")?.lowercased() ?? "cpu"

        let engine = PulseEngine(recordsHistory: false)
        // First sample establishes baseline
        _ = await engine.sample(topProcessLimit: Int.max)
        // Wait 250ms for delta
        try? await Task.sleep(for: .milliseconds(250))
        let snapshot = await engine.sample(topProcessLimit: Int.max)

        var procs = snapshot.topProcesses
        if sortBy == "mem" || sortBy == "memory" {
            procs.sort { $0.residentBytes > $1.residentBytes }
        } else {
            procs.sort { $0.cpuPercent > $1.cpuPercent }
        }

        let sliced = Array(procs.prefix(limit)).map { ProcessDTO(sample: $0) }

        if output.isJSON {
            output.emitJSON(sliced)
        } else {
            output.printHeader("Top Processes (by \(sortBy.uppercased()))")
            let hdr = "  PID    " + "NAME".padding(toLength: 24, withPad: " ", startingAt: 0) + "CPU%    " + "MEMORY    " + "APP"
            print(output.dim(hdr))
            for p in sliced {
                let pidStr = String(p.pid).padding(toLength: 7, withPad: " ", startingAt: 0)
                let nameStr = p.name.prefix(22).padding(toLength: 24, withPad: " ", startingAt: 0)
                let cpuStr = String(format: "%5.1f%% ", p.cpuPercent)
                let memStr = p.residentFormatted.padding(toLength: 10, withPad: " ", startingAt: 0)
                let appStr = p.appName ?? "—"
                print("  \(output.cyan(pidStr))\(nameStr)\(output.yellow(cpuStr))\(memStr)\(output.dim(appStr))")
            }
        }
    }
}
