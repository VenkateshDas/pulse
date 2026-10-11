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
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var streamGeneration = UUID()
    @ObservationIgnored private var ignoresCancelledEvents = false

    var isBusy: Bool { state == .running || state == .awaitingApproval || state == .starting }

    func newConversation() {
        guard !isBusy else { return }
        sessionId = nil; items = []; state = .idle; status = "Ready"
    }
    private var seenEventIDs = Set<String>()
    private var lastSequence = 0
    /// DeepSeek and similar providers can emit hundreds of tiny deltas per
    /// second. Coalesce them before publishing to SwiftUI's main actor.
    private var pendingAnswerText: [String: String] = [:]
    private var pendingAnswerChunks: [String: Int] = [:]

    func start() async {
        guard !isBusy else { return }
        hasApiKey = !AgentConfiguration.apiKey.isEmpty
        guard hasApiKey else { status = "Set up an AI provider to ask Pulse"; return }
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
        activeRunId = nil; ignoresCancelledEvents = false
        pendingAnswerText.removeAll(); pendingAnswerChunks.removeAll()
        let generation = UUID(); streamGeneration = generation
        streamTask = Task {
            do {
                for try await event in await AgentClient.shared.run(message: message, sessionId: sessionId) {
                    guard generation == streamGeneration, !Task.isCancelled else { return }
                    apply(event)
                }
            } catch { if generation == streamGeneration, !Task.isCancelled { fail(error.localizedDescription) } }
        }
    }

    func resolveApproval(_ approved: Bool) {
        guard state == .awaitingApproval, let runId = activeRunId else { return }
        state = .running; status = approved ? "Continuing…" : "Action declined"
        let generation = streamGeneration
        streamTask = Task {
            do {
                for try await event in await AgentClient.shared.continueRun(runId: runId, approved: approved) {
                    guard generation == streamGeneration, !Task.isCancelled else { return }
                    apply(event)
                }
            } catch { if generation == streamGeneration, !Task.isCancelled { fail(error.localizedDescription) } }
        }
    }

    func cancel() {
        guard state == .running || state == .awaitingApproval else { return }
        for (id, text) in pendingAnswerText where !text.isEmpty {
            appendOrUpdate(id: id, kind: .answer, title: "Ask Pulse", detail: text)
        }
        pendingAnswerText.removeAll(); pendingAnswerChunks.removeAll()
        ignoresCancelledEvents = true
        streamGeneration = UUID()
        streamTask?.cancel(); streamTask = nil
        state = .cancelled
        status = "Stopped waiting. Already started actions may still finish."
        for index in items.indices { items[index].isRunning = false }
        if let runId = activeRunId {
            Task {
                do {
                    try await AgentClient.shared.cancel(runId: runId)
                    if state == .cancelled { status = "Stop requested. Check completed actions before trying again." }
                } catch {
                    if state == .cancelled { status = "Could not confirm a stop. Already started actions may still finish." }
                }
            }
        }
    }

    func loadSession(_ id: String) async {
        guard !isBusy else { return }
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
        guard !ignoresCancelledEvents, event.version == 1, seenEventIDs.insert(event.eventId).inserted, event.sequence > lastSequence else { return }
        lastSequence = event.sequence; activeRunId = event.runId
        let text = event.payload["text"] ?? ""
        switch event.kind {
        case "run.started": status = "Working…"; state = .running
        case "reasoning.summary.delta": appendOrUpdate(id: "reasoning-\(event.runId)", kind: .progress, title: "Working on it", detail: text)
        case "answer.delta":
            removeProgress(runId: event.runId)
            bufferAnswerDelta(runId: event.runId, text: text)
        case "answer.interim": items.append(.init(id: event.eventId, kind: .progress, title: "Progress update", detail: text))
        case "answer.final":
            removeProgress(runId: event.runId)
            clearPendingAnswer(runId: event.runId)
            replace(id: "answer-\(event.runId)", kind: .answer, title: "Pulse Agent", detail: text)
        case "tool.started": items.append(.init(id: event.payload["tool_call_id"] ?? event.eventId, kind: .tool, title: event.payload["title"] ?? "Running tool", detail: event.payload["detail"] ?? "", isRunning: true))
        case "tool.completed", "tool.failed":
            let id = event.payload["tool_call_id"] ?? event.eventId
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].detail = event.payload["detail"] ?? text; items[index].isRunning = false }
            else { items.append(.init(id: id, kind: .tool, title: event.payload["title"] ?? "Tool result", detail: event.payload["detail"] ?? text)) }
        case "approval.requested":
            state = .awaitingApproval; status = "Approval required"
            items.append(.init(id: event.eventId, kind: .approval, title: event.payload["title"] ?? "Review action", detail: event.payload["detail"] ?? text))
        case "run.completed": removeProgress(runId: event.runId); state = .completed; status = "Complete"
        case "run.cancelled": state = .cancelled; status = "Cancelled"
        case "run.failed": fail(text.isEmpty ? "Agent run failed" : text)
        default: break
        }
    }

    private func appendOrUpdate(id: String, kind: AgentTimelineItem.Kind, title: String, detail: String) {
        if let index = items.firstIndex(where: { $0.id == id }) { items[index].detail += detail; if !title.isEmpty { items[index].title = title } }
        else { items.append(.init(id: id, kind: kind, title: title, detail: detail)) }
    }

    private func bufferAnswerDelta(runId: String, text: String) {
        let id = "answer-\(runId)"
        pendingAnswerText[id, default: ""] += text
        pendingAnswerChunks[id, default: 0] += 1
        guard pendingAnswerChunks[id, default: 0] >= 8 else { return }
        appendOrUpdate(id: id, kind: .answer, title: "", detail: pendingAnswerText[id, default: ""])
        pendingAnswerText[id] = ""; pendingAnswerChunks[id] = 0
    }

    private func clearPendingAnswer(runId: String) {
        let id = "answer-\(runId)"
        pendingAnswerText[id] = nil; pendingAnswerChunks[id] = nil
    }

    private func removeProgress(runId: String) {
        items.removeAll { $0.id == "reasoning-\(runId)" }
    }

    func toggleExpansion(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isExpanded.toggle()
    }

    private func replace(id: String, kind: AgentTimelineItem.Kind, title: String, detail: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].title = title; items[index].detail = detail
        } else { items.append(.init(id: id, kind: kind, title: title, detail: detail)) }
    }

    private func fail(_ detail: String) { state = .failed; status = "Something went wrong"; items.append(.init(id: UUID().uuidString, kind: .error, title: "Agent run failed", detail: detail)) }
}
