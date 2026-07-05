import Foundation
import Testing

@testable import PulseKit

// MARK: - Helpers

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeFile(at url: URL, megabytes: Int) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = Data(repeating: 0xAB, count: megabytes * 1_000_000)
    try data.write(to: url)
}

private func setModified(_ url: URL, daysAgo: Int) throws {
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSinceNow: -Double(daysAgo) * 86400)],
        ofItemAtPath: url.path)
}

// MARK: - Column pruning (in-place delete sync)

@Suite struct StoragePruningTests {
    private func node(_ path: String, _ size: UInt64, children: [StorageNode]? = nil) -> StorageNode {
        StorageNode(
            id: path, name: URL(fileURLWithPath: path).lastPathComponent,
            path: path, sizeBytes: size, isDirectory: true, children: children)
    }

    private var columns: [StorageNode] {
        [
            node("/", 100, children: [node("/Users", 60), node("/opt", 40)]),
            node("/Users", 60, children: [node("/Users/v", 50), node("/Users/Shared", 10)]),
            node("/Users/v", 50, children: [node("/Users/v/Downloads", 30), node("/Users/v/Documents", 20)]),
        ]
    }

    @Test func removesNodeAndSubtractsAncestors() {
        let pruned = columns.pruning(deletedPath: "/Users/v/Downloads", bytes: 30)
        #expect(pruned.count == 3)
        #expect(pruned[0].sizeBytes == 70)
        #expect(pruned[0].children?.first { $0.path == "/Users" }?.sizeBytes == 30)
        #expect(pruned[1].sizeBytes == 30)
        #expect(pruned[1].children?.first { $0.path == "/Users/v" }?.sizeBytes == 20)
        #expect(pruned[2].sizeBytes == 20)
        #expect(pruned[2].children?.contains { $0.path == "/Users/v/Downloads" } == false)
        #expect(pruned[2].children?.count == 1)
    }

    @Test func dropsColumnsAtAndBelowDeletedFolder() {
        let pruned = columns.pruning(deletedPath: "/Users/v", bytes: 50)
        #expect(pruned.map(\.path) == ["/", "/Users"])
        #expect(pruned[0].sizeBytes == 50)
        #expect(pruned[1].sizeBytes == 10)
        #expect(pruned[1].children?.contains { $0.path == "/Users/v" } == false)
    }

    @Test func siblingPathPrefixNotConfusedWithAncestor() {
        let cols = [node("/", 100, children: [node("/opt", 40), node("/optical", 10)])]
        let pruned = cols.pruning(deletedPath: "/opt", bytes: 40)
        #expect(pruned[0].sizeBytes == 60)
        #expect(pruned[0].children?.map(\.path) == ["/optical"])
    }

    @Test func pseudoOtherFilesRowUntouched() {
        let other = StorageNode(
            id: "/Users/v/_other_files", name: "Other Files", path: "/Users/v",
            sizeBytes: 5, isDirectory: false)
        let cols = [node("/Users/v", 50, children: [node("/Users/v/Downloads", 30), other])]
        let pruned = cols.pruning(deletedPath: "/Users/v/Downloads", bytes: 30)
        #expect(pruned[0].children?.first { $0.name == "Other Files" }?.sizeBytes == 5)
        #expect(pruned[0].sizeBytes == 20)
    }
}

// MARK: - StorageScanner

@Suite struct FastDirectorySizeTests {
    @Test func prunedPathReturnsZero() {
        let scanner = StorageScanner()
        let (size, count) = "/System/Volumes/Data".withCString { scanner.fastDirectorySize($0) }
        #expect(size == 0)
        #expect(count == 0)
    }

    @Test func countsFilesInTempTree() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeFile(at: dir.appendingPathComponent("a.bin"), megabytes: 2)
        try writeFile(at: dir.appendingPathComponent("sub/b.bin"), megabytes: 3)

        let scanner = StorageScanner()
        let (size, count) = dir.path.withCString { scanner.fastDirectorySize($0) }
        #expect(size >= 5_000_000)
        #expect(count == 3)
    }
}

