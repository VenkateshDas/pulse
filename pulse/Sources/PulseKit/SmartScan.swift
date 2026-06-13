import Foundation

/// Deletability of a clean suggestion. The grade drives the entire UX:
/// safe rows are pre-selected, careful rows need an explicit tick, review
/// rows can never be bulk-selected — only opened in Finder.
public enum SafetyGrade: String, Codable, Sendable, CaseIterable {
    case safe, careful, review

    /// Sort rank: safe first, review last.
    public var rank: Int {
        switch self {
        case .safe: 0
        case .careful: 1
        case .review: 2
        }
    }
}

/// One evidence-based clean suggestion: what it is in plain English, what
/// happens if deleted, and why the grade applies.
public struct CleanItem: Identifiable, Sendable, Equatable {
    /// The absolute path doubles as a stable identity across rescans.
    public var id: String { path }
    public let category: String
    public let label: String
    /// Consequence sentence ("regenerates on next launch").
    public let detail: String
    public let path: String
    public let sizeBytes: UInt64
    /// Days since the item (or its owning project) was last touched.
    public let idleDays: Int?
    public let grade: SafetyGrade

    public init(
        category: String, label: String, detail: String, path: String,
        sizeBytes: UInt64, idleDays: Int?, grade: SafetyGrade
    ) {
        self.category = category
        self.label = label
        self.detail = detail
        self.path = path
        self.sizeBytes = sizeBytes
        self.idleDays = idleDays
        self.grade = grade
    }
}

/// Top-level home folder size for the storage map.
public struct FolderUsage: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let sizeBytes: UInt64
    /// Dominant deletability tint for the map cell.
    public let grade: SafetyGrade
}

/// Result of one full storage scan.
public struct StorageScan: Sendable, Equatable {
    public let items: [CleanItem]
    public let topFolders: [FolderUsage]
    public let scannedFiles: Int
    public let finished: Date

    public init(items: [CleanItem], topFolders: [FolderUsage], scannedFiles: Int, finished: Date) {
        self.items = items
        self.topFolders = topFolders
        self.scannedFiles = scannedFiles
        self.finished = finished
    }
}

/// Sudoless smart-storage scan, ported from the mac-monitor TUI engine.
/// Pure FileManager — no subprocesses, ever. One walk of the home folder
/// powers the storage map, stale-dev-junk, and large+old detection; known
/// Library cache locations are sized directly.
public struct SmartScanner: Sendable {
    public let home: URL
    public let now: Date
    /// When on, the scan adds the heavier developer-junk locations (Homebrew,
    /// Docker, Xcode simulators) — the "Developer Junk Mode" Settings toggle.
    public let developerMode: Bool

    /// Persisted Developer-Junk-Mode toggle (UserDefaults), the default the
    /// app uses when constructing a scanner without an explicit value.
    public static let developerModeKey = "PulseDeveloperMode"
    public static var developerModeDefault: Bool {
        UserDefaults.standard.bool(forKey: developerModeKey)
    }

    static let devJunkDirs: Set<String> = [
        "node_modules", ".venv", "venv", ".tox", "target", ".gradle",
    ]
    static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]
    static let staleProjectDays = 60
    static let oldInstallerDays = 30
    static let largeOldDays = 180
    static let largeFileBytes: UInt64 = 500 * 1_000_000
    static let maxWalkDepth = 6
    /// Directories never descended into during the home walk.
    static let prunedNames: Set<String> = [
        "Library", ".Trash", "miniforge", "miniconda3", "anaconda3",
    ]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, now: Date = .now,
        developerMode: Bool = SmartScanner.developerModeDefault
    ) {
        self.home = home
        self.now = now
        self.developerMode = developerMode
    }

    /// Full scan. Blocking — call from a background task.
    public func scan() -> StorageScan {
        var items: [CleanItem] = []
        items += scanKnownLocations()
        let walk = walkHome()
        items += walk.items
        items.sort {
            $0.grade.rank != $1.grade.rank
                ? $0.grade.rank < $1.grade.rank
                : $0.sizeBytes > $1.sizeBytes
        }
        return StorageScan(
            items: items,
            topFolders: walk.folders.sorted { $0.sizeBytes > $1.sizeBytes },
            scannedFiles: walk.fileCount,
            // Completion time, not `now` — a first scan can stall minutes on
            // TCC consent prompts, and "indexed Xm ago" must stay honest.
            finished: Date()
        )
    }

    // MARK: - Known Library locations

    /// (relative path, category, grade, consequence). Expanded entries get
    /// per-app subfolder rows instead of one opaque blob.
    private static let knownTargets:
        [(rel: String, category: String, grade: SafetyGrade, detail: String, expand: Bool)] = [
            (
                "Library/Caches", "App caches", .safe,
                "regenerated automatically on next launch", true
            ),
            (
                "Library/Logs", "App logs", .safe,
                "only useful for active debugging", true
            ),
            (
                "Library/Developer/Xcode/DerivedData", "Developer junk", .safe,
                "next build is a clean build — no source touched", false
            ),
            (
                "Library/Developer/Xcode/Archives", "Developer junk", .careful,
                "needed only to re-symbolicate or re-submit past builds", false
            ),
            (
                ".npm", "Developer junk", .safe,
                "package download cache — refilled on next npm install", false
            ),
            (
                ".cache", "Developer junk", .safe,
                "pip wheels and CLI tool caches — regenerated on next install", false
            ),
            (
                "Library/Application Support/MobileSync/Backup", "iOS backups", .review,
                "full device backups — delete only with a current backup elsewhere", false
            ),
            (
                ".Trash", "Trash", .safe,
                "already deleted — cleaning via Pulse keeps 7-day restore", false
            ),
        ]

    /// Heavier developer locations, included only in Developer Junk Mode.
    private static let developerTargets:
        [(rel: String, category: String, grade: SafetyGrade, detail: String, expand: Bool)] = [
            (
                "Library/Caches/Homebrew", "Developer junk", .safe,
                "Homebrew download cache — refilled on next brew install", false
            ),
            (
                "Library/Developer/CoreSimulator/Caches", "Developer junk", .safe,
                "Xcode simulator caches — rebuilt by Xcode automatically", false
            ),
            (
                "Library/Developer/CoreSimulator/Devices", "Developer junk", .careful,
                "simulator devices and their data — recreate from Xcode if removed", false
            ),
            (
                "Library/Containers/com.docker.docker/Data/vms", "Developer junk", .review,
                "Docker VM disk — deleting loses all containers, images, and volumes", false
            ),
        ]

    private var effectiveTargets:
        [(rel: String, category: String, grade: SafetyGrade, detail: String, expand: Bool)]
    {
        developerMode ? Self.knownTargets + Self.developerTargets : Self.knownTargets
    }

    private func scanKnownLocations() -> [CleanItem] {
        var out: [CleanItem] = []
        for target in effectiveTargets {
            let url = home.appendingPathComponent(target.rel)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if target.rel == ".Trash" {
                // Stage individual trashed items, never the ~/.Trash directory
                // itself — moving the dir wholesale breaks Finder "Put Back"
                // and buries items the user may still want to recover.
                out += expandTrash(parent: url, detail: target.detail)
            } else if target.expand {
                out += expandPerApp(
                    parent: url, category: target.category,
                    grade: target.grade, detail: target.detail)
            } else {
                let size = Self.directorySize(url)
                guard size >= 10 * 1_000_000 else { continue }
                out.append(
                    CleanItem(
                        category: target.category,
                        label: url.lastPathComponent == ".Trash"
                            ? "Trash" : url.lastPathComponent,
                        detail: target.detail,
                        path: url.path,
                        sizeBytes: size,
                        idleDays: idleDays(of: url),
                        grade: target.grade
                    ))
            }
        }
        return out
    }

    /// Per-app subfolders of a cache/log dir as individual rows — granular
    /// rows show *which app* hoards space, and the parent dir itself is a
    /// system-required folder that must never be deleted whole.
    private func expandPerApp(
        parent: URL, category: String, grade: SafetyGrade, detail: String,
        minBytes: UInt64 = 10 * 1_000_000, topN: Int = 12
    ) -> [CleanItem] {
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants])
        else { return [] }
        var out: [CleanItem] = []
        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let size = Self.directorySize(child)
            guard size >= minBytes else { continue }
            out.append(
                CleanItem(
                    category: category,
                    label: child.lastPathComponent,
                    detail: detail,
                    path: child.path,
                    sizeBytes: size,
                    idleDays: idleDays(of: child),
                    grade: grade
                ))
        }
        out.sort { $0.sizeBytes > $1.sizeBytes }
        return Array(out.prefix(topN))
    }

    /// Each top-level entry in ~/.Trash as its own row, so cleaning stages the
    /// trashed items individually instead of moving the .Trash directory whole.
    private func expandTrash(parent: URL, detail: String) -> [CleanItem] {
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isDirectoryKey],
                options: [])
        else { return [] }
        var out: [CleanItem] = []
        for child in children {
            let isDir =
                (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let size =
                isDir
                ? Self.directorySize(child)
                : UInt64(
                    (try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                        .totalFileAllocatedSize ?? 0)
            out.append(
                CleanItem(
                    category: "Trash",
                    label: child.lastPathComponent,
                    detail: detail,
                    path: child.path,
                    sizeBytes: size,
                    idleDays: idleDays(of: child),
                    grade: .safe
                ))
        }
        out.sort { $0.sizeBytes > $1.sizeBytes }
        return out
    }

    // MARK: - Home walk

    private struct WalkResult {
        var items: [CleanItem] = []
        var folders: [FolderUsage] = []
        var fileCount = 0
    }

    /// One recursive pass over home (Library pruned): per-top-level-folder
    /// totals, stale dev junk, old installers, and large+old files.
    private func walkHome() -> WalkResult {
        var result = WalkResult()
        guard
            let topLevel = try? FileManager.default.contentsOfDirectory(
                at: home, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [])
        else { return result }

        var largeOld: [CleanItem] = []
        var devJunk: [CleanItem] = []
        var installers: [CleanItem] = []

        for entry in topLevel {
            let name = entry.lastPathComponent
            guard !Self.prunedNames.contains(name), !name.hasPrefix(".") else { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

            var folderBytes: UInt64 = 0
            walk(
                entry, depth: 1, folderBytes: &folderBytes, fileCount: &result.fileCount,
                largeOld: &largeOld, devJunk: &devJunk)
            if name == "Downloads" {
                installers = scanInstallers(in: entry)
            }
            if folderBytes >= 50 * 1_000_000 {
                result.folders.append(
                    FolderUsage(
                        name: name, path: entry.path, sizeBytes: folderBytes,
                        grade: Self.folderGrade(name)
                    ))
            }
        }

        largeOld.sort { $0.sizeBytes > $1.sizeBytes }
        devJunk.sort { $0.sizeBytes > $1.sizeBytes }
        installers.sort { $0.sizeBytes > $1.sizeBytes }
        result.items = Array(devJunk.prefix(15)) + installers + Array(largeOld.prefix(10))
        return result
    }

    private func walk(
        _ dir: URL, depth: Int, folderBytes: inout UInt64, fileCount: inout Int,
        largeOld: inout [CleanItem], devJunk: inout [CleanItem]
    ) {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .contentModificationDateKey,
        ]
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [])
        else { return }

        for child in children {
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            let name = child.lastPathComponent

            if values.isRegularFile == true {
                let size = UInt64(values.totalFileAllocatedSize ?? 0)
                folderBytes += size
                fileCount += 1
                if size >= Self.largeFileBytes,
                    let modified = values.contentModificationDate,
                    days(since: modified) >= Self.largeOldDays
                {
                    largeOld.append(
                        CleanItem(
                            category: "Large & old", label: name,
                            detail:
                                "real data — Pulse never bulk-selects this; review it yourself",
                            path: child.path, sizeBytes: size,
                            idleDays: days(since: modified), grade: .review
                        ))
                }
                continue
            }

            guard values.isDirectory == true else { continue }
            if Self.prunedNames.contains(name) { continue }
            if name.hasPrefix("."), !Self.devJunkDirs.contains(name) { continue }

            if Self.devJunkDirs.contains(name) {
                let size = Self.directorySize(child)
                folderBytes += size
                let idle = projectIdleDays(junkDir: child)
                if idle >= Self.staleProjectDays, size >= 20 * 1_000_000 {
                    let project = child.deletingLastPathComponent().lastPathComponent
                    devJunk.append(
                        CleanItem(
                            category: "Stale dev junk",
                            label: "\(name) — “\(project)”",
                            detail: "restores with one install/build · repo itself untouched",
                            path: child.path, sizeBytes: size,
                            idleDays: idle, grade: .careful
                        ))
                }
                continue  // never descend into junk dirs
            }

            if depth < Self.maxWalkDepth {
                walk(
                    child, depth: depth + 1, folderBytes: &folderBytes, fileCount: &fileCount,
                    largeOld: &largeOld, devJunk: &devJunk)
            } else {
                folderBytes += Self.directorySize(child)
            }
        }
    }

    private func scanInstallers(in downloads: URL) -> [CleanItem] {
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: downloads,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey,
                ], options: [])
        else { return [] }
        var out: [CleanItem] = []
        for child in children {
            guard Self.installerExtensions.contains(child.pathExtension.lowercased()),
                let values = try? child.resourceValues(forKeys: [
                    .isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey,
                ]),
                values.isRegularFile == true,
                let modified = values.contentModificationDate
            else { continue }
            let size = UInt64(values.totalFileAllocatedSize ?? 0)
            let age = days(since: modified)
            guard age >= Self.oldInstallerDays, size >= 5 * 1_000_000 else { continue }
            out.append(
                CleanItem(
                    category: "Old installers",
                    label: child.lastPathComponent,
                    detail: "installer untouched \(age)d — the app is already installed",
                    path: child.path, sizeBytes: size, idleDays: age, grade: .careful
                ))
        }
        return Array(out.prefix(12))
    }

    /// Last real activity of the project owning a junk dir: newest mtime
    /// among project-root entries that aren't junk themselves.
    func projectIdleDays(junkDir: URL) -> Int {
        let project = junkDir.deletingLastPathComponent()
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [])
        else { return 0 }
        let newest =
            children
            .filter { !Self.devJunkDirs.contains($0.lastPathComponent) }
            .compactMap {
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
            }
            .max()
        guard let newest else { return 0 }
        return days(since: newest)
    }

    // MARK: - Helpers

    static func folderGrade(_ name: String) -> SafetyGrade {
        switch name {
        case "Movies", "Pictures", "Music", "Documents": .review
        case "Downloads", "Desktop": .careful
        default: .careful
        }
    }

    /// Allocated size of a directory tree (matches what deleting frees).
    public static func directorySize(_ url: URL) -> UInt64 {
        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                options: [])
        else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard
                let values = try? file.resourceValues(forKeys: [
                    .totalFileAllocatedSizeKey, .isRegularFileKey,
                ]),
                values.isRegularFile == true
            else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    private func idleDays(of url: URL) -> Int? {
        guard
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        else { return nil }
        return days(since: modified)
    }

    private func days(since date: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 86400))
    }
}
