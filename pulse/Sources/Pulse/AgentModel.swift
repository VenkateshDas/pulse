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
    var markdownBlocks: [AgentMarkdownBlock] = []
    var rendersMarkdown = false
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
    var selectedToolID: String?
    var hasMoreHistory = false
    var isLoadingHistory = false
    /// Title shown before server persists its first event. The live row is
    /// replaced by its durable session ID as soon as `run.started` arrives.
    private var pendingSessionTitle = "New conversation"
    private var seenEventIDs = Set<String>()
    private var lastSequence = 0
    /// DeepSeek and similar providers can emit hundreds of tiny deltas per
    /// second. Coalesce them before publishing to SwiftUI's main actor.
    private var pendingAnswerText: [String: String] = [:]
    private var pendingAnswerChunks: [String: Int] = [:]
    private var streamTask: Task<Void, Never>?
    private var nextHistoryOffset: Int?
    private var markdownQueue: [(id: String, text: String)] = []
    private var isRenderingMarkdown = false

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
        pendingSessionTitle = String(message.prefix(52))
        state = .running; status = "Working…"; activeRunId = nil; lastSequence = 0; seenEventIDs.removeAll()
        streamTask?.cancel()
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await event in await AgentClient.shared.run(message: message, sessionId: sessionId) {
                    guard !Task.isCancelled else { return }
                    apply(event)
                }
            } catch {
                guard !Task.isCancelled else { return }
                fail(error.localizedDescription)
            }
        }
    }

    func resolveApproval(_ approved: Bool) {
        guard let runId = activeRunId else { return }
        state = .running; status = approved ? "Continuing…" : "Action declined"
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await event in await AgentClient.shared.continueRun(runId: runId, approved: approved) {
                    guard !Task.isCancelled else { return }
                    apply(event)
                }
            } catch {
                guard !Task.isCancelled else { return }
                fail(error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard state == .running else { return }
        if let activeRunId { flushPendingAnswer(runId: activeRunId) }
        for index in items.indices where items[index].kind == .tool && items[index].isRunning {
            items[index].isRunning = false
            if items[index].detail.isEmpty { items[index].detail = "Cancelled" }
        }
        streamTask?.cancel(); streamTask = nil
        if let activeRunId { Task { try? await AgentClient.shared.cancel(runId: activeRunId) } }
        state = .cancelled; status = "Cancelled"
    }

    func loadSession(_ id: String) async {
        streamTask?.cancel()
        sessionId = id; items = []; selectedToolID = nil; state = .starting; status = "Loading conversation…"
        hasMoreHistory = false; nextHistoryOffset = nil; markdownQueue.removeAll(); isRenderingMarkdown = false
        do {
            let history = try await AgentClient.shared.fetchHistory(sessionId: id)
            items = history.messages.map { message in
                .init(id: UUID().uuidString, kind: message.role == "user" ? .user : .answer,
                      title: message.role == "user" ? message.content : "Pulse Agent",
                      detail: message.role == "user" ? "" : message.content)
            }
            nextHistoryOffset = history.nextOffset; hasMoreHistory = history.nextOffset != nil
            for item in items where item.kind == .answer { enqueueMarkdown(id: item.id, text: item.detail) }
            state = .idle; status = "Ready"
        } catch {
            state = .failed; status = "Could not load conversation"
        }
    }

    func loadEarlierHistory() async {
        guard let offset = nextHistoryOffset, !isLoadingHistory, let sessionId else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let page = try await AgentClient.shared.fetchHistory(sessionId: sessionId, offset: offset)
            let earlier: [AgentTimelineItem] = page.messages.map { message in
                .init(id: UUID().uuidString, kind: message.role == "user" ? .user : .answer,
                      title: message.role == "user" ? message.content : "Pulse Agent",
                      detail: message.role == "user" ? "" : message.content)
            }
            items.insert(contentsOf: earlier, at: 0)
            nextHistoryOffset = page.nextOffset; hasMoreHistory = page.nextOffset != nil
            for item in earlier where item.kind == .answer { enqueueMarkdown(id: item.id, text: item.detail) }
        } catch { status = "Could not load earlier messages" }
    }

    func apply(_ event: AgentEnvelope) {
        guard event.version == 1, seenEventIDs.insert(event.eventId).inserted, event.sequence > lastSequence else { return }
        lastSequence = event.sequence; activeRunId = event.runId
        if sessionId != event.sessionId {
            sessionId = event.sessionId
            upsertLiveSession(id: event.sessionId, title: pendingSessionTitle)
        }
        let text = event.payload["text"] ?? ""
        switch event.kind {
        case "run.started": status = "Working…"; state = .running
        case "reasoning.summary.delta": appendOrUpdate(id: "reasoning-\(event.runId)", kind: .progress, title: "Thinking", detail: text)
        case "answer.delta":
            bufferAnswerDelta(runId: event.runId, text: text)
        case "answer.interim": items.append(.init(id: event.eventId, kind: .progress, title: "Progress update", detail: text))
        case "answer.final":
            clearPendingAnswer(runId: event.runId)
            replace(id: "answer-\(event.runId)", kind: .answer, title: "Pulse Agent", detail: text)
            enqueueMarkdown(id: "answer-\(event.runId)", text: text)
        case "tool.started":
            insertTool(.init(id: event.payload["tool_call_id"] ?? event.eventId, kind: .tool, title: event.payload["title"] ?? "Running tool", detail: event.payload["detail"] ?? "", isRunning: true), runId: event.runId)
        case "tool.completed", "tool.failed":
            let id = event.payload["tool_call_id"] ?? event.eventId
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].detail = event.payload["detail"] ?? text; items[index].isRunning = false }
            else { insertTool(.init(id: id, kind: .tool, title: event.payload["title"] ?? "Tool result", detail: event.payload["detail"] ?? text), runId: event.runId) }
        case "approval.requested":
            state = .awaitingApproval; status = "Approval required"
            items.append(.init(id: event.eventId, kind: .approval, title: event.payload["title"] ?? "Review action", detail: event.payload["detail"] ?? text))
        case "run.completed": streamTask = nil; state = .completed; status = "Complete"; refreshSessions()
        case "run.cancelled": streamTask = nil; state = .cancelled; status = "Cancelled"; refreshSessions()
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

    private func flushPendingAnswer(runId: String) {
        let id = "answer-\(runId)"
        let pending = pendingAnswerText[id, default: ""]
        guard !pending.isEmpty else { return }
        appendOrUpdate(id: id, kind: .answer, title: "Pulse Agent", detail: pending)
        clearPendingAnswer(runId: runId)
    }

    private func insertTool(_ item: AgentTimelineItem, runId: String) {
        if let answerIndex = items.firstIndex(where: { $0.id == "answer-\(runId)" }) {
            items.insert(item, at: answerIndex)
        } else {
            items.append(item)
        }
    }

    func toggleExpansion(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isExpanded.toggle()
    }

    func selectTool(id: String) { selectedToolID = selectedToolID == id ? nil : id }

    func newConversation() {
        sessionId = nil; items = []; selectedToolID = nil; activeRunId = nil
        state = .idle; status = "Ready"; pendingSessionTitle = "New conversation"
    }

    var selectedTool: AgentTimelineItem? {
        guard let selectedToolID else { return nil }
        return items.first { $0.id == selectedToolID && $0.kind == .tool }
    }

    private func upsertLiveSession(id: String, title: String) {
        sessions.removeAll { $0.sessionId == id }
        sessions.insert(.init(sessionId: id, name: title, updatedAt: Int(Date().timeIntervalSince1970)), at: 0)
    }

    private func refreshSessions() {
        Task {
            guard let refreshed = try? await AgentClient.shared.fetchSessions() else { return }
            sessions = refreshed
        }
    }

    private func replace(id: String, kind: AgentTimelineItem.Kind, title: String, detail: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].title = title; items[index].detail = detail
        } else { items.append(.init(id: id, kind: kind, title: title, detail: detail)) }
    }

    /// Parse one answer at a time, off-main. Rendering old rich text must not
    /// block a follow-up prompt after a large response.
    private func enqueueMarkdown(id: String, text: String) {
        guard !text.isEmpty else { return }
        markdownQueue.append((id, text))
        renderNextMarkdown()
    }

    private func renderNextMarkdown() {
        guard !isRenderingMarkdown, !markdownQueue.isEmpty else { return }
        isRenderingMarkdown = true
        let next = markdownQueue.removeFirst()
        Task { [weak self] in
            let blocks = await Task.detached(priority: .utility) { AgentMarkdownParser.parse(next.text) }.value
            guard let self else { return }
            if let index = items.firstIndex(where: { $0.id == next.id && $0.detail == next.text }) {
                items[index].markdownBlocks = blocks
                items[index].rendersMarkdown = true
            }
            isRenderingMarkdown = false
            renderNextMarkdown()
        }
    }

    private func fail(_ detail: String) { state = .failed; status = "Something went wrong"; items.append(.init(id: UUID().uuidString, kind: .error, title: "Agent run failed", detail: detail)) }
}
