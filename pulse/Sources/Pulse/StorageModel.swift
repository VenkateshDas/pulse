import AppKit
import PulseKit
import SwiftUI

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

    private(set) var trashItemCount: Int = 0
    private(set) var trashBytes: UInt64 = 0
    private(set) var trashItems: [TrashItem] = []
    private(set) var trashAccessError: Bool = false
    private(set) var undoEntries: [UndoEntry] = []
    
    @ObservationIgnored private var trashObserver: DispatchSourceFileSystemObject?
    @ObservationIgnored private var refreshTrashTask: Task<Void, Never>?

    init() {
        startTrashObserver()
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
        if scanState == .idle { runScan() }
    }

    func refreshAll() {
        refreshPurgeable()
        refreshTrashInfo()
        refreshUndoHistory()
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
        Task {
            for await updatedNode in StorageScanner().scanSizesStream(node: rootNodeInitial) {
                if self.navigationPath.first?.id == updatedNode.id {
                    self.navigationPath[0] = updatedNode
                }
            }
            self.isStreamingSizes = false
        }
        
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                SmartScanner().scan()
            }.value
            self.scan = result
            self.rootNode = self.navigationPath.first
            self.scanState = .done(result.finished)
            self.selection = Set(
                result.items.filter { $0.grade == .safe }.map(\.id))
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
        guard item.grade != .review else { return }
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func selectAllSafe() {
        guard let scan else { return }
        for item in scan.items where item.grade == .safe {
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
    
    func popDirectory() {
        if navigationPath.count > 1 {
            navigationPath.removeLast()
        }
    }

    func navigateToPath(_ path: String, name: String) {
        scanState = .scanning
        
        let node = StorageScanner(rootURL: URL(fileURLWithPath: path)).shallowScan(path: path)
        let anchor = StorageNode(
            id: node.id, name: name, path: node.path,
            sizeBytes: node.sizeBytes, isDirectory: true, children: node.children)
        self.navigationPath = [anchor]
        
        isStreamingSizes = true
        Task {
            for await updatedNode in StorageScanner().scanSizesStream(node: anchor) {
                if self.navigationPath.first?.id == updatedNode.id {
                    self.navigationPath[0] = updatedNode
                }
            }
            self.isStreamingSizes = false
            self.scanState = .done(Date())
        }
    }

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
        let nodePath = node.path
        let nodeName = node.name
        let nodeSizeBytes = node.sizeBytes
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                var rep: String
                do {
                    var trashedURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: nodePath), resultingItemURL: &trashedURL)
                    if let trashPath = trashedURL?.path {
                        let item = TrashedItem(originalPath: nodePath, trashPath: trashPath)
                        await UndoJournal.shared.record(UndoEntry(op: "Storage Map Clean", items: [item], bytesFreed: Int64(nodeSizeBytes)))
                    }
                    rep = "\(ByteFormat.string(nodeSizeBytes)) moved to Trash"
                } catch {
                    rep = "Failed to move \(nodeName) to Trash"
                }
                return rep
            }.value
            self.isCleaning = false
            self.cleanReport = report
            self.refreshTrashInfo()
            if let current = self.navigationPath.last {
                self.navigationPath.removeLast()
                self.pushDirectory(current)
            }
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
                    rep = "Moved \(count) items (\(ByteFormat.string(trashedBytes))) to Trash"
                } else {
                    rep = "Failed to move items to Trash"
                }
                return rep
            }.value
            self.isCleaning = false
            self.cleanReport = report
            self.selection.removeAll()
            self.refreshTrashInfo()
            self.refreshPurgeable()
            self.runScan()
            if let current = self.navigationPath.last {
                self.navigationPath.removeLast()
                self.pushDirectory(current)
            }
        }
    }

    func emptyTrash() {
        guard !isCleaning, trashItemCount > 0 else { return }
        isCleaning = true
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                let trash = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".Trash")
                guard let entries = try? FileManager.default.contentsOfDirectory(
                    at: trash, includingPropertiesForKeys: nil, options: [])
                else { return "Failed to empty Trash" }
                var count = 0
                for url in entries {
                    do {
                        try FileManager.default.removeItem(at: url)
                        count += 1
                    } catch {}
                }
                return count > 0 ? "Emptied \(count) items from Trash" : "Failed to empty Trash"
            }.value
            self.isCleaning = false
            self.cleanReport = report
            self.refreshTrashInfo()
            self.refreshPurgeable()
        }
    }

    func refreshUndoHistory() {
        Task {
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
                    self.cleanReport = "Nothing restored — items no longer in Trash"
                case entry.items.count:
                    self.cleanReport = "Restored \(restored) items"
                default:
                    self.cleanReport = "Restored \(restored) of \(entry.items.count) items"
                }
            } catch {
                self.cleanReport = "Failed to restore items"
            }
            self.isCleaning = false
            self.refreshTrashInfo()
            self.refreshUndoHistory()
            self.refreshPurgeable()
            self.runScan()
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
}
