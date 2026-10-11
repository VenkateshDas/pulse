import Foundation
import Darwin
import Observation
import PulseKit

enum AgentRunState: Equatable { case idle, starting, running, awaitingApproval, completed, failed, cancelled }

struct AgentTimelineItem: Identifiable, Codable {
    enum Kind: String, Equatable, Codable { case user, answer, progress, tool, approval, error }
    let id: String
    var kind: Kind
    var title: String
    var detail: String
    var approvalID: String? = nil
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
    var approvalId: String?
    var surfaceVisible = false
    var hasEarlier = false
    @ObservationIgnored private var historyPage = 1
    var memories: [AgentMemoryItem] = []
    var memoryStatus = ""
    var memoryEnabled = AgentConfiguration.memoryEnabled
    @ObservationIgnored private let nativeToken = UUID().uuidString + UUID().uuidString
    @ObservationIgnored private var answerFlushTask: Task<Void, Never>?
    @ObservationIgnored private var approvalExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var runExpiry = Date.distantFuture
    @ObservationIgnored private var shutdownTask: Task<Void, Never>?
    var hasApiKey = false
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var streamGeneration = UUID()
    @ObservationIgnored private var ignoresCancelledEvents = false
    @ObservationIgnored private let cancelRun: @Sendable (String) async throws -> Void

    init(cancelRun: @escaping @Sendable (String) async throws -> Void = { try await AgentClient.shared.cancel(runId: $0) }) {
        self.cancelRun = cancelRun
    }

    var isBusy: Bool { state == .running || state == .awaitingApproval || state == .starting }

    func newConversation() {
        guard !isBusy else { return }
        sessionId = nil; activeRunId = nil; approvalId = nil; items = []; hasEarlier = false; historyPage = 1; state = .idle; status = "Ready"
    }
    private var seenEventIDs = Set<String>()
    private var lastSequence = 0
    /// DeepSeek and similar providers can emit hundreds of tiny deltas per
    /// second. Coalesce them before publishing to SwiftUI's main actor.
    private var pendingAnswerText: [String: String] = [:]
    private var pendingAnswerChunks: [String: Int] = [:]

    func start() async {
        guard !isBusy else { return }
        state = .starting; status = "Unlocking provider credentials…"
        let key = await AgentConfiguration.loadAPIKey(interactive: true)
        state = .idle
        hasApiKey = AgentConfiguration.isReady(baseURL: AgentConfiguration.baseURL, apiKey: key, provider: AgentConfiguration.provider)
        guard hasApiKey else { status = "Set up an AI provider to ask Pulse"; return }
        guard AgentConfiguration.providerURL(AgentConfiguration.baseURL) != nil else {
            state = .failed; status = "Review the provider URL in Settings before asking Pulse"
            return
        }
        state = .starting; status = "Starting local agent…"
        defer { if !isBusy && !surfaceVisible { scheduleShutdown() } }
        do {
            let port = try await AgentNativeBridge.shared.start(token: nativeToken)
            await AgentDaemonManager.shared.configureNativeBridge(port: port, token: nativeToken)
        } catch { state = .failed; status = "Native tools could not start"; return }
        guard await AgentDaemonManager.shared.ensureRunning(apiKey: key) else {
            state = .failed; status = "Pulse Agent could not start"
            items.append(.init(id: UUID().uuidString, kind: .error, title: "Agent unavailable", detail: "Check that the local agent runtime is installed."))
            return
        }
        try? await AgentClient.shared.updateConfiguration(baseURL: AgentConfiguration.baseURL, apiKey: key, model: AgentConfiguration.model)
        let daemon = await AgentClient.shared.checkStatus()
        hasApiKey = daemon.hasApiKey; state = .idle; status = daemon.summary ?? "Ready"
        sessions = (try? await AgentClient.shared.fetchSessions()) ?? []
    }

    func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, state == .idle || state == .completed || state == .failed || state == .cancelled else { return }
        items.append(.init(id: UUID().uuidString, kind: .user, title: message, detail: ""))
        state = .running; status = "Working…"; lastSequence = 0; seenEventIDs.removeAll()
        activeRunId = nil; ignoresCancelledEvents = false; approvalExpiryTask?.cancel()
        pendingAnswerText.removeAll(); pendingAnswerChunks.removeAll(); answerFlushTask?.cancel(); answerFlushTask = nil
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
        guard state == .awaitingApproval, let runId = activeRunId, let approvalId else { return }
        state = .running; status = approved ? "Continuing…" : "Action declined"
        let generation = streamGeneration
        streamTask = Task {
            do {
                for try await event in await AgentClient.shared.continueRun(runId: runId, approved: approved, approvalId: approvalId) {
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
        pendingAnswerText.removeAll(); pendingAnswerChunks.removeAll(); answerFlushTask?.cancel(); answerFlushTask = nil
        approvalExpiryTask?.cancel()
        ignoresCancelledEvents = true
        streamGeneration = UUID()
        let cancellationGeneration = streamGeneration
        streamTask?.cancel(); streamTask = nil
        state = .cancelled
        status = "Stopped waiting. Already started actions may still finish."
        for index in items.indices { items[index].isRunning = false }
        if !surfaceVisible { scheduleShutdown() }
        if let runId = activeRunId {
            Task {
                do {
                    try await cancelRun(runId)
                    if state == .cancelled && cancellationGeneration == streamGeneration { status = "Stop requested. Check completed actions before trying again." }
                } catch {
                    if state == .cancelled && cancellationGeneration == streamGeneration { status = "Could not confirm a stop. Already started actions may still finish." }
                }
            }
        }
    }

    func loadSession(_ id: String) async {
        guard !isBusy else { return }
        sessionId = id; items = []; state = .starting; status = "Loading conversation…"
        do {
            let page = try await AgentClient.shared.fetchHistoryPage(sessionId: id, page: 1)
            historyPage = 1; hasEarlier = page.hasMore
            items = page.messages.map { message in
                .init(id: UUID().uuidString, kind: message.role == "user" ? .user : .answer,
                      title: message.role == "user" ? message.content : "Pulse Agent",
                      detail: message.role == "user" ? "" : message.content)
            }
            state = .idle; status = "Ready"
        } catch {
            state = .failed; status = "Could not load conversation"
        }
    }

    func loadEarlier() async {
        guard !isBusy, hasEarlier, let sessionId, items.count < 500 else { return }
        state = .starting
        do {
            let page = try await AgentClient.shared.fetchHistoryPage(sessionId: sessionId, page: historyPage + 1)
            historyPage += 1; hasEarlier = page.hasMore && items.count + page.messages.count < 500
            let earlier = page.messages.map { message in
                AgentTimelineItem(id: UUID().uuidString, kind: message.role == "user" ? .user : .answer,
                    title: message.role == "user" ? message.content : "Ask Pulse", detail: message.role == "user" ? "" : message.content)
            }
            items.insert(contentsOf: earlier, at: 0); state = .idle
        } catch { state = .failed; status = "Earlier messages could not load" }
    }

    func apply(_ event: AgentEnvelope) {
        guard !ignoresCancelledEvents, event.version == 1, seenEventIDs.insert(event.eventId).inserted, event.sequence > lastSequence else { return }
        if items.count > 500 { items.removeFirst(items.count - 500) }
        lastSequence = event.sequence; activeRunId = event.runId; sessionId = event.sessionId
        let text = event.payload["text"] ?? ""
        switch event.kind {
        case "run.started": runExpiry = .now.addingTimeInterval(900); status = "Working…"; state = .running
        case "reasoning.summary.delta": appendOrUpdate(id: "reasoning-\(event.runId)", kind: .progress, title: "Working on it", detail: text)
        case "answer.delta":
            removeProgress(runId: event.runId)
            bufferAnswerDelta(runId: event.runId, text: text)
        case "answer.interim": items.append(.init(id: event.eventId, kind: .progress, title: "Progress update", detail: text))
        case "answer.final":
            removeProgress(runId: event.runId)
            clearPendingAnswer(runId: event.runId)
            replace(id: "answer-\(event.runId)", kind: .answer, title: "Pulse Agent", detail: text)
        case "tool.started": items.append(.init(id: "tool-\(event.runId)-\(event.payload["tool_call_id"] ?? event.eventId)", kind: .tool, title: event.payload["title"] ?? "Running tool", detail: event.payload["detail"] ?? "", isRunning: true))
        case "tool.completed", "tool.failed":
            let id = "tool-\(event.runId)-\(event.payload["tool_call_id"] ?? event.eventId)"
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].detail = event.payload["detail"] ?? text; items[index].isRunning = false }
            else { items.append(.init(id: id, kind: .tool, title: event.payload["title"] ?? "Tool result", detail: event.payload["detail"] ?? text, approvalID: event.payload["approval_id"])) }
        case "approval.requested":
            approvalId = event.payload["approval_id"]
            approvalExpiryTask?.cancel()
            let expected = approvalId
            let wait = max(0, min(900, runExpiry.timeIntervalSinceNow))
            approvalExpiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled, self.state == .awaitingApproval, self.approvalId == expected else { return }
                self.cancel()
            }
            state = .awaitingApproval; status = "Approval required"
            items.append(.init(id: event.eventId, kind: .approval, title: event.payload["title"] ?? "Review action", detail: event.payload["detail"] ?? text, approvalID: event.payload["approval_id"]))
        case "run.completed": approvalId = nil; Task { sessions = (try? await AgentClient.shared.fetchSessions()) ?? sessions }; removeProgress(runId: event.runId); state = .completed; status = "Complete"
        case "run.cancelled": state = .cancelled; status = "Cancelled"
        case "run.failed": fail(text.isEmpty ? "Agent run failed" : text)
        default: break
        }
        if !isBusy && !surfaceVisible { scheduleShutdown() }
    }

    private func appendOrUpdate(id: String, kind: AgentTimelineItem.Kind, title: String, detail: String) {
        if let index = items.firstIndex(where: { $0.id == id }) { items[index].detail += detail; if !title.isEmpty { items[index].title = title } }
        else { items.append(.init(id: id, kind: kind, title: title, detail: detail)) }
    }

    private func bufferAnswerDelta(runId: String, text: String) {
        let id = "answer-\(runId)"
        pendingAnswerText[id, default: ""] += text
        pendingAnswerChunks[id, default: 0] += 1
        if answerFlushTask == nil {
            let generation = streamGeneration
            answerFlushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, generation == self.streamGeneration, !Task.isCancelled else { return }
                self.flushAnswers(); self.answerFlushTask = nil
            }
        }
        guard pendingAnswerChunks[id, default: 0] >= 8 else { return }
        appendOrUpdate(id: id, kind: .answer, title: "", detail: pendingAnswerText[id, default: ""])
        pendingAnswerText[id] = ""; pendingAnswerChunks[id] = 0
    }

    private func flushAnswers() {
        for (id, text) in pendingAnswerText where !text.isEmpty {
            appendOrUpdate(id: id, kind: .answer, title: "Ask Pulse", detail: text)
            pendingAnswerText[id] = ""; pendingAnswerChunks[id] = 0
        }
    }

    func visibilityChanged(_ visible: Bool) {
        surfaceVisible = visible
        if visible { shutdownTask?.cancel(); shutdownTask = nil }
        else if !isBusy { scheduleShutdown() }
    }

    private func scheduleShutdown() {
        shutdownTask?.cancel()
        shutdownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, !self.surfaceVisible, !self.isBusy else { return }
            await AgentDaemonManager.shared.shutdown()
            await AgentNativeBridge.shared.stop()
            // Release unused allocator pages after WebKit/sidecar teardown.
            _ = await Task.detached(priority: .utility) { malloc_zone_pressure_relief(nil, 0) }.value
        }
    }

    func refreshMemory() async {
        do {
            let data = try await AgentClient.shared.memoryRequest()
            struct Response: Decodable { let memories: [AgentMemoryItem]; let enabled: Bool }
            let response = try JSONDecoder().decode(Response.self, from: data)
            memories = response.memories; memoryEnabled = response.enabled; memoryStatus = ""
        } catch { memoryStatus = "Memory could not load. Reconnect and try again." }
    }
    func deleteMemory(_ id: String) async {
        guard !isBusy, id == "all" || UUID(uuidString: id) != nil else { return }
        do { _ = try await AgentClient.shared.memoryRequest(path: "/memory/\(id)", method: "DELETE"); await refreshMemory() }
        catch { memoryStatus = "Stop active runs before changing memory." }
    }
    func setMemoryEnabled(_ enabled: Bool) async {
        guard !isBusy else { return }
        do {
            _ = try await AgentClient.shared.memoryRequest(path: "/memory/toggle?enabled=\(enabled)", method: "POST")
            AgentConfiguration.memoryEnabled = enabled; memoryEnabled = enabled
        } catch { memoryStatus = "Memory setting could not change. Stop active runs and retry." }
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

    private func fail(_ detail: String) { state = .failed; status = "Something went wrong"; items.append(.init(id: UUID().uuidString, kind: .error, title: "Agent run failed", detail: detail)); if !surfaceVisible { scheduleShutdown() } }
}

struct AgentMemoryItem: Codable, Identifiable {
    let id: String
    let content: String
    let evidence: String
    let kind: String
    let source_session: String
    let created_at: Int
}
