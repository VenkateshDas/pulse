import Foundation
import Testing

@testable import PulseKit

// MARK: - Fixtures

private func makeSnapshot(
    cpuTotalPercent: Double = 10,
    cpuPerCore: [Double] = Array(repeating: 10, count: 8),
    memoryUsedBytes: UInt64 = 4_000_000_000,
    memoryTotalBytes: UInt64 = 8_000_000_000,
    memoryAppBytes: UInt64 = 0,
    memoryWiredBytes: UInt64 = 0,
    memoryCompressedBytes: UInt64 = 0,
    swapUsedBytes: UInt64 = 0,
    memoryPressure: MemoryPressure = .normal,
    diskFreeBytes: UInt64 = 100_000_000_000,
    diskTotalBytes: UInt64 = 0,
    diskWeeklyGrowthBytes: Int64? = nil,
    networkBytesInPerSecond: UInt64 = 0,
    networkBytesOutPerSecond: UInt64 = 0,
    thermal: ThermalLevel = .nominal,
    sensors: SensorReadings = SensorReadings(),
    sleepAssertions: [SleepAssertion] = [],
    topProcesses: [ProcessSample] = []
) -> SystemSnapshot {
    SystemSnapshot(
        timestamp: .now,
        cpuTotalPercent: cpuTotalPercent,
        cpuPerCore: cpuPerCore,
        cpuEfficiencyPercent: nil,
        cpuPerformancePercent: nil,
        loadAverage1m: 1,
        memoryUsedBytes: memoryUsedBytes,
        memoryTotalBytes: memoryTotalBytes,
        memoryAppBytes: memoryAppBytes,
        memoryWiredBytes: memoryWiredBytes,
        memoryCompressedBytes: memoryCompressedBytes,
        swapUsedBytes: swapUsedBytes,
        memoryPressure: memoryPressure,
        diskFreeBytes: diskFreeBytes,
        diskTotalBytes: diskTotalBytes,
        diskWeeklyGrowthBytes: diskWeeklyGrowthBytes,
        networkBytesInPerSecond: networkBytesInPerSecond,
        networkBytesOutPerSecond: networkBytesOutPerSecond,
        thermal: thermal,
        sleepAssertions: sleepAssertions,
        topProcesses: topProcesses,
        uptime: 3600
    )
}

// MARK: - Suites

@Suite("ByteFormat")
struct ByteFormatTests {
    @Test func bytesStayInBytes() {
        #expect(ByteFormat.string(0) == "0 B")
        #expect(ByteFormat.string(999) == "999 B")
    }

    @Test func scalesDecimalUnits() {
        #expect(ByteFormat.string(1_000) == "1.0 KB")
        #expect(ByteFormat.string(12_400_000_000) == "12.4 GB")
        #expect(ByteFormat.string(512_000_000) == "512 MB")
        #expect(ByteFormat.string(2_000_000_000_000) == "2.0 TB")
    }
}

@Suite("SystemSnapshot")
struct SnapshotTests {
    @Test func fractionsAreSafeOnZeroTotals() {
        let snapshot = makeSnapshot(memoryTotalBytes: 0, diskFreeBytes: 0, diskTotalBytes: 0)
        #expect(snapshot.memoryUsedFraction == 0)
        #expect(snapshot.diskUsedFraction == 0)
    }
}

@Suite("AlertsEngine")
struct AlertsEngineTests {
    @Test func quietSystemProducesNoAlerts() {
        #expect(AlertsEngine.evaluate(makeSnapshot()).isEmpty)
    }

    @Test func cpuHogIsFlaggedWithQuitAction() {
        let snapshot = makeSnapshot(
            topProcesses: [
                ProcessSample(pid: 42, name: "Chrome Helper", cpuPercent: 95, residentBytes: 1_000_000)
            ]
        )
        let alerts = AlertsEngine.evaluate(snapshot)
        let hog = try! #require(alerts.first { $0.id == "cpu-hog" })
        #expect(hog.actions == [.quitProcess(pid: 42, name: "Chrome Helper")])
        #expect(hog.title.contains("Chrome Helper"))
    }

    @Test func ownProcessIsNeverFlagged() {
        let snapshot = makeSnapshot(
            topProcesses: [
                ProcessSample(pid: 42, name: "Pulse", cpuPercent: 95, residentBytes: 0)
            ]
        )
        #expect(AlertsEngine.evaluate(snapshot, ownPID: 42).isEmpty)
    }

    @Test func lowDiskIsCritical() {
        let alerts = AlertsEngine.evaluate(makeSnapshot(diskFreeBytes: 10_000_000_000))
        let alert = try! #require(alerts.first { $0.id == "low-disk" })
        #expect(alert.severity == .critical)
    }

    @Test func memoryPressureAndHeavySwapFlagged() {
        let pressured = makeSnapshot(memoryPressure: .warning)
        #expect(AlertsEngine.evaluate(pressured).contains { $0.id == "memory-pressure" })

        let swapping = makeSnapshot(swapUsedBytes: 6_000_000_000)
        #expect(AlertsEngine.evaluate(swapping).contains { $0.id == "memory-pressure" })
    }

    @Test func sleepBlockersFlaggedButSystemDaemonsIgnored() {
        let blocked = makeSnapshot(
            sleepAssertions: [
                SleepAssertion(pid: 7, processName: "Teams", assertionName: "CallActive"),
                SleepAssertion(pid: 8, processName: "powerd", assertionName: "internal"),
            ]
        )
        let alerts = AlertsEngine.evaluate(blocked)
        let alert = try! #require(alerts.first { $0.id == "sleep-blockers" })
        #expect(alert.title.contains("Teams"))
        #expect(!alert.title.contains("powerd"))

        let onlySystem = makeSnapshot(
            sleepAssertions: [
                SleepAssertion(pid: 8, processName: "powerd", assertionName: "internal")
            ]
        )
        #expect(AlertsEngine.evaluate(onlySystem).isEmpty)
    }

    @Test func seriousThermalStateFlagged() {
        let alerts = AlertsEngine.evaluate(makeSnapshot(thermal: .serious))
        #expect(alerts.contains { $0.id == "thermal" })
    }
}

@Suite("DiskHistoryStore")
struct DiskHistoryTests {
    @Test func growthNeedsADayOfHistory() {
        let store = DiskHistoryStore(fileURL: nil)
        store.record(usedBytes: 100, at: .now)
        #expect(store.weeklyGrowth(currentUsedBytes: 200, at: .now) == nil)
    }

    @Test func growthScalesPartialWindowToWeeklyRate() {
        let store = DiskHistoryStore(fileURL: nil)
        let start = Date(timeIntervalSince1970: 1_000_000)
        store.record(usedBytes: 1_000_000_000, at: start)
        // 3.5 days later, used grew by 2 GB -> weekly rate 4 GB.
        let now = start.addingTimeInterval(3.5 * 24 * 3600)
        let growth = try! #require(store.weeklyGrowth(currentUsedBytes: 3_000_000_000, at: now))
        #expect(growth == 4_000_000_000)
    }

    @Test func shrinkingDiskReportsNegativeGrowth() {
        let store = DiskHistoryStore(fileURL: nil)
        let start = Date(timeIntervalSince1970: 1_000_000)
        store.record(usedBytes: 5_000_000_000, at: start)
        let now = start.addingTimeInterval(7 * 24 * 3600)
        let growth = try! #require(store.weeklyGrowth(currentUsedBytes: 4_000_000_000, at: now))
        #expect(growth == -1_000_000_000)
    }

    @Test func recordingIsThrottledToInterval() {
        let store = DiskHistoryStore(fileURL: nil)
        let start = Date(timeIntervalSince1970: 1_000_000)
        store.record(usedBytes: 1, at: start)
        store.record(usedBytes: 2, at: start.addingTimeInterval(60))
        #expect(store.entries.count == 1)
        store.record(usedBytes: 3, at: start.addingTimeInterval(7 * 3600))
        #expect(store.entries.count == 2)
    }
}

@Suite("MinuteHistoryStore")
struct MinuteHistoryTests {
    // Aligned to a minute boundary so adding seconds never crosses one
    // unexpectedly.
    private let start = Date(timeIntervalSince1970: 1_000_020)

    @Test func samplesWithinAMinuteAreAveraged() {
        let store = MinuteHistoryStore(fileURL: nil)
        store.record(10, at: start)
        store.record(20, at: start.addingTimeInterval(2))
        store.record(30, at: start.addingTimeInterval(4))
        #expect(store.currentAverage == 20)
        #expect(store.entries.isEmpty)  // minute not finalized yet
    }

    @Test func minuteRolloverFinalizesTheAverage() {
        let store = MinuteHistoryStore(fileURL: nil)
        store.record(10, at: start)
        store.record(30, at: start.addingTimeInterval(2))
        store.record(50, at: start.addingTimeInterval(60))
        #expect(store.entries.count == 1)
        #expect(store.entries[0].value == 20)
        #expect(store.currentAverage == 50)
    }

    @Test func seriesAlignsByMinuteAndKeepsGaps() {
        let store = MinuteHistoryStore(fileURL: nil)
        store.record(10, at: start)
        // Skip two minutes (gap), then sample again.
        store.record(40, at: start.addingTimeInterval(3 * 60))
        let series = store.series(at: start.addingTimeInterval(3 * 60))
        #expect(series.count == MinuteHistoryStore.capacity)
        #expect(series[series.count - 1] == 40)  // live in-progress minute
        #expect(series[series.count - 2] == nil)  // gap
        #expect(series[series.count - 3] == nil)  // gap
        #expect(series[series.count - 4] == 10)  // finalized minute
    }

    @Test func entriesOlderThanADayAreTrimmed() {
        let store = MinuteHistoryStore(fileURL: nil)
        store.record(1, at: start)
        store.record(2, at: start.addingTimeInterval(60))  // finalizes minute 0
        // Exactly capacity minutes later: minute 0 falls out of the 24h
        // window, minute 1 is its last slot.
        let dayLater = start.addingTimeInterval(Double(MinuteHistoryStore.capacity) * 60)
        store.record(3, at: dayLater)  // finalize + trim
        #expect(store.entries.count == 1)
        #expect(store.entries[0].value == 2)
    }

    @Test func persistsAndReloadsWithin24hWindow() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = MinuteHistoryStore(fileURL: url)
        // Finalize persistEvery minutes so a write happens.
        for minute in 0...MinuteHistoryStore.persistEvery {
            store.record(Double(minute), at: start.addingTimeInterval(Double(minute) * 60))
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reloaded = MinuteHistoryStore(
            fileURL: url, now: start.addingTimeInterval(600))
        #expect(reloaded.entries.count == MinuteHistoryStore.persistEvery)
        #expect(reloaded.entries[0].value == 0)

        // Reloading a day later drops everything as stale.
        let stale = MinuteHistoryStore(
            fileURL: url,
            now: start.addingTimeInterval(Double(MinuteHistoryStore.capacity + 10) * 60))
        #expect(stale.entries.isEmpty)
    }
}

@Suite("SMCDecode")
struct SMCDecodeTests {
    @Test func decodesLittleEndianFloat() {
        // 47.5 as IEEE 754 float32 little-endian: 0x423E0000
        #expect(SMCDecode.flt([0x00, 0x00, 0x3E, 0x42]) == 47.5)
        #expect(SMCDecode.flt([0x00, 0x00]) == nil)
    }

    @Test func decodesSP78FixedPoint() {
        // 0x2F80 big-endian = 47.5
        #expect(SMCDecode.sp78([0x2F, 0x80]) == 47.5)
        // negative: 0xFF00 = -1.0
        #expect(SMCDecode.sp78([0xFF, 0x00]) == -1.0)
        #expect(SMCDecode.sp78([0x2F]) == nil)
    }

    @Test func fourCCRoundTrips() {
        let key = SMCDecode.fourCC("#KEY")
        #expect(key == 0x234B_4559)
        #expect(SMCDecode.string(fromFourCC: key) == "#KEY")
    }

    @Test func plausibilityWindowRejectsGarbage() {
        #expect(SMCDecode.plausibleTemp(47))
        #expect(!SMCDecode.plausibleTemp(0))
        #expect(!SMCDecode.plausibleTemp(-127))
        #expect(!SMCDecode.plausibleTemp(255))
    }
}

@Suite("SMCSensors (hardware)")
struct SMCSensorsLiveTests {
    /// Runs against the real SMC; skipped (trivially passes) where absent.
    @Test func liveReadingsArePlausible() {
        guard let smc = SMCSensors() else { return }
        let readings = smc.sample()
        if let cpu = readings.cpuTempC { #expect(cpu > 5 && cpu < 125) }
        if let gpu = readings.gpuTempC { #expect(gpu > 5 && gpu < 125) }
        if let battery = readings.batteryTempC { #expect(battery > 5 && battery < 60) }
        // An Apple Silicon Mac must expose at least a CPU temperature.
        if SystemInfo.efficiencyCoreCount > 0 {
            #expect(readings.cpuTempC != nil)
        }
    }
}

@Suite("PulseEngine")
struct EngineTests {
    @Test func producesSaneSnapshot() async throws {
        let engine = PulseEngine()
        _ = await engine.sample()  // warm-up: deltas need two samples
        try await Task.sleep(for: .milliseconds(300))
        let snapshot = await engine.sample(topProcessLimit: 5)

        #expect(snapshot.cpuTotalPercent >= 0)
        #expect(snapshot.cpuTotalPercent <= 100)
        #expect(!snapshot.cpuPerCore.isEmpty)
        #expect(snapshot.memoryTotalBytes > 4_000_000_000)  // any modern Mac has >4 GB
        #expect(snapshot.memoryUsedBytes > 0)
        #expect(snapshot.memoryUsedBytes < snapshot.memoryTotalBytes)
        #expect(snapshot.diskTotalBytes > 0)
        #expect(snapshot.diskFreeBytes <= snapshot.diskTotalBytes)
        #expect(snapshot.topProcesses.count == 5)
        #expect(snapshot.uptime > 0)

        if SystemInfo.efficiencyCoreCount > 0 {
            let e = try #require(snapshot.cpuEfficiencyPercent)
            let p = try #require(snapshot.cpuPerformancePercent)
            #expect(e >= 0 && e <= 100)
            #expect(p >= 0 && p <= 100)
        }
    }

    @Test func topProcessesSortedByCPU() async throws {
        let engine = PulseEngine()
        _ = await engine.sample()
        try await Task.sleep(for: .milliseconds(300))
        let top = await engine.sample(topProcessLimit: 10).topProcesses
        let cpus = top.map(\.cpuPercent)
        #expect(cpus == cpus.sorted(by: >))
        #expect(top.allSatisfy { !$0.name.isEmpty })
    }
}

// MARK: - DiagnosisEngine (F1)

@Suite("DiagnosisEngine")
struct DiagnosisEngineTests {
    @Test func quietSystemIsAllClear() {
        let d = DiagnosisEngine.evaluate(makeSnapshot())
        #expect(d.line == "All clear")
        #expect(d.severity == .clear)
        #expect(d.culpritPID == nil)
    }

    @Test func highCPUNamesLeadingProcess() {
        let snap = makeSnapshot(
            cpuTotalPercent: 92,
            topProcesses: [ProcessSample(pid: 501, name: "Chrome", cpuPercent: 88, residentBytes: 0)])
        let d = DiagnosisEngine.evaluate(snap)
        #expect(d.line == "Chrome high CPU")
        #expect(d.severity == .critical)
        #expect(d.culpritPID == 501)
        #expect(d.factor == .cpu)
    }

    @Test func highCPUWithoutLeaderIsGeneric() {
        // Total high but spread across processes (none above 50% alone).
        let snap = makeSnapshot(
            cpuTotalPercent: 90,
            topProcesses: [ProcessSample(pid: 1, name: "a", cpuPercent: 30, residentBytes: 0)])
        #expect(DiagnosisEngine.evaluate(snap).line == "CPU load high")
    }

    @Test func memoryPressureBeatsDisk() {
        let snap = makeSnapshot(
            memoryPressure: .critical,
            diskFreeBytes: 1_000_000_000, diskTotalBytes: 100_000_000_000,
            topProcesses: [ProcessSample(pid: 7, name: "Xcode", cpuPercent: 5, residentBytes: 9_000_000_000)])
        let d = DiagnosisEngine.evaluate(snap)
        #expect(d.line == "Xcode memory pressure")
        #expect(d.culpritPID == 7)
    }

    @Test func lowDiskReportsFreeSpace() {
        let snap = makeSnapshot(diskFreeBytes: 5_000_000_000, diskTotalBytes: 100_000_000_000)
        let d = DiagnosisEngine.evaluate(snap)
        #expect(d.line.hasPrefix("Disk low"))
        #expect(d.factor == .disk)
    }

    @Test func longNamesAreShortened() {
        let snap = makeSnapshot(
            cpuTotalPercent: 92,
            topProcesses: [ProcessSample(pid: 1, name: "ReallyLongProcessNameHere", cpuPercent: 99, residentBytes: 0)])
        #expect(DiagnosisEngine.evaluate(snap).line.count <= "ReallyLongProcessNa high CPU".count)
    }
}

// MARK: - HealthScore (F1)

@Suite("HealthScore")
struct HealthScoreTests {
    @Test func idleSystemScoresHigh() {
        let s = HealthScore.evaluate(makeSnapshot(sensors: SensorReadings(cpuTempC: 45)))
        #expect(s.value >= 95)
        #expect(s.band == .excellent)
    }

    @Test func pinnedSystemScoresLow() {
        let s = HealthScore.evaluate(makeSnapshot(
            cpuTotalPercent: 100,
            memoryUsedBytes: 7_900_000_000, memoryTotalBytes: 8_000_000_000,
            memoryPressure: .critical,
            diskFreeBytes: 1_000_000_000, diskTotalBytes: 100_000_000_000,
            sensors: SensorReadings(cpuTempC: 100)))
        #expect(s.value < 30)
        #expect(s.band == .poor)
    }

    @Test func belowNormalLosesNoPoints() {
        #expect(HealthScore.pointsLost(.cpu, value: 40) == 0)
        #expect(HealthScore.pointsLost(.cpu, value: 50) == 0)
    }

    @Test func atHighLosesHalfWeight() {
        // CPU normal 50, high 85, weight 30 → at high, half weight (15) lost.
        #expect(abs(HealthScore.pointsLost(.cpu, value: 85) - 15) < 0.01)
    }

    @Test func wellAboveHighLosesFullWeight() {
        #expect(abs(HealthScore.pointsLost(.cpu, value: 120) - 30) < 0.01)
    }

    @Test func bandThresholds() {
        #expect(HealthScore.Band(value: 90) == .excellent)
        #expect(HealthScore.Band(value: 70) == .good)
        #expect(HealthScore.Band(value: 50) == .fair)
        #expect(HealthScore.Band(value: 20) == .poor)
    }
}

// MARK: - OptimizeEngine (F2)

@Suite("OptimizeEngine")
struct OptimizeEngineTests {
    @Test func refusalManifestHasFiveEntries() {
        #expect(OptimizeEngine.refusals.count == 5)
        #expect(OptimizeEngine.refusals.allSatisfy { !$0.op.isEmpty && !$0.reason.isEmpty })
    }

    @Test func inProcessTasksNeverNeedSudo() {
        #expect(OptimizeEngine.inProcessTasks.allSatisfy { !$0.needsSudo })
        #expect(!OptimizeEngine.inProcessTasks.isEmpty)
    }

    @Test func privilegedTasksAllNeedSudo() {
        #expect(OptimizeEngine.privilegedTasks.allSatisfy { $0.needsSudo })
    }

    @Test func taskIDsAreUnique() {
        let ids = OptimizeEngine.tasks.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func sudoTasksRefuseToRunInProcess() async throws {
        let task = try #require(OptimizeEngine.tasks.first { $0.needsSudo })
        let result = try await task.run()
        #expect(!result.success)
    }

    @Test func dirBytesSumsFileSizes() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(repeating: 0, count: 10_000).write(to: tmp.appendingPathComponent("a.bin"))
        let bytes = await OptimizeEngine.dirBytes(tmp)
        #expect(bytes >= 10_000)
    }
}
