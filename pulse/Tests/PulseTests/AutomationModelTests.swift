import Foundation
import Testing
import PulseKit
@testable import Pulse

@MainActor
struct AutomationModelTests {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("automations.json")
    }

    private func automation() -> PulseAutomation {
        PulseAutomation(title: "Morning health", instructions: "Inspect memory pressure.",
                        schedule: .init(repeatRule: .once, onceAt: .now.addingTimeInterval(120)))
    }

    @Test func saveValidatesAndReloadsWithoutPublishingFailedWrites() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let model = AutomationModel(fileURL: file, scheduleTimers: false)
        var item = automation()
        item.title = "  Morning health  "
        try model.save(item)
        let restored = AutomationModel(fileURL: file, scheduleTimers: false)
        #expect(restored.automations == model.automations)
        #expect(restored.automations.first?.title == "Morning health")
        let before = try Data(contentsOf: file)
        item.instructions = String(repeating: "界", count: 4001)
        #expect(throws: (any Error).self) { try model.save(item) }
        #expect(try Data(contentsOf: file) == before)
        #expect(model.automations.count == 1)
        item = automation(); item.schedule.hour = 24
        #expect(throws: (any Error).self) { try model.save(item) }
    }

    @Test func repeatedCreateCannotDuplicatePaidSchedule() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let model = AutomationModel(fileURL: file, scheduleTimers: false)
        let item = automation(); try model.save(item)
        var duplicate = item; duplicate.id = UUID().uuidString
        #expect(throws: (any Error).self) { try model.save(duplicate) }
        #expect(model.automations.count == 1)
        model.stop()
    }

    @Test func corruptStorageIsPreservedAndBlocksOverwrite() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let broken = Data("not JSON".utf8)
        try broken.write(to: file)
        let model = AutomationModel(fileURL: file, scheduleTimers: false)
        #expect(model.status.contains("preserved"))
        #expect(throws: (any Error).self) { try model.save(automation()) }
        #expect(try Data(contentsOf: file) == broken)
        #expect(model.automations.isEmpty)
    }

    @Test func unwritableDestinationDoesNotPublishAutomation() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try Data("parent is a file".utf8).write(to: file)
        let model = AutomationModel(fileURL: file.appendingPathComponent("child.json"), scheduleTimers: false)
        #expect(throws: (any Error).self) { try model.save(automation()) }
        #expect(model.automations.isEmpty)
        #expect(model.status.contains("paused"))
    }

    @Test func dueOccurrenceIsClaimedOnceAndCrashRecoveryNeverReplaysIt() async throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let model = AutomationModel(fileURL: file, scheduleTimers: false)
        let item = automation()
        try model.save(item)
        var gate: CheckedContinuation<AutomationOutcome, Never>?
        var calls = 0
        model.configure { _, session, run in
            #expect(UUID(uuidString: session) != nil && UUID(uuidString: run) != nil)
            calls += 1
            return await withCheckedContinuation { gate = $0 }
        }
        let due = item.schedule.onceAt!.addingTimeInterval(1)
        model.reconcile(now: due); model.reconcile(now: due)
        for _ in 0..<100 where gate == nil { await Task.yield() }
        #expect(calls == 1 && model.runs.count == 1)
        #expect(model.automations.first?.runCount == 1)
        #expect(model.automations.first?.nextRun == nil)
        let recovered = AutomationModel(fileURL: file, scheduleTimers: false)
        #expect(recovered.runs.first?.status == "interrupted")
        #expect(recovered.automations.first?.lastStatus == "interrupted")
        #expect(recovered.automations.first?.nextRun == nil)
        gate?.resume(returning: .init(status: "completed", summary: "Healthy"))
        for _ in 0..<100 where !model.activeIDs.isEmpty { await Task.yield() }
        #expect(model.runs.first?.status == "completed")
        #expect(model.runs.first?.summary == "Healthy")
        model.stop(); recovered.stop()
    }

    @Test func cancelledAgentCommandCannotCreatePaidSchedule() async throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let model = AutomationModel(fileURL: file, scheduleTimers: false)
        let payload = "{\"title\":\"Daily check\",\"instructions\":\"Review CPU\",\"repeatRule\":\"daily\",\"hour\":9,\"minute\":0,\"weekday\":2,\"timezoneID\":\"Asia/Kolkata\"}"
        let task = Task { @MainActor in
            await Task.yield()
            return model.agentCommand(["automation", "create", payload])
        }
        task.cancel()
        let result = await task.value
        #expect(result.exitCode == 1)
        #expect(model.automations.isEmpty)
    }

    @Test func manualRunConsumesMissedOneTimeOccurrence() async throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let model = AutomationModel(fileURL: file, scheduleTimers: false)
        let item = automation(); try model.save(item)
        var gate: CheckedContinuation<AutomationOutcome, Never>?
        model.configure { _, _, _ in await withCheckedContinuation { gate = $0 } }
        model.runNow(item.id, now: item.schedule.onceAt!.addingTimeInterval(1))
        for _ in 0..<100 where gate == nil { await Task.yield() }
        #expect(model.automations.first?.nextRun == nil)
        gate?.resume(returning: .init(status: "completed", summary: "Done"))
        for _ in 0..<100 where !model.activeIDs.isEmpty { await Task.yield() }
        #expect(model.runs.count == 1 && model.automations.first?.runCount == 1)
        model.stop()
    }

    @Test func twoRunLimitRetainsDueWorkAndCancellationFinalizesClaim() async throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let model = AutomationModel(fileURL: file, scheduleTimers: false)
        // Distinct tasks; wall-clock precision must not decide whether the
        // duplicate-schedule guard accepts this concurrency fixture.
        let items = (0..<3).map { index in
            var item = automation(); item.title = "Health check \(index)"; return item
        }
        for item in items { try model.save(item) }
        var gates: [String: CheckedContinuation<AutomationOutcome, Never>] = [:]
        model.configure { item, _, _ in await withCheckedContinuation { gates[item.id] = $0 } }
        let due = items.map { $0.schedule.onceAt! }.max()!.addingTimeInterval(1)
        model.reconcile(now: due)
        for _ in 0..<100 where gates.count < 2 { await Task.yield() }
        #expect(model.activeIDs.count == 2 && model.runs.count == 2)
        #expect(model.automations.filter { $0.nextRun != nil }.count == 1)
        let first = try #require(model.activeIDs.first)
        model.cancel(first)
        gates.removeValue(forKey: first)?.resume(returning: .init(status: "completed", summary: "Stopped"))
        for _ in 0..<100 where model.activeIDs.contains(first) { await Task.yield() }
        #expect(model.runs.first(where: { $0.automationID == first })?.status == "cancelled")
        // The synthetic future deadline stays pending until the supplied clock reaches it again.
        model.reconcile(now: due)
        for _ in 0..<100 where gates.count < 2 { await Task.yield() }
        #expect(model.runs.count == 3)
        for gate in gates.values { gate.resume(returning: .init(status: "completed", summary: "Done")) }
        for _ in 0..<100 where !model.activeIDs.isEmpty { await Task.yield() }
        #expect(model.activeIDs.isEmpty)
        model.stop()
    }
}
