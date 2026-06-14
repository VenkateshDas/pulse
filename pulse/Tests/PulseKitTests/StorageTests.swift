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

