import Foundation
import PulseKit

public struct AttentionDTO: Codable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: String
    public struct Remedy: Codable, Sendable {
        public let kind: String
        public let target: String?
        public let pid: Int32?
    }
    public let remedy: Remedy?

    public init(item: AttentionItem) {
        self.id = item.id
        self.title = item.title
        self.detail = item.detail
        self.severity = item.severity.rawValue
        switch item.action {
        case .quitProcess(let pid, _): remedy = .init(kind: "quitProcess", target: nil, pid: pid)
        case .cleanJunk: remedy = .init(kind: "previewClean", target: "clean --scan", pid: nil)
        case .openPane(let target): remedy = .init(kind: "inspect", target: target.rawValue, pid: nil)
        case nil: remedy = nil
        }
    }
}

public enum AttentionCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let engine = PulseEngine(recordsHistory: false)
        _ = await engine.sample(topProcessLimit: 30)
        try? await Task.sleep(for: .milliseconds(250))
        let snapshot = await engine.sample(topProcessLimit: 30)
        let diagnosis = DiagnosisEngine.evaluate(snapshot)
        let alerts = AlertsEngine.evaluate(snapshot)
        let attentionEngine = AttentionEngine()
        let items = await attentionEngine.currentItems(diagnosis: diagnosis, alerts: alerts)

        let dtos = items.map { AttentionDTO(item: $0) }

        if output.isJSON {
            output.emitJSON(dtos)
        } else {
            output.printHeader("Needs Attention")
            if dtos.isEmpty {
                print("  \(output.green("✓")) All systems nominal. No items requiring attention.")
            } else {
                for item in dtos {
                    let sevStr: String
                    switch item.severity {
                    case "critical": sevStr = output.red("[CRITICAL]")
                    case "warn": sevStr = output.yellow("[WARN]")
                    default: sevStr = output.cyan("[INFO]")
                    }
                    print("  \(sevStr) \(output.bold(item.title))")
                    print("         \(output.dim(item.detail))")
                }
            }
        }
    }
}
