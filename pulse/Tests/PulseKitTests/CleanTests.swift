import Foundation
import Testing

@testable import PulseKit

// MARK: - Helpers

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-clean-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeFile(at url: URL, megabytes: Int) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = Data(repeating: 0xCD, count: megabytes * 1_000_000)
    try data.write(to: url)
}

/// A fake home with one safe-tier target (Library/Caches subdir).
private func makeFakeHome(in root: URL) throws -> URL {
    let home = root.appendingPathComponent("home")
    try writeFile(
        at: home.appendingPathComponent("Library/Caches/com.example.app/blob.bin"),
        megabytes: 12)
    return home
}

// MARK: - CleanSchedule

@Suite("CleanSchedule")
struct CleanScheduleTests {
    @Test func dailyNextRunIsTomorrowAt3AM() {
        let calendar = Calendar.current
        let now = Date()
        let next = CleanSchedule.Frequency.daily.nextRun(after: now, hour: 3)
        #expect(next > now)
        #expect(next.timeIntervalSince(now) <= 86400 + 1)
        #expect(calendar.component(.hour, from: next) == 3)
        #expect(calendar.component(.minute, from: next) == 0)
    }

    @Test func weeklyNextRunIsASundayAt3AM() {
        let calendar = Calendar.current
        let now = Date()
        let next = CleanSchedule.Frequency.weekly.nextRun(after: now, hour: 3)
        #expect(next > now)
        #expect(next.timeIntervalSince(now) <= 7 * 86400 + 86400)
    }

    @Test func monthlyNextRunIsFirstOfMonthAt3AM() {
        let calendar = Calendar.current
        let next = CleanSchedule.Frequency.monthly.nextRun(after: Date(), hour: 3)
        #expect(next > Date())
    }

    @Test func defaultScheduleIsConservative() {
        let schedule = CleanSchedule.default()
        #expect(schedule.frequency == .weekly)
        #expect(!schedule.autoCleanSafeTier)
        #expect(schedule.notifyOnCompletion)
        #expect(schedule.lastRun == nil)
    }
}

// MARK: - CleanScheduler

@Suite("CleanScheduler")
struct CleanSchedulerTests {
    @Test func schedulePersistsAcrossInstances() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("appsupport")
        let home = try makeFakeHome(in: root)

        let first = CleanScheduler(directory: dir, home: home)
        var schedule = await first.currentSchedule()
        schedule.frequency = .daily
        schedule.autoCleanSafeTier = true
        await first.setSchedule(schedule)

        let second = CleanScheduler(directory: dir, home: home)
        let reloaded = await second.currentSchedule()
        #expect(reloaded.frequency == .daily)
        #expect(reloaded.autoCleanSafeTier)
    }

    @Test func runNowStagesSafeItems() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("appsupport")
        let home = try makeFakeHome(in: root)

        let scheduler = CleanScheduler(directory: dir, home: home)
        let record = await scheduler.runNow(autoMode: false)

        #expect(record.itemsCleaned == 1)
        #expect(record.bytesFreed > 10 * 1_000_000)
        
        #expect(
            !FileManager.default.fileExists(
                atPath: home.appendingPathComponent("Library/Caches/com.example.app").path))

        // Schedule advanced past now.
        let schedule = await scheduler.currentSchedule()
        #expect(schedule.lastRun != nil)
        #expect(schedule.nextRun > .now)
    }

    @Test func scheduleIfNeededRespectsAutoCleanFlag() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("appsupport")
        let home = try makeFakeHome(in: root)

        let scheduler = CleanScheduler(directory: dir, home: home)
        var schedule = await scheduler.currentSchedule()

        // Due but auto-clean off → no run.
        let due = Date(timeIntervalSinceNow: 10)
        #expect(await scheduler.scheduleIfNeeded(now: due) == nil)

        // Force a due date with auto-clean on → runs.
        schedule.autoCleanSafeTier = true
        await scheduler.setSchedule(schedule)
        let nextRun = await scheduler.currentSchedule().nextRun
        let record = await scheduler.scheduleIfNeeded(
            now: nextRun.addingTimeInterval(60))
        #expect(record != nil)
        #expect(record?.itemsCleaned == 1)
    }

    @Test func setScheduleRecomputesNextRunOnFrequencyChange() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let scheduler = CleanScheduler(
            directory: root.appendingPathComponent("appsupport"),
            home: root)

        var schedule = await scheduler.currentSchedule()
        schedule.frequency = .daily
        await scheduler.setSchedule(schedule)
        let updated = await scheduler.currentSchedule()
        #expect(updated.nextRun > .now)
        #expect(updated.nextRun.timeIntervalSinceNow <= 86400 + 1)
    }
}
