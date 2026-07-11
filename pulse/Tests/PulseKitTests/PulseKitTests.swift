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

    @Test func leakVerdictAppearsWhenQuiet() {
        let leak = LeakAlert(pid: 77, name: "WhatsApp", startBytes: 1 << 30,
                             currentBytes: 5 << 30, windowSeconds: 1800, isNewlySustained: true)
        let d = DiagnosisEngine.evaluate(makeSnapshot(), leak: leak)
        #expect(d.line == "WhatsApp leaking memory")
        #expect(d.severity == .warn)
        #expect(d.culpritPID == 77)
        #expect(d.factor == .memory)
    }

    @Test func highCPUOutranksLeak() {
        let leak = LeakAlert(pid: 77, name: "WhatsApp", startBytes: 0,
                             currentBytes: 2 << 30, windowSeconds: 1800, isNewlySustained: true)
        let snap = makeSnapshot(
            cpuTotalPercent: 92,
            topProcesses: [ProcessSample(pid: 501, name: "Chrome", cpuPercent: 88, residentBytes: 0)])
        #expect(DiagnosisEngine.evaluate(snap, leak: leak).line == "Chrome high CPU")
    }

    @Test func groupedBlameNamesAppWithCount() {
        // No single helper crosses the 50% floor, but the app group's sum does.
        let snap = makeSnapshot(
            cpuTotalPercent: 92,
            topProcesses: [
                ProcessSample(pid: 1, name: "Chrome Helper", cpuPercent: 20, residentBytes: 0, appName: "Chrome"),
                ProcessSample(pid: 2, name: "Chrome Helper (GPU)", cpuPercent: 35, residentBytes: 0, appName: "Chrome"),
                ProcessSample(pid: 3, name: "Chrome", cpuPercent: 25, residentBytes: 0, appName: "Chrome"),
            ])
        let d = DiagnosisEngine.evaluate(snap)
        #expect(d.line == "Chrome (3) high CPU")
        #expect(d.culpritPID == 2)   // hottest member for tap-through
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

// MARK: - Privileged operations (F2)

@Suite("PrivilegedOperation")
struct PrivilegedOperationTests {
    @Test func everyOperationMapsToAbsolutePathCommands() {
        for op in PrivilegedOperation.allCases {
            #expect(!op.commands.isEmpty)
            for cmd in op.commands {
                #expect(cmd.path.hasPrefix("/"))   // no PATH lookup, no injection
                #expect(!op.label.isEmpty)
            }
        }
    }

    @Test func rawValuesRoundTrip() {
        for op in PrivilegedOperation.allCases {
            #expect(PrivilegedOperation(rawValue: op.rawValue) == op)
        }
        #expect(PrivilegedOperation(rawValue: "rm -rf /") == nil)
    }

    @Test func shellScriptIsBuiltFromFixedTokensOnly() {
        // Each token single-quoted; no caller input can enter the string.
        #expect(PrivilegedOperation.purgeMemory.shellScript == "'/usr/sbin/purge'")
        #expect(PrivilegedOperation.flushNetworkStack.shellScript
            == "'/sbin/route' '-n' 'flush' ; '/usr/sbin/arp' '-a' '-d'")
        // No double quotes → safe to embed in the AppleScript string literal.
        for op in PrivilegedOperation.allCases {
            #expect(!op.shellScript.contains("\""))
        }
    }

    @Test func privilegedTasksCoverThreeOperations() {
        #expect(OptimizeEngine.privilegedTasks.count == PrivilegedOperation.allCases.count)
    }
}

// MARK: - InsightScanner (F4)

@Suite("InsightScanner")
struct InsightScannerTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func oldDownloadsCountsOnlyStaleFiles() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()

        let old = dir.appendingPathComponent("old.zip")
        try Data(repeating: 1, count: 20_000).write(to: old)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-100 * 86400)], ofItemAtPath: old.path)

        let fresh = dir.appendingPathComponent("fresh.zip")
        try Data(repeating: 1, count: 50_000).write(to: fresh)
        try FileManager.default.setAttributes(
            [.modificationDate: now], ofItemAtPath: fresh.path)

        let bytes = InsightScanner.oldDownloadsBytes(in: dir, days: 90, now: now)
        #expect(bytes >= 20_000)
        #expect(bytes < 50_000)   // the fresh file is excluded
    }

    @Test func resolveMatchesWildcardSegment() throws {
        let home = try tempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let container = home.appendingPathComponent("Library/Group Containers/HUAQ.dev.orbstack")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let scanner = InsightScanner(home: home)
        let url = scanner.resolve("Library/Group Containers/*dev.orbstack/data")
        #expect(url?.path.contains("HUAQ.dev.orbstack/data") == true)
        // No match → nil.
        #expect(scanner.resolve("Library/Group Containers/*nonesuch/data") == nil)
    }

    @Test func scanReturnsNothingForEmptyHome() async throws {
        let home = try tempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let found = await InsightScanner(home: home).scan()
        #expect(found.isEmpty)
    }
}

// MARK: - ProcessWatcher (F5)

@Suite("ProcessWatcher")
struct ProcessWatcherTests {
    private func proc(_ pid: Int32, _ name: String, _ cpu: Double) -> ProcessSample {
        ProcessSample(pid: pid, name: name, cpuPercent: cpu, residentBytes: 0)
    }

    @Test func spikeBelowWindowDoesNotAlert() {
        var w = ProcessWatcher(cpuThreshold: 50, window: 60)
        let t0 = Date()
        #expect(w.ingest([proc(1, "A", 90)], now: t0).isEmpty)
        // 30s later — still under the 60s window.
        #expect(w.ingest([proc(1, "A", 90)], now: t0.addingTimeInterval(30)).isEmpty)
    }

    @Test func sustainedAboveWindowAlertsOnce() {
        var w = ProcessWatcher(cpuThreshold: 50, window: 60)
        let t0 = Date()
        _ = w.ingest([proc(1, "A", 90)], now: t0)
        let fired = w.ingest([proc(1, "A", 95)], now: t0.addingTimeInterval(61))
        #expect(fired.count == 1)
        #expect(fired.first?.isNewlySustained == true)
        // Next tick still sustained, but no longer "newly".
        let again = w.ingest([proc(1, "A", 95)], now: t0.addingTimeInterval(63))
        #expect(again.first?.isNewlySustained == false)
    }

    @Test func droppingBelowThresholdResetsClock() {
        var w = ProcessWatcher(cpuThreshold: 50, window: 60)
        let t0 = Date()
        _ = w.ingest([proc(1, "A", 90)], now: t0)
        // Cools off → track cleared.
        _ = w.ingest([proc(1, "A", 10)], now: t0.addingTimeInterval(30))
        // Hot again, but clock restarts: 40s later is not yet sustained.
        let fired = w.ingest([proc(1, "A", 90)], now: t0.addingTimeInterval(70))
        #expect(fired.isEmpty)
    }

    @Test func belowThresholdNeverTracked() {
        var w = ProcessWatcher(cpuThreshold: 50, window: 60)
        let t0 = Date()
        #expect(w.ingest([proc(1, "A", 40)], now: t0).isEmpty)
        #expect(w.ingest([proc(1, "A", 49)], now: t0.addingTimeInterval(120)).isEmpty)
    }
}

@Suite("AnomalyStore")
struct AnomalyStoreTests {
    @Test func recordsNewestFirstAndCapsCount() {
        let store = AnomalyStore(fileURL: nil)
        let base = Date()
        for i in 0..<5 {
            store.record(AnomalyRecord(
                processName: "P\(i)", pid: Int32(i), cpuPercent: 90,
                date: base.addingTimeInterval(Double(i)), sustainedSeconds: 60))
        }
        #expect(store.records.first?.processName == "P4")   // newest first
        #expect(store.records.count == 5)
    }

    @Test func dropsEntriesOlderThanMaxAge() {
        let store = AnomalyStore(fileURL: nil)
        let now = Date()
        store.record(AnomalyRecord(processName: "old", pid: 1, cpuPercent: 90,
            date: now.addingTimeInterval(-Double(40 * 24 * 3600)), sustainedSeconds: 60))
        store.record(AnomalyRecord(processName: "new", pid: 2, cpuPercent: 90,
            date: now, sustainedSeconds: 60))
        #expect(store.records.contains { $0.processName == "new" })
        #expect(!store.records.contains { $0.processName == "old" })
    }

    @Test func legacyRecordsWithoutKindDecode() throws {
        // A pre-kind anomalies.json must load untouched (kind/growthBytes nil).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-anomalies-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = """
        [{"id":"\(UUID().uuidString)","processName":"OldProc","pid":42,
          "cpuPercent":91,"date":\(Date().timeIntervalSinceReferenceDate),
          "sustainedSeconds":120}]
        """
        try legacy.data(using: .utf8)!.write(to: url)
        let store = AnomalyStore(fileURL: url)
        #expect(store.records.count == 1)
        #expect(store.records.first?.kind == nil)
        #expect(store.records.first?.growthBytes == nil)
    }

    @Test func leakRecordRoundTrips() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("leak-anomalies-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AnomalyStore(fileURL: url)
        store.record(AnomalyRecord(processName: "Leaky", pid: 9, cpuPercent: 0,
            sustainedSeconds: 1800, kind: .memoryLeak, growthBytes: 2 << 30))
        let reloaded = AnomalyStore(fileURL: url)
        #expect(reloaded.records.first?.kind == .memoryLeak)
        #expect(reloaded.records.first?.growthBytes == 2 << 30)
    }
}

// MARK: - LeakWatcher

@Suite("LeakWatcher")
struct LeakWatcherTests {
    private let gib = UInt64(1) << 30
    private let mib = UInt64(1) << 20

    private func proc(_ pid: Int32, _ name: String, rss: UInt64) -> ProcessSample {
        ProcessSample(pid: pid, name: name, cpuPercent: 0, residentBytes: rss)
    }

    /// Drives one pid through `minutes` one-minute ingests, RSS from `bytes`.
    private func run(_ w: inout LeakWatcher, minutes: Int, from t0: Date,
                     bytes: (Int) -> UInt64) -> [[LeakAlert]] {
        (0...minutes).map { m in
            w.ingest([proc(1, "Leaky", rss: bytes(m))], now: t0.addingTimeInterval(Double(m) * 60))
        }
    }

    @Test func steadyGrowthPastWindowFiresOnce() {
        var w = LeakWatcher()
        let t0 = Date()
        // +40 MiB/min → +1.2 GiB over 31 min, strictly monotonic.
        let results = run(&w, minutes: 31, from: t0) { self.gib + UInt64($0) * 40 * self.mib }
        let firstFire = results.firstIndex { !$0.isEmpty }
        #expect(firstFire != nil)
        #expect(results[firstFire!].first?.isNewlySustained == true)
        #expect(results[firstFire!].first?.growthBytes ?? 0 >= 1 << 30)
        // Later ticks still report the leak, but not as new.
        #expect(results.last?.first?.isNewlySustained == false)
    }

    @Test func growthBelowThresholdStaysQuiet() {
        var w = LeakWatcher()
        // +16 MiB/min → ~+0.5 GiB over 32 min: under the 1 GiB floor.
        let results = run(&w, minutes: 32, from: Date()) { self.gib + UInt64($0) * 16 * self.mib }
        #expect(results.allSatisfy { $0.isEmpty })
    }

    @Test func sawtoothIsNotALeak() {
        var w = LeakWatcher()
        // Grows +2 GiB overall, but drops every 7th minute: ≥4 negative deltas
        // in any 30-minute window → ≤86.7% monotonic, below the 90% bar.
        let results = run(&w, minutes: 32, from: Date()) { m in
            let base = self.gib + UInt64(m) * 64 * self.mib
            return m % 7 == 6 ? base - 200 * self.mib : base
        }
        #expect(results.allSatisfy { $0.isEmpty })
    }

    @Test func shortWindowStaysQuiet() {
        var w = LeakWatcher()
        // +2 GiB in 10 min — huge, but window not yet covered.
        let results = run(&w, minutes: 10, from: Date()) { self.gib + UInt64($0) * 205 * self.mib }
        #expect(results.allSatisfy { $0.isEmpty })
    }

    @Test func briefDropoutKeepsTrack() {
        var w = LeakWatcher()
        let t0 = Date()
        var fired = false
        for m in 0...31 where m != 15 {   // absent for one minute mid-window
            let alerts = w.ingest(
                [proc(1, "Leaky", rss: gib + UInt64(m) * 40 * mib)],
                now: t0.addingTimeInterval(Double(m) * 60))
            fired = fired || !alerts.isEmpty
        }
        #expect(fired)
    }

    @Test func staleTrackIsDropped() {
        var w = LeakWatcher()
        let t0 = Date()
        _ = w.ingest([proc(1, "Leaky", rss: gib)], now: t0)
        // Reappears 20 min later, 29 min of growth after that: old track was
        // evicted (>5 min unseen), so the window isn't covered yet.
        var fired = false
        for m in 20...49 {
            let alerts = w.ingest(
                [proc(1, "Leaky", rss: gib + UInt64(m) * 40 * mib)],
                now: t0.addingTimeInterval(Double(m) * 60))
            fired = fired || !alerts.isEmpty
        }
        #expect(!fired)
    }

    @Test func subMinuteIngestsDontFloodPoints() {
        var w = LeakWatcher()
        let t0 = Date()
        // 10 minutes of 3-second ingests: growth huge, window uncovered, and
        // (implicitly) point storage stays one-per-minute — no early fire.
        for tick in 0...200 {
            let alerts = w.ingest(
                [proc(1, "Leaky", rss: gib + UInt64(tick) * 20 * mib)],
                now: t0.addingTimeInterval(Double(tick) * 3))
            #expect(alerts.isEmpty)
        }
    }
}

// MARK: - ProcessGrouper

@Suite("ProcessGrouper")
struct ProcessGrouperTests {
    @Test func appNameFromHelperPath() {
        #expect(ProcessGrouper.appName(fromPath:
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)")
            == "Google Chrome")
        #expect(ProcessGrouper.appName(fromPath: "/Applications/Safari.app/Contents/MacOS/Safari")
            == "Safari")
        #expect(ProcessGrouper.appName(fromPath: "/usr/libexec/trustd") == nil)
        #expect(ProcessGrouper.appName(fromPath: "") == nil)
    }

    @Test func groupSumsAndCounts() {
        let procs = [
            ProcessSample(pid: 1, name: "Chrome", cpuPercent: 10, residentBytes: 100, appName: "Chrome"),
            ProcessSample(pid: 2, name: "Chrome Helper", cpuPercent: 30, residentBytes: 200, appName: "Chrome"),
            ProcessSample(pid: 3, name: "Chrome Helper (GPU)", cpuPercent: 20, residentBytes: 300, appName: "Chrome"),
        ]
        let groups = ProcessGrouper.group(procs)
        #expect(groups.count == 1)
        #expect(groups.first?.count == 3)
        #expect(groups.first?.cpuPercent == 60)
        #expect(groups.first?.residentBytes == 600)
        #expect(groups.first?.topPID == 2)   // hottest member
    }

    @Test func ungroupedFallsBackToOwnName() {
        let procs = [
            ProcessSample(pid: 1, name: "trustd", cpuPercent: 5, residentBytes: 10),
            ProcessSample(pid: 2, name: "mds", cpuPercent: 3, residentBytes: 10),
        ]
        let groups = ProcessGrouper.group(procs)
        #expect(groups.count == 2)
        #expect(groups.map(\.name).sorted() == ["mds", "trustd"])
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    @Test func sortedByCPUThenRSS() {
        let procs = [
            ProcessSample(pid: 1, name: "idle-big", cpuPercent: 0, residentBytes: 9_000),
            ProcessSample(pid: 2, name: "hot-small", cpuPercent: 50, residentBytes: 10),
        ]
        #expect(ProcessGrouper.group(procs).first?.name == "hot-small")
    }
}
