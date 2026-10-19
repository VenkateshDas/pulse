import AppKit
import Foundation
import PulseKit
import PulseCommands
import UniformTypeIdentifiers

struct InvestigationTask: Codable, Equatable { let title: String; let status: String }

extension AgentModel {
    func bootstrap(dashboard: DashboardModel) async {
        await AgentNativeBridge.shared.configureContext {
            guard let snapshot = dashboard.snapshot else { return "{\"unavailable\":\"No cached native snapshot\"}" }
            return (try? CLIOutput.json(VitalsDTO(snapshot: snapshot))) ?? "{}"
        }
        AutomationModel.shared.configure { [weak self] automation, sessionID, runID in
            guard let self else { return AutomationOutcome(status: "interrupted", summary: "Agent unavailable") }
            return await self.runAutomation(automation, runID: runID, sessionID: sessionID)
        }
    }

    func openPage(_ value: String) {
        guard ["conversation", "automations", "memory", "inbox", "search", "skills"].contains(value) else { return }
        if value != "conversation" { VoiceInput.shared.stop() }
        workspaceStatus = ""; VoiceInput.shared.status = ""
        page = value
        if value == "memory" { Task { await withWorkspace { await self.refreshMemory() } } }
        if value == "search" { Task { await searchChats(query: searchQuery, archived: searchArchived) } }
    }

    func openSession(_ id: String) async {
        guard !isBusy, UUID(uuidString: id) != nil else { return }
        await withWorkspace { await self.loadSession(id) }
    }

    func withWorkspace(_ work: () async -> Void) async {
        runtimeLeases += 1
        defer { runtimeLeases -= 1; if !surfaceVisible && !isBusy { scheduleShutdown() } }
        if !(await AgentClient.shared.checkStatus()).isOnline {
            if isBusy && state != .starting { workspaceStatus = "Wait for the current run to finish."; return }
            await start()
        }
        guard hasApiKey else { workspaceStatus = "Connect a model in Settings to continue."; return }
        await work()
    }

    func finishWorkspaceRefresh(session: String) {
        runtimeLeases += 1
        Task { [weak self] in
            guard let self else { return }
            defer { self.runtimeLeases -= 1; if !self.surfaceVisible && !self.isBusy { self.scheduleShutdown() } }
            await AgentClient.shared.awaitTitle(sessionId: session)
            self.sessions = (try? await AgentClient.shared.fetchSessions()) ?? self.sessions
            if self.sessionId == session { await self.refreshTasks(); await self.refreshUsage() }
        }
    }

    func refreshTasks() async {
        guard let id = sessionId else { return }
        struct Response: Decodable { let tasks: [InvestigationTask] }
        if let data = try? await AgentClient.shared.workspaceRequest(path: "/sessions/\(id)/tasks"),
           let response = try? JSONDecoder().decode(Response.self, from: data), sessionId == id {
            investigationTasks = response.tasks
        }
    }

    func searchChats(query: String, archived: Bool) async {
        guard query.count <= 200 else { return }
        searchQuery = query; searchArchived = archived
        await withWorkspace {
            do {
                let results = try await AgentClient.shared.fetchSessions(query: query, archived: archived)
                guard searchQuery == query, searchArchived == archived else { return }
                searchResults = results; workspaceStatus = results.isEmpty ? "No matching conversations." : ""
            } catch { workspaceStatus = "Search could not load. Reconnect and retry." }
        }
    }

    func updateSession(_ id: String, title: String? = nil, pinned: Bool? = nil, archived: Bool? = nil) async {
        guard !isBusy, UUID(uuidString: id) != nil, !workspaceBusy else { return }
        workspaceBusy = true; defer { workspaceBusy = false }
        await withWorkspace {
            do {
                var flags: [String: Bool] = [:]
                if let pinned { flags["pinned"] = pinned }; if let archived { flags["archived"] = archived }
                _ = try await AgentClient.shared.workspaceRequest(path: "/sessions/\(id)", method: "PATCH", body: title.map { ["title": $0] }, flags: flags)
                sessions = try await AgentClient.shared.fetchSessions()
                if archived == true && sessionId == id { newConversation() }
                if page == "search" { searchResults = try await AgentClient.shared.fetchSessions(query: searchQuery, archived: searchArchived) }
                workspaceStatus = archived == true ? "Conversation archived. Find it in Search → Archived." : "Conversation updated."
            } catch { workspaceStatus = "Conversation could not change. Wait for active runs, then retry." }
        }
    }

    func saveMemory(id: String?, content: String, evidence: String, kind: String, revision: Int) async {
        guard !isBusy, !workspaceBusy, id == nil || UUID(uuidString: id!) != nil else { return }
        workspaceBusy = true; defer { workspaceBusy = false }
        await withWorkspace {
            do {
                let data = try await AgentClient.shared.workspaceRequest(path: id.map { "/memory/\($0)" } ?? "/memory", method: id == nil ? "POST" : "PUT",
                    body: ["content": content, "evidence": evidence, "kind": kind, "revision": String(revision)])
                if id == nil, let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any], receipt["status"] as? String == "Remembered" { memoryUndoID = receipt["id"] as? String }
                await refreshMemory(); memoryStatus = "Memory saved. Changes apply to future requests."
            } catch { memoryStatus = "Could not save. Check memory is on, use at most 400 characters per field, and reload before editing changed entries." }
        }
    }

    func undoMemorySave() async {
        guard !isBusy, let id = memoryUndoID, UUID(uuidString: id) != nil else { return }
        await withWorkspace {
            do {
                _ = try await AgentClient.shared.workspaceRequest(path: "/memory/\(id)/undo", method: "POST", body: ["revision": "0"])
                memoryUndoID = nil; await refreshMemory(); memoryStatus = "Memory save undone."
            } catch { memoryStatus = "Memory changed or a run is active. Reload before removing it." }
        }
    }

    func saveInstructions(_ text: String) async {
        guard !isBusy, !workspaceBusy, text.count <= 4000, text.utf8.count <= 6000 else { return }
        workspaceBusy = true; defer { workspaceBusy = false }
        await withWorkspace {
            do {
                _ = try await AgentClient.shared.workspaceRequest(path: "/instructions", method: "PUT", body: ["text": text])
                instructions = text; memoryStatus = "Instructions saved for future requests."
            } catch { memoryStatus = "Instructions could not save. Stop active runs and retry." }
        }
    }

    func runAutomation(_ automation: PulseAutomation, runID: String, sessionID: String) async -> AutomationOutcome {
        runtimeLeases += 1
        defer { runtimeLeases -= 1; if !surfaceVisible && !isBusy { scheduleShutdown() } }
        if !(await AgentClient.shared.checkStatus()).isOnline {
            guard !isBusy || state == .starting else { return .init(status: "failed", summary: "Agent is starting another request. Run again when ready.") }
            await start()
        }
        guard hasApiKey else { return .init(status: "failed", summary: "Connect an AI provider in Settings, then run this automation again.") }
        var outcome = AutomationOutcome(status: "interrupted", summary: "Run ended before completion. Review its transcript before retrying.")
        return await withTaskCancellationHandler {
        do {
            try Task.checkCancellation()
            let bounded = String(decoding: automation.instructions.utf8.prefix(10_500), as: UTF8.self)
            let trimmed = automation.instructions.utf8.count > 10_500 ? "\n[Instructions trimmed to the request limit.]" : ""
            let message = "Scheduled Mac investigation: \(automation.title)\n\(bounded)\(trimmed)\nThis is an unattended run. Investigate using read-only native tools. Do not ask a blocking question or request plan approval; explain missing information and changes that need human review. Do not create schedules or save memory."
            for try await event in await AgentClient.shared.run(message: message, sessionId: sessionID, runId: runID, readOnly: true) {
                if Task.isCancelled { try? await AgentClient.shared.cancel(runId: runID); return .init(status: "cancelled", summary: "Stopped. Check the transcript for completed evidence collection.") }
                switch event.kind {
                case "answer.final": outcome.summary = String((event.payload["text"] ?? "").prefix(4000))
                case "tool.failed": if event.payload["status"] == "denied" { outcome.status = "needs_review" }
                case "approval.requested":
                    try? await AgentClient.shared.cancel(runId: runID)
                    return .init(status: "needs_review", summary: event.payload["title"] ?? "Your input is needed. Open this run and continue with fresh evidence.")
                case "run.failed": return .init(status: "failed", summary: event.payload["text"] ?? "Agent run failed.")
                case "run.cancelled": return .init(status: "cancelled", summary: "Run cancelled.")
                case "run.completed": if outcome.status != "needs_review" { outcome.status = "completed" }
                default: break
                }
            }
            if Task.isCancelled {
                try? await AgentClient.shared.cancel(runId: runID)
                return .init(status: "cancelled", summary: "Run stopped. Review the saved conversation.")
            }
            await AgentClient.shared.awaitTitle(sessionId: sessionID)
            sessions = (try? await AgentClient.shared.fetchSessions()) ?? sessions
            return outcome
        } catch {
            try? await AgentClient.shared.cancel(runId: runID)
            return .init(status: Task.isCancelled ? "cancelled" : "failed", summary: "Run stopped. Check its transcript before trying again.")
        }
        } onCancel: {
            Task { try? await AgentClient.shared.cancel(runId: runID) }
        }
    }

    func attachTextFile() {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .json, .sourceCode, .commaSeparatedText]
        panel.message = "Selected text is added to your draft. Review it before sending to your model. Maximum 8 KB."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 8000 else { workspaceStatus = "Choose a text file smaller than 8 KB."; return }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: 8001) ?? Data()
            guard data.count <= 8000, let text = String(data: data, encoding: .utf8), !text.contains("\0") else { workspaceStatus = "Choose a UTF-8 text file smaller than 8 KB."; return }
            let combined = draft + "\n\nAttached text (untrusted evidence):\n" + text
            guard combined.utf8.count <= 12_000 else { workspaceStatus = "Attachment and draft exceed 12 KB. Shorten your draft first."; return }
            setDraft(combined, publish: true); workspaceStatus = "Text attached to draft. Review before sending."
        } catch { workspaceStatus = "File could not load. Choose a readable UTF-8 text file." }
    }

    func exportAnswer() {
        guard let answer = items.last(where: { $0.kind == .answer }), !answer.detail.isEmpty else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Pulse report.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try answer.detail.write(to: url, atomically: true, encoding: .utf8); workspaceStatus = "Report exported." }
        catch { workspaceStatus = "Report could not save. Choose another location." }
    }
}
