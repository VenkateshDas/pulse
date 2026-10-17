import Testing
import Foundation
import Observation
import os
@testable import Pulse
import PulseKit

@MainActor
struct AgentModelTests {
    @Test func rendererSnapshotTracksReadyState() {
        let model = AgentModel()
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = AgentWebView.snapshot(for: model, largerText: false) } onChange: { changed.withLock { $0 = true } }
        model.hasApiKey = true
        #expect(changed.withLock { $0 })
        #expect(AgentWebView.snapshot(for: model, largerText: false).ready)
    }

    @Test func toolIdentityIsScopedToItsRun() {
        let model = AgentModel()
        model.apply(.init(sequence: 1, runId: "first", sessionId: "session", kind: "tool.started", payload: ["tool_call_id": "reused"]))
        model.apply(.init(sequence: 2, runId: "second", sessionId: "session", kind: "tool.started", payload: ["tool_call_id": "reused"]))
        model.apply(.init(sequence: 3, runId: "second", sessionId: "session", kind: "tool.completed", payload: ["tool_call_id": "reused", "detail": "Second result"]))
        #expect(model.items.count == 2)
        #expect(model.items[0].isRunning)
        #expect(model.items[1].detail == "Second result")
        #expect(model.items[0].id != model.items[1].id)
    }

    @Test func startedRunRetainsConversationIdentity() {
        let model = AgentModel()
        model.apply(.init(sequence: 1, runId: "run", sessionId: "session", kind: "run.started", payload: [:]))
        #expect(model.sessionId == "session")
        #expect(model.activeRunId == "run")
    }

    @Test func duplicateEnvelopeDoesNotDuplicateTimeline() {
        let model = AgentModel()
        let event = AgentEnvelope(eventId: "once", sequence: 1, runId: "run", sessionId: "session", kind: "tool.started", payload: ["tool_call_id": "tool", "title": "Reading system vitals"])
        model.apply(event)
        model.apply(event)
        #expect(model.items.count == 1)
        #expect(model.items.first?.isRunning == true)
    }

    @Test func approvalPausesRunUntilResolved() {
        let model = AgentModel()
        model.apply(.init(sequence: 1, runId: "run", sessionId: "session", kind: "approval.requested", payload: ["title": "Previewing cleanup"]))
        #expect(model.state == .awaitingApproval)
        #expect(model.items.last?.kind == .approval)
    }

    @Test func finalAnswerReplacesStreamingDraft() {
        let model = AgentModel()
        model.apply(.init(sequence: 1, runId: "run", sessionId: "session", kind: "answer.delta", payload: ["text": "CPU is "]))
        model.apply(.init(sequence: 2, runId: "run", sessionId: "session", kind: "answer.final", payload: ["text": "CPU is healthy."]))
        #expect(model.items.count == 1)
        #expect(model.items[0].detail == "CPU is healthy.")
    }

    @Test func streamedAnswerRendersAtMostOncePerEightChunks() {
        let model = AgentModel()
        for sequence in 1...7 {
            model.apply(.init(sequence: sequence, runId: "run", sessionId: "session", kind: "answer.delta", payload: ["text": "x"]))
        }
        #expect(model.items.isEmpty)
        model.apply(.init(sequence: 8, runId: "run", sessionId: "session", kind: "answer.delta", payload: ["text": "x"]))
        #expect(model.items.count == 1)
        #expect(model.items[0].detail == "xxxxxxxx")
    }

    @Test func answerRemovesWorkingProgress() {
        let model = AgentModel()
        model.apply(.init(sequence: 1, runId: "run", sessionId: "session", kind: "reasoning.summary.delta", payload: ["text": "Checking evidence"]))
        for sequence in 2...9 {
            model.apply(.init(sequence: sequence, runId: "run", sessionId: "session", kind: "answer.delta", payload: ["text": "x"]))
        }
        #expect(model.items.count == 1)
        #expect(model.items[0].kind == .answer)
    }
}

@Suite("Conversation controls")
@MainActor
struct ConversationControlTests {
    @Test func stopBeforeFirstEventUsesAllocatedRequestID() async throws {
        let requests = OSAllocatedUnfairLock(initialState: [String]())
        let model = AgentModel(cancelRun: { id in requests.withLock { $0.append(id) } })
        model.send("Fixture question")
        let request = model.activeRunId
        #expect(request != nil)
        model.cancel()
        for _ in 0..<50 where requests.withLock({ $0.isEmpty }) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(requests.withLock { $0 } == [request!])
    }

    @Test func failedBufferedAnswerCannotLeakIntoNewConversation() async throws {
        let model = AgentModel()
        model.apply(.init(sequence: 1, runId: "old", sessionId: "old", kind: "answer.delta", payload: ["text": "Old partial"]))
        model.apply(.init(sequence: 2, runId: "old", sessionId: "old", kind: "run.failed", payload: ["text": "Interrupted"]))
        model.newConversation()
        try await Task.sleep(for: .milliseconds(60))
        #expect(model.items.isEmpty)
    }

    @Test func failuresWithoutStartedEventsRetainOutcome() {
        let model = AgentModel()
        model.apply(.init(sequence: 1, runId: "r", sessionId: "s", kind: "tool.failed", payload: ["tool_call_id": "c", "status": "denied"]))
        #expect(model.items.first?.outcome == "denied")
    }

    @Test func draftEvictionKeepsRecentConversations() {
        let model = AgentModel()
        for i in 0..<52 { model.sessionId = "s\(i)"; model.setDraft("Draft \(i)") }
        model.sessionId = "s50"; #expect(model.draft == "Draft 50")
        model.sessionId = "s51"; #expect(model.draft == "Draft 51")
        model.sessionId = "s0"; #expect(model.draft.isEmpty)
    }

    @Test func stopBeforeRunIDIsAvailableStillStopsLocalState() {
        let model = AgentModel()
        model.state = .running
        model.cancel()
        #expect(model.state == .cancelled)
        model.apply(.init(sequence: 1, runId: "late", sessionId: "session", kind: "run.started", payload: [:]))
        #expect(model.state == .cancelled)
        #expect(model.activeRunId == nil)
    }

    @Test func newConversationCannotDiscardAnActiveApproval() {
        let model = AgentModel()
        model.sessionId = "existing"
        model.apply(.init(sequence: 1, runId: "run", sessionId: "existing", kind: "approval.requested", payload: ["title": "Review removal"]))
        model.newConversation()
        #expect(model.sessionId == "existing")
        #expect(model.items.count == 1)
    }
}

private actor CancellationFixture {
    private var requests: [String: CheckedContinuation<Void, any Error>] = [:]
    func cancel(_ id: String) async throws {
        try await withCheckedThrowingContinuation { requests[id] = $0 }
    }
    var count: Int { requests.count }
    func finish(_ id: String) { requests.removeValue(forKey: id)?.resume() }
}

@Suite("Conversation usage")
@MainActor
struct ConversationUsageTests {
    private let snapshotJSON = #"{"context":{"estimatedTokens":1200,"limit":32000,"outputReserve":4096,"purpose":"turn","model":"fixture","measuredAt":1700000000,"categories":[{"label":"Tools","tokens":900},{"label":"History","tokens":300}],"reportedTokens":1250},"totals":{"input":4000,"output":200,"cacheRead":3000,"cacheWrite":0,"totalTokens":4200,"requests":2,"missingUsage":0,"missingCost":0,"costUSD":"0.0123","compactionTokens":100},"historical":false}"#

    @Test func usageEventUpdatesRendererWithoutAddingTranscriptRows() {
        let model = AgentModel()
        model.sessionId = "session"; model.activeRunId = "run"
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = AgentWebView.snapshot(for: model, largerText: false).usage } onChange: { changed.withLock { $0 = true } }
        model.apply(.init(sequence: 1, runId: "run", sessionId: "session", kind: "usage.updated", payload: ["usage": snapshotJSON]))
        #expect(changed.withLock { $0 })
        #expect(model.usage?.context?.estimatedTokens == 1200)
        #expect(model.usage?.totals.costUSD == "0.0123")
        #expect(AgentWebView.snapshot(for: model, largerText: false).usage == model.usage)
        #expect(model.items.isEmpty)
    }

    @Test func replayedUsageReplacesSnapshotInsteadOfAccumulatingTotals() {
        let model = AgentModel()
        let event = AgentEnvelope(eventId: "usage-once", sequence: 1, runId: "run", sessionId: "session", kind: "usage.updated", payload: ["usage": snapshotJSON])
        model.apply(event); model.apply(event)
        model.apply(.init(sequence: 2, runId: "run", sessionId: "session", kind: "usage.updated", payload: ["usage": snapshotJSON]))
        #expect(model.usage?.totals.totalTokens == 4200)
        #expect(model.usage?.totals.requests == 2)
    }

    @Test func foreignUsageDoesNotChangeIdentityOrConsumeItsSequence() {
        let model = AgentModel()
        model.sessionId = "session"; model.activeRunId = "run"
        for (run, session) in [("foreign", "session"), ("run", "foreign")] {
            model.apply(.init(eventId: "shared-event", sequence: 5, runId: run, sessionId: session, kind: "usage.updated", payload: ["usage": snapshotJSON]))
            #expect(model.usage == nil)
            #expect(model.sessionId == "session")
            #expect(model.activeRunId == "run")
        }
        model.apply(.init(eventId: "shared-event", sequence: 1, runId: "run", sessionId: "session", kind: "usage.updated", payload: ["usage": snapshotJSON]))
        #expect(model.usage?.totals.totalTokens == 4200)
    }

    @Test func malformedUsagePreservesLastKnownSnapshotAndNewConversationClearsIt() {
        let model = AgentModel()
        model.apply(.init(sequence: 1, runId: "run", sessionId: "session", kind: "usage.updated", payload: ["usage": snapshotJSON]))
        let previous = model.usage
        model.apply(.init(sequence: 2, runId: "run", sessionId: "session", kind: "usage.updated", payload: ["usage": "{invalid"]))
        #expect(model.usage == previous)
        model.newConversation()
        #expect(model.usage == nil)
        #expect(model.sessionId == nil)
    }
}

@Suite("Cancellation responses")
@MainActor
struct CancellationResponseTests {
    @Test func olderStopResponseCannotReplaceNewerStopStatus() async throws {
        let fixture = CancellationFixture()
        let model = AgentModel(cancelRun: { try await fixture.cancel($0) })
        model.state = .running; model.activeRunId = "first"; model.cancel()
        model.newConversation()
        model.state = .running; model.activeRunId = "second"; model.cancel()
        for _ in 0..<100 where await fixture.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let requested = await fixture.count
        #expect(requested == 2)
        let secondStatus = model.status
        await fixture.finish("first")
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.status == secondStatus)
        await fixture.finish("second")
        for _ in 0..<100 where model.status == secondStatus {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.status == "Stop requested. Check completed actions before trying again.")
    }
}
