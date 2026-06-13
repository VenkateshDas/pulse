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
    private(set) var rootNode: StorageNode?
    private(set) var navigationPath: [StorageNode] = []
    private(set) var selection: Set<String> = []
    /// Path of the row whose evidence card is expanded.
    var expandedItem: String?
    private(set) var vaultSessions: [VaultSession] = []
    var vaultSelection: Set<String> = []
    private(set) var isCleaning = false
    private(set) var isStreamingSizes = false
    /// Post-clean honesty report ("11.5 GB staged in Vault…").
    private(set) var cleanReport: String?
    /// Finder counts purgeable space as free; the raw number doesn't. The
    /// difference explains "Finder says 50 GB free but I can't use it".
    private(set) var purgeableBytes: UInt64 = 0
    /// System Trash size/count — files in Trash still occupy disk until emptied.
    private(set) var trashBytes: UInt64 = 0
    private(set) var trashItemCount: Int = 0

    /// User-configurable Vault retention window (1–30 days), persisted in
    /// UserDefaults. Drives auto-expiry and the per-session countdown.
    var retentionDays: Int {
        didSet {
            let clamped = min(30, max(1, retentionDays))
            if clamped != retentionDays { retentionDays = clamped; return }
            UserDefaults.standard.set(clamped, forKey: Self.retentionKey)
            vault = SafetyVault(rootURL: SafetyVault.defaultRootURL(), retentionDays: clamped)
            refreshVault()
        }
    }
    private static let retentionKey = "PulseVaultRetentionDays"

    private var vault: SafetyVault

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.retentionKey)
        let days = stored == 0 ? 7 : min(30, max(1, stored))
        self.retentionDays = days
        self.vault = SafetyVault(rootURL: SafetyVault.defaultRootURL(), retentionDays: days)
    }

    func appeared() {
        refreshVault()
        refreshPurgeable()
        refreshTrash()
        if scanState == .idle { runScan() }
    }

    func refreshAll() {
        refreshVault()
        refreshPurgeable()
        refreshTrash()
        runScan()
    }

    func runScan() {
        guard scanState != .scanning else { return }
        scanState = .scanning
        cleanReport = nil
        
        let rootNodeInitial = StorageScanner().shallowScan(path: "/")
        if self.navigationPath.isEmpty {
            self.navigationPath = [rootNodeInitial]
        }
        
        isStreamingSizes = true
        Task.detached(priority: .userInitiated) {
            for await updatedNode in StorageScanner().scanSizesStream(node: rootNodeInitial) {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.navigationPath.first?.id == updatedNode.id {
                        self.navigationPath[0] = updatedNode
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.isStreamingSizes = false
            }
        }
        
        Task.detached(priority: .userInitiated) {
            let result = SmartScanner().scan()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scan = result
                self.rootNode = self.navigationPath.first // Ensure rootNode is updated
                self.scanState = .done(result.finished)
                // Default selection = safe tier only, per spec.
                self.selection = Set(
                    result.items.filter { $0.grade == .safe }.map(\.id))
            }
        }
    }

    func toggleNode(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
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
    
    func pushDirectory(_ node: StorageNode) {
        guard node.isDirectory else { return }
        scanState = .scanning
        
        let initialNode = StorageScanner().shallowScan(path: node.path)
        self.navigationPath.append(initialNode)
        
        isStreamingSizes = true
        Task.detached(priority: .userInitiated) {
            for await updatedNode in StorageScanner().scanSizesStream(node: initialNode) {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.navigationPath.last?.id == updatedNode.id {
                        self.navigationPath[self.navigationPath.count - 1] = updatedNode
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.isStreamingSizes = false
                self?.scanState = .done(Date())
            }
        }
    }
    
    func popDirectory() {
        if navigationPath.count > 1 {
            navigationPath.removeLast()
        }
    }

    /// Resets the browse stack to a specific location — used by the storage
    /// sidebar (real volumes + favorite folders) so taps actually navigate.
    func navigateToPath(_ path: String, name: String) {
        scanState = .scanning
        
        let node = StorageScanner(rootURL: URL(fileURLWithPath: path)).shallowScan(path: path)
        let anchor = StorageNode(
            id: node.id, name: name, path: node.path,
            sizeBytes: node.sizeBytes, isDirectory: true, children: node.children)
        self.navigationPath = [anchor]
        
        isStreamingSizes = true
        Task.detached(priority: .userInitiated) {
            for await updatedNode in StorageScanner().scanSizesStream(node: anchor) {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.navigationPath.first?.id == updatedNode.id {
                        self.navigationPath[0] = updatedNode
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.isStreamingSizes = false
                self?.scanState = .done(Date())
            }
        }
    }

    /// Per-path lookup into the smart-scan items, so treemap cells can show the
    /// real safety grade / idle age / category for a folder when known.
    var scanItemsByPath: [String: CleanItem] {
        guard let scan else { return [:] }
        return Dictionary(scan.items.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    }
    
    func navigateTo(index: Int) {
        if index >= 0 && index < navigationPath.count {
            navigationPath = Array(navigationPath.prefix(index + 1))
        }
    }
    
    func cleanNode(_ node: StorageNode) {
        guard !isCleaning else { return }
        isCleaning = true
        let payload = [(path: node.path, label: node.name, sizeBytes: node.sizeBytes)]
        let title = "Manual Clean — 1 item"
        Task.detached(priority: .userInitiated) { [vault] in
            var report: String
            do {
                let session = try vault.stage(items: payload, title: title)
                let staged = ByteFormat.string(session.totalBytes)
                report = "\(staged) staged in Vault — restore anytime for 7 days"
            } catch {
                report = "Failed to stage \(node.name)"
            }
            await MainActor.run { [weak self, report] in
                guard let self else { return }
                self.isCleaning = false
                self.cleanReport = report
                self.refreshVault()
                // refresh the current directory
                if let current = self.navigationPath.last {
                    self.navigationPath.removeLast()
                    self.pushDirectory(current)
                }
            }
        }
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

    /// Restores a single staged file back to its original location.
    func restoreItem(_ item: VaultItem, from session: VaultSession) {
        Task.detached(priority: .userInitiated) { [vault] in
            let ok = (try? { try vault.restoreItem(item, from: session); return true }()) ?? false
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanReport =
                    ok
                    ? "Restored \(item.label) to its original location"
                    : "Restore failed — the staged file may have been removed"
                self.refreshVault()
            }
        }
    }
    
    func purgeItem(_ item: VaultItem, from session: VaultSession) {
        Task.detached(priority: .userInitiated) { [vault] in
            let before = Self.rawFreeBytes()
            try? vault.purgeItem(item, from: session)
            let after = Self.rawFreeBytes()
            await MainActor.run { [weak self] in
                guard let self else { return }
                let freed = after > before ? after - before : 0
                self.cleanReport = "Vault item purged — \(ByteFormat.string(freed)) freed"
                self.refreshVault()
                self.refreshPurgeable()
            }
        }
    }

    struct FlatVaultItem: Identifiable, Hashable {
        let id: String
        let item: VaultItem
        let session: VaultSession
        
        static func == (lhs: FlatVaultItem, rhs: FlatVaultItem) -> Bool {
            lhs.id == rhs.id
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    var flatVaultItems: [FlatVaultItem] {
        vaultSessions.flatMap { session in
            session.items.map { item in
                FlatVaultItem(
                    id: "\(session.id.uuidString)/\(item.storedName)",
                    item: item,
                    session: session
                )
            }
        }.sorted { $0.session.date > $1.session.date }
    }
    
    func toggleVaultItem(_ flatItem: FlatVaultItem) {
        if vaultSelection.contains(flatItem.id) {
            vaultSelection.remove(flatItem.id)
        } else {
            vaultSelection.insert(flatItem.id)
        }
    }
    
    func toggleAllVaultItems() {
        if vaultSelection.count == flatVaultItems.count {
            vaultSelection.removeAll()
        } else {
            vaultSelection = Set(flatVaultItems.map(\.id))
        }
    }
    
    func purgeSelectedVaultItems() {
        let selected = flatVaultItems.filter { vaultSelection.contains($0.id) }
        guard !selected.isEmpty else { return }
        Task.detached(priority: .userInitiated) { [vault] in
            let before = Self.rawFreeBytes()
            for flat in selected {
                try? vault.purgeItem(flat.item, from: flat.session)
            }
            let after = Self.rawFreeBytes()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.vaultSelection.removeAll()
                let freed = after > before ? after - before : 0
                self.cleanReport = "Purged \(selected.count) items — \(ByteFormat.string(freed)) freed"
                self.refreshVault()
                self.refreshPurgeable()
            }
        }
    }

    func restoreSelectedVaultItems() {
        let selected = flatVaultItems.filter { vaultSelection.contains($0.id) }
        guard !selected.isEmpty else { return }
        Task.detached(priority: .userInitiated) { [vault] in
            var restoredCount = 0
            for flat in selected {
                let ok = (try? { try vault.restoreItem(flat.item, from: flat.session); return true }()) ?? false
                if ok { restoredCount += 1 }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.vaultSelection.removeAll()
                self.cleanReport = "Restored \(restoredCount) items to original locations"
                self.refreshVault()
            }
        }
    }

    func purgeAllVaultItems() {
        guard !vaultSessions.isEmpty else { return }
        Task.detached(priority: .userInitiated) { [vault, vaultSessions] in
            let before = Self.rawFreeBytes()
            for session in vaultSessions {
                vault.purge(session)
            }
            let after = Self.rawFreeBytes()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.vaultSelection.removeAll()
                let freed = after > before ? after - before : 0
                self.cleanReport = "Vault cleared — \(ByteFormat.string(freed)) freed"
                self.refreshVault()
                self.refreshPurgeable()
            }
        }
    }

    func restoreAllVaultItems() {
        guard !vaultSessions.isEmpty else { return }
        Task.detached(priority: .userInitiated) { [vault, vaultSessions] in
            var restoredCount = 0
            for session in vaultSessions {
                restoredCount += (try? vault.restore(session)) ?? 0
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.vaultSelection.removeAll()
                self.cleanReport = "Restored \(restoredCount) items across all sessions"
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

    /// Empties the system Trash by staging every item into the Vault — keeps
    /// Pulse's "no delete without restore" guarantee. Space frees when the
    /// Vault session purges (auto-expiry or manual), exactly like any clean.
    func emptyTrash() {
        guard !isCleaning, trashItemCount > 0 else { return }
        isCleaning = true
        Task.detached(priority: .userInitiated) { [vault] in
            let trash = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash")
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: trash, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                options: [])) ?? []
            let payload = entries.map { url -> (path: String, label: String, sizeBytes: UInt64) in
                (path: url.path, label: url.lastPathComponent,
                 sizeBytes: Self.itemSize(url))
            }
            var report: String
            if payload.isEmpty {
                report = "Trash is already empty"
            } else {
                do {
                    let session = try vault.stage(items: payload, title: "Empty Trash — \(payload.count) items")
                    report = "\(ByteFormat.string(session.totalBytes)) moved from Trash to Vault — frees on purge"
                } catch {
                    report = "Couldn't empty Trash — items may need Full Disk Access"
                }
            }
            await MainActor.run { [weak self, report] in
                guard let self else { return }
                self.isCleaning = false
                self.cleanReport = report
                self.refreshVault()
                self.refreshTrash()
            }
        }
    }

    /// Lightweight Trash-only refresh — for the menu bar popover, which must
    /// not trigger a full storage scan.
    func refreshTrashInfo() { refreshTrash() }

    private func refreshTrash() {
        let trash = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil, options: [])
        else {
            trashBytes = 0
            trashItemCount = 0
            return
        }
        trashItemCount = entries.count
        trashBytes = entries.reduce(0) { $0 + Self.itemSize($1) }
    }

    /// Allocated size of a file or directory tree.
    private nonisolated static func itemSize(_ url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        if let values = try? url.resourceValues(forKeys: Set(keys)), values.isDirectory != true {
            return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: UInt64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: []) {
            for case let child as URL in enumerator {
                if let values = try? child.resourceValues(forKeys: Set(keys)), values.isDirectory != true {
                    total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
            }
        }
        return total
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
