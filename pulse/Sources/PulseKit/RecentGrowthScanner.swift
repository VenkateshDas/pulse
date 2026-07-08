import Foundation

/// One file written inside the growth window.
public struct RecentFile: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let sizeBytes: UInt64
    public let modified: Date

    public init(path: String, name: String, sizeBytes: UInt64, modified: Date) {
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.modified = modified
    }
}

/// A folder that accumulated recent files, with its biggest offenders.
public struct GrowthGroup: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let recentBytes: UInt64
    public let fileCount: Int
    public let topFiles: [RecentFile]

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }

    public init(path: String, recentBytes: UInt64, fileCount: Int, topFiles: [RecentFile]) {
        self.path = path
        self.recentBytes = recentBytes
        self.fileCount = fileCount
        self.topFiles = topFiles
    }
}

/// Result of one growth scan: where the disk grew inside the window.
public struct GrowthReport: Sendable, Equatable {
    public let groups: [GrowthGroup]
    public let totalRecentBytes: UInt64
    public let scannedFiles: Int
    public let cutoff: Date

    public init(groups: [GrowthGroup], totalRecentBytes: UInt64, scannedFiles: Int, cutoff: Date) {
        self.groups = groups
        self.totalRecentBytes = totalRecentBytes
        self.scannedFiles = scannedFiles
        self.cutoff = cutoff
    }
}

/// Answers "where did my free space go since <day>" without any prior
/// baseline: one volume walk collecting files whose modification date falls
/// inside the window, rolled up by folder. Retroactive by design — file
/// dates are the baseline the filesystem already keeps.
public struct RecentGrowthScanner: Sendable {
    /// Folders a group key is capped to, so results read as recognizable
    /// locations ("/Users/x/Library/Caches") instead of one row per leaf dir.
    static let groupDepth = 4
    /// Groups smaller than this are summed into the report total but not listed.
    static let minimumGroupBytes: UInt64 = 25_000_000
    static let topFilesPerGroup = 8

    public init() {}

    /// Blocking full-volume walk — call from a detached task. Honors task
    /// cancellation between directories.
    public func scan(since cutoff: Date) -> GrowthReport {
        var files: [RecentFile] = []
        var scanned = 0
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey, .creationDateKey,
        ]
        let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: "/"), includingPropertiesForKeys: keys,
            options: [], errorHandler: { _, _ in true })
        while let url = enumerator?.nextObject() as? URL {
            if Task.isCancelled { break }
            let path = url.path
            if StorageScanner.prunedPaths.contains(path) || path == "/Volumes"
                || path.hasPrefix("/Volumes/")
            {
                enumerator?.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true {
                enumerator?.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            scanned += 1
            // Copies and unarchives preserve mtime, so a file downloaded
            // yesterday can carry a years-old modification date — its
            // birthtime is when it landed on this disk. Newest of the two
            // decides membership in the window.
            let modified = values.contentModificationDate ?? .distantPast
            let created = values.creationDate ?? .distantPast
            let arrived = max(modified, created)
            guard arrived >= cutoff,
                let size = values.totalFileAllocatedSize, size > 0
            else { continue }
            files.append(
                RecentFile(
                    path: path, name: url.lastPathComponent,
                    sizeBytes: UInt64(size), modified: arrived))
        }
        return Self.report(from: files, scannedFiles: scanned, cutoff: cutoff)
    }

    /// Pure rollup, separated from the walk for testability.
    static func report(from files: [RecentFile], scannedFiles: Int, cutoff: Date) -> GrowthReport {
        var byGroup: [String: [RecentFile]] = [:]
        var total: UInt64 = 0
        for file in files {
            total += file.sizeBytes
            byGroup[groupKey(for: file.path), default: []].append(file)
        }
        let groups = byGroup.compactMap { path, members -> GrowthGroup? in
            let bytes = members.reduce(0) { $0 + $1.sizeBytes }
            guard bytes >= minimumGroupBytes else { return nil }
            let top = members.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(topFilesPerGroup)
            return GrowthGroup(
                path: path, recentBytes: bytes, fileCount: members.count, topFiles: Array(top))
        }
        .sorted { $0.recentBytes > $1.recentBytes }
        return GrowthReport(
            groups: groups, totalRecentBytes: total, scannedFiles: scannedFiles, cutoff: cutoff)
    }

    /// Parent folder capped to `groupDepth` components: files deep inside
    /// "/Users/x/Library/Caches/Foo/Bar" all group under
    /// "/Users/x/Library/Caches".
    static func groupKey(for path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let components = parent.split(separator: "/").prefix(groupDepth)
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }
}
