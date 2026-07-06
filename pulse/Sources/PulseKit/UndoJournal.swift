import Foundation

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

public actor UndoJournal {
    public static let shared = UndoJournal()

    private let storeURL: URL
    public private(set) var entries: [UndoEntry] = []

    /// Default journal location: Pulse's own Application Support directory.
    /// Must NOT live under any path the cleaners can delete (e.g. `~/.gemini`,
    /// which CleanCatalog stages as developer junk) — that would let Smart Clean
    /// wipe its own undo history.
    public static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Pulse/undo_journal.json")
    }

    public init(storeURL: URL = UndoJournal.defaultStoreURL()) {
        self.storeURL = storeURL
        if let data = try? Data(contentsOf: storeURL),
           let loaded = try? JSONDecoder().decode([UndoEntry].self, from: data) {
            self.entries = loaded
        } else {
            self.entries = []
        }
    }

    private func save() {
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    public func record(_ entry: UndoEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    /// Attempts to restore every item in the entry. Returns the count actually
    /// moved back. Items whose trashed copy is gone (Trash emptied) or whose
    /// original path is already occupied are skipped, not fatal — one bad item
    /// must not abort the rest. Successfully restored items are dropped from the
    /// entry; the entry is removed only once it's fully restored.
    @discardableResult
    public func restore(_ id: UUID) async throws -> Int {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return 0 }
        let entry = entries[index]
        let fm = FileManager.default

        var restored = 0
        var remaining: [TrashedItem] = []
        for item in entry.items {
            let trashURL = URL(fileURLWithPath: item.trashPath)
            let originalURL = URL(fileURLWithPath: item.originalPath)

            // Trashed copy gone (e.g. Trash emptied) — nothing to restore.
            guard fm.fileExists(atPath: trashURL.path) else { continue }
            // Original path reoccupied (e.g. cache regenerated) — leave the
            // trashed copy in place rather than clobbering live data.
            guard !fm.fileExists(atPath: originalURL.path) else {
                remaining.append(item)
                continue
            }

            let parent = originalURL.deletingLastPathComponent()
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)

            do {
                try fm.moveItem(at: trashURL, to: originalURL)
                restored += 1
            } catch {
                remaining.append(item)
            }
        }

        if remaining.isEmpty {
            entries.remove(at: index)
        } else {
            entries[index] = UndoEntry(
                id: entry.id, op: entry.op, date: entry.date,
                items: remaining, bytesFreed: entry.bytesFreed)
        }
        save()
        return restored
    }

    /// Drops items whose trashed copy no longer exists (Trash emptied in
    /// Finder or Pulse), so history never shows a Restore that can't work.
    /// Entries left with no restorable items disappear entirely.
    public func pruneMissing() {
        let fm = FileManager.default
        var changed = false
        entries = entries.compactMap { entry in
            let alive = entry.items.filter { fm.fileExists(atPath: $0.trashPath) }
            if alive.count == entry.items.count { return entry }
            changed = true
            guard !alive.isEmpty else { return nil }
            return UndoEntry(
                id: entry.id, op: entry.op, date: entry.date,
                items: alive, bytesFreed: entry.bytesFreed)
        }
        if changed { save() }
    }

    public func prune(olderThan days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        entries.removeAll { $0.date < cutoff }
        save()
    }
}
