import Foundation
import PulseKit

public struct GrowthGroupDTO: Codable, Sendable {
    public struct FileDTO: Codable, Sendable {
        public let name: String
        public let sizeFormatted: String
        public let sizeBytes: UInt64
    }

    public let path: String
    public let name: String
    public let recentBytes: UInt64
    public let recentFormatted: String
    public let fileCount: Int
    public let topFiles: [FileDTO]

    public init(group: GrowthGroup) {
        self.path = group.path
        self.name = group.name
        self.recentBytes = group.recentBytes
        self.recentFormatted = CLIOutput.bytes(Int64(group.recentBytes))
        self.fileCount = group.fileCount
        self.topFiles = group.topFiles.map {
            FileDTO(
                name: $0.name,
                sizeFormatted: CLIOutput.bytes(Int64($0.sizeBytes)),
                sizeBytes: $0.sizeBytes
            )
        }
    }
}

public struct GrowthReportDTO: Codable, Sendable {
    public let days: Int
    public let totalRecentBytes: UInt64
    public let totalRecentFormatted: String
    public let scannedFiles: Int
    public let groups: [GrowthGroupDTO]
}

public enum GrowthCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let days = parser.intOption("days", "d", default: 1) ?? 1
        let limit = parser.intOption("limit", "n", default: 5) ?? 5

        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let scanner = RecentGrowthScanner()

        if !output.isJSON {
            print(output.dim("Scanning volume for files modified in the last \(days) day(s)..."))
        }

        let report = await Task.detached {
            scanner.scan(since: cutoff)
        }.value

        let topGroups = Array(report.groups.prefix(limit)).map { GrowthGroupDTO(group: $0) }
        let dto = GrowthReportDTO(
            days: days,
            totalRecentBytes: report.totalRecentBytes,
            totalRecentFormatted: CLIOutput.bytes(Int64(report.totalRecentBytes)),
            scannedFiles: report.scannedFiles,
            groups: topGroups
        )

        if output.isJSON {
            output.emitJSON(dto)
        } else {
            output.printHeader("Disk Growth (Past \(days) Day(s))")
            output.printRow(label: "Total Recent Growth", value: output.bold(dto.totalRecentFormatted))
            output.printRow(label: "Files Scanned", value: "\(dto.scannedFiles)")

            if dto.groups.isEmpty {
                print("\n  \(output.green("✓")) No significant folder growth (> 25 MB) detected.")
            } else {
                print("\n" + output.dim("  TOP GROWTH DIRECTORIES:"))
                for g in dto.groups {
                    print("  \(output.bold(output.cyan(g.recentFormatted)))  \(g.path) (\(g.fileCount) files)")
                    for f in g.topFiles.prefix(3) {
                        print("    • \(f.sizeFormatted.padding(toLength: 10, withPad: " ", startingAt: 0)) \(output.dim(f.name))")
                    }
                }
            }
        }
    }
}
