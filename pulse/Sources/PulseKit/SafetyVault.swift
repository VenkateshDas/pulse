import Foundation

/// One staged path inside a vault session.
public struct VaultItem: Codable, Sendable, Equatable {
    public let originalPath: String
    /// Name inside the session directory (deduplicated).
    public let storedName: String
    public let label: String
    public let sizeBytes: UInt64
}

/// One cleanup's worth of staged deletions, restorable as a unit.
public struct VaultSession: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let title: String
    public let items: [VaultItem]

    public var totalBytes: UInt64 { items.reduce(0) { $0 + $1.sizeBytes } }

    /// When this session is purged for good.
    public func expiry(ttl: TimeInterval = SafetyVault.defaultTTL) -> Date {
        date.addingTimeInterval(ttl)
    }
}

/// Staging area for every deletion Pulse performs — the spec's hard rule:
/// no delete ships without staging + restore. Same-volume moves are APFS
/// renames (instant, no copy); disk space frees when a session purges, not
/// when it's staged, and the UI must say so honestly.
public final class SafetyVault: Sendable {
    public static let defaultTTL: TimeInterval = 7 * 86400

    public let rootURL: URL
    private static let manifestName = "manifest.json"

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func defaultRootURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Pulse/Vault")
    }

    /// All sessions, newest first.
    public func sessions() -> [VaultSession] {
        guard
            let dirs = try? FileManager.default.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: nil, options: [])
        else { return [] }
        return dirs.compactMap { dir -> VaultSession? in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(Self.manifestName))
            else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(VaultSession.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }

    public func totalBytes() -> UInt64 {
        sessions().reduce(0) { $0 + $1.totalBytes }
    }

    /// Moves the given paths into a new session. Paths that fail to move
    /// (vanished, permission) are skipped; throws only if nothing staged.
    @discardableResult
    public func stage(
        items: [(path: String, label: String, sizeBytes: UInt64)],
        title: String,
        date: Date = .now
    ) throws -> VaultSession {
        let id = UUID()
        let sessionDir = rootURL.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(
            at: sessionDir, withIntermediateDirectories: true)

        var staged: [VaultItem] = []
        for (index, item) in items.enumerated() {
            let source = URL(fileURLWithPath: item.path)
            // Index prefix keeps same-named items (two "Cache" dirs) apart.
            let storedName = "\(index)-\(source.lastPathComponent)"
            do {
                try FileManager.default.moveItem(
                    at: source, to: sessionDir.appendingPathComponent(storedName))
                staged.append(
                    VaultItem(
                        originalPath: item.path, storedName: storedName,
                        label: item.label, sizeBytes: item.sizeBytes))
            } catch {
                continue
            }
        }

        guard !staged.isEmpty else {
            try? FileManager.default.removeItem(at: sessionDir)
            throw CocoaError(.fileNoSuchFile)
        }

        let session = VaultSession(id: id, date: date, title: title, items: staged)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try data.write(to: sessionDir.appendingPathComponent(Self.manifestName), options: .atomic)
        return session
    }

    /// Moves every item back to its original path (recreating parent dirs;
    /// a name collision restores alongside as "name (restored)"). The
    /// session is removed only when everything made it out — items that
    /// failed to move stay staged under a rewritten manifest, never lost.
    @discardableResult
    public func restore(_ session: VaultSession) throws -> Int {
        let sessionDir = rootURL.appendingPathComponent(session.id.uuidString)
        var restored = 0
        var stranded: [VaultItem] = []
        for item in session.items {
            let source = sessionDir.appendingPathComponent(item.storedName)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let original = URL(fileURLWithPath: item.originalPath)
            try? FileManager.default.createDirectory(
                at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            let destination =
                FileManager.default.fileExists(atPath: original.path)
                ? Self.collisionFreeURL(for: original) : original
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                restored += 1
            } catch {
                stranded.append(item)
            }
        }
        guard restored > 0 || session.items.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        if stranded.isEmpty {
            try? FileManager.default.removeItem(at: sessionDir)
        } else {
            let remainder = VaultSession(
                id: session.id, date: session.date, title: session.title, items: stranded)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(remainder) {
                try? data.write(
                    to: sessionDir.appendingPathComponent(Self.manifestName), options: .atomic)
            }
        }
        return restored
    }

    /// Permanently deletes one session — the freed space materializes here.
    public func purge(_ session: VaultSession) {
        try? FileManager.default.removeItem(
            at: rootURL.appendingPathComponent(session.id.uuidString))
    }

    /// Removes sessions past their TTL. Returns bytes freed.
    @discardableResult
    public func purgeExpired(ttl: TimeInterval = defaultTTL, now: Date = .now) -> UInt64 {
        var freed: UInt64 = 0
        for session in sessions() where session.expiry(ttl: ttl) <= now {
            freed += session.totalBytes
            purge(session)
        }
        return freed
    }

    static func collisionFreeURL(for url: URL) -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        var candidate = dir.appendingPathComponent(
            ext.isEmpty ? "\(base) (restored)" : "\(base) (restored).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(
                ext.isEmpty
                    ? "\(base) (restored \(counter))" : "\(base) (restored \(counter)).\(ext)")
            counter += 1
        }
        return candidate
    }
}
