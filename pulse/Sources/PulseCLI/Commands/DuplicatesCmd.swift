import Foundation
import PulseKit

public struct DuplicateGroupDTO: Codable, Sendable {
    public let hash: String
    public let fileSize: Int64
    public let fileSizeFormatted: String
    public let fileCount: Int
    public let isAPFSClone: Bool
    public let totalReclaimableBytes: Int64
    public let totalReclaimableFormatted: String
    public let paths: [String]

    public init(group: DuplicateScanner.DuplicateGroup) {
        self.hash = group.id
        self.fileSize = group.fileSize
        self.fileSizeFormatted = CLIOutput.bytes(group.fileSize)
        self.fileCount = group.files.count
        self.isAPFSClone = group.isAPFSClone
        self.totalReclaimableBytes = group.totalReclaimableBytes
        self.totalReclaimableFormatted = CLIOutput.bytes(group.totalReclaimableBytes)
        self.paths = group.files.map(\.url.path).sorted()
    }
}

public enum DuplicatesCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        guard let path = parser.positional.first else {
            output.printError("Missing directory path to scan. Usage: pulse duplicates <path> [--json]")
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

        if !output.isJSON {
            print(output.dim("Scanning '\(resolvedURL.path)' for duplicate files (size bucketing + BLAKE3 hash)..."))
        }

        let scanner = DuplicateScanner(minFileSize: Int64((parser.doubleOption("min-size-mb") ?? (4096.0 / 1_048_576)) * 1_048_576))
        do {
            let groups = try await scanner.scan(directories: [resolvedURL]) { _ in }
            let dtos = groups.sorted { $0.id < $1.id }.map { DuplicateGroupDTO(group: $0) }
            let totalReclaimable = groups.reduce(0) { $0 + $1.totalReclaimableBytes }

            if output.isJSON {
                struct Report: Encodable { let scannedPath: String; let duplicateGroupsCount: Int; let totalReclaimableBytes: Int64; let groups: [DuplicateGroupDTO] }
                output.emitJSON(Report(scannedPath: resolvedURL.path, duplicateGroupsCount: dtos.count, totalReclaimableBytes: totalReclaimable, groups: dtos))
            } else {
                output.printHeader("Duplicate Files: \(resolvedURL.path)")
                output.printRow(label: "Duplicate Groups", value: "\(dtos.count) set(s)")
                output.printRow(label: "Reclaimable Space", value: output.bold(output.green(CLIOutput.bytes(totalReclaimable))))

                if dtos.isEmpty {
                    print("\n  \(output.green("✓")) No duplicate files found.")
                } else {
                    for g in dtos.prefix(10) {
                        let cloneTag = g.isAPFSClone ? output.dim(" [APFS clone - zero space]") : ""
                        print("\n  • \(output.bold(g.fileSizeFormatted)) per file (\(g.fileCount) copies)\(cloneTag)")
                        for p in g.paths {
                            print("    \(output.dim(p))")
                        }
                    }
                }
            }
        } catch {
            output.printError("Failed to scan duplicates: \(error.localizedDescription)")
            exit(1)
        }
    }
}
