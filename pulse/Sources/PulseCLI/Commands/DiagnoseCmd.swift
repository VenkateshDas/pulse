import Foundation
import PulseKit

public struct DiagnoseDTO: Codable, Sendable {
    public struct CulpritInfo: Codable, Sendable {
        public let pid: Int32?
        public let name: String?
        public let cpuPercent: Double?
        public let appName: String?
    }

    public struct FactorLoss: Codable, Sendable {
        public let factor: String
        public let penalty: Double
    }

    public let score: Int
    public let band: String
    public let verdict: String
    public let severity: String
    public let triggeredFactor: String?
    public let culprit: CulpritInfo?
    public let deductions: [FactorLoss]

    public init(score: HealthScore, diagnosis: Diagnosis, topProcesses: [ProcessSample]) {
        self.score = score.value
        self.band = "\(score.band)"
        self.verdict = diagnosis.line
        self.severity = "\(diagnosis.severity)"
        self.triggeredFactor = diagnosis.factor.map { "\($0)" }

        if let pid = diagnosis.culpritPID, let proc = topProcesses.first(where: { $0.pid == pid }) {
            self.culprit = CulpritInfo(
                pid: proc.pid,
                name: proc.name,
                cpuPercent: (proc.cpuPercent * 10).rounded() / 10,
                appName: proc.appName
            )
        } else if let pid = diagnosis.culpritPID {
            self.culprit = CulpritInfo(pid: pid, name: nil, cpuPercent: nil, appName: nil)
        } else {
            self.culprit = nil
        }

        self.deductions = score.breakdown
            .filter { $0.value > 0.1 }
            .map { FactorLoss(factor: $0.key.label, penalty: ($0.value * 10).rounded() / 10) }
            .sorted { $0.penalty == $1.penalty ? $0.factor < $1.factor : $0.penalty > $1.penalty }
    }
}

public enum DiagnoseCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let engine = PulseEngine(recordsHistory: false)
        _ = await engine.sample(topProcessLimit: 30)
        try? await Task.sleep(for: .milliseconds(250))
        let snapshot = await engine.sample(topProcessLimit: 30)
        let diagnosis = DiagnosisEngine.evaluate(snapshot)
        let health = HealthScore.evaluate(snapshot)

        let dto = DiagnoseDTO(score: health, diagnosis: diagnosis, topProcesses: snapshot.topProcesses)

        if output.isJSON {
            output.emitJSON(dto)
        } else {
            output.printHeader("Pulse Health & Diagnosis")
            let scoreStr = "\(dto.score) / 100 (\(dto.band.capitalized))"
            let coloredScore = dto.score >= 80 ? output.green(scoreStr) : (dto.score >= 60 ? output.yellow(scoreStr) : output.red(scoreStr))
            output.printRow(label: "Health Score", value: coloredScore)

            let severityColored: String
            switch dto.severity {
            case "critical": severityColored = output.red("CRITICAL")
            case "warn": severityColored = output.yellow("WARNING")
            case "info": severityColored = output.cyan("INFO")
            default: severityColored = output.green("CLEAR")
            }
            output.printRow(label: "Severity", value: severityColored)
            output.printRow(label: "Verdict", value: output.bold(dto.verdict))

            if let culprit = dto.culprit {
                var cDesc = "PID \(culprit.pid ?? 0)"
                if let n = culprit.name { cDesc += " (\(n))" }
                if let cpu = culprit.cpuPercent { cDesc += " at \(cpu)% CPU" }
                output.printRow(label: "Culprit Process", value: cDesc)
            }

            if !dto.deductions.isEmpty {
                let dedList = dto.deductions.map { "\($0.factor): -\($0.penalty) pts" }.joined(separator: ", ")
                output.printRow(label: "Score Deductions", value: dedList)
            }
        }
    }
}
