import Foundation
import PulseKit

public struct EvidenceDTO: Codable, Sendable {
    public let kind: String
    public let headline: String
    public let detail: String
    public let favorsDeletion: Bool?

    public init(evidence: VerdictEvidence) {
        self.kind = evidence.kind.rawValue
        self.headline = evidence.headline
        self.detail = evidence.detail
        self.favorsDeletion = evidence.favorsDeletion
    }
}

public struct VerdictDTO: Codable, Sendable {
    public let path: String
    public let verdict: String
    public let headline: String
    public let species: String?
    public let sizeBytes: UInt64
    public let sizeFormatted: String
    public let regenCommand: String?
    public let evidence: [EvidenceDTO]

    public init(verdict: FolderVerdict) {
        self.path = verdict.targetPath
        self.verdict = verdict.verdict.rawValue
        self.headline = verdict.headline
        self.species = verdict.species?.name
        self.sizeBytes = verdict.sizeBytes
        self.sizeFormatted = CLIOutput.bytes(Int64(verdict.sizeBytes))
        self.regenCommand = verdict.regenCommand
        self.evidence = verdict.evidence.map { EvidenceDTO(evidence: $0) }
    }
}

public enum VerdictCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        guard let path = parser.positional.first else {
            output.printError("Missing directory path. Usage: pulse verdict <path> [--json]")
            exit(2)
        }

        let resolvedURL: URL
        if path.hasPrefix("~") {
            let expanded = NSString(string: path).expandingTildeInPath
            resolvedURL = URL(fileURLWithPath: expanded)
        } else {
            resolvedURL = URL(fileURLWithPath: path).standardized
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            output.printError("Directory does not exist: \(resolvedURL.path)")
            exit(1)
        }

        let engine = FolderVerdictEngine()
        let result = await engine.verdict(for: resolvedURL)
        let dto = VerdictDTO(verdict: result)

        if output.isJSON {
            output.emitJSON(dto)
        } else {
            output.printHeader("Folder Verdict: \(dto.path)")
            let verdictColored: String
            switch dto.verdict {
            case "safeToDelete": verdictColored = output.green("SAFE TO DELETE")
            case "likelyUnused": verdictColored = output.yellow("LIKELY UNUSED")
            case "inUse": verdictColored = output.red("IN USE — DO NOT DELETE")
            case "staleReview": verdictColored = output.yellow("STALE REVIEW")
            default: verdictColored = output.dim("UNKNOWN")
            }
            output.printRow(label: "Verdict", value: output.bold(verdictColored))
            output.printRow(label: "Headline", value: dto.headline)
            if let species = dto.species {
                output.printRow(label: "Species", value: species)
            }
            output.printRow(label: "Size", value: dto.sizeFormatted)
            if let regen = dto.regenCommand {
                output.printRow(label: "Regen Command", value: output.cyan(regen))
            }

            print("\n" + output.dim("  EVIDENCE:"))
            for ev in dto.evidence {
                let icon: String
                if ev.favorsDeletion == true {
                    icon = output.green("✓ [deletable]")
                } else if ev.favorsDeletion == false {
                    icon = output.red("✗ [keep]")
                } else {
                    icon = output.dim("• [info]")
                }
                print("  \(icon) \(output.bold(ev.headline))")
                print("         \(output.dim(ev.detail))")
            }
        }
    }
}
