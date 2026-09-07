import Foundation
import PulseKit

public struct InstalledAppDTO: Codable, Sendable {
    public let name: String
    public let bundleID: String
    public let version: String
    public let path: String
    public let lastUsedDays: Int?

    public init(app: InstalledApp) {
        self.name = app.name
        self.bundleID = app.bundleID
        self.version = app.version
        self.path = app.path
        self.lastUsedDays = app.lastUsedDays
    }
}

public enum UninstallCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let scanner = UninstallScanner()
        let apps = scanner.installedApps()
        if parser.hasFlag("list") || parser.positional.isEmpty {
            let results = apps.map { InstalledAppDTO(app: $0) }
            if output.isJSON { output.emitJSON(results) }
            else { for app in results { print("\(app.name) [\(app.bundleID)] \(app.path)") } }
            return
        }
        do {
            let app = try CLISafety.exactApp(parser.positional[0], apps: apps)
            let url = URL(fileURLWithPath: app.path).standardizedFileURL
            guard !BundleGuard.isProtected(bundleID: app.bundleID),
                  !CLISafety.contains("/System", url.path), app.bundleID != "com.pulse.app",
                  url.pathExtension == "app", url.resolvingSymlinksInPath().path == url.path else {
                throw CLIUsageError("Protected or symlinked application")
            }
            guard let identity = scanner.identity(forApp: url), identity.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame else { throw CLIUsageError("Application identity changed") }
            let running = await CLISafety.activePaths()
            guard !running.contains(where: { CLISafety.contains(url.path, $0) }) else { throw CLIUsageError("Quit the application before uninstalling") }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let excluded = await CleanScheduler().currentSchedule().excludedPaths
            let openPaths = UsageObserver.sampleOpenFiles(includeNoise: true).map(\.path)
            guard !openPaths.contains(where: { CLISafety.contains(url.path, $0) }) else { throw CLIUsageError("Application bundle has open files") }
            let leftovers = scanner.scanLeftovers(for: identity).filter { $0.grade == .safe }.sorted { $0.path < $1.path }
            var report = TrashReport(dryRun: parser.isDryRun)
            let appSize = SmartScanner.directorySize(url)
            let candidates = [(url.path, appSize)] + leftovers.map { ($0.path, $0.sizeBytes) }
            for (path, bytes) in candidates {
                if path != url.path, let reason = CLISafety.refusal(path: path, home: home, excluded: excluded, activePaths: running + openPaths) {
                    report.failures[path] = reason; continue
                }
                if parser.isDryRun { report.affectedPaths.append(path); report.bytesMovedToTrash += bytes; continue }
                do {
                    // Recheck process use immediately before each move.
                    let active = UsageObserver.sampleOpenFiles(includeNoise: true).map(\.path) + (await CLISafety.activePaths())
                    guard !active.contains(where: { CLISafety.contains(path, $0) }) else { throw CLIUsageError("Target became active") }
                    let entry = try await UndoJournal.shared.trashItem(at: URL(fileURLWithPath: path), operation: "CLI Uninstall \(app.name)", bytes: bytes)
                    report.affectedPaths.append(path); report.bytesMovedToTrash += bytes; report.undoIDs.append(entry.id)
                } catch {
                    report.failures[path] = error.localizedDescription
                    if path == url.path { break } // Never remove leftovers after bundle removal fails.
                }
            }
            if output.isJSON { output.emitJSON(report) }
            else {
                output.printHeader(parser.isDryRun ? "Uninstall preview" : "Uninstall result")
                for path in report.affectedPaths { print(path) }
                for (path, reason) in report.failures.sorted(by: { $0.key < $1.key }) { output.printWarning("\(path): \(reason)") }
                print("Only high-confidence leftovers selected. Trash retains disk usage until emptied.")
                for id in report.undoIDs { print("Undo: pulse undo restore \(id)") }
            }
            if !report.failures.isEmpty { exit(1) }
        } catch { output.printError(error.localizedDescription); exit(1) }
    }
}
