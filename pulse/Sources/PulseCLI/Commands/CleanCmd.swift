import Foundation
import PulseKit

public struct CleanItemDTO: Encodable, Sendable {
    public let id: String
    public let category: String
    public let label: String
    public let path: String
    public let sizeBytes: UInt64
    public let grade: String
    public let refusal: String?
}
public struct TrashReport: Encodable {
    public var dryRun: Bool
    public var affectedPaths: [String] = []
    public var bytesMovedToTrash: UInt64 = 0
    public var undoIDs: [UUID] = []
    public var failures: [String: String] = [:]
}
public enum CleanCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let excluded = await CleanScheduler().currentSchedule().excludedPaths
        let appPaths = await CLISafety.activePaths()
        let openPaths = UsageObserver.sampleOpenFiles(includeNoise: true).map(\.path)
        // Catalog only: no recursive whole-home discovery of personal documents.
        let items = (CleanCatalog.knownTargets + CleanCatalog.developerTargets).flatMap { target -> [CleanItemDTO] in
            let root = URL(fileURLWithPath: home).appendingPathComponent(target.rel)
            let urls = target.expand ? ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []) : [root]
            return urls.filter { FileManager.default.fileExists(atPath: $0.path) }.map { url in
                CleanItemDTO(id: url.path, category: target.category, label: url.lastPathComponent, path: url.path,
                    sizeBytes: CLISafety.refusal(path: url.path, home: home) == nil ? SmartScanner.directorySize(url) : 0,
                    grade: target.grade.rawValue, refusal: CLISafety.refusal(path: url.path, home: home, excluded: excluded, activePaths: appPaths + openPaths))
            }
        }
        let unique = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.id < $1.id }
        let scanOnly = parser.hasFlag("scan") || (parser.stringOption("target") == nil && !parser.hasFlag("all-safe"))
        if scanOnly {
            if output.isJSON { output.emitJSON(unique) }
            else {
                output.printHeader("Clean targets — IDs are exact paths")
                for item in unique { print("\(item.id)  \(CLIOutput.bytes(Int64(clamping: item.sizeBytes)))  [\(item.grade)] \(item.refusal ?? "")") }
            }
            return
        }
        var selected = unique.filter { item in
            if let target = parser.stringOption("target") { return item.id == target }
            return item.grade == "safe" && item.refusal == nil
        }
        guard !selected.isEmpty else { output.printError("No eligible target; copy an exact ID from clean --scan"); exit(1) }
        // Remove nested duplicates: trashing a parent already includes its children.
        selected = selected.filter { item in !selected.contains { $0.path != item.path && CLISafety.contains($0.path, item.path) } }
        var report = TrashReport(dryRun: parser.isDryRun)
        for item in selected {
            if let refusal = item.refusal { report.failures[item.path] = refusal; continue }
            if parser.isDryRun { report.affectedPaths.append(item.path); report.bytesMovedToTrash += item.sizeBytes; continue }
            do {
                let active = UsageObserver.sampleOpenFiles(includeNoise: true).map(\.path) + (await CLISafety.activePaths())
                if let reason = CLISafety.refusal(path: item.path, home: home, excluded: excluded, activePaths: active) { throw CLIUsageError(reason) }
                let entry = try await UndoJournal.shared.trashItem(at: URL(fileURLWithPath: item.path), operation: "CLI Clean", bytes: item.sizeBytes)
                report.affectedPaths.append(item.path); report.bytesMovedToTrash += item.sizeBytes; report.undoIDs.append(entry.id)
            } catch { report.failures[item.path] = error.localizedDescription }
        }
        if output.isJSON { output.emitJSON(report) }
        else {
            output.printHeader(parser.isDryRun ? "Clean preview" : "Moved to Trash")
            for path in report.affectedPaths { print(path) }
            for (path, error) in report.failures.sorted(by: { $0.key < $1.key }) { output.printWarning("\(path): \(error)") }
            print("\(report.bytesMovedToTrash) bytes \(parser.isDryRun ? "selected" : "moved"). Space is freed only when Trash is emptied.")
            for id in report.undoIDs { print("Undo: pulse undo restore \(id)") }
        }
        if !report.failures.isEmpty { exit(1) }
    }
}
