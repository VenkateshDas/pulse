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

    /// A removal target awaiting (or retrying) a move into the Vault.
    struct PendingItem: Equatable, Sendable {
        let path: String
        let label: String
        let sizeBytes: UInt64
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
        /// Leftovers requested but not staged (move failed / needs FDA) —
        /// retained so a retry can re-attempt exactly these.
        let failedItems: [PendingItem]
        /// REVIEW leftovers deliberately left untouched.
        let reviewLeftCount: Int
        /// Every Vault session this uninstall (plus retries) produced.
        let sessionIDs: [UUID]

        var stagedCount: Int { stagedItems.count }
        var failedCount: Int { failedItems.count }
        /// Something didn't complete — the app stayed put or a leftover failed.
        var needsAttention: Bool { !appTrashed || !failedItems.isEmpty }
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
            let trashed = Self.moveAppToTrash(appURL)

            // 2. Ticked leftovers → one Vault session (instant APFS rename).
            //    The session's items are the *real* staged contents — a row only
            //    exists if its move truly succeeded.
            var session: VaultSession?
            if !leftovers.isEmpty {
                session = try? vault.stage(
                    items: leftovers, title: "Uninstall \(appName) — \(leftovers.count) leftovers")
            }
            let stagedItems = session?.items ?? []
            let stagedPaths = Set(stagedItems.map(\.originalPath))
            let failed = leftovers
                .filter { !stagedPaths.contains($0.path) }
                .map { PendingItem(path: $0.path, label: $0.label, sizeBytes: $0.sizeBytes) }

            let receipt = UninstallResult(
                appName: appName,
                appBundlePath: appURL.path,
                appTrashed: trashed,
                stagedItems: stagedItems,
                stagedBytes: session?.totalBytes ?? 0,
                failedItems: failed,
                reviewLeftCount: reviewLeft,
                sessionIDs: session.map { [$0.id] } ?? [])

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

    /// Re-attempts only the parts that failed (the app move and/or unstaged
    /// leftovers) — used after the user grants Full Disk Access. Merges the new
    /// outcome into the existing receipt so the list stays cumulative.
    func retryUninstall() {
        guard let previous = result, previous.needsAttention, !isUninstalling else { return }
        isUninstalling = true
        report = nil
        let appURL = URL(fileURLWithPath: previous.appBundlePath)
        let appName = previous.appName
        let needsTrash = !previous.appTrashed
        let failed = previous.failedItems.map {
            (path: $0.path, label: $0.label, sizeBytes: $0.sizeBytes)
        }

        Task.detached(priority: .userInitiated) { [vault] in
            var trashed = previous.appTrashed
            if needsTrash {
                trashed = Self.moveAppToTrash(appURL)
            }

            var session: VaultSession?
            if !failed.isEmpty {
                session = try? vault.stage(
                    items: failed, title: "Uninstall \(appName) (retry) — \(failed.count) leftovers")
            }
            let newlyStaged = session?.items ?? []
            let newlyStagedPaths = Set(newlyStaged.map(\.originalPath))
            let stillFailed = previous.failedItems.filter { !newlyStagedPaths.contains($0.path) }

            let merged = UninstallResult(
                appName: appName,
                appBundlePath: previous.appBundlePath,
                appTrashed: trashed,
                stagedItems: previous.stagedItems + newlyStaged,
                stagedBytes: previous.stagedBytes + (session?.totalBytes ?? 0),
                failedItems: stillFailed,
                reviewLeftCount: previous.reviewLeftCount,
                sessionIDs: previous.sessionIDs + (session.map { [$0.id] } ?? []))

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isUninstalling = false
                self.result = merged
                if trashed { self.installedApps.removeAll { $0.path == appURL.path } }
                if !merged.needsAttention {
                    self.report = "All set — \(appName) and its leftovers are fully removed."
                }
            }
        }
    }

    /// Moves an app bundle to the system Trash. Uses `FileManager.trashItem`
    /// (not `NSWorkspace.recycle`): recycle silently fails on Mac App Store
    /// bundles carrying a `com.apple.macl` sandbox xattr, while `trashItem`
    /// performs the same rename into `~/.Trash` and still records Finder
    /// "Put Back" metadata. Succeeds whenever the parent dir is writable
    /// (`/Applications` is writable by admin users), regardless of the
    /// bundle's own root ownership.
    nonisolated static func moveAppToTrash(_ url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            // Fallback: if even trashItem refuses, a direct rename into
            // ~/.Trash works whenever the parent dir is writable (it loses
            // the Finder "Put Back" anchor, but the app is still recoverable).
            let trash = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash")
            var dest = trash.appendingPathComponent(url.lastPathComponent)
            var counter = 2
            while FileManager.default.fileExists(atPath: dest.path) {
                let base = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                dest = trash.appendingPathComponent(
                    ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
                counter += 1
            }
            return (try? FileManager.default.moveItem(at: url, to: dest)) != nil
        }
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access so the
    /// user can grant Pulse the access a system-area move needs.
    func openFullDiskAccessSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Pulls the just-uninstalled app's Vault session back to its original
    /// locations. The `.app` itself is restored by the user via Finder's
    /// "Put Back" — Pulse can't undo a system Trash move programmatically.
    func restoreLastUninstall() {
        guard let result, !result.sessionIDs.isEmpty, !isRestoringResult else { return }
        isRestoringResult = true
        let ids = Set(result.sessionIDs)
        Task.detached(priority: .userInitiated) { [vault] in
            var restored = 0
            for session in vault.sessions() where ids.contains(session.id) {
                restored += (try? vault.restore(session)) ?? 0
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
