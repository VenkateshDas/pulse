import AppKit
import Foundation
import Observation
import PulseKit

@MainActor
@Observable
final class UninstallModel {
    struct Plan: Equatable {
        let app: InstalledApp
        let identity: AppIdentity
        let leftovers: [CleanItem]
    }

    enum Tab: String, CaseIterable, Identifiable {
        case uninstall = "Uninstall"
        case orphans = "Orphans"
        var id: String { rawValue }
    }

    struct PendingItem: Equatable, Sendable {
        let path: String
        let label: String
        let sizeBytes: UInt64
    }

    struct UninstallResult: Equatable {
        let appName: String
        let appBundlePath: String
        let appBundleID: String
        let appTrashed: Bool
        let trashedLeftovers: [PendingItem]
        let trashedBytes: UInt64
        let failedItems: [PendingItem]
        let reviewLeftCount: Int

        var trashedCount: Int { trashedLeftovers.count }
        var failedCount: Int { failedItems.count }
        var needsAttention: Bool { !appTrashed || !failedItems.isEmpty }
        var appNeedsAttention: Bool { !appTrashed }
        var leftoversNeedAttention: Bool { !failedItems.isEmpty }
    }

    var tab: Tab = .uninstall

    private(set) var installedApps: [InstalledApp] = []
    private(set) var isLoadingApps = false

    private(set) var plan: Plan?
    private(set) var isScanning = false
    private(set) var selection: Set<String> = []
    private(set) var isUninstalling = false

    private(set) var orphans: [CleanItem] = []
    private(set) var isScanningOrphans = false
    private(set) var orphanSelection: Set<String> = []
    private(set) var hasScannedOrphans = false
    private(set) var isRemovingOrphans = false

    private(set) var report: String?
    private(set) var result: UninstallResult?

    private let scanner = UninstallScanner()

    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = image
        return image
    }

    func appeared() {
        if installedApps.isEmpty { loadInstalledApps() }
    }

    func loadInstalledApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        Task.detached(priority: .userInitiated) { [scanner] in
            let apps = scanner.installedApps()
            await MainActor.run { [weak self] in
                self?.installedApps = apps
                self?.isLoadingApps = false
            }
        }
    }

    func selectApp(_ app: InstalledApp) {
        scan(appPath: app.path)
    }

    func handleDrop(_ url: URL) {
        guard url.pathExtension == "app" else {
            report = "That isn't an application — drop a .app bundle."
            return
        }
        scan(appPath: url.path)
    }

    private func scan(appPath: String) {
        guard !isScanning else { return }
        isScanning = true
        report = nil
        result = nil
        plan = nil
        selection = []
        let appURL = URL(fileURLWithPath: appPath)
        Task.detached(priority: .userInitiated) { [scanner] in
            guard let identity = scanner.identity(forApp: appURL),
                let app = scanner.describeApp(at: appURL)
            else {
                await MainActor.run { [weak self] in
                    self?.isScanning = false
                    self?.report = "Couldn't read that app's Info.plist."
                }
                return
            }
            let leftovers = scanner.scanLeftovers(for: identity)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.plan = Plan(app: app, identity: identity, leftovers: leftovers)
                self.selection = Set(leftovers.filter { $0.grade == .safe }.map(\.id))
                self.isScanning = false
            }
        }
    }

    func clearPlan() {
        plan = nil
        selection = []
        report = nil
    }

    func toggle(_ item: CleanItem) {
        guard item.grade != .review else { return }
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    var selectedLeftovers: [CleanItem] {
        plan?.leftovers.filter { selection.contains($0.id) } ?? []
    }

    var selectedLeftoverBytes: UInt64 {
        selectedLeftovers.reduce(0) { $0 + $1.sizeBytes }
    }

    var totalRemovalBytes: UInt64 {
        (plan?.app.sizeBytes ?? 0) + selectedLeftoverBytes
    }

    var isPlanAppRunning: Bool {
        guard let plan else { return false }
        return Self.isRunning(plan.app.bundleID)
    }

    nonisolated static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func uninstall() {
        guard let plan, !isUninstalling else { return }
        if isPlanAppRunning {
            report = "Quit \(plan.app.name) first — it's currently running."
            return
        }
        result = nil
        _ = plan.leftovers.filter { $0.grade == .review }.count
        let needsTrash = Self.isRunning(plan.identity.bundleID) == false
        let leftovers = selectedLeftovers
        let unselected = plan.leftovers.count - leftovers.count
        uninstall(
            plan.app.name, appURL: URL(fileURLWithPath: plan.app.path),
            bundleID: plan.identity.bundleID,
            leftovers: leftovers, reviewLeft: unselected, needsTrash: needsTrash
        )
    }

    func retryUninstall() {
        guard let result, result.needsAttention, !isUninstalling else { return }
        let needsTrash = !result.appTrashed && Self.isRunning(result.appBundleID) == false
        let leftovers = result.failedItems.map {
            CleanItem(category: "Cache", label: $0.label, detail: "", path: $0.path, sizeBytes: $0.sizeBytes, idleDays: nil, grade: .safe)
        }
        uninstall(
            result.appName, appURL: URL(fileURLWithPath: result.appBundlePath),
            bundleID: result.appBundleID,
            leftovers: leftovers, reviewLeft: result.reviewLeftCount,
            needsTrash: needsTrash, base: result, titleSuffix: " (retry)"
        )
    }

    private func uninstall(
        _ appName: String, appURL: URL, bundleID: String,
        leftovers: [CleanItem], reviewLeft: Int,
        needsTrash: Bool, base: UninstallResult? = nil, titleSuffix: String = ""
    ) {
        isUninstalling = true
        report = nil
        Task.detached(priority: .userInitiated) {
            let trashed = needsTrash ? Self.moveAppToTrash(appURL) : (base?.appTrashed ?? true)

            var trashedLeftovers: [PendingItem] = []
            var failedItems: [PendingItem] = []
            var trashedBytes: UInt64 = 0

            var trashedJournalItems: [TrashedItem] = []

            for item in leftovers {
                do {
                    var trashedURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &trashedURL)
                    trashedLeftovers.append(PendingItem(path: item.path, label: item.label, sizeBytes: item.sizeBytes))
                    trashedBytes += item.sizeBytes
                    if let trashPath = trashedURL?.path {
                        trashedJournalItems.append(TrashedItem(originalPath: item.path, trashPath: trashPath))
                    }
                } catch {
                    failedItems.append(PendingItem(path: item.path, label: item.label, sizeBytes: item.sizeBytes))
                }
            }
            
            if !trashedJournalItems.isEmpty {
                await UndoJournal.shared.record(UndoEntry(op: "Uninstall Leftovers (\(appName))", items: trashedJournalItems, bytesFreed: Int64(trashedBytes)))
            }

            let receipt = UninstallResult(
                appName: appName,
                appBundlePath: appURL.path,
                appBundleID: bundleID,
                appTrashed: trashed,
                trashedLeftovers: (base?.trashedLeftovers ?? []) + trashedLeftovers,
                trashedBytes: (base?.trashedBytes ?? 0) + trashedBytes,
                failedItems: failedItems,
                reviewLeftCount: reviewLeft)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isUninstalling = false
                self.result = receipt
                if trashed || !trashedLeftovers.isEmpty { TrashSound.moveToTrash() }
                if trashed {
                    self.installedApps.removeAll { $0.path == appURL.path }
                    // Self-healing: a removed app may leave launch agents/daemons
                    // behind, so refresh the Orphans pane right after.
                    self.hasScannedOrphans = false
                    self.scanOrphans()
                }
                if base != nil, !receipt.needsAttention {
                    self.report = "All set — \(appName) and its leftovers are fully removed."
                }
            }
        }
    }

    nonisolated static func moveAppToTrash(_ url: URL) -> Bool {
        var trashedURL: NSURL?
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)) != nil {
            if let trashPath = trashedURL?.path {
                let tItem = TrashedItem(originalPath: url.path, trashPath: trashPath)
                Task { await UndoJournal.shared.record(UndoEntry(op: "Uninstall App", items: [tItem], bytesFreed: 0)) }
            }
            return true
        }
        let escaped = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Finder\" to delete (POSIX file \"\(escaped)\" as alias)"
        var scriptError: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&scriptError)
        guard script != nil, scriptError == nil else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    func openFullDiskAccessSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissResult() {
        result = nil
        report = nil
        plan = nil
    }

    func scanOrphans() {
        guard !isScanningOrphans else { return }
        isScanningOrphans = true
        report = nil
        Task.detached(priority: .userInitiated) { [scanner] in
            let found = scanner.scanOrphans(resolver: Self.isBundleInstalled)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.orphans = found
                self.orphanSelection = []
                self.hasScannedOrphans = true
                self.isScanningOrphans = false
            }
        }
    }

    func toggleOrphan(_ item: CleanItem) {
        if orphanSelection.contains(item.id) {
            orphanSelection.remove(item.id)
        } else {
            orphanSelection.insert(item.id)
        }
    }

    var selectedOrphans: [CleanItem] {
        orphans.filter { orphanSelection.contains($0.id) }
    }

    var selectedOrphanBytes: UInt64 {
        selectedOrphans.reduce(0) { $0 + $1.sizeBytes }
    }

    func removeOrphans() {
        let items = selectedOrphans
        guard !items.isEmpty, !isRemovingOrphans else { return }
        isRemovingOrphans = true
        report = nil
        Task.detached(priority: .userInitiated) {
            var trashedPaths: Set<String> = []
            var trashedBytes: UInt64 = 0
            for item in items {
                // Unload a running user launch agent before trashing its plist,
                // so the change takes effect now (not just next login). Daemons
                // need root to bootout and are left to unload on reboot.
                await Self.bootoutUserAgentIfNeeded(path: item.path)
                do {
                    var trashedURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &trashedURL)
                    trashedPaths.insert(item.id)
                    trashedBytes += item.sizeBytes
                    if let trashPath = trashedURL?.path {
                        let tItem = TrashedItem(originalPath: item.path, trashPath: trashPath)
                        await UndoJournal.shared.record(UndoEntry(op: "Remove Orphan", items: [tItem], bytesFreed: Int64(item.sizeBytes)))
                    }
                } catch {
                }
            }
            var report: String
            if !trashedPaths.isEmpty {
                report = "\(trashedPaths.count) orphaned items (\(ByteFormat.string(trashedBytes))) moved to Trash."
            } else {
                report = "Nothing was removed — items may need Full Disk Access."
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isRemovingOrphans = false
                if !trashedPaths.isEmpty { TrashSound.moveToTrash() }
                self.report = report
                self.orphans.removeAll { trashedPaths.contains($0.id) }
                self.orphanSelection.subtract(trashedPaths)
            }
        }
    }

    nonisolated static func isBundleInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// `launchctl bootout` for a user LaunchAgent plist (gui domain, no root),
    /// so disabling it unloads the running job immediately. No-op for system
    /// `/Library` jobs (need root) and non-agent paths.
    nonisolated static func bootoutUserAgentIfNeeded(path: String) async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home), path.contains("/LaunchAgents/"),
            path.hasSuffix(".plist"),
            let plist = UninstallScanner.readLaunchPlist(URL(fileURLWithPath: path)),
            let label = plist["Label"] as? String, !label.isEmpty
        else { return }
        _ = try? await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
    }
}
