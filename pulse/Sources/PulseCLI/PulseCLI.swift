import Foundation
import PulseKit

@main
struct PulseCLI {
    static let version = "1.0.0"

    static func printUsage(output: CLIOutput, command: String? = nil) {
        if output.isJSON {
            struct Help: Encodable { let name: String; let version: String; let subcommands: [String]; let usage: [String: String] }
            output.emitJSON(Help(name: "pulse", version: version, subcommands: CLIParser.commands.sorted(), usage: CLIParser.usage))
            return
        }

        if let command, let usage = CLIParser.usage[command] {
            print("Usage: pulse \(usage) [--json]\nExit codes: 0 success, 1 failure/partial result, 2 invalid usage.")
            return
        }
        let banner = """
        \(output.bold(output.cyan("Pulse macOS Command Center CLI"))) (v\(version))
        Native system intelligence, diagnosis, and maintenance for agents and power users.

        \(output.bold("USAGE:"))
          pulse <subcommand> [flags]

        \(output.bold("CORE TELEMETRY & DIAGNOSIS:"))
          vitals       Real-time CPU, memory, disk, network, GPU, battery, thermal metrics
          diagnose     Priority cascade diagnosis (CPU→RAM→Disk→Battery→Thermal) & health score
          procs        Active processes sorted by CPU% or Memory RSS with .app attribution
          attention    Prioritized system triage alerts requiring user attention
          anomalies    Historical record of sustained hot processes (>50% for 60s) & memory leaks
          sensors      SMC fan speeds, temperatures, power wattage, and battery health

        \(output.bold("STORAGE & HYGIENE:"))
          growth       Retroactive disk growth analysis (where space went since N days)
          verdict      Forensic inspection of a directory (safe to delete? rebuild command?)
          clean        Scan or purge 30+ cleanup targets (Xcode, Docker, AI dev caches)
          uninstall    Application removal with confidence-graded ~/Library leftover scan
          duplicates   BLAKE3 hash-based duplicate finder with APFS clone awareness
          undo         Inspect recent deletions and restore files from Trash

        \(output.bold("SYSTEM & HARDWARE:"))
          display      Read or set brightness for built-in and external DDC displays
          sleep        Inspect sleep-blocking assertions or hold a keep-awake lock
          speedtest    Read latest cached network speed test

        \(output.bold("COMMON FLAGS:"))
          --json       Output deterministic JSON formatted for machine parsing (agents/jq)
          --help, -h   Show this help reference
          --version    Show CLI version
        """
        print(banner)
    }

    static func main() async {
        let parser = CLIParser()
        let isJSON = parser.hasFlag("json")
        let output = CLIOutput(isJSON: isJSON)

        do { try parser.validate() }
        catch { output.printError(error.localizedDescription); exit(2) }

        if parser.hasFlag("help", "h") || parser.subcommand == "help" {
            printUsage(output: output, command: parser.subcommand)
            return
        }

        if parser.hasFlag("version", "v") || parser.subcommand == "version" {
            if isJSON {
                output.emitJSON(["version": version])
            } else {
                print("pulse v\(version)")
            }
            return
        }

        guard let subcommand = parser.subcommand?.lowercased() else {
            printUsage(output: output, command: parser.subcommand)
            return
        }

        switch subcommand {
        case "vitals":
            await VitalsCmd.run(parser: parser, output: output)
        case "diagnose":
            await DiagnoseCmd.run(parser: parser, output: output)
        case "procs", "ps":
            await ProcsCmd.run(parser: parser, output: output)
        case "attention", "alerts":
            await AttentionCmd.run(parser: parser, output: output)
        case "anomalies", "spikes":
            AnomaliesCmd.run(parser: parser, output: output)
        case "growth":
            await GrowthCmd.run(parser: parser, output: output)
        case "verdict":
            await VerdictCmd.run(parser: parser, output: output)
        case "clean":
            await CleanCmd.run(parser: parser, output: output)
        case "uninstall", "rm":
            await UninstallCmd.run(parser: parser, output: output)
        case "display", "brightness":
            await DisplayCmd.run(parser: parser, output: output)
        case "sleep", "awake":
            await SleepCmd.run(parser: parser, output: output)
        case "sensors", "smc":
            await SensorsCmd.run(parser: parser, output: output)
        case "undo", "restore":
            await UndoCmd.run(parser: parser, output: output)
        case "duplicates", "dups":
            await DuplicatesCmd.run(parser: parser, output: output)
        case "speedtest", "speed":
            await SpeedTestCmd.run(parser: parser, output: output)
        default:
            output.printError("Unknown subcommand '\(subcommand)'. Run 'pulse --help' for available commands.")
            exit(2)
        }
    }
}
