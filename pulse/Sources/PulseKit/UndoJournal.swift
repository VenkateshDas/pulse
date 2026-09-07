import Foundation
import Darwin

public struct TrashedItem: Codable, Sendable, Equatable {
    public let originalPath: String
    public let trashPath: String
    
    public init(originalPath: String, trashPath: String) {
        self.originalPath = originalPath
        self.trashPath = trashPath
    }
}

public struct UndoEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let op: String
    public let date: Date
    public let items: [TrashedItem]
    public let bytesFreed: Int64

    public init(id: UUID = UUID(), op: String, date: Date = .now, items: [TrashedItem], bytesFreed: Int64) {
        self.id = id
        self.op = op
        self.date = date
        self.items = items
        self.bytesFreed = bytesFreed
    }
}

/// File lock spans reload, mutation and atomic save across GUI and CLI processes.
public actor UndoJournal {
    public static let shared = UndoJournal()
    private let storeURL: URL
    private var cached: [UndoEntry] = []
    public private(set) var lastError: String?
    public var entries: [UndoEntry] { (try? read()) ?? cached }
    public static func defaultStoreURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pulse/undo_journal.json")
    }
    public init(storeURL: URL = UndoJournal.defaultStoreURL()) { self.storeURL = storeURL }
    private func read() throws -> [UndoEntry] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        return try JSONDecoder().decode([UndoEntry].self, from: Data(contentsOf: storeURL))
    }
    private func save() throws {
        try JSONEncoder().encode(cached).write(to: storeURL, options: .atomic)
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(storeURL.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(fd, LOCK_UN) }
        cached = try read()
        return try body()
    }
    public func snapshot() throws -> [UndoEntry] { try locked { cached } }
    public func recordChecked(_ entry: UndoEntry) throws {
        try locked { cached.insert(entry, at: 0); try save() }
    }
    /// Compatibility for existing GUI callers; failure remains observable.
    public func record(_ entry: UndoEntry) {
        do { try recordChecked(entry); lastError = nil }
        catch { lastError = error.localizedDescription; NSLog("Pulse undo journal: %@", error.localizedDescription) }
    }
    /// Persist each CLI move before starting the next one. Roll back on save failure.
    public func trashItem(at url: URL, operation: String, bytes: UInt64) throws -> UndoEntry {
        try locked {
            try save() // Preflight persistence before touching user files.
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            guard let trashPath = trashed?.path else {
                throw NSError(domain: "Pulse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Trash moved \(url.path) without returning its destination; inspect Finder Trash."])
            }
            let entry = UndoEntry(op: operation, items: [.init(originalPath: url.path, trashPath: trashPath)], bytesFreed: Int64(clamping: bytes))
            cached.insert(entry, at: 0)
            do { try save() }
            catch {
                do { try FileManager.default.moveItem(atPath: trashPath, toPath: url.path) }
                catch { throw NSError(domain: "Pulse", code: 2, userInfo: [NSLocalizedDescriptionKey: "Journal save and rollback failed. Recover \(trashPath) to \(url.path) manually."]) }
                throw error
            }
            return entry
        }
    }
    @discardableResult public func restore(_ id: UUID) throws -> Int {
        try locked {
            guard let index = cached.firstIndex(where: { $0.id == id }) else { return 0 }
            try save()
            let entry = cached[index]
            var count = 0, remaining: [TrashedItem] = []
            for item in entry.items {
                let fm = FileManager.default
                guard fm.fileExists(atPath: item.trashPath) else { continue }
                guard !fm.fileExists(atPath: item.originalPath) else { remaining.append(item); continue }
                do {
                    try fm.createDirectory(at: URL(fileURLWithPath: item.originalPath).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(atPath: item.trashPath, toPath: item.originalPath)
                    count += 1
                } catch { remaining.append(item) }
            }
            if remaining.isEmpty { cached.remove(at: index) }
            else { cached[index] = .init(id: entry.id, op: entry.op, date: entry.date, items: remaining, bytesFreed: entry.bytesFreed) }
            try save()
            return count
        }
    }
    public func pruneMissing() {
        do {
            try locked {
                cached = cached.compactMap { entry in
                    let items = entry.items.filter { FileManager.default.fileExists(atPath: $0.trashPath) }
                    return items.isEmpty ? nil : .init(id: entry.id, op: entry.op, date: entry.date, items: items, bytesFreed: entry.bytesFreed)
                }
                try save()
            }
        } catch { lastError = error.localizedDescription; NSLog("Pulse undo journal: %@", error.localizedDescription) }
    }
    public func prune(olderThan days: Int = 30) {
        do { try locked { cached.removeAll { $0.date < Date().addingTimeInterval(-Double(days) * 86400) }; try save() } }
        catch { lastError = error.localizedDescription; NSLog("Pulse undo journal: %@", error.localizedDescription) }
    }
}
