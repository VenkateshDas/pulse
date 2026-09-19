import Foundation
import Observation
import PulseKit

enum AgentRunState: Equatable { case idle, starting, running, awaitingApproval, completed, failed, cancelled }

struct AgentTimelineItem: Identifiable {
    enum Kind: Equatable { case user, answer, progress, tool, approval, error }
    let id: String
    var kind: Kind
    var title: String
    var detail: String
    var isExpanded = false
    var isRunning = false
}

/// Main-actor event reducer. Event IDs make replay and SSE reconnect safe.
@MainActor @Observable
final class AgentModel {
    var items: [AgentTimelineItem] = []
    var sessions: [AgentSessionItem] = []
    var sessionId: String?
    var state: AgentRunState = .idle
    var status = "Ready"
    var activeRunId: String?
    var hasApiKey = false
    private var seenEventIDs = Set<String>()
    private var lastSequence = 0

    func start() async {
        state = .starting; status = "Starting local agent…"
        guard await AgentDaemonManager.shared.ensureRunning() else {
            state = .failed; status = "Pulse Agent could not start"
            items.append(.init(id: UUID().uuidString, kind: .error, title: "Agent unavailable", detail: "Check that the local agent runtime is installed."))
            return
        }
        let daemon = await AgentClient.shared.checkStatus()
        hasApiKey = daemon.hasApiKey; state = .idle; status = daemon.summary ?? "Ready"
        sessions = (try? await AgentClient.shared.fetchSessions()) ?? []
    }

    func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, state == .idle || state == .completed || state == .failed || state == .cancelled else { return }
        items.append(.init(id: UUID().uuidString, kind: .user, title: message, detail: ""))
        state = .running; status = "Working…"; lastSequence = 0; seenEventIDs.removeAll()
        Task {
            do {
                for try await event in await AgentClient.shared.run(message: message, sessionId: sessionId) { apply(event) }
            } catch { fail(error.localizedDescription) }
        }
    }

    func resolveApproval(_ approved: Bool) {
        guard let runId = activeRunId else { return }
        state = .running; status = approved ? "Continuing…" : "Action declined"
        Task {
            do {
                for try await event in await AgentClient.shared.continueRun(runId: runId, approved: approved) { apply(event) }
            } catch { fail(error.localizedDescription) }
        }
    }

    func cancel() {
        guard let runId = activeRunId else { return }
        Task { try? await AgentClient.shared.cancel(runId: runId) }
        state = .cancelled; status = "Cancelled"
    }

    func loadSession(_ id: String) async {
        sessionId = id; items = []; state = .starting; status = "Loading conversation…"
        do {
            let history = try await AgentClient.shared.fetchHistory(sessionId: id)
            items = history.map { message in
                .init(id: UUID().uuidString, kind: message.role == "user" ? .user : .answer,
                      title: message.role == "user" ? message.content : "Pulse Agent",
                      detail: message.role == "user" ? "" : message.content)
            }
            state = .idle; status = "Ready"
        } catch {
            state = .failed; status = "Could not load conversation"
        }
    }

    func apply(_ event: AgentEnvelope) {
        guard event.version == 1, seenEventIDs.insert(event.eventId).inserted, event.sequence > lastSequence else { return }
        lastSequence = event.sequence; activeRunId = event.runId
        let text = event.payload["text"] ?? ""
        switch event.kind {
        case "run.started": status = "Working…"; state = .running
        case "reasoning.summary.delta": appendOrUpdate(id: "reasoning-\(event.runId)", kind: .progress, title: "Working on it", detail: text)
        case "answer.delta": appendOrUpdate(id: "answer-\(event.runId)", kind: .answer, title: "", detail: text)
        case "answer.interim": items.append(.init(id: event.eventId, kind: .progress, title: "Progress update", detail: text))
        case "answer.final": replace(id: "answer-\(event.runId)", kind: .answer, title: "Pulse Agent", detail: text)
        case "tool.started": items.append(.init(id: event.payload["tool_call_id"] ?? event.eventId, kind: .tool, title: event.payload["title"] ?? "Running tool", detail: event.payload["detail"] ?? "", isRunning: true))
        case "tool.completed", "tool.failed":
            let id = event.payload["tool_call_id"] ?? event.eventId
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].detail = event.payload["detail"] ?? text; items[index].isRunning = false }
            else { items.append(.init(id: id, kind: .tool, title: event.payload["title"] ?? "Tool result", detail: event.payload["detail"] ?? text)) }
        case "approval.requested":
            state = .awaitingApproval; status = "Approval required"
            items.append(.init(id: event.eventId, kind: .approval, title: event.payload["title"] ?? "Review action", detail: event.payload["detail"] ?? text))
        case "run.completed": state = .completed; status = "Complete"
        case "run.cancelled": state = .cancelled; status = "Cancelled"
        case "run.failed": fail(text.isEmpty ? "Agent run failed" : text)
        default: break
        }
    }

    private func appendOrUpdate(id: String, kind: AgentTimelineItem.Kind, title: String, detail: String) {
        if let index = items.firstIndex(where: { $0.id == id }) { items[index].detail += detail; if !title.isEmpty { items[index].title = title } }
        else { items.append(.init(id: id, kind: kind, title: title, detail: detail)) }
    }

    private func replace(id: String, kind: AgentTimelineItem.Kind, title: String, detail: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].title = title; items[index].detail = detail
        } else { items.append(.init(id: id, kind: kind, title: title, detail: detail)) }
    }

    private func fail(_ detail: String) { state = .failed; status = "Something went wrong"; items.append(.init(id: UUID().uuidString, kind: .error, title: "Agent run failed", detail: detail)) }
}
