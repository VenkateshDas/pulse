import Foundation
import CPulse

public final class DuplicateScanner: @unchecked Sendable {
    public struct DuplicateFile: Identifiable, Equatable, Sendable, Hashable {
        public let id: String
        public let url: URL
        public let fileSize: Int64
        public let inode: UInt64
        public let dev: Int32
        public let createdAt: Date
        public let modifiedAt: Date
        public var isSelectedForDeletion: Bool
        public var isKeepCandidate: Bool

        public init(
            url: URL,
            fileSize: Int64,
            inode: UInt64,
            dev: Int32,
            createdAt: Date,
            modifiedAt: Date,
            isSelectedForDeletion: Bool = false,
            isKeepCandidate: Bool = false
        ) {
            self.id = url.path
            self.url = url
            self.fileSize = fileSize
            self.inode = inode
            self.dev = dev
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.isSelectedForDeletion = isSelectedForDeletion
            self.isKeepCandidate = isKeepCandidate
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    public struct DuplicateGroup: Identifiable, Equatable, Sendable {
        public let id: String // BLAKE3 hex hash
        public let fileSize: Int64
        public var files: [DuplicateFile]
        public let isAPFSClone: Bool

        public var totalReclaimableBytes: Int64 {
            guard !isAPFSClone else { return 0 }
            let deleteCount = files.filter(\.isSelectedForDeletion).count
            return Int64(deleteCount) * fileSize
        }

        public init(id: String, fileSize: Int64, files: [DuplicateFile], isAPFSClone: Bool) {
            self.id = id
            self.fileSize = fileSize
            self.files = files
            self.isAPFSClone = isAPFSClone
        }
    }

    public struct ScanProgress: Sendable {
        public let phase: Phase
        public let processedFiles: Int
        public let totalFiles: Int
        public let foundDuplicates: Int

        public enum Phase: Sendable {
            case indexing
            case sizeBucketing
            case headTailHashing
            case fullHashing
            case completed
        }

        public init(phase: Phase, processedFiles: Int, totalFiles: Int, foundDuplicates: Int) {
            self.phase = phase
            self.processedFiles = processedFiles
            self.totalFiles = totalFiles
            self.foundDuplicates = foundDuplicates
        }
    }

    private let minFileSize: Int64 = 4096 // Ignore files smaller than 4 KiB
    private let maxConcurrentTasks = min(ProcessInfo.processInfo.activeProcessorCount, 8)

    public init() {}

    public func scan(
        directories: [URL],
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [DuplicateGroup] {
        // Stage 1: File Size Bucketing
        progress(ScanProgress(phase: .indexing, processedFiles: 0, totalFiles: 0, foundDuplicates: 0))
        let sizeBuckets = try await buildSizeBuckets(directories: directories, progress: progress)

        var totalCandidateFiles = 0
        for bucket in sizeBuckets.values {
            totalCandidateFiles += bucket.count
        }

        progress(ScanProgress(phase: .sizeBucketing, processedFiles: totalCandidateFiles, totalFiles: totalCandidateFiles, foundDuplicates: 0))
        if sizeBuckets.isEmpty {
            progress(ScanProgress(phase: .completed, processedFiles: 0, totalFiles: 0, foundDuplicates: 0))
            return []
        }

        // Stage 2: Head/Tail Hashing
        let headTailBuckets = try await buildHeadTailBuckets(sizeBuckets: sizeBuckets, totalCandidates: totalCandidateFiles, progress: progress)

        // Stage 3: Full BLAKE3 Hashing
        let rawGroups = try await buildFullHashGroups(headTailBuckets: headTailBuckets, progress: progress)

        // Stage 4: APFS Inode & Smart Auto-Selection Analysis
        let finalGroups = processFinalGroups(rawGroups)
        progress(ScanProgress(phase: .completed, processedFiles: totalCandidateFiles, totalFiles: totalCandidateFiles, foundDuplicates: finalGroups.count))

        return finalGroups
    }

    // Single-file BLAKE3 streaming helper
    public static func hashFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let ctx = pulse_blake3_create() else {
            throw NSError(domain: "DuplicateScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate BLAKE3 context"])
        }
        defer { pulse_blake3_free(ctx) }

        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            chunk.withUnsafeBytes { buffer in
                if let ptr = buffer.baseAddress {
                    pulse_blake3_update(ctx, ptr, buffer.count)
                }
            }
        }

        var hash = [UInt8](repeating: 0, count: 32)
        pulse_blake3_final(ctx, &hash)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // Partial head-tail BLAKE3 helper
    public static func hashHeadTail(at url: URL, fileSize: Int64) throws -> String {
        if fileSize <= 8192 {
            return try hashFile(at: url)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let ctx = pulse_blake3_create() else {
            throw NSError(domain: "DuplicateScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate BLAKE3 context"])
        }
        defer { pulse_blake3_free(ctx) }

        // Read first 4096 bytes
        if let headChunk = try handle.read(upToCount: 4096), !headChunk.isEmpty {
            headChunk.withUnsafeBytes { buffer in
                if let ptr = buffer.baseAddress {
                    pulse_blake3_update(ctx, ptr, buffer.count)
                }
            }
        }

        // Read last 4096 bytes
        try handle.seek(toOffset: UInt64(fileSize - 4096))
        if let tailChunk = try handle.read(upToCount: 4096), !tailChunk.isEmpty {
            tailChunk.withUnsafeBytes { buffer in
                if let ptr = buffer.baseAddress {
                    pulse_blake3_update(ctx, ptr, buffer.count)
                }
            }
        }

        var hash = [UInt8](repeating: 0, count: 32)
        pulse_blake3_final(ctx, &hash)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // Helper: Stage 1 Size Bucketing
    private func buildSizeBuckets(
        directories: [URL],
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [Int64: [URL]] {
        var sizeMap: [Int64: [URL]] = [:]
        let fileManager = FileManager.default

        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                do {
                    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey])
                    guard values.isRegularFile == true,
                          values.isSymbolicLink != true,
                          values.isPackage != true,
                          let fileSize = values.fileSize,
                          Int64(fileSize) >= minFileSize else { continue }

                    sizeMap[Int64(fileSize), default: []].append(fileURL)
                } catch {
                    continue
                }
            }
        }

        return sizeMap.filter { $0.value.count > 1 }
    }

    // Helper: Stage 2 Head/Tail Hashing
    private func buildHeadTailBuckets(
        sizeBuckets: [Int64: [URL]],
        totalCandidates: Int,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [String: [URL]] {
        var headTailMap: [String: [URL]] = [:]
        var processedCount = 0

        for (fileSize, urls) in sizeBuckets {
            for url in urls {
                do {
                    let hash = try Self.hashHeadTail(at: url, fileSize: fileSize)
                    let key = "\(fileSize)_\(hash)"
                    headTailMap[key, default: []].append(url)
                } catch {
                    // Skip unreadable files
                }
                processedCount += 1
                if processedCount % 50 == 0 {
                    progress(ScanProgress(phase: .headTailHashing, processedFiles: processedCount, totalFiles: totalCandidates, foundDuplicates: headTailMap.count))
                }
            }
        }

        return headTailMap.filter { $0.value.count > 1 }
    }

    // Helper: Stage 3 Full Hash Groups with Race Condition Check
    private func buildFullHashGroups(
        headTailBuckets: [String: [URL]],
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [String: [URL]] {
        var fullMap: [String: [URL]] = [:]
        var processedCount = 0
        let totalCount = headTailBuckets.values.reduce(0) { $0 + $1.count }

        for (_, urls) in headTailBuckets {
            for url in urls {
                do {
                    let attributesBefore = try FileManager.default.attributesOfItem(atPath: url.path)
                    let modificationBefore = attributesBefore[.modificationDate] as? Date ?? .distantPast

                    let hash = try Self.hashFile(at: url)

                    let attributesAfter = try FileManager.default.attributesOfItem(atPath: url.path)
                    let modificationAfter = attributesAfter[.modificationDate] as? Date ?? .distantPast

                    // Invalidate if file was modified mid-hash
                    if modificationBefore == modificationAfter {
                        fullMap[hash, default: []].append(url)
                    }
                } catch {
                    // Skip unreadable files
                }
                processedCount += 1
                if processedCount % 20 == 0 {
                    progress(ScanProgress(phase: .fullHashing, processedFiles: processedCount, totalFiles: totalCount, foundDuplicates: fullMap.count))
                }
            }
        }

        return fullMap.filter { $0.value.count > 1 }
    }

    // Helper: Stage 4 APFS & Smart Selection Analysis
    private func processFinalGroups(_ rawGroups: [String: [URL]]) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []

        for (hash, urls) in rawGroups {
            var files: [DuplicateFile] = []
            var inodes: Set<UInt64> = []

            for url in urls {
                var statBuf = stat()
                if stat(url.path, &statBuf) == 0 {
                    let inode = UInt64(statBuf.st_ino)
                    let dev = statBuf.st_dev
                    let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                    let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    let fileSize = Int64(statBuf.st_size)

                    inodes.insert(inode)
                    let file = DuplicateFile(
                        url: url,
                        fileSize: fileSize,
                        inode: inode,
                        dev: dev,
                        createdAt: createdAt,
                        modifiedAt: modifiedAt
                    )
                    files.append(file)
                }
            }

            guard files.count > 1 else { continue }

            let fileSize = files.first?.fileSize ?? 0
            // APFS clone or hard link if all copies share same inode
            let isAPFSClone = (inodes.count == 1)

            // Apply Smart Selection Heuristics
            files = applySmartSelection(to: files)

            let group = DuplicateGroup(
                id: hash,
                fileSize: fileSize,
                files: files,
                isAPFSClone: isAPFSClone
            )
            groups.append(group)
        }

        return groups.sorted { $0.totalReclaimableBytes > $1.totalReclaimableBytes }
    }

    // Smart Selection Heuristics Implementation
    private func applySmartSelection(to files: [DuplicateFile]) -> [DuplicateFile] {
        guard files.count > 1 else { return files }

        // Rank files to pick the best KEEP candidate:
        // 1. Location priority: ~/Documents > ~/Pictures > ~/Desktop > ~/Downloads > /tmp
        // 2. Path depth (shorter path depth wins)
        // 3. Creation date (oldest wins)
        // 4. Filename (clean name wins over " (1)" copy suffix)
        let sorted = files.sorted { f1, f2 in
            let score1 = locationScore(path: f1.url.path)
            let score2 = locationScore(path: f2.url.path)
            if score1 != score2 { return score1 > score2 }

            let depth1 = f1.url.pathComponents.count
            let depth2 = f2.url.pathComponents.count
            if depth1 != depth2 { return depth1 < depth2 }

            if f1.createdAt != f2.createdAt { return f1.createdAt < f2.createdAt }

            let isCopy1 = f1.url.lastPathComponent.contains(" (") || f1.url.lastPathComponent.contains(" copy")
            let isCopy2 = f2.url.lastPathComponent.contains(" (") || f2.url.lastPathComponent.contains(" copy")
            if isCopy1 != isCopy2 { return !isCopy1 }

            return f1.url.path < f2.url.path
        }

        guard let keepCandidate = sorted.first else { return files }

        return files.map { file in
            var updated = file
            if file.id == keepCandidate.id {
                updated.isKeepCandidate = true
                updated.isSelectedForDeletion = false
            } else {
                updated.isKeepCandidate = false
                updated.isSelectedForDeletion = true
            }
            return updated
        }
    }

    private func locationScore(path: String) -> Int {
        if path.contains("/Documents/") { return 100 }
        if path.contains("/Pictures/") { return 90 }
        if path.contains("/Desktop/") { return 80 }
        if path.contains("/Downloads/") { return 50 }
        if path.contains("/tmp/") { return 10 }
        return 60
    }
}
