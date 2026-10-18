import Foundation
import Testing
@testable import Pulse

@MainActor struct AgentWorkspaceTests {
    @Test func returnToCurrentConversationPreservesRunAndDecision() {
        for state in [AgentRunState.running, .awaitingApproval] {
            let model = AgentModel()
            model.state = state; model.page = "memory"
            model.activeRunId = "run"; model.sessionId = "chat"; model.approvalId = "decision"
            model.openPage("conversation")
            #expect(model.page == "conversation" && model.state == state)
            #expect(model.activeRunId == "run" && model.sessionId == "chat" && model.approvalId == "decision")
        }
    }
}
