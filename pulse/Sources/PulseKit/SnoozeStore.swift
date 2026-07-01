import Foundation

/// Actor-isolated store of user-issued "stop showing me this" snoozes for
/// `AttentionEngine` items. JSON-file backed, same pattern as `UndoJournal`.
public actor SnoozeStore {
    private let storeURL: URL
    private var untilByID: [String: Date]

    public static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Pulse/snoozes.json")
    }

    public init(storeURL: URL = SnoozeStore.defaultStoreURL(), now: Date = .now) {
        self.storeURL = storeURL
        if let data = try? Data(contentsOf: storeURL),
            let loaded = try? JSONDecoder().decode([String: Date].self, from: data)
        {
            self.untilByID = loaded.filter { $0.value > now }
        } else {
            self.untilByID = [:]
        }
    }

    public func snooze(_ id: String, until: Date) {
        untilByID[id] = until
        save()
    }

    public func isSnoozed(_ id: String, now: Date = .now) -> Bool {
        guard let until = untilByID[id] else { return false }
        if until <= now {
            untilByID.removeValue(forKey: id)
            save()
            return false
        }
        return true
    }

    private func save() {
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(untilByID) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
