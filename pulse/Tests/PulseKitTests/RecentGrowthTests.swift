import Foundation
import Testing

@testable import PulseKit

@Suite("RecentGrowthScanner rollup")
struct RecentGrowthTests {
    private let gb: UInt64 = 1_000_000_000

    private func file(_ path: String, _ bytes: UInt64) -> RecentFile {
        RecentFile(
            path: path, name: (path as NSString).lastPathComponent,
            sizeBytes: bytes, modified: .now)
    }

    @Test func groupKeyCapsDepthAtFour() {
        #expect(
            RecentGrowthScanner.groupKey(for: "/Users/x/Library/Caches/Foo/Bar/blob.bin")
                == "/Users/x/Library/Caches")
        #expect(RecentGrowthScanner.groupKey(for: "/opt/homebrew/lib/big.dylib") == "/opt/homebrew/lib")
        #expect(RecentGrowthScanner.groupKey(for: "/rootfile") == "/")
    }

    @Test func groupsSortedBySizeWithTopFiles() {
        let files = [
            file("/Users/x/Downloads/movie.mkv", 5 * gb),
            file("/Users/x/Downloads/iso.dmg", 2 * gb),
            file("/Users/x/Library/Caches/App/a.db", 3 * gb),
        ]
        let report = RecentGrowthScanner.report(from: files, scannedFiles: 3, cutoff: .now)
        #expect(report.groups.map(\.path) == ["/Users/x/Downloads", "/Users/x/Library/Caches"])
        #expect(report.groups.first?.recentBytes == 7 * gb)
        #expect(report.groups.first?.topFiles.first?.name == "movie.mkv")
        #expect(report.totalRecentBytes == 10 * gb)
    }

    @Test func smallGroupsCountTowardTotalButAreHidden() {
        let files = [
            file("/Users/x/Documents/note.txt", 10_000_000),
            file("/Users/x/Downloads/big.zip", gb),
        ]
        let report = RecentGrowthScanner.report(from: files, scannedFiles: 2, cutoff: .now)
        #expect(report.groups.map(\.path) == ["/Users/x/Downloads"])
        #expect(report.totalRecentBytes == gb + 10_000_000)
    }
}
