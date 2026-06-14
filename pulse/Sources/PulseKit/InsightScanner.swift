import Foundation

/// A space hog the treemap buries — surfaced for awareness ("👀"), not staged
/// for deletion. Some are real data (iOS backups, archives); others are
/// rebuildable caches. The `reversibleHint` tells the user which is which.
public struct Insight: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case hiddenSpace   // 👀 real data — review before touching
        case cleanable     // rebuildable / re-downloadable
    }

    public var id: String { path }
    public let label: String
    public let path: String
    public var bytes: Int64
    public let kind: Kind
    public let reversibleHint: String

    public init(label: String, path: String, bytes: Int64, kind: Kind, reversibleHint: String) {
        self.label = label
        self.path = path
        self.bytes = bytes
        self.kind = kind
        self.reversibleHint = reversibleHint
    }
}

/// Measures a curated set of large, easy-to-forget locations. Paths are facts
/// ported from mole's insight list; sizes are measured on demand. Pure
/// filesystem reads, bounded concurrency (mole's 2–12 worker cap → 8 here).
public struct InsightScanner: Sendable {
    /// A target whose size is the whole directory tree.
    struct Target: Sendable {
        let rel: String          // relative to home; may contain one "*" segment
        let label: String
        let kind: Insight.Kind
        let hint: String
    }

    let home: URL
    let now: Date
    let oldDownloadsDays: Int

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now,
        oldDownloadsDays: Int = 90
    ) {
        self.home = home
        self.now = now
        self.oldDownloadsDays = oldDownloadsDays
    }

    static let targets: [Target] = [
        .init(rel: "Library/Application Support/MobileSync/Backup", label: "iOS device backups",
              kind: .hiddenSpace, hint: "Real data — restoring a device needs these."),
        .init(rel: "Library/Developer/CoreSimulator/Devices", label: "Xcode simulators",
              kind: .hiddenSpace, hint: "Re-downloadable, but slow to rebuild."),
        .init(rel: "Library/Developer/Xcode/Archives", label: "Xcode archives",
              kind: .hiddenSpace, hint: "Keep these if you still ship those builds."),
        .init(rel: "Library/Containers/com.docker.docker/Data", label: "Docker data",
              kind: .hiddenSpace, hint: "Docker's VM disk — deleting drops images/volumes."),
        .init(rel: "Library/Group Containers/*dev.orbstack/data", label: "OrbStack data",
              kind: .hiddenSpace, hint: "Container/VM data — review before removing."),
        .init(rel: "Library/Developer/Xcode/DerivedData", label: "Xcode DerivedData",
              kind: .cleanable, hint: "Build artifacts — regenerated on next build."),
        .init(rel: "Library/Caches/JetBrains", label: "JetBrains caches",
              kind: .cleanable, hint: "IDE caches — rebuilt automatically."),
        .init(rel: ".gradle/caches", label: "Gradle caches",
              kind: .cleanable, hint: "Re-downloaded on next build."),
        .init(rel: "Library/Caches/CocoaPods", label: "CocoaPods cache",
              kind: .cleanable, hint: "Re-fetched on next pod install."),
        .init(rel: "Library/Application Support/Spotify/PersistentCache", label: "Spotify cache",
              kind: .cleanable, hint: "Streaming cache — refills as you listen."),
    ]

    public func scan() async -> [Insight] {
        var found: [Insight] = []

        // "Old Downloads" is computed differently (mtime filter), not a tree size.
        let downloads = home.appendingPathComponent("Downloads")
        let oldBytes = Self.oldDownloadsBytes(in: downloads, days: oldDownloadsDays, now: now)
        if oldBytes > 0 {
            found.append(Insight(
                label: "Downloads older than \(oldDownloadsDays) days",
                path: downloads.path, bytes: oldBytes, kind: .hiddenSpace,
                reversibleHint: "Untouched for \(oldDownloadsDays)+ days — likely safe to clear."))
        }

        // Measure each present target's tree size, bounded to 8 at a time.
        let targets = Self.targets
        await withTaskGroup(of: Insight?.self) { group in
            var active = 0
            var index = 0
            func submit(_ t: Target) {
                let resolved = self.resolve(t.rel)
                group.addTask {
                    guard let url = resolved,
                        FileManager.default.fileExists(atPath: url.path) else { return nil }
                    let bytes = Int64(SmartScanner.directorySize(url))
                    guard bytes > 0 else { return nil }
                    return Insight(label: t.label, path: url.path, bytes: bytes,
                                   kind: t.kind, reversibleHint: t.hint)
                }
            }
            while index < targets.count && active < 8 { submit(targets[index]); index += 1; active += 1 }
            while let result = await group.next() {
                if let result { found.append(result) }
                active -= 1
                if index < targets.count { submit(targets[index]); index += 1; active += 1 }
            }
        }

        return found.sorted { $0.bytes > $1.bytes }
    }

    /// Resolves a home-relative path; if it contains a "*" segment, matches the
    /// first directory whose name contains the wildcard's literal part.
    func resolve(_ rel: String) -> URL? {
        guard rel.contains("*") else { return home.appendingPathComponent(rel) }
        let comps = rel.split(separator: "/").map(String.init)
        var url = home
        for comp in comps {
            if comp.contains("*") {
                let needle = comp.replacingOccurrences(of: "*", with: "")
                guard let children = try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil),
                    let match = children.first(where: { $0.lastPathComponent.contains(needle) })
                else { return nil }
                url = match
            } else {
                url = url.appendingPathComponent(comp)
            }
        }
        return url
    }

    /// Total size of top-level Downloads entries last modified before the cutoff.
    /// Shallow (one level) — a bounded sweep, like the residue scan.
    static func oldDownloadsBytes(in downloads: URL, days: Int, now: Date) -> Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        var total: Int64 = 0
        for entry in entries {
            let values = try? entry.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey, .totalFileAllocatedSizeKey])
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }
            if values?.isDirectory == true {
                total += Int64(SmartScanner.directorySize(entry))
            } else {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
