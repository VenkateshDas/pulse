import Foundation
import Testing

@testable import PulseKit

@Suite("BatteryDecode")
struct BatteryDecodeTests {
    /// Keys as AppleSmartBattery reports them on Apple Silicon
    /// (CurrentCapacity is a percentage, MaxCapacity pinned to 100).
    static func appleSiliconProps(
        charging: Bool = false, onAC: Bool = false, current: Int = 60,
        rawMax: Int = 3766, design: Int = 4563, timeRemaining: Int = 565,
        avgToFull: Int = 65535, failure: Int = 0
    ) -> [String: Any] {
        [
            "DesignCapacity": design,
            "AppleRawMaxCapacity": rawMax,
            "CurrentCapacity": current,
            "MaxCapacity": 100,
            "CycleCount": 381,
            "IsCharging": charging,
            "ExternalConnected": onAC,
            "TimeRemaining": timeRemaining,
            "AvgTimeToFull": avgToFull,
            "AvgTimeToEmpty": timeRemaining,
            "PermanentFailureStatus": failure,
        ]
    }

    @Test func decodesDischargingAppleSilicon() {
        let battery = BatteryDecode.battery(from: Self.appleSiliconProps())
        #expect(battery != nil)
        #expect(battery!.currentChargePercent == 60)
        #expect(battery!.capacityPercent == 83)  // 3766/4563 rounded
        #expect(battery!.cycleCount == 381)
        #expect(!battery!.isCharging)
        #expect(!battery!.isOnAC)
        #expect(battery!.timeToEvent == TimeInterval(565 * 60))
        #expect(battery!.condition == "Normal")
    }

    @Test func chargingUsesAvgTimeToFull() {
        let battery = BatteryDecode.battery(
            from: Self.appleSiliconProps(charging: true, onAC: true, avgToFull: 72))
        #expect(battery!.isCharging)
        #expect(battery!.timeToEvent == TimeInterval(72 * 60))
    }

    @Test func gaugeUnknownSentinelBecomesNil() {
        let charging = BatteryDecode.battery(
            from: Self.appleSiliconProps(charging: true, onAC: true, avgToFull: 65535))
        #expect(charging!.timeToEvent == nil)

        // Idle on AC, not charging: no event to count down to.
        let idle = BatteryDecode.battery(from: Self.appleSiliconProps(onAC: true))
        #expect(idle!.timeToEvent == nil)
    }

    @Test func intelStyleRawCurrentCapacityScalesToPercent() {
        var props = Self.appleSiliconProps()
        props["CurrentCapacity"] = 2500
        props["MaxCapacity"] = 5000
        let battery = BatteryDecode.battery(from: props)
        #expect(battery!.currentChargePercent == 50)
    }

    @Test func degradedOrFailedBatteryReportsService() {
        let degraded = BatteryDecode.battery(from: Self.appleSiliconProps(rawMax: 3000))
        #expect(degraded!.capacityPercent == 66)
        #expect(degraded!.condition == "Service Recommended")

        let failed = BatteryDecode.battery(from: Self.appleSiliconProps(failure: 1))
        #expect(failed!.condition == "Service Recommended")
    }

    @Test func desktopMacMissingKeysDecodesNil() {
        #expect(BatteryDecode.battery(from: [:]) == nil)
        #expect(BatteryDecode.battery(from: ["DesignCapacity": 0]) == nil)
    }
}

@Suite("StartupItems")
struct StartupItemTests {
    /// Temp LaunchAgents dir with one enabled and one disabled agent.
    func makeAgentsDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-health-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let enabled: [String: Any] = [
            "Label": "com.example.helper",
            "ProgramArguments": ["/usr/local/bin/helper", "--daemon"],
        ]
        let disabled: [String: Any] = ["Label": "com.example.off", "Program": "/bin/echo"]
        try PropertyListSerialization.data(
            fromPropertyList: enabled, format: .xml, options: 0
        ).write(to: dir.appendingPathComponent("com.example.helper.plist"))
        try PropertyListSerialization.data(
            fromPropertyList: disabled, format: .xml, options: 0
        ).write(to: dir.appendingPathComponent("com.example.off.plist.disabled"))
        return dir
    }

    @Test func listsAndParsesAgents() async throws {
        let dir = try makeAgentsDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sampler = HealthSampler(
            userAgentsURL: dir,
            globalAgentsURL: URL(fileURLWithPath: "/nonexistent"))

        let items = await sampler.listStartupItems()
        #expect(items.count == 2)

        let helper = items.first { $0.label == "com.example.helper" }
        #expect(helper != nil)
        #expect(helper!.isEnabled)
        #expect(helper!.program == "/usr/local/bin/helper")
        #expect(helper!.kind == .userAgent)

        let off = items.first { $0.label == "com.example.off" }
        #expect(off != nil)
        #expect(!off!.isEnabled)
        // Identity is the canonical path — stable across toggles.
        #expect(off!.id.hasSuffix("com.example.off.plist"))
    }

    @Test func toggleRenameRoundTrips() async throws {
        let dir = try makeAgentsDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sampler = HealthSampler(
            userAgentsURL: dir,
            globalAgentsURL: URL(fileURLWithPath: "/nonexistent"))

        let helper = await sampler.listStartupItems().first { $0.label == "com.example.helper" }!
        try await sampler.toggleStartupItem(helper)

        let afterDisable = await sampler.listStartupItems()
            .first { $0.label == "com.example.helper" }!
        #expect(!afterDisable.isEnabled)
        #expect(afterDisable.path.hasSuffix(".plist.disabled"))
        #expect(afterDisable.id == helper.id)

        try await sampler.toggleStartupItem(afterDisable)
        let restored = await sampler.listStartupItems()
            .first { $0.label == "com.example.helper" }!
        #expect(restored.isEnabled)
        #expect(restored.path == helper.path)
    }

    @Test func globalAgentsRefuseToggle() async throws {
        let dir = try makeAgentsDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sampler = HealthSampler(
            userAgentsURL: URL(fileURLWithPath: "/nonexistent"), globalAgentsURL: dir)

        let items = await sampler.listStartupItems()
        #expect(items.allSatisfy { $0.kind == .globalAgent })
        await #expect(throws: StartupItemError.notToggleable("com.example.helper")) {
            try await sampler.toggleStartupItem(
                items.first { $0.label == "com.example.helper" }!)
        }
    }

    @Test func plistDisabledKeyReadsAsDisabled() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-health-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("com.example.keyoff.plist")
        try PropertyListSerialization.data(
            fromPropertyList: ["Label": "com.example.keyoff", "Disabled": true],
            format: .xml, options: 0
        ).write(to: url)

        let item = HealthSampler.startupItem(at: url, kind: .userAgent)
        #expect(item != nil)
        #expect(!item!.isEnabled)
    }
}

@Suite("BatteryHistoryStore")
struct BatteryHistoryStoreTests {
    @Test func aggregatesTimePerDayAndTrimsTo60Days() {
        let store = BatteryHistoryStore(fileURL: nil)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        store.addTimeOnBattery(3600, at: start) // 1 hour
        // Same day — should aggregate.
        store.addTimeOnBattery(1800, at: start.addingTimeInterval(10)) // +30 mins
        #expect(store.entries.count == 1)
        #expect(store.entries[0].timeOnBattery == 5400)

        // 70 daily readings: only the trailing 60 days survive.
        for day in 1...70 {
            store.addTimeOnBattery(
                3600,
                at: start.addingTimeInterval(Double(day) * 24 * 3600))
        }
        #expect(store.entries.allSatisfy {
            start.addingTimeInterval(70 * 24 * 3600).timeIntervalSince($0.date)
                <= BatteryHistoryStore.maxAge
        })
        #expect(store.entries.count == 60)
    }

    @Test func persistsAndPrunesOldEntriesOnLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-battery-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = BatteryHistoryStore(fileURL: url)
        let old = Date.now.addingTimeInterval(-70 * 24 * 3600)
        store.addTimeOnBattery(3600, at: old)
        // End at 03:00 today so the 2h duration can't span midnight (a
        // duration ending 00:00–02:00 splits across two day entries).
        let recent = Calendar.current.startOfDay(for: .now).addingTimeInterval(3 * 3600)
        store.addTimeOnBattery(7200, at: recent)

        let reloaded = BatteryHistoryStore(fileURL: url)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries[0].timeOnBattery == 7200)
    }

    @Test func splitsDurationSpanningMidnightAcrossBothDays() {
        let store = BatteryHistoryStore(fileURL: nil)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let day0 = Calendar.current.startOfDay(for: base)
        let day1 = Calendar.current.date(byAdding: .day, value: 1, to: day0)!
        // A 2-hour tick ending at day1 01:00 started at day0 23:00 — one
        // hour belongs to each day.
        let sessionEnd = day1.addingTimeInterval(3600)
        store.addTimeOnBattery(2 * 3600, at: sessionEnd)

        #expect(store.entries.count == 2)
        let e0 = store.entries.first { $0.date == day0 }
        let e1 = store.entries.first { $0.date == day1 }
        #expect(e0?.timeOnBattery == 3600)
        #expect(e1?.timeOnBattery == 3600)
    }
}

@Suite("Benchmark")
struct BenchmarkTests {
    @Test func tinyRunProducesPositiveThroughputs() async {
        let result = await Benchmark().run(config: .tiny)
        #expect(result.cpuHashMBps > 0)
        #expect(result.diskWriteMBps > 0)
        #expect(result.memCopyGBps > 0)
        #expect(result.score > 0)
    }

    @Test func storeKeepsLatestAndPrevious() {
        let store = BenchmarkStore(fileURL: nil)
        #expect(store.latest == nil)
        #expect(store.previous == nil)

        let first = BenchmarkResult(
            date: .now, cpuHashMBps: 1000, diskWriteMBps: 2000, memCopyGBps: 40)
        let second = BenchmarkResult(
            date: .now, cpuHashMBps: 1100, diskWriteMBps: 2100, memCopyGBps: 41)
        store.record(first)
        store.record(second)
        #expect(store.latest == second)
        #expect(store.previous == first)
    }

    @Test func scoreFormulaIsTransparent() {
        // Exactly the reference machine → score 1000.
        let reference = BenchmarkResult(
            date: .now,
            cpuHashMBps: BenchmarkResult.references.cpuMBps,
            diskWriteMBps: BenchmarkResult.references.diskMBps,
            memCopyGBps: BenchmarkResult.references.memGBps)
        #expect(reference.score == 1000)
    }
}
