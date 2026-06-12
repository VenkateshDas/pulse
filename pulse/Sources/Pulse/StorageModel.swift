import Foundation
import Observation
import PulseKit

/// Owns the storage scan, the clean selection, and the Safety Vault.
/// Scanning is one-shot user-initiated work on a background task — it never
/// joins the 2s sampling loop.
@MainActor
@Observable
final class StorageModel {
    enum ScanState: Equatable {
        case idle
        case scanning
        case done(Date)
    }

    private(set) var scanState: ScanState = .idle
    private(set) var scan: StorageScan?
    private(set) var selection: Set<String> = []
    /// Path of the row whose evidence card is expanded.
    var expandedItem: String?
    private(set) var vaultSessions: [VaultSession] = []
    private(set) var isCleaning = false
    /// Post-clean honesty report ("11.5 GB staged in Vault…").
    private(set) var cleanReport: String?
    /// Finder counts purgeable space as free; the raw number doesn't. The
    /// difference explains "Finder says 50 GB free but I can't use it".
    private(set) var purgeableBytes: UInt64 = 0

    private let vault = SafetyVault(rootURL: SafetyVault.defaultRootURL())

    func appeared() {
        refreshVault()
        refreshPurgeable()
        if scanState == .idle { runScan() }
    }

    func runScan() {
        guard scanState != .scanning else { return }
        scanState = .scanning
        cleanReport = nil
        Task.detached(priority: .userInitiated) {
            let result = SmartScanner().scan()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scan = result
                self.scanState = .done(result.finished)
                // Default selection = safe tier only, per spec.
                self.selection = Set(
                    result.items.filter { $0.grade == .safe }.map(\.id))
            }
        }
    }

    func toggle(_ item: CleanItem) {
        guard item.grade != .review else { return }  // never bulk-selectable
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    var selectedItems: [CleanItem] {
        scan?.items.filter { selection.contains($0.id) } ?? []
    }

    var selectedBytes: UInt64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Stages the selection into the Vault. Nothing is permanently deleted
    /// here — that's the entire safety model.
    func cleanSelected() {
        let items = selectedItems
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        let payload = items.map { (path: $0.path, label: $0.label, sizeBytes: $0.sizeBytes) }
        let title = "Smart Clean — \(items.count) items"
        Task.detached(priority: .userInitiated) { [vault] in
            var report: String
            var stagedPaths: Set<String> = []
            do {
                let session = try vault.stage(items: payload, title: title)
                stagedPaths = Set(session.items.map(\.originalPath))
                let staged = ByteFormat.string(session.totalBytes)
                report =
                    session.items.count == payload.count
                    ? "\(staged) staged in Vault — restore anytime for 7 days"
                    : "\(staged) staged (\(payload.count - session.items.count) items skipped) — restore anytime for 7 days"
            } catch {
                report = "Nothing was cleaned — items may have moved or need Full Disk Access"
            }
            await MainActor.run { [weak self, stagedPaths, report] in
                guard let self else { return }
                self.isCleaning = false
                self.cleanReport = report
                self.refreshVault()
                self.removeStagedFromScan(stagedPaths)
            }
        }
    }

    func restore(_ session: VaultSession) {
        Task.detached(priority: .userInitiated) { [vault] in
            let restored = (try? vault.restore(session)) ?? 0
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanReport =
                    restored > 0
                    ? "Restored \(restored) items to their original locations"
                    : "Restore failed — vault contents may have been removed"
                self.refreshVault()
            }
        }
    }

    /// The one irreversible action: permanently delete a session. This is
    /// where disk space actually frees, verified against the volume.
    func purge(_ session: VaultSession) {
        Task.detached(priority: .userInitiated) { [vault] in
            let before = Self.rawFreeBytes()
            vault.purge(session)
            let after = Self.rawFreeBytes()
            await MainActor.run { [weak self] in
                guard let self else { return }
                let freed = after > before ? after - before : 0
                self.cleanReport =
                    "Vault purged — \(ByteFormat.string(freed)) freed, verified against the disk"
                self.refreshVault()
                self.refreshPurgeable()
            }
        }
    }

    var vaultTotalBytes: UInt64 {
        vaultSessions.reduce(0) { $0 + $1.totalBytes }
    }

    private func refreshVault() {
        vault.purgeExpired()
        vaultSessions = vault.sessions()
    }

    /// Removes only the rows that actually made it into the Vault — rows
    /// whose move failed stay visible and selected for a retry.
    private func removeStagedFromScan(_ stagedPaths: Set<String>) {
        guard let old = scan, !stagedPaths.isEmpty else { return }
        let remaining = old.items.filter { !stagedPaths.contains($0.path) }
        scan = StorageScan(
            items: remaining, topFolders: old.topFolders,
            scannedFiles: old.scannedFiles, finished: old.finished)
        selection.subtract(stagedPaths)
    }

    private func refreshPurgeable() {
        let root = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ]
        guard let values = try? root.resourceValues(forKeys: keys) else { return }
        let finder = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let raw = UInt64(values.volumeAvailableCapacity ?? 0)
        purgeableBytes = finder > raw ? finder - raw : 0
    }

    private nonisolated static func rawFreeBytes() -> UInt64 {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityKey
        ])
        return UInt64(values?.volumeAvailableCapacity ?? 0)
    }
}
