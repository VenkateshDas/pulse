import Foundation

/// Presentation only. Conversation identity, drafts and execution stay in AgentModel.
struct HomeAssistantState {
    var isOpen = false
    var returnFromSettings = false
    private(set) var answerReady = false
    private var trackedRunID: String?

    mutating func open(runID: String?) {
        isOpen = true; markRead(runID: runID)
        returnFromSettings = false
    }

    mutating func markRead(runID: String?) { answerReady = false; trackedRunID = runID }

    mutating func minimize() { isOpen = false }

    mutating func runChanged(_ state: AgentRunState, runID: String?, visible: Bool) {
        if visible { markRead(runID: runID) }
        else if runID != trackedRunID { answerReady = false }
        if state == .completed, !visible, let runID, runID == trackedRunID {
            answerReady = true
        }
    }

    func label(for state: AgentRunState) -> String {
        switch state {
        case .awaitingApproval: "Review request"
        case .running: "Pulse is working…"
        case .starting: "Connecting Pulse…"
        default: answerReady ? "Answer ready" : "Ask Pulse"
        }
    }

    static func isVisible(selection: SidebarItem, homeOpen: Bool, windowVisible: Bool, screenLocked: Bool, onboarding: Bool) -> Bool {
        windowVisible && !screenLocked && !onboarding && (selection == .agent || (selection == .dashboard && homeOpen))
    }

    static func usesFullDetail(width: CGFloat, height: CGFloat) -> Bool { width < 600 || height < 640 }
}
