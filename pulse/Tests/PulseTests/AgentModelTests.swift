import Testing
@testable import Pulse
import PulseKit

@MainActor
struct AgentModelTests {
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
