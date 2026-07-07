import Foundation
import Testing

@testable import PulseKit

@Suite("TimelineStore attribution")
struct TimelineAttributionTests {
    private let cal = Calendar.current
    private let gb: UInt64 = 1_000_000_000

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: Date.now.addingTimeInterval(TimeInterval(offset) * 86400))
    }

    @Test func attributesGrowthToCategoriesSortedByMagnitude() {
        let store = TimelineStore(fileURL: nil)
        store.record(
            totalUsedBytes: 100 * gb,
            categories: ["Downloads": 10 * gb, "Caches": 5 * gb], at: day(-1))
        store.record(
            totalUsedBytes: 106 * gb,
            categories: ["Downloads": 14 * gb, "Caches": 4 * gb], at: day(0))

        let attribution = store.attribution(for: day(0))
        #expect(attribution != nil)
        #expect(attribution?.baselineDate == day(-1))
        #expect(attribution?.changes.map(\.name) == ["Downloads", "Caches"])
        #expect(attribution?.changes.first?.deltaBytes == Int64(4 * gb))
        #expect(attribution?.changes.last?.deltaBytes == -Int64(gb))
        // total +6, explained +3 → elsewhere +3
        #expect(attribution?.otherBytes == Int64(3 * gb))
    }

    @Test func skipsUnscannedDaysWhenPickingBaseline() {
        let store = TimelineStore(fileURL: nil)
        store.record(totalUsedBytes: 100 * gb, categories: ["Docs": 10 * gb], at: day(-3))
        store.record(totalUsedBytes: 101 * gb, categories: [:], at: day(-2))  // no scan
        store.record(totalUsedBytes: 103 * gb, categories: ["Docs": 13 * gb], at: day(0))

        let attribution = store.attribution(for: day(0))
        #expect(attribution?.baselineDate == day(-3))
        #expect(attribution?.changes == [.init(name: "Docs", deltaBytes: Int64(3 * gb))])
        #expect(attribution?.otherBytes == 0)
    }

    @Test func nilWithoutScanOnEitherEnd() {
        let store = TimelineStore(fileURL: nil)
        store.record(totalUsedBytes: 100 * gb, categories: [:], at: day(-1))
        store.record(totalUsedBytes: 105 * gb, categories: ["Docs": gb], at: day(0))
        // No categorized baseline exists.
        #expect(store.attribution(for: day(0)) == nil)
        // Day itself never scanned.
        #expect(store.attribution(for: day(-1)) == nil)
        // Unknown day.
        #expect(store.attribution(for: day(-9)) == nil)
    }

    @Test func hidesNoiseBelowMinimumButKeepsItExplained() {
        let store = TimelineStore(fileURL: nil)
        store.record(
            totalUsedBytes: 100 * gb,
            categories: ["Docs": 10 * gb, "Movies": 5 * gb], at: day(-1))
        store.record(
            totalUsedBytes: 102 * gb,
            categories: ["Docs": 12 * gb, "Movies": 5 * gb + 10_000_000], at: day(0))

        let attribution = store.attribution(for: day(0))
        // Movies' +10 MB is under the 50 MB floor — hidden from the list…
        #expect(attribution?.changes.map(\.name) == ["Docs"])
        // …but still counted as explained, so "elsewhere" stays ≈ 0.
        #expect(attribution?.otherBytes == 0)
    }

    @Test func categoryThatDisappearsCountsAsShrink() {
        let store = TimelineStore(fileURL: nil)
        store.record(totalUsedBytes: 100 * gb, categories: ["Xcode caches": 2 * gb], at: day(-1))
        store.record(totalUsedBytes: 98 * gb, categories: ["Docs": gb], at: day(0))

        let attribution = store.attribution(for: day(0))
        let names = attribution?.changes.map(\.name) ?? []
        #expect(names.contains("Xcode caches"))
        #expect(
            attribution?.changes.first(where: { $0.name == "Xcode caches" })?.deltaBytes
                == -Int64(2 * gb))
    }
}
