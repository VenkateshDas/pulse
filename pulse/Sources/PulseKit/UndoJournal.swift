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
    private(set) var entries: [UndoEntry] = []

    public init(storeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/undo_journal.json")) {
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

    public func restore(_ id: UUID) async throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        let fm = FileManager.default

        for item in entry.items {
            let trashURL = URL(fileURLWithPath: item.trashPath)
            let originalURL = URL(fileURLWithPath: item.originalPath)

            guard fm.fileExists(atPath: trashURL.path) else { continue }
            
            // Re-create parent directories if needed
            let parent = originalURL.deletingLastPathComponent()
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)

            // Move it back
            try fm.moveItem(at: trashURL, to: originalURL)
        }

        entries.remove(at: index)
        save()
    }

    public func prune(olderThan days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        entries.removeAll { $0.date < cutoff }
        save()
    }
}
