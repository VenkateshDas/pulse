import AppKit
import PulseKit
import SwiftUI
import os

private let log = Logger(subsystem: "com.pulse.app", category: "Storage")

@MainActor
@Observable
final class StorageModel {
    enum ScanState: Equatable {
        case idle
        case scanning
        case stopped
        case done(Date)
    }

    @ObservationIgnored private var collectionScanTask: Task<StorageScan, Never>?
    @ObservationIgnored private var sizingScanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = UUID()
    private(set) var scanState: ScanState = .idle
    private(set) var scan: StorageScan?
    /// Deep-link handoff: which Disk tab to open on next appearance. Set by
    /// RootView's navigation handlers because DiskView may not exist yet when
    /// the notification fires (it subscribes too late to receive it).
    var pendingDiskTab: Int?
    private(set) var rootNode: StorageNode?
    private(set) var navigationPath: [StorageNode] = []
    private(set) var selection: Set<String> = []
    var expandedItem: String?
    private(set) var isCleaning = false
    private(set) var isStreamingSizes = false
    private(set) var cleanReport: String?
    private(set) var purgeableBytes: UInt64 = 0
    struct TrashItem: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let sizeBytes: UInt64
    }

    /// Yesterday's (or the last earlier day's) root-folder sizes, for the
    /// per-folder ▲/▼ growth chips in Browse. Keyed by path.
    private(set) var rootBaseline: [String: UInt64] = [:]
    private static let rootBaselineKey = "PulseRootFolderBaseline"
    private static let rootBaselineDateKey = "PulseRootFolderBaselineDate"
    /// Pseudo-path key in the baseline dict for the hidden & system remainder.
    private static let hiddenBaselineKey = "pulse://hidden"

    /// Size of OS update downloads (subfolders of /Library/Updates) —
    /// deletable as root; Software Update re-downloads on demand.
    private(set) var updateDownloadsBytes: UInt64 = 0
    /// SF_RESTRICTED (SIP) on any download subfolder — deletion is then
    /// impossible for every process except Apple's softwareupdated, even as
    /// root, so the UI must not offer a delete that can only fail.
    private(set) var updateDownloadsRestricted = false

    /// One measurable slice of "Hidden & system data" — a helper volume in
    /// the APFS container that lives outside every listed root folder.
    struct HiddenComponent: Identifiable, Equatable, Sendable {
        var id: String { label }
        let label: String
        let subtitle: String
        let bytes: UInt64
    }

    private(set) var hiddenComponents: [HiddenComponent] = []
    /// An os.update APFS snapshot exists — a downloaded macOS update is
    /// staged/prepared, pinning GBs that free themselves after install.
    private(set) var stagedUpdatePinned = false
    /// com.apple.TimeMachine snapshots — the one hidden-data slice that IS
    /// safely reclaimable (tmutil thinlocalsnapshots).
    private(set) var tmSnapshotCount = 0

    // MARK: Growth scan ("where did my free space go")

    private(set) var growthReport: GrowthReport?
    private(set) var isGrowthScanning = false
    var growthWindowDays = 2 {
        didSet { if growthWindowDays != oldValue { runGrowthScan() } }
    }
    @ObservationIgnored private var growthTask: Task<Void, Never>?

    func runGrowthScan() {
        growthTask?.cancel()
        isGrowthScanning = true
        growthReport = nil
        let cutoff = Calendar.current.startOfDay(
            for: .now.addingTimeInterval(-Double(growthWindowDays) * 86400))
        growthTask = Task {
            let report = await Task.detached(priority: .userInitiated) {
                RecentGrowthScanner().scan(since: cutoff)
            }.value
            guard !Task.isCancelled else { return }
            self.growthReport = report
            self.isGrowthScanning = false
        }
    }

    // MARK: Folder verdict ("can I delete this?")

    /// Path currently shown in the verdict sheet; nil hides it.
    var verdictTarget: String?
    private(set) var verdict: FolderVerdict?
    private(set) var isScanningVerdict = false
    @ObservationIgnored private let referenceScanner = UsageGraphScanner()

    func inspect(path: String, forceRescan: Bool = false) {
        verdictTarget = path
        isScanningVerdict = true
        verdict = nil
        let scanner = referenceScanner
        Task {
            if forceRescan {
                _ = await scanner.referrers(
                    for: URL(fileURLWithPath: path), forceRescan: Set(ReferenceSignal.allCases))
            }
            let engine = FolderVerdictEngine(referenceScanner: scanner)
            let result = await engine.verdict(for: URL(fileURLWithPath: path))
            guard self.verdictTarget == path else { return }
            self.verdict = result
            self.isScanningVerdict = false
        }
    }

    func dismissVerdict() {
        verdictTarget = nil
        verdict = nil
    }

    /// Trashes the folder currently shown in the verdict sheet — only
    /// offered by the UI for delete-leaning verdict classes.
    func trashInspectedTarget() {
        guard let path = verdictTarget, !isCleaning else { return }
        isCleaning = true
        let size = Self.itemSize(URL(fileURLWithPath: path))
        let name = (path as NSString).lastPathComponent
        Task {
            let (report, trashed) = await Task.detached(priority: .userInitiated) {
                do {
                    var trashedURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &trashedURL)
                    if let trashPath = trashedURL?.path {
                        let item = TrashedItem(originalPath: path, trashPath: trashPath)
                        await UndoJournal.shared.record(UndoEntry(op: "Verdict Clean", items: [item], bytesFreed: Int64(size)))
                    }
                    return ("\(ByteFormat.string(size)) moved to Trash", true)
                } catch {
                    return ("Failed to move \(name) to Trash", false)
                }
            }.value
            self.isCleaning = false
            self.cleanReport = report
            if trashed {
                TrashSound.moveToTrash()
                self.dismissVerdict()
                self.navigationPath = self.navigationPath.pruning(deletedPath: path, bytes: size)
            }
            self.refreshTrashInfo()
            self.refreshPurgeable()
        }
    }

    private(set) var trashItemCount: Int = 0
    private(set) var trashBytes: UInt64 = 0
    private(set) var trashItems: [TrashItem] = []
    private(set) var trashAccessError: Bool = false
    private(set) var undoEntries: [UndoEntry] = []

    @ObservationIgnored private var trashObserver: DispatchSourceFileSystemObject?
    @ObservationIgnored private var refreshTrashTask: Task<Void, Never>?

    init() {
        startTrashObserver()
        if let saved = UserDefaults.standard.dictionary(forKey: Self.rootBaselineKey) as? [String: Int] {
            rootBaseline = saved.mapValues { UInt64($0) }
        }
    }

    /// Growth since the saved baseline day for a root folder, nil when the
    /// folder is new or the baseline was taken today (no earlier day yet).
    func rootDelta(for path: String) -> Int64? {
        guard let old = rootBaseline[path], old > 0 else { return nil }
        guard let node = navigationPath.first?.children?.first(where: { $0.path == path }),
            node.sizeBytes > 0
        else { return nil }
        return Int64(node.sizeBytes) - Int64(old)
    }

    /// Growth of the hidden & system remainder since the baseline day, given
    /// its current size (computed by the view from used − listed folders).
    func hiddenDelta(current: UInt64) -> Int64? {
        guard let old = rootBaseline[Self.hiddenBaselineKey], old > 0 else { return nil }
        return Int64(current) - Int64(old)
    }

    /// Once per day, after root sizes finish streaming: persist them so the
    /// next day's Browse can show per-folder growth. In-memory baseline keeps
    /// the earlier day's values for the rest of this session.
    private func saveRootBaselineIfNewDay() {
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: Self.rootBaselineDateKey) != today,
            let children = navigationPath.first?.children, !children.isEmpty
        else { return }
        var sizes = Dictionary(
            children.filter { $0.sizeBytes > 0 }.map { ($0.path, Int($0.sizeBytes)) },
            uniquingKeysWith: { a, _ in a })
        // Baseline the hidden remainder too (same math as the view's pseudo
        // row: used − listed), so its growth chip works like folder chips.
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) {
            let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let used = total > free ? total - free : 0
            let listed = children.reduce(UInt64(0)) { $0 + $1.sizeBytes }
            if used > listed { sizes[Self.hiddenBaselineKey] = Int(used - listed) }
        }
        UserDefaults.standard.set(sizes, forKey: Self.rootBaselineKey)
        UserDefaults.standard.set(today, forKey: Self.rootBaselineDateKey)
        if rootBaseline.isEmpty { rootBaseline = sizes.mapValues { UInt64($0) } }
    }

    private func startTrashObserver() {
        guard trashObserver == nil else { return }
        let trashPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        let descriptor = open(trashPath, O_EVTONLY)
        guard descriptor != -1 else { return }

        let observer = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        observer.setEventHandler { [weak self] in
            self?.refreshTrashInfo()
        }
        observer.setCancelHandler {
            close(descriptor)
        }
        observer.resume()
        trashObserver = observer
    }

    func appeared() {
        refreshPurgeable()
        refreshTrashInfo()
        refreshUndoHistory()
        refreshUpdateDownloads()
        refreshHiddenBreakdown()
        if scanState == .idle { runScan() }
    }

    func refreshAll() {
        refreshPurgeable()
        refreshTrashInfo()
        refreshUndoHistory()
        refreshUpdateDownloads()
        refreshHiddenBreakdown()
        runScan()
    }

    /// Attributes the hidden remainder: per-volume used bytes of the APFS
    /// helper volumes plus APFS snapshot state from tmutil. All readable
    /// without privileges. Volume sizes come from `df -k` — statfs f_bfree
    /// is container-wide on APFS, so it can't give per-volume used.
    private func refreshHiddenBreakdown() {
        Task {
            let volumes: [(path: String, label: String, subtitle: String)] = [
                ("/System/Volumes/Preboot", "Boot support (Preboot)",
                 "Cryptexes, firmware & boot loaders — system-managed"),
                ("/System/Volumes/VM", "Swap files (VM)",
                 "Shrinks after a restart or when memory pressure drops"),
                ("/System/Volumes/Update", "Update staging volume",
                 "Cleared by macOS when updates finish"),
            ]
            var comps: [HiddenComponent] = []
            for vol in volumes {
                var st = statfs()
                if statfs(vol.path, &st) == 0 {
                    let bsize = UInt64(st.f_bsize)
                    let usedBlocks = st.f_blocks > st.f_bfree ? UInt64(st.f_blocks - st.f_bfree) : 0
                    let usedBytes = usedBlocks * bsize
                    if usedBytes > 0 {
                        comps.append(HiddenComponent(
                            label: vol.label, subtitle: vol.subtitle, bytes: usedBytes))
                    }
                }
            }
            self.hiddenComponents = comps
            // Snapshot enumeration is not available through a supported,
            // unprivileged native interface. Do not report zero as a finding.

        }
    }

    /// Thins local Time Machine snapshots (Apple's own reclaim command) —
    /// the safe deletion inside hidden data. os.update snapshots are not
    /// touched; Time Machine re-creates hourly snapshots while backing up.
    func thinLocalSnapshots() {
        guard !isCleaning else { return }
        isCleaning = true
        Task {
            let result = await PrivilegedRunner.run(.thinLocalSnapshots)
            self.isCleaning = false
            self.cleanReport = result.success
                ? "Time Machine snapshots thinned — space returns as purgeable clears"
                : String(result.summary.split(separator: "\n", maxSplits: 1)[0])
            self.refreshHiddenBreakdown()
            self.refreshPurgeable()
        }
    }

    /// Sums the download subfolders of /Library/Updates (world-readable even
    /// though root-owned). The two bookkeeping plists there don't count.
    private func refreshUpdateDownloads() {
        Task {
            let (bytes, restricted) = await Task.detached(priority: .background) {
                let dir = URL(fileURLWithPath: "/Library/Updates")
                guard let entries = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
                else { return (UInt64(0), false) }
                let subdirs = entries.filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }
                let total = subdirs.reduce(UInt64(0)) { $0 + Self.itemSize($1) }
                let sipFlagged = subdirs.contains { url in
                    var st = stat()
                    return stat(url.path, &st) == 0 && st.st_flags & UInt32(SF_RESTRICTED) != 0
                }
                return (total, sipFlagged)
            }.value
            self.updateDownloadsBytes = bytes
            self.updateDownloadsRestricted = restricted
        }
    }

    /// Deletes the downloaded (not installed) macOS/firmware updates in
    /// /Library/Updates via an admin prompt. Permanent — root-owned files
    /// can't go to the Trash — but Software Update re-downloads on demand.
    func clearUpdateDownloads() {
        guard !isCleaning else { return }
        isCleaning = true
        let freed = updateDownloadsBytes
        Task {
            let result = await PrivilegedRunner.run(.clearUpdateDownloads)
            self.isCleaning = false
            // Failure summaries can carry multi-line rm stderr — first line
            // only; the bottom bar is a status strip, not a log view.
            self.cleanReport = result.success
                ? "\(ByteFormat.string(freed)) of update downloads deleted"
                : String(result.summary.split(separator: "\n", maxSplits: 1)[0])
            self.refreshUpdateDownloads()
            self.refreshPurgeable()
        }
    }

    func runScan(preserveResult: Bool = false) {
        guard scanState != .scanning else { return }
        let generation = UUID(); scanGeneration = generation
        scanState = .scanning
        if !preserveResult { cleanReport = nil }

        let rootNodeInitial = StorageScanner().shallowScan(path: "/")
        if self.navigationPath.isEmpty {
            self.navigationPath = [rootNodeInitial]
        }

        isStreamingSizes = true
        sizingScanTask = Task {
            for await updatedNode in StorageScanner().scanSizesStream(node: rootNodeInitial) {
                guard !Task.isCancelled, self.scanGeneration == generation else { return }
                if self.navigationPath.first?.id == updatedNode.id {
                    self.navigationPath[0] = updatedNode
                }
            }
            guard !Task.isCancelled, self.scanGeneration == generation else { return }
            self.isStreamingSizes = false
            self.saveRootBaselineIfNewDay()
        }

        let worker = Task.detached(priority: .userInitiated) { SmartScanner().scan() }
        collectionScanTask = worker
        Task {
            let result = await worker.value
            guard !worker.isCancelled, self.scanGeneration == generation else { return }
            self.collectionScanTask = nil
            self.scan = result
            self.scanItemsByPath = Dictionary(result.items.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            self.rootNode = self.navigationPath.first
            self.scanState = .done(result.finished)
            self.selection = Set(
                result.items.filter { $0.grade == .safe }.map(\.id))
        }
    }

    func cancelScan() {
        guard scanState == .scanning || isStreamingSizes else { return }
        scanGeneration = UUID()
        collectionScanTask?.cancel(); collectionScanTask = nil
        sizingScanTask?.cancel(); sizingScanTask = nil
        isStreamingSizes = false
        scanState = .stopped
        cleanReport = "Scan stopped. Previous cleanup results are kept; folder sizes may be incomplete. Rescan when you are ready."
    }

    func toggleNode(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func toggle(_ item: CleanItem) {
        guard item.grade != .review else { return }
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func selectAllSafe(excludedPaths: Set<String> = []) {
        guard let scan else { return }
        for item in scan.items where item.grade == .safe {
            if !CleanSchedule.isPathExcluded(item.path, in: excludedPaths) {
                selection.insert(item.id)
            }
        }
    }

    func trashProtectedItem(_ item: CleanItem, cleanModel: CleanModel) {
        guard !isCleaning else { return }
        isCleaning = true
        let itemPath = item.path
        let itemSize = item.sizeBytes
        Task {
            let (report, trashed) = await Task.detached(priority: .userInitiated) {
                do {
                    var trashedURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: itemPath), resultingItemURL: &trashedURL)
                    var items: [TrashedItem] = []
                    if let trashPath = trashedURL?.path {
                        items.append(TrashedItem(originalPath: itemPath, trashPath: trashPath))
                    }
                    if !items.isEmpty {
                        await UndoJournal.shared.record(UndoEntry(op: "Worth a Look Clean", items: items, bytesFreed: Int64(itemSize)))
                    }
                    return ("\(ByteFormat.string(itemSize)) moved to Trash", true)
                } catch {
                    return ("Failed to move item to Trash", false)
                }
            }.value
            self.isCleaning = false
            self.cleanReport = report
            if trashed {
                TrashSound.moveToTrash()
                cleanModel.toggleExclusion(itemPath)
                self.selection.remove(item.id)
                self.runScan(preserveResult: true)
            }
            self.refreshTrashInfo()
            self.refreshPurgeable()
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
        Task {
            for await updatedNode in StorageScanner().scanSizesStream(node: initialNode) {
                if self.navigationPath.last?.id == updatedNode.id {
                    self.navigationPath[self.navigationPath.count - 1] = updatedNode
                }
            }
            self.isStreamingSizes = false
            self.scanState = .done(Date())
        }
    }

    /// Miller-column drill: truncate to the clicked column, then open `node`
    /// as the next column. No-op when that column is already open.
    func openColumn(_ node: StorageNode, fromColumn index: Int) {
        guard node.isDirectory else { return }
        if navigationPath.indices.contains(index + 1), navigationPath[index + 1].path == node.path { return }
        navigationPath = Array(navigationPath.prefix(index + 1))
        pushDirectory(node)
    }

    func popDirectory() {
        if navigationPath.count > 1 {
            navigationPath.removeLast()
        }
    }

    private(set) var scanItemsByPath: [String: CleanItem] = [:]

    func navigateTo(index: Int) {
        if index >= 0 && index < navigationPath.count {
            navigationPath = Array(navigationPath.prefix(index + 1))
        }
    }

    func cleanNode(_ node: StorageNode) {
        guard !isCleaning else { return }
        isCleaning = true
        let nodePath = node.path
        let nodeName = node.name
        let nodeSizeBytes = node.sizeBytes
        Task {
            let (report, trashed) = await Task.detached(priority: .userInitiated) {
                do {
                    var trashedURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: nodePath), resultingItemURL: &trashedURL)
                    if let trashPath = trashedURL?.path {
                        let item = TrashedItem(originalPath: nodePath, trashPath: trashPath)
                        await UndoJournal.shared.record(UndoEntry(op: "Storage Map Clean", items: [item], bytesFreed: Int64(nodeSizeBytes)))
                    }
                    return ("\(ByteFormat.string(nodeSizeBytes)) moved to Trash", true)
                } catch {
                    return ("Failed to move \(nodeName) to Trash", false)
                }
            }.value
            self.isCleaning = false
            self.cleanReport = report
            if trashed {
                TrashSound.moveToTrash()
                // In-place sync: no rescan — remove the node and subtract its
                // size from every ancestor column so all views agree instantly.
                self.navigationPath = self.navigationPath.pruning(deletedPath: nodePath, bytes: nodeSizeBytes)
            }
            self.refreshTrashInfo()
            self.refreshPurgeable()
        }
    }

    func cleanSelected() {
        let items = selectedItems
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        let itemPaths = items.map(\.path)
        let itemSizes = items.map(\.sizeBytes)
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                var rep: String
                var trashedBytes: UInt64 = 0
                var count = 0
                var trashedItems: [TrashedItem] = []
                for (path, size) in zip(itemPaths, itemSizes) {
                    do {
                        var trashedURL: NSURL?
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &trashedURL)
                        if let trashPath = trashedURL?.path {
                            trashedItems.append(TrashedItem(originalPath: path, trashPath: trashPath))
                        }
                        trashedBytes += size
                        count += 1
                    } catch {
                        // ignore
                    }
                }
                if !trashedItems.isEmpty {
                    await UndoJournal.shared.record(UndoEntry(op: "Reclaim Clean", items: trashedItems, bytesFreed: Int64(trashedBytes)))
                }
                if count > 0 {
                    rep = "Moved \(count) of \(itemPaths.count) items (\(ByteFormat.string(trashedBytes))) to Trash. Space remains used until Trash is emptied."
                } else {
                    rep = "Failed to move items to Trash"
                }
                return (rep, count)
            }.value
            self.isCleaning = false
            self.cleanReport = report.0
            if report.1 > 0 { TrashSound.moveToTrash() }
            self.selection.removeAll()
            self.refreshTrashInfo()
            self.refreshUndoHistory()
            self.refreshPurgeable()
            self.runScan(preserveResult: true)
            if let current = self.navigationPath.last {
                self.navigationPath.removeLast()
                self.pushDirectory(current)
            }
        }
    }

    func emptyTrash() {
        guard !isCleaning, trashItemCount > 0 else { return }
        isCleaning = true
        MenuBarFlash.shared.flash("trash")
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                let trash = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".Trash")
                guard let entries = try? FileManager.default.contentsOfDirectory(
                    at: trash, includingPropertiesForKeys: nil, options: [])
                else { return ("Failed to empty Trash", 0) }
                var count = 0
                for url in entries {
                    do {
                        try FileManager.default.removeItem(at: url)
                        count += 1
                    } catch {
                        log.error("empty Trash: couldn't remove \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                    }
                }
                return (count == entries.count ? "Permanently removed \(count) items from Trash." : "Removed \(count) of \(entries.count) items. The remaining items are still in Trash.", count)
            }.value
            self.isCleaning = false
            self.cleanReport = report.0
            if report.1 > 0 { TrashSound.emptyTrash() }
            self.refreshTrashInfo()
            self.refreshPurgeable()
        }
    }

    func refreshUndoHistory() {
        Task {
            // Trash may have been emptied (here or in Finder) — drop history
            // items that can no longer be restored before showing the list.
            await UndoJournal.shared.pruneMissing()
            self.undoEntries = await UndoJournal.shared.entries
        }
    }

    func restore(entry: UndoEntry) {
        guard !isCleaning else { return }
        isCleaning = true
        Task {
            do {
                let restored = try await UndoJournal.shared.restore(entry.id)
                switch restored {
                case 0:
                    self.cleanReport = "Nothing restored. Items may be missing from Trash or their original locations may already be occupied."
                case entry.items.count:
                    self.cleanReport = "Restored \(restored) items"
                default:
                    self.cleanReport = "Restored \(restored) of \(entry.items.count) items. The remaining items could not be restored; check Trash and the original folders."
                }
            } catch {
                self.cleanReport = "Could not restore these items. Check that their original folders are writable and their names are not already in use."
            }
            self.isCleaning = false
            self.refreshTrashInfo()
            self.refreshUndoHistory()
            self.refreshPurgeable()
            self.runScan(preserveResult: true)
        }
    }

    func refreshTrashInfo() {
        startTrashObserver()
        refreshTrashTask?.cancel()
        refreshTrashTask = Task {
            let (count, bytes, items, accessError) = await Task.detached(priority: .background) {
                let trash = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".Trash")
                var entries: [URL]
                var errorEncountered = false
                do {
                    entries = try FileManager.default.contentsOfDirectory(
                        at: trash, includingPropertiesForKeys: nil, options: [])
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == NSCocoaErrorDomain && nsError.code == 257 {
                        errorEncountered = true
                    }
                    return (0, UInt64(0), [TrashItem](), errorEncountered)
                }
                var totalBytes: UInt64 = 0
                var items: [TrashItem] = []
                for url in entries {
                    if Task.isCancelled { return (0, UInt64(0), [TrashItem](), false) }
                    let size = Self.itemSize(url)
                    totalBytes += size
                    items.append(TrashItem(id: url.path, name: url.lastPathComponent, sizeBytes: size))
                }
                items.sort { $0.sizeBytes > $1.sizeBytes }
                return (entries.count, totalBytes, items, false)
            }.value

            if !Task.isCancelled {
                self.trashItemCount = count
                self.trashBytes = bytes
                self.trashItems = items
                self.trashAccessError = accessError
            }
        }
        refreshUndoHistory()
    }

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

    // MARK: - Duplicate Finder State & Caching
    private(set) var duplicateGroups: [DuplicateScanner.DuplicateGroup] = []
    private(set) var isDuplicateScanning = false
    private(set) var duplicateScanProgress: DuplicateScanner.ScanProgress?
    private(set) var duplicateStatusMessage: String?

    @ObservationIgnored private var duplicateScanTask: Task<Void, Never>?
    private(set) var didScanDuplicates = false
    private(set) var duplicateRoots: [URL] = []
    private(set) var isRemovingDuplicates = false

    func retainDuplicate(groupId: String, fileId: String) {
        guard !isRemovingDuplicates, let index = duplicateGroups.firstIndex(where: { $0.id == groupId }) else { return }
        for i in duplicateGroups[index].files.indices {
            duplicateGroups[index].files[i].isKeepCandidate = duplicateGroups[index].files[i].id == fileId
            if duplicateGroups[index].files[i].isKeepCandidate { duplicateGroups[index].files[i].isSelectedForDeletion = false }
        }
    }

    func toggleDuplicateSelection(groupId: String, fileId: String, isSelected: Bool) {
        guard !isRemovingDuplicates, let gIdx = duplicateGroups.firstIndex(where: { $0.id == groupId }),
              let fIdx = duplicateGroups[gIdx].files.firstIndex(where: { $0.id == fileId }),
              !duplicateGroups[gIdx].files[fIdx].isKeepCandidate else { return }
        duplicateGroups[gIdx].files[fIdx].isSelectedForDeletion = isSelected
    }

    func startDuplicateScan(directories: [URL]? = nil) {
        guard !isDuplicateScanning, !isRemovingDuplicates else { return }
        let fm = FileManager.default
        let roots = directories ?? [FileManager.SearchPathDirectory.downloadsDirectory, .documentDirectory, .desktopDirectory]
            .compactMap { fm.urls(for: $0, in: .userDomainMask).first }
        guard !roots.isEmpty else { return }
        duplicateRoots = roots
        isDuplicateScanning = true
        duplicateScanProgress = nil
        duplicateStatusMessage = nil
        duplicateScanTask = Task {
            defer { isDuplicateScanning = false; duplicateScanTask = nil }
            do {
                let scanner = DuplicateScanner()
                let result = try await scanner.scan(directories: roots) { progress in
                    Task { @MainActor in
                        if self.isDuplicateScanning { self.duplicateScanProgress = progress }
                    }
                }
                try Task.checkCancellation()
                duplicateGroups = result.map { group in
                    var reviewed = group
                    for index in reviewed.files.indices { reviewed.files[index].isSelectedForDeletion = false }
                    return reviewed
                }
                didScanDuplicates = true
                duplicateStatusMessage = result.isEmpty ? "No identical files found in the selected folders." : "Scan complete. Review where each copy is used before choosing files to remove."
            } catch is CancellationError {
                duplicateStatusMessage = "Scan stopped. Previous results remain available."
            } catch {
                duplicateStatusMessage = "The scan could not finish: \(error.localizedDescription)"
            }
        }
    }

    func cancelDuplicateScan() { duplicateScanTask?.cancel() }

    func deleteSelectedDuplicates() {
        guard !isRemovingDuplicates, !isDuplicateScanning else { return }
        let groups = duplicateGroups
        guard groups.contains(where: { !$0.files.filter(\.isSelectedForDeletion).isEmpty }) else { return }
        isRemovingDuplicates = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                var moved: Set<String> = []
                var failed = 0
                for group in groups {
                    guard let keeper = group.files.first(where: { !$0.isSelectedForDeletion }),
                          (try? DuplicateScanner.hashFile(at: keeper.url)) == group.id else {
                        failed += group.files.filter(\.isSelectedForDeletion).count
                        continue
                    }
                    for file in group.files where file.isSelectedForDeletion {
                        // Revalidate content and protection at the action boundary.
                        guard !StorageScanner.isProtected(file.url.path),
                              (try? DuplicateScanner.hashFile(at: file.url)) == group.id else { failed += 1; continue }
                        do {
                            _ = try await UndoJournal.shared.trashItem(at: file.url, operation: "Duplicate files", bytes: UInt64(max(0, file.fileSize)))
                            moved.insert(file.id)
                        } catch { failed += 1 }
                    }
                }
                return (moved, failed)
            }.value
            for index in duplicateGroups.indices {
                duplicateGroups[index].files.removeAll { result.0.contains($0.id) }
            }
            duplicateGroups.removeAll { $0.files.count < 2 }
            isRemovingDuplicates = false
            duplicateStatusMessage = "Moved \(result.0.count) duplicate files to Trash. " + (result.1 > 0 ? "\(result.1) files could not be moved and remain in their folders." : "Space remains used until Trash is emptied.")
            refreshTrashInfo()
            refreshUndoHistory()
        }
    }
}
