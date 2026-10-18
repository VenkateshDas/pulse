import Foundation
import Testing
import PulseKit
@testable import Pulse

@MainActor struct AutomationInboxTests {
    private struct Saved: Encodable { let automations: [PulseAutomation]; let runs: [AutomationRunRecord] }
    private func fixture(statuses: [String]) throws -> (AutomationModel, URL, PulseAutomation, [AutomationRunRecord]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("automation.json")
        let item = PulseAutomation(title: "Health check", instructions: "Review evidence", schedule: .init(repeatRule: .once, onceAt: .now.addingTimeInterval(3600)))
        let records = statuses.map { status in AutomationRunRecord(id: UUID().uuidString, automationID: item.id, sessionID: UUID().uuidString, title: item.title, status: status, startedAt: .now, finishedAt: .now, summary: "Saved evidence") }
        try JSONEncoder().encode(Saved(automations: [item], runs: records)).write(to: file)
        return (AutomationModel(fileURL: file, scheduleTimers: false), folder, item, records)
    }

    @Test func olderAttentionSurvivesNewestHundredCompletedRuns() throws {
        let (model, folder, _, records) = try fixture(statuses: Array(repeating: "completed", count: 100) + ["needs_review"])
        defer { model.stop(); try? FileManager.default.removeItem(at: folder) }
        #expect(model.inboxRuns.map(\.id) == [records.last!.id])
        try model.acknowledgeRun(records.last!.id)
        #expect(model.inboxRuns.isEmpty)
        #expect(model.runs.last?.summary == "Saved evidence")
    }

    @Test func unreadReviewItemsCannotBeEvictedByAnotherRun() async throws {
        let (model, folder, item, records) = try fixture(statuses: Array(repeating: "needs_review", count: 200))
        defer { model.stop(); try? FileManager.default.removeItem(at: folder) }
        model.configure { _, _, _ in .init(status: "completed", summary: "New evidence") }
        model.runNow(item.id)
        #expect(model.runs.count == 200 && model.activeIDs.isEmpty)
        #expect(model.automations.first?.runCount == 0)
        #expect(model.status.contains("Review"))
        try model.acknowledgeRun(records[50].id)
        model.runNow(item.id)
        for _ in 0..<100 where !model.activeIDs.isEmpty { await Task.yield() }
        #expect(model.runs.count == 200)
        #expect(model.runs.contains(where: { $0.id == records.last!.id && $0.status == "needs_review" }))
        #expect(!model.runs.contains(where: { $0.id == records[50].id }))
    }
}
