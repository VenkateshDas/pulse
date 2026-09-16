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
}
