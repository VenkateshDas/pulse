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

