import Testing
import Foundation
import os
@testable import Pulse

@MainActor struct HomeAssistantTests {
    @Test func collapsedHomeAndHiddenWindowsNeverOwnAnAssistantSurface() {
        #expect(!HomeAssistantState.isVisible(selection: .dashboard, homeOpen: false, windowVisible: true, screenLocked: false, onboarding: false))
        for selection in [SidebarItem.dashboard, .agent] {
            #expect(!HomeAssistantState.isVisible(selection: selection, homeOpen: true, windowVisible: false, screenLocked: false, onboarding: false))
            #expect(!HomeAssistantState.isVisible(selection: selection, homeOpen: true, windowVisible: true, screenLocked: true, onboarding: false))
            #expect(!HomeAssistantState.isVisible(selection: selection, homeOpen: true, windowVisible: true, screenLocked: false, onboarding: true))
            #expect(HomeAssistantState.isVisible(selection: selection, homeOpen: true, windowVisible: true, screenLocked: false, onboarding: false))
        }
        #expect(!HomeAssistantState.isVisible(selection: .storage, homeOpen: true, windowVisible: true, screenLocked: false, onboarding: false))
    }

    @Test func transferAndMinimizePreserveAnActiveConversationAndDraft() {
        let model = AgentModel()
        model.sessionId = "chat"; model.activeRunId = "run"; model.approvalId = "decision"
        model.state = .awaitingApproval; model.page = "memory"; model.specialist = "storage"
        model.setDraft("Keep this unsent question")
        model.investigationOnly = true
        var home = HomeAssistantState()
        home.open(runID: model.activeRunId)
        model.openPage("conversation")
        home.minimize()
        home.open(runID: model.activeRunId)
        #expect(model.sessionId == "chat" && model.activeRunId == "run" && model.approvalId == "decision")
        #expect(model.state == .awaitingApproval && model.page == "conversation")
        #expect(model.draft == "Keep this unsent question" && model.specialist == "storage")
        #expect(model.investigationOnly)
        #expect(model.items.isEmpty)
    }

    @Test func completionBadgeBelongsOnlyToAViewedRunCompletedWhileHidden() {
        var home = HomeAssistantState()
        home.runChanged(.completed, runID: "old history", visible: false)
        #expect(!home.answerReady)
        home.open(runID: "run")
        home.minimize()
        home.runChanged(.completed, runID: "other", visible: false)
        #expect(!home.answerReady)
        home.runChanged(.completed, runID: "run", visible: false)
        #expect(home.answerReady && home.label(for: .completed) == "Answer ready")
        home.open(runID: "run")
        #expect(!home.answerReady)
        home.runChanged(.completed, runID: "run", visible: true)
        #expect(!home.answerReady)
        home.minimize()
        home.runChanged(.completed, runID: "run", visible: false)
        home.markRead(runID: "run")
        #expect(!home.answerReady)
        #expect(home.label(for: .awaitingApproval) == "Review request")
    }

    @Test func compactSnapshotDoesNotChangeRunOrDecisionAuthority() {
        let model = AgentModel()
        model.state = .awaitingApproval; model.sessionId = "chat"; model.activeRunId = "run"; model.approvalId = "decision"
        model.items = [.init(id: "review", kind: .approval, title: "Review exact targets", detail: String(repeating: "/exact/path\n", count: 200), approvalID: "decision")]
        let compact = AgentWebView.snapshot(for: model, largerText: true, compact: true)
        let workspace = AgentWebView.snapshot(for: model, largerText: true)
        #expect(compact.compact && !workspace.compact)
        #expect(compact.items == workspace.items && compact.items[0].isRunning)
        #expect(compact.items[0].detail == model.items[0].detail)
        #expect(compact.sessionId == "chat" && model.activeRunId == "run" && model.approvalId == "decision")
    }

    @Test func smallViewportsUseTheWholeHomeDetailArea() {
        #expect(HomeAssistantState.usesFullDetail(width: 600, height: 600))
        #expect(HomeAssistantState.usesFullDetail(width: 550, height: 900))
        #expect(!HomeAssistantState.usesFullDetail(width: 900, height: 700))
    }

    @Test func returningToChatCancelsPendingRuntimeShutdown() async throws {
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let model = AgentModel(shutdownRuntime: { stops.withLock { $0 += 1 } })
        model.visibilityChanged(false)
        model.visibilityChanged(true)
        try await Task.sleep(for: .milliseconds(2200))
        #expect(stops.withLock { $0 } == 0)
        model.visibilityChanged(false)
        try await Task.sleep(for: .milliseconds(2200))
        #expect(stops.withLock { $0 } == 1)
    }

    @Test func hiddenActiveRunsAndWorkspaceLeasesRetainRuntime() async throws {
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let leased = AgentModel(shutdownRuntime: { stops.withLock { $0 += 1 } })
        leased.runtimeLeases = 1
        leased.visibilityChanged(false)
        let working = AgentModel(shutdownRuntime: { stops.withLock { $0 += 1 } })
        working.state = .awaitingApproval
        working.visibilityChanged(false)
        try await Task.sleep(for: .milliseconds(2200))
        #expect(stops.withLock { $0 } == 0)
        leased.runtimeLeases = 0
        leased.scheduleShutdown()
        try await Task.sleep(for: .milliseconds(2200))
        #expect(stops.withLock { $0 } == 1)
    }
}
