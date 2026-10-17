import Foundation
import Observation
import PulseKit

enum AgentRunState: Equatable { case idle, starting, running, awaitingApproval, completed, failed, cancelled }

struct AgentTimelineItem: Identifiable, Codable, Equatable {
    enum Kind: String, Equatable, Codable { case user, answer, progress, tool, approval, error }
    let id: String
    var kind: Kind
    var title: String
    var detail: String
    var approvalID: String? = nil
    var isExpanded = false
    var isRunning = false
    var outcome: String? = nil
    var interaction: String? = nil
    var options: [String]? = nil
}

/// Main-actor event reducer. Event IDs make replay and SSE reconnect safe.
@MainActor @Observable
final class AgentModel {
    var items: [AgentTimelineItem] = []
    var sessions: [AgentSessionItem] = []
    var sessionId: String?
    var usage: AgentUsageSnapshot?
    @ObservationIgnored private var usageRevision = 0
    var state: AgentRunState = .idle
    var status = "Ready"
    var activeRunId: String?
    var approvalId: String?
    var surfaceVisible = false
    var hasEarlier = false
    @ObservationIgnored private var historyPage = 1
    @ObservationIgnored private var drafts: [String: String] = [:]
    @ObservationIgnored private var draftOrder: [String] = []
    var draft: String { drafts[sessionId ?? "new"] ?? "" }
    func setDraft(_ text: String) {
        guard text.utf8.count <= 12_000 else { return }
        let key = sessionId ?? "new"
        draftOrder.removeAll { $0 == key }; draftOrder.append(key)
        while draftOrder.count > 50 { drafts.removeValue(forKey: draftOrder.removeFirst()) }
        drafts[key] = text
    }
    var memories: [AgentMemoryItem] = []
    var memoryStatus = ""
    var memoryEnabled = AgentConfiguration.memoryEnabled
    @ObservationIgnored private let nativeToken = UUID().uuidString + UUID().uuidString
    @ObservationIgnored private var answerFlushTask: Task<Void, Never>?
    @ObservationIgnored private var approvalExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var runExpiry = Date.distantFuture
    @ObservationIgnored private var shutdownTask: Task<Void, Never>?
    var hasApiKey = false
    var investigationOnly = UserDefaults.standard.bool(forKey: "PulseAgentReadOnly")
    func setInvestigationOnly(_ value: Bool) {
        guard !isBusy else { return }
        investigationOnly = value; UserDefaults.standard.set(value, forKey: "PulseAgentReadOnly")
    }
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
        resetStream()
        sessionId = nil; usage = nil; usageRevision += 1; activeRunId = nil; approvalId = nil; items = []; hasEarlier = false; historyPage = 1; state = .idle; status = "Ready"
    }
    private var seenEventIDs = Set<String>()
    private var lastSequence = 0
    /// DeepSeek and similar providers can emit hundreds of tiny deltas per
    /// second. Coalesce them before publishing to SwiftUI's main actor.
    private var pendingAnswerText: [String: String] = [:]
    private var pendingAnswerChunks: [String: Int] = [:]

    func start() async {
        guard !isBusy else { return }
        let selection = AgentConfiguration.runtimeEnvironment
        let endpoint = selection["OPENAI_BASE_URL"] ?? ""
        let provider = selection["PULSE_PROVIDER"] ?? ""
        let model = selection["PULSE_MODEL_ID"] ?? ""
        state = .starting; status = "Loading provider settings…"
        let key = await AgentConfiguration.loadAPIKey(endpoint: endpoint)
        state = .idle
        guard selection == AgentConfiguration.runtimeEnvironment else {
            hasApiKey = false; status = "Provider settings changed. Reconnect to use them."; return
        }
        hasApiKey = AgentConfiguration.isReady(baseURL: endpoint, apiKey: key, provider: provider)
        guard hasApiKey else { status = "Set up an AI provider to ask Pulse"; return }
        guard AgentConfiguration.providerURL(endpoint) != nil else {
            state = .failed; status = "Review the provider URL in Settings before asking Pulse"
            return
        }
        state = .starting; status = "Starting local agent…"
        defer { if !isBusy && !surfaceVisible { scheduleShutdown() } }
        do {
            let port = try await AgentNativeBridge.shared.start(token: nativeToken)
            await AgentDaemonManager.shared.configureNativeBridge(port: port, token: nativeToken)
        } catch { state = .failed; status = "Native tools could not start"; return }
        guard await AgentDaemonManager.shared.ensureRunning(apiKey: key, providerEnvironment: selection) else {
            state = .failed; status = "Pulse Agent could not start"
            items.append(.init(id: UUID().uuidString, kind: .error, title: "Agent unavailable", detail: "Check that the local agent runtime is installed."))
            return
        }
        guard selection == AgentConfiguration.runtimeEnvironment else {
            hasApiKey = false; state = .idle; status = "Provider settings changed. Reconnect to use them."; return
        }
        do { try await AgentClient.shared.updateConfiguration(baseURL: endpoint, apiKey: key, model: model, configuration: selection) }
        catch { hasApiKey = false; state = .failed; status = "Provider settings could not be applied. Reconnect before sending a question."; return }
        let daemon = await AgentClient.shared.checkStatus()
        hasApiKey = daemon.hasApiKey; state = .idle; status = daemon.summary ?? "Ready"
        sessions = (try? await AgentClient.shared.fetchSessions()) ?? []
        await refreshUsage()
    }

    func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, state == .idle || state == .completed || state == .failed || state == .cancelled else { return }
        setDraft("")
        items.append(.init(id: UUID().uuidString, kind: .user, title: message, detail: ""))
        state = .running; status = "Working…"; lastSequence = 0; seenEventIDs.removeAll()
        let runId = UUID().uuidString
        activeRunId = runId; sessionId = sessionId ?? UUID().uuidString
        ignoresCancelledEvents = false; approvalExpiryTask?.cancel()
        pendingAnswerText.removeAll(); pendingAnswerChunks.removeAll(); answerFlushTask?.cancel(); answerFlushTask = nil
        let generation = UUID(); streamGeneration = generation
        streamTask = Task {
            guard !Task.isCancelled, generation == streamGeneration else { return }
            do {
                for try await event in await AgentClient.shared.run(message: message, sessionId: sessionId, runId: runId, readOnly: investigationOnly) {
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
                for try await event in await AgentClient.shared.continueRun(runId: runId, approved: approved, approvalId: approvalId, afterSequence: lastSequence) {
                    guard generation == streamGeneration, !Task.isCancelled else { return }
                    apply(event)
                }
            } catch { if generation == streamGeneration, !Task.isCancelled { fail(error.localizedDescription) } }
        }
    }

    func answerQuestion(_ answer: String) {
        guard state == .awaitingApproval, let runId = activeRunId, let approvalId,
              items.last(where: { $0.approvalID == approvalId })?.interaction == "question",
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, answer.utf8.count <= 12_000 else { return }
        state = .running; status = "Continuing…"
        let generation = streamGeneration
        streamTask = Task {
            do {
                for try await event in await AgentClient.shared.answerQuestion(runId: runId, approvalId: approvalId, answer: answer, afterSequence: lastSequence) {
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
                guard cancellationGeneration == streamGeneration else { return }
                await refreshUsage()
                // Stop acknowledges the interrupt before an in-flight provider finishes accounting.
                try? await Task.sleep(for: .seconds(1))
                guard cancellationGeneration == streamGeneration else { return }
                await refreshUsage()
            }
        }
    }

    func loadSession(_ id: String) async {
        guard !isBusy else { return }
        resetStream()
        sessionId = id; usage = nil; usageRevision += 1; activeRunId = nil
        let generation = streamGeneration
        items = []; state = .starting; status = "Loading conversation…"
        do {
            let page = try await AgentClient.shared.fetchHistoryPage(sessionId: id, page: 1)
            guard sessionId == id, generation == streamGeneration else { return }
            historyPage = 1; hasEarlier = page.hasMore
            items = page.messages.map(Self.historyItem)
            state = .idle; status = page.interrupted == true ? "Previous run interrupted. Review completed actions before continuing." : "Ready"
            await refreshUsage()
        } catch {
            guard sessionId == id, generation == streamGeneration else { return }
            state = .failed; status = "Could not load conversation"
        }
    }

    func loadEarlier() async {
        guard !isBusy, hasEarlier, let sessionId, items.count < 500 else { return }
        state = .starting
        do {
            let page = try await AgentClient.shared.fetchHistoryPage(sessionId: sessionId, page: historyPage + 1)
            historyPage += 1; hasEarlier = page.hasMore && items.count + page.messages.count < 500
            let earlier = page.messages.map(Self.historyItem)
            items.insert(contentsOf: earlier, at: 0); state = .idle
        } catch { state = .failed; status = "Earlier messages could not load" }
    }

    private static func historyItem(_ message: AgentHistoryMessage) -> AgentTimelineItem {
        let kind: AgentTimelineItem.Kind = message.role == "user" ? .user : message.role == "tool" ? .tool : message.role == "notice" ? .progress : .answer
        return .init(id: "history-\(message.id ?? UUID().uuidString)", kind: kind,
            title: kind == .user ? message.content : kind == .tool ? (message.name ?? "Tool result").replacingOccurrences(of: "_", with: " ") : "Ask Pulse",
            detail: kind == .user ? "" : message.content, outcome: message.status)
    }

    func apply(_ event: AgentEnvelope) {
        if event.kind == "usage.updated" {
            guard sessionId == nil || sessionId == event.sessionId,
                  activeRunId == nil || activeRunId == event.runId else { return }
        }
        guard !ignoresCancelledEvents, event.version == 1, seenEventIDs.insert(event.eventId).inserted, event.sequence > lastSequence else { return }
        if items.count > 500 { items.removeFirst(items.count - 500) }
        lastSequence = event.sequence; activeRunId = event.runId; sessionId = event.sessionId
        let text = event.payload["text"] ?? ""
        switch event.kind {
        case "usage.updated":
            if let encoded = event.payload["usage"]?.data(using: .utf8),
               let snapshot = try? JSONDecoder().decode(AgentUsageSnapshot.self, from: encoded) {
                usageRevision += 1; usage = snapshot
            }
        case "answer.reset":
            clearPendingAnswer(runId: event.runId)
            items.removeAll { $0.id == "answer-\(event.runId)" }
        case "run.started": runExpiry = .now.addingTimeInterval(900); status = "Working…"; state = .running
        case "reasoning.summary.delta": appendOrUpdate(id: "reasoning-\(event.runId)", kind: .progress, title: "Working on it", detail: text)
        case "answer.delta":
            removeProgress(runId: event.runId)
            bufferAnswerDelta(runId: event.runId, text: text)
        case "answer.interim":
            clearPendingAnswer(runId: event.runId)
            items.removeAll { $0.id == "answer-\(event.runId)" }
            if !text.isEmpty { items.append(.init(id: event.eventId, kind: .progress, title: "Progress update", detail: text)) }
        case "answer.final":
            removeProgress(runId: event.runId)
            clearPendingAnswer(runId: event.runId)
            replace(id: "answer-\(event.runId)", kind: .answer, title: "Pulse Agent", detail: text)
        case "tool.started": items.append(.init(id: "tool-\(event.runId)-\(event.payload["tool_call_id"] ?? event.eventId)", kind: .tool, title: event.payload["title"] ?? "Running tool", detail: event.payload["detail"] ?? "", isRunning: true))
        case "tool.completed", "tool.failed":
            let id = "tool-\(event.runId)-\(event.payload["tool_call_id"] ?? event.eventId)"
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].detail = event.payload["detail"] ?? text; items[index].isRunning = false; items[index].outcome = event.payload["status"] ?? (event.kind == "tool.failed" ? "error" : "ok") }
            else { items.append(.init(id: id, kind: .tool, title: event.payload["title"] ?? "Tool result", detail: event.payload["detail"] ?? text, approvalID: event.payload["approval_id"], outcome: event.payload["status"] ?? (event.kind == "tool.failed" ? "error" : "ok"))) }
        case "approval.requested":
            approvalId = event.payload["approval_id"]
            items.removeAll { $0.kind == .approval && $0.approvalID == approvalId }
            approvalExpiryTask?.cancel()
            let expected = approvalId
            let wait = max(0, min(300, runExpiry.timeIntervalSinceNow))
            approvalExpiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled, self.state == .awaitingApproval, self.approvalId == expected else { return }
                self.cancel()
            }
            state = .awaitingApproval; status = "Approval required"
            let options = event.payload["options"].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([String].self, from: $0) }
            items.append(.init(id: event.eventId, kind: .approval, title: event.payload["title"] ?? "Review action", detail: event.payload["detail"] ?? text, approvalID: event.payload["approval_id"], interaction: event.payload["interaction"] ?? "action", options: options))
        case "approval.resolved":
            if let index = items.firstIndex(where: { $0.approvalID == event.payload["approval_id"] }) {
                items[index].outcome = text; items[index].isRunning = false
            }
        case "run.completed": approvalId = nil; Task { sessions = (try? await AgentClient.shared.fetchSessions()) ?? sessions }; removeProgress(runId: event.runId); state = .completed; status = "Complete"; scheduleUsageRefresh()
        case "run.cancelled": state = .cancelled; status = "Cancelled"; scheduleUsageRefresh()
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

    private func resetStream() {
        streamGeneration = UUID(); streamTask?.cancel(); streamTask = nil
        answerFlushTask?.cancel(); answerFlushTask = nil; approvalExpiryTask?.cancel()
        pendingAnswerText.removeAll(); pendingAnswerChunks.removeAll()
    }

    private func refreshUsage() async {
        guard let id = sessionId else { return }
        let generation = streamGeneration, revision = usageRevision
        guard let snapshot = try? await AgentClient.shared.fetchUsage(sessionId: id),
              sessionId == id, generation == streamGeneration, revision == usageRevision else { return }
        usage = snapshot
    }

    private func scheduleUsageRefresh() {
        let id = sessionId, generation = streamGeneration
        Task { [weak self] in
            guard let self, self.sessionId == id, self.streamGeneration == generation else { return }
            await self.refreshUsage()
        }
    }

    private func fail(_ detail: String) {
        flushAnswers(); resetStream()
        for index in items.indices where items[index].isRunning { items[index].isRunning = false; items[index].outcome = "unknown" }
        state = .failed; status = "Request stopped"
        items.append(.init(id: UUID().uuidString, kind: .error, title: "Agent run failed", detail: detail))
        scheduleUsageRefresh()
        if !surfaceVisible { scheduleShutdown() }
    }
}

struct AgentMemoryItem: Codable, Identifiable {
    let id: String
    let content: String
    let evidence: String
    let kind: String
    let source_session: String
    let created_at: Int
}
