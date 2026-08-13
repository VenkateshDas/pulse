import Foundation
import Testing

@testable import PulseKit

@Suite("DuplicateScanner")
struct DuplicateScannerTests {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuplicateScannerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let real = realpath(dir.path, nil) else { return dir }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real))
    }

    @Test func blake3SingleFileHash() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.txt")
        let data = "Hello Pulse BLAKE3 Scanner!".data(using: .utf8)!
        try data.write(to: fileURL)

        let hash = try DuplicateScanner.hashFile(at: fileURL)
        #expect(hash.count == 64)
    }

    @Test func duplicateScannerPipelineIdenticalFiles() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let content = Data(repeating: 0xAB, count: 16384) // 16 KiB

        let file1 = dir.appendingPathComponent("file1.bin")
        let file2 = dir.appendingPathComponent("file2.bin")
        let file3 = dir.appendingPathComponent("file3.bin")

        try content.write(to: file1)
        try content.write(to: file2)
        try content.write(to: file3)

        let scanner = DuplicateScanner()
        let groups = try await scanner.scan(directories: [dir]) { _ in }

        #expect(groups.count == 1)
        guard let group = groups.first else { return }
        #expect(group.files.count == 3)
        #expect(group.fileSize == 16384)

        let deleteCount = group.files.filter(\.isSelectedForDeletion).count
        let keepCount = group.files.filter(\.isKeepCandidate).count
        #expect(deleteCount == 2)
        #expect(keepCount == 1)
    }

    @Test func duplicateScannerDisambiguatesDifferentContent() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let content1 = Data(repeating: 0xAA, count: 8192)
        let content2 = Data(repeating: 0xBB, count: 8192)

        let file1 = dir.appendingPathComponent("fileA.bin")
        let file2 = dir.appendingPathComponent("fileB.bin")

        try content1.write(to: file1)
        try content2.write(to: file2)

        let scanner = DuplicateScanner()
        let groups = try await scanner.scan(directories: [dir]) { _ in }

        #expect(groups.isEmpty)
    }

    @Test func duplicateScannerFiltersSmallFiles() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tinyContent = Data(repeating: 0x12, count: 500) // 500 bytes (< 4096 min size)

        let file1 = dir.appendingPathComponent("tiny1.bin")
        let file2 = dir.appendingPathComponent("tiny2.bin")

        try tinyContent.write(to: file1)
        try tinyContent.write(to: file2)

        let scanner = DuplicateScanner()
        let groups = try await scanner.scan(directories: [dir]) { _ in }

        #expect(groups.isEmpty)
    }
}
