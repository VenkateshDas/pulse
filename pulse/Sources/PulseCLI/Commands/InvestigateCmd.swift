import Foundation
import PulseKit

public enum InvestigateCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        do {
            switch parser.subcommand {
            case "observe":
                let report = try await ObservationEngine.observe(seconds: parser.intOption("seconds", default: 30) ?? 30)
                if output.isJSON { output.emitJSON(report) }
                else { for finding in report.findings { print(finding) }; print(String(format: "Mean CPU %.1f%% · peak %.1f%% · %.1fs", report.meanCPUPercent ?? 0, report.peakCPUPercent ?? 0, report.durationSeconds)) }
            case "process":
                guard let raw = parser.positional.first, let pid = Int32(raw), let identity = ProcessIdentity.read(pid) else { throw CLIUsageError("Process exited or identity is unreadable") }
                let engine = MonitorEngine()
                _ = await engine.sample(sortKey: .pid, ascending: true)
                try await Task.sleep(for: .milliseconds(600))
                let rows = await engine.sample(sortKey: .pid, ascending: true)
                guard let latest = ProcessIdentity.read(pid), latest.startToken == identity.startToken else { throw CLIUsageError("Process identity changed during inspection") }
                struct Detail: Encodable { let identity: ProcessIdentity; let metrics: ProcessExtendedSample?; let coverage: ProcessCoverage }
                output.emitJSON(Detail(identity: latest, metrics: rows.first { $0.pid == pid }, coverage: await engine.coverage))
            case "network":
                let context = try await NetworkDiagnostic.read(url: parser.stringOption("url"))
                output.emitJSON(context)
                if context.probeError != nil { exit(1) }
            case "history": output.emitJSON(DiagnosticHistory.read(hours: parser.intOption("hours", default: 24) ?? 24))
            case "startup": output.emitJSON(StartupInventory.read())
            case "quit":
                let result = try await AppQuit.run(pid: Int32(parser.positional[0])!, startToken: parser.stringOption("started-at")!, dryRun: parser.isDryRun)
                output.emitJSON(result)
                if !result.dryRun && !result.terminated { exit(1) }
            default: break
            }
        } catch { output.printError(error.localizedDescription); exit(1) }
    }
}
