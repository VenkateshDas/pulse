import Foundation
import PulseKit

public struct AnomalyDTO: Codable, Sendable {
    public let id: String
    public let processName: String
    public let pid: Int32
    public let cpuPercent: Double
    public let date: Date
    public let sustainedSeconds: Double
    public let kind: String
    public let growthFormatted: String?

    public init(record: AnomalyRecord) {
        self.id = record.id.uuidString
        self.processName = record.processName
        self.pid = record.pid
        self.cpuPercent = (record.cpuPercent * 10).rounded() / 10
        self.date = record.date
        self.sustainedSeconds = record.sustainedSeconds
        self.kind = record.kind == .memoryLeak ? "memoryLeak" : "cpu"
        self.growthFormatted = record.growthBytes.map { CLIOutput.bytes($0) }
    }
}

public enum AnomaliesCmd {
    public static func run(parser: CLIParser, output: CLIOutput) {
        let hours = parser.intOption("hours", default: 24) ?? 24
        let store = AnomalyStore()
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)

        let filtered = store.records.filter { $0.date >= cutoff }
        let dtos = filtered.map { AnomalyDTO(record: $0) }

        if output.isJSON {
            output.emitJSON(dtos)
        } else {
            output.printHeader("Sustained Anomalies (Past \(hours) Hours)")
            if dtos.isEmpty {
                print("  \(output.green("✓")) No sustained anomalies recorded in the last \(hours)h.")
            } else {
                let fmt = DateFormatter()
                fmt.dateStyle = .short
                fmt.timeStyle = .medium
                for a in dtos {
                    let timeStr = fmt.string(from: a.date)
                    let kindStr = a.kind == "memoryLeak" ? output.red("[LEAK]") : output.yellow("[CPU]")
                    let detail = a.growthFormatted.map { "grew \($0)" } ?? "\(a.cpuPercent)% CPU for \(Int(a.sustainedSeconds))s"
                    print("  \(output.dim(timeStr)) \(kindStr) \(output.bold(a.processName)) (PID \(a.pid)) — \(detail)")
                }
            }
        }
    }
}
