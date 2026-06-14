import AppKit
import Foundation
import Observation
import PulseKit

/// Owns the App Uninstaller flow (§3.14): installed-app discovery, the
/// confidence-graded leftover scan for a chosen app, and the orphan scan.
/// Removal is split across two reversible stores — the `.app` goes to the
/// system Trash (Finder "Put Back"); every ticked leftover stages into the
/// Vault. All blocking work (scan, trash, stage) runs on detached tasks.
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
        /// Carried so a retry can re-check the running-app guard.
        let appBundleID: String
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
        /// The app bundle move failed — an App Management / Finder-consent issue,
        /// distinct from leftover (Full Disk Access) failures.
        var appNeedsAttention: Bool { !appTrashed }
        /// Leftovers couldn't be staged — the genuine Full Disk Access case.
        var leftoversNeedAttention: Bool { !failedItems.isEmpty }
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

    /// Memoized file icons so SwiftUI row builders don't re-hit LaunchServices
    /// on every render (e.g. each keystroke in the installed-app filter).
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    /// Cached icon for a path — fetched once per path, not once per render.
    func icon(for path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = image
        return image
    }

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
        scan(appPath: app.path)
    }

    /// Handles an `.app` dropped onto the drop zone.
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
            // describeApp computes the real bundle size here (the installed-app
            // list defers it to keep its load cheap), so the plan/receipt show
            // an accurate size for just the one chosen app.
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

    /// True when the bundle ID has a running instance — the hard guard against
    /// trashing a live app.
    nonisolated static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// True when the currently-planned app is running.
    var isPlanAppRunning: Bool {
        guard let plan else { return false }
        return Self.isRunning(plan.app.bundleID)
    }

    // MARK: - Uninstall

    func uninstall() {
        guard let plan, !isUninstalling else { return }
        if isPlanAppRunning {
            report = "Quit \(plan.app.name) first — it's currently running."
            return
        }
        result = nil
        let reviewLeft = plan.leftovers.filter { $0.grade == .review }.count
        perform(
            appURL: URL(fileURLWithPath: plan.app.path),
            appName: plan.app.name,
            bundleID: plan.app.bundleID,
            needsTrash: true,
            leftovers: selectedLeftovers.map {
                PendingItem(path: $0.path, label: $0.label, sizeBytes: $0.sizeBytes)
            },
            reviewLeft: reviewLeft,
            titleSuffix: "",
            base: nil)
        self.plan = nil
        self.selection = []
    }

    /// Re-attempts only the parts that failed (the app move and/or unstaged
    /// leftovers) — used after the user grants the missing permission. Merges
    /// the new outcome into the existing receipt so the list stays cumulative.
    func retryUninstall() {
        guard let previous = result, previous.needsAttention, !isUninstalling else { return }
        let needsTrash = !previous.appTrashed
        // Same running-app guard as the first pass: never trash a live app.
        if needsTrash, Self.isRunning(previous.appBundleID) {
            report = "Quit \(previous.appName) first — it's currently running."
            return
        }
        perform(
            appURL: URL(fileURLWithPath: previous.appBundlePath),
            appName: previous.appName,
            bundleID: previous.appBundleID,
            needsTrash: needsTrash,
            leftovers: previous.failedItems,
            reviewLeft: previous.reviewLeftCount,
            titleSuffix: " (retry)",
            base: previous)
    }

    /// Shared engine for both the first uninstall and a retry. Trashes the app
    /// (if needed) and stages the leftovers on a background task, then builds a
    /// receipt — accumulating onto `base` when this is a retry. Runs entirely
    /// off the main actor so the Finder consent / admin prompt never freezes
    /// the UI; only the final state write hops back to the main actor.
    private func perform(
        appURL: URL, appName: String, bundleID: String, needsTrash: Bool,
        leftovers: [PendingItem], reviewLeft: Int, titleSuffix: String, base: UninstallResult?
    ) {
        isUninstalling = true
        report = nil
        Task.detached(priority: .userInitiated) { [vault] in
            let trashed = needsTrash ? Self.moveAppToTrash(appURL) : (base?.appTrashed ?? true)

            let session: VaultSession? =
                leftovers.isEmpty
                ? nil
                : try? vault.stage(
                    items: leftovers.map {
                        (path: $0.path, label: $0.label, sizeBytes: $0.sizeBytes)
                    },
                    title: "Uninstall \(appName)\(titleSuffix) — \(leftovers.count) leftovers")

            // Real staged contents only — a row exists iff its move succeeded.
            let newlyStaged = session?.items ?? []
            let stagedPaths = Set(newlyStaged.map(\.originalPath))
            let stillFailed = leftovers.filter { !stagedPaths.contains($0.path) }

            let receipt = UninstallResult(
                appName: appName,
                appBundlePath: appURL.path,
                appBundleID: bundleID,
                appTrashed: trashed,
                stagedItems: (base?.stagedItems ?? []) + newlyStaged,
                stagedBytes: (base?.stagedBytes ?? 0) + (session?.totalBytes ?? 0),
                failedItems: stillFailed,
                reviewLeftCount: reviewLeft,
                sessionIDs: (base?.sessionIDs ?? []) + (session.map { [$0.id] } ?? []))

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isUninstalling = false
                self.result = receipt
                if trashed { self.installedApps.removeAll { $0.path == appURL.path } }
                if base != nil, !receipt.needsAttention {
                    self.report = "All set — \(appName) and its leftovers are fully removed."
                }
            }
        }
    }

    /// Moves an app bundle to the system Trash, handling macOS's protections:
    ///
    /// 1. `FileManager.trashItem` — fast, silent, works for ordinary
    ///    user-writable apps and keeps Finder "Put Back".
    /// 2. If that fails (Mac App Store bundles with a `com.apple.macl` xattr
    ///    live under **App Management** protection — a separate gate from Full
    ///    Disk Access that blocks a GUI app from moving *other* apps' bundles),
    ///    ask **Finder** to trash it via Apple Events. Finder is exempt from
    ///    App Management and prompts for admin auth exactly like a manual
    ///    drag-to-Trash. `NSAppleScript` sends Apple Events in-process — no
    ///    subprocess. Called off the main actor so its modal prompt never
    ///    freezes the UI.
    ///
    /// Returns true only if the Apple Event reported no error AND the bundle
    /// actually left its original location (so a denied consent prompt or a
    /// coincidentally-missing path is never mistaken for success).
    nonisolated static func moveAppToTrash(_ url: URL) -> Bool {
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
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
        // Confirm against the filesystem, not just the event result.
        return !FileManager.default.fileExists(atPath: url.path)
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
