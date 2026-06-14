import AppKit
import Foundation
import Observation
import PulseKit

/// Owns the App Uninstaller flow (§3.14): installed-app discovery, the
/// confidence-graded leftover scan for a chosen app, and the orphan scan.
/// Removal is split across two reversible stores — the `.app` goes to the
/// system Trash (`NSWorkspace.recycle`, Finder "Put Back"); every ticked
/// leftover stages into the Vault. All blocking work runs detached.
@MainActor
@Observable
final class UninstallModel {
    /// The chosen app plus its graded leftovers (nil until a scan completes).
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

    /// Post-uninstall receipt — the "Verify" beat. Every field reflects what
    /// actually happened (real `recycle` result, real Vault session contents),
    /// never an optimistic guess.
    struct UninstallResult: Equatable {
        let appName: String
        let appBundlePath: String
        let appTrashed: Bool
        /// The leftovers that genuinely made it into the Vault.
        let stagedItems: [VaultItem]
        let stagedBytes: UInt64
        /// Leftovers requested but not staged (move failed / needs FDA).
        let failedCount: Int
        /// REVIEW leftovers deliberately left untouched.
        let reviewLeftCount: Int
        let sessionID: UUID?

        var stagedCount: Int { stagedItems.count }
    }

    var tab: Tab = .uninstall

    private(set) var installedApps: [InstalledApp] = []
    private(set) var isLoadingApps = false

    private(set) var plan: Plan?
    private(set) var isScanning = false
    /// Leftover paths the uninstall will stage (SAFE pre-selected).
    private(set) var selection: Set<String> = []
    private(set) var isUninstalling = false

    private(set) var orphans: [CleanItem] = []
    private(set) var isScanningOrphans = false
    private(set) var orphanSelection: Set<String> = []
    private(set) var hasScannedOrphans = false
    private(set) var isRemovingOrphans = false

    /// Honest result line after an action (orphan tab + transient messages).
    private(set) var report: String?
    /// Post-uninstall receipt, shown until dismissed.
    private(set) var result: UninstallResult?
    private(set) var isRestoringResult = false

    private let scanner = UninstallScanner()
    private let vault = SafetyVault(rootURL: SafetyVault.defaultRootURL())

    // MARK: - Lifecycle

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

    // MARK: - Selecting an app

    /// Scans leftovers for an app picked from the installed list.
    func selectApp(_ app: InstalledApp) {
        scan(appPath: app.path, prebuilt: app)
    }

    /// Handles an `.app` dropped onto the drop zone.
    func handleDrop(_ url: URL) {
        guard url.pathExtension == "app" else {
            report = "That isn't an application — drop a .app bundle."
            return
        }
        scan(appPath: url.path, prebuilt: nil)
    }

    private func scan(appPath: String, prebuilt: InstalledApp?) {
        guard !isScanning else { return }
        isScanning = true
        report = nil
        result = nil
        plan = nil
        selection = []
        let appURL = URL(fileURLWithPath: appPath)
        Task.detached(priority: .userInitiated) { [scanner] in
            guard let identity = scanner.identity(forApp: appURL),
                let app = prebuilt ?? scanner.describeApp(at: appURL)
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
                // Default selection = the SAFE tier only, per the safety model.
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
        guard item.grade != .review else { return }  // never bulk-selectable
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

    /// Total removed: app bundle + ticked leftovers.
    var totalRemovalBytes: UInt64 {
        (plan?.app.sizeBytes ?? 0) + selectedLeftoverBytes
    }

    /// True when the target app is currently running — the hard guard.
    var isPlanAppRunning: Bool {
        guard let plan else { return false }
        return !NSRunningApplication.runningApplications(
            withBundleIdentifier: plan.app.bundleID
        ).isEmpty
    }

    // MARK: - Uninstall

    func uninstall() {
        guard let plan, !isUninstalling else { return }
        if isPlanAppRunning {
            report = "Quit \(plan.app.name) first — it's currently running."
            return
        }
        isUninstalling = true
        report = nil
        result = nil
        let appURL = URL(fileURLWithPath: plan.app.path)
        let appName = plan.app.name
        let leftovers = selectedLeftovers.map {
            (path: $0.path, label: $0.label, sizeBytes: $0.sizeBytes)
        }
        let reviewLeft = plan.leftovers.filter { $0.grade == .review }.count

        Task.detached(priority: .userInitiated) { [vault] in
            // 1. App bundle → system Trash (Finder "Put Back" restores it).
            let trashed: Bool = await withCheckedContinuation { continuation in
                NSWorkspace.shared.recycle([appURL]) { _, error in
                    continuation.resume(returning: error == nil)
                }
            }

            // 2. Ticked leftovers → one Vault session (instant APFS rename).
            //    The session's items are the *real* staged contents — a row only
            //    exists if its move truly succeeded.
            var session: VaultSession?
            if !leftovers.isEmpty {
                session = try? vault.stage(
                    items: leftovers, title: "Uninstall \(appName) — \(leftovers.count) leftovers")
            }
            let stagedItems = session?.items ?? []

            let receipt = UninstallResult(
                appName: appName,
                appBundlePath: appURL.path,
                appTrashed: trashed,
                stagedItems: stagedItems,
                stagedBytes: session?.totalBytes ?? 0,
                failedCount: max(0, leftovers.count - stagedItems.count),
                reviewLeftCount: reviewLeft,
                sessionID: session?.id)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isUninstalling = false
                self.result = receipt
                self.plan = nil
                self.selection = []
                // The trashed app is gone — drop it from the installed list.
                if trashed { self.installedApps.removeAll { $0.path == appURL.path } }
            }
        }
    }

    /// Pulls the just-uninstalled app's Vault session back to its original
    /// locations. The `.app` itself is restored by the user via Finder's
    /// "Put Back" — Pulse can't undo a system Trash move programmatically.
    func restoreLastUninstall() {
        guard let result, let sessionID = result.sessionID, !isRestoringResult else { return }
        isRestoringResult = true
        Task.detached(priority: .userInitiated) { [vault] in
            let restored: Int
            if let session = vault.sessions().first(where: { $0.id == sessionID }) {
                restored = (try? vault.restore(session)) ?? 0
            } else {
                restored = 0
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isRestoringResult = false
                self.report =
                    restored > 0
                    ? "Restored \(restored) leftover\(restored == 1 ? "" : "s") to original locations. The app is in the Trash — use Finder’s “Put Back” to restore it."
                    : "Nothing to restore — the Vault session may have already been emptied."
                self.result = nil
            }
        }
    }

    func dismissResult() {
        result = nil
        report = nil
    }

    // MARK: - Orphans

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
        let payload = items.map { (path: $0.path, label: $0.label, sizeBytes: $0.sizeBytes) }
        let removedPaths = Set(items.map(\.id))
        Task.detached(priority: .userInitiated) { [vault] in
            var report: String
            var stagedPaths: Set<String> = []
            if let session = try? vault.stage(
                items: payload, title: "Orphan cleanup — \(payload.count) items")
            {
                stagedPaths = Set(session.items.map(\.originalPath))
                report =
                    "\(session.items.count) orphaned items (\(ByteFormat.string(session.totalBytes))) staged in Vault — restore anytime for 7 days"
            } else {
                report = "Nothing was removed — items may need Full Disk Access."
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isRemovingOrphans = false
                self.report = report
                let staged = stagedPaths.isEmpty ? removedPaths : stagedPaths
                self.orphans.removeAll { staged.contains($0.id) }
                self.orphanSelection.subtract(staged)
            }
        }
    }

    /// LaunchServices lookup — true when the bundle ID resolves to an app on
    /// disk. Non-isolated so the detached orphan scan can call it directly.
    nonisolated static func isBundleInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}
