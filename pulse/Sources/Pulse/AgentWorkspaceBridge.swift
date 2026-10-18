import AppKit
import Foundation
import PulseKit

extension AgentWebView.Coordinator {
    func handleWorkspace(action: String, body: [String: Any]) {
        switch action {
        case "page": if let page = body["page"] as? String { model.openPage(page) }
        case "search":
            guard let query = body["query"] as? String, query.count <= 200, let archived = body["archived"] as? Bool else { return }
            Task { await model.searchChats(query: query, archived: archived) }
        case "sessionUpdate":
            guard let id = body["id"] as? String, UUID(uuidString: id) != nil else { return }
            Task { await model.updateSession(id, title: body["title"] as? String, pinned: body["pinned"] as? Bool, archived: body["archived"] as? Bool) }
        case "memorySave":
            guard let content = body["content"] as? String, content.count <= 400, let evidence = body["evidence"] as? String, evidence.count <= 400,
                  let kind = body["kind"] as? String, ["preference", "lesson"].contains(kind) else { return }
            Task { await model.saveMemory(id: body["id"] as? String, content: content, evidence: evidence, kind: kind, revision: body["revision"] as? Int ?? 0) }
        case "memoryUndo": Task { await model.undoMemorySave() }
        case "instructionsSave":
            guard let text = body["text"] as? String, text.count <= 4000, text.utf8.count <= 6000 else { model.memoryStatus = "Use at most 4,000 characters and 6 KB of instructions."; return }
            Task { await model.saveInstructions(text) }
        case "automationSave": saveAutomation(body)
        case "automationToggle":
            guard let id = body["id"] as? String, UUID(uuidString: id) != nil else { return }
            do { try AutomationModel.shared.toggle(id) } catch { model.workspaceStatus = error.localizedDescription }
        case "automationRun": if let id = body["id"] as? String { AutomationModel.shared.runNow(id) }
        case "automationCancel": if let id = body["id"] as? String { AutomationModel.shared.cancel(id) }
        case "automationReview":
            guard !model.isBusy, let id = body["id"] as? String, let run = AutomationModel.shared.runs.first(where: { $0.id == id && $0.status == "needs_review" }) else { return }
            Task {
                await model.openSession(run.sessionID)
                model.setInvestigationOnly(false)
                model.setDraft("Review this scheduled investigation with me. Recheck current evidence and present a fresh preview before proposing any change.", publish: true)
                model.workspaceStatus = "Review draft ready. Send it to continue with fresh evidence."
            }
        case "specialist":
            guard !model.isBusy, let mode = body["mode"] as? String, ["general", "performance", "storage", "energy"].contains(mode) else { return }
            model.newConversation(); model.specialist = mode
            let drafts = ["performance": "Help me investigate why my Mac feels slow.", "storage": "Help me understand what is using storage and what I can safely review.", "energy": "Help me investigate battery use and energy pressure."]
            model.setDraft(drafts[mode] ?? "", publish: true); model.workspaceStatus = "\(mode.capitalized) focus selected."
        case "attach": model.attachTextFile()
        case "export": model.exportAnswer()
        case "voice":
            guard !model.isBusy else { return }
            if VoiceInput.shared.isRecording { VoiceInput.shared.stop() }
            else {
                VoiceInput.shared.start { [weak model] text in
                    guard let model else { return }
                    let draft = model.draft + (model.draft.isEmpty ? "" : "\n") + text
                    if draft.utf8.count <= 12_000 { model.setDraft(draft, publish: true); model.workspaceStatus = "Dictation added to draft. Review before sending." }
                    else { model.workspaceStatus = "Dictation exceeds the draft limit. Shorten your draft first." }
                }
            }
        default: break
        }
    }

    private func saveAutomation(_ body: [String: Any]) {
        guard let title = body["title"] as? String, title.count <= 80,
              let instructions = body["instructions"] as? String, instructions.utf8.count <= 12_000,
              let rule = body["repeatRule"] as? String, let repeatRule = PulseAutomationSchedule.RepeatRule(rawValue: rule),
              let hour = body["hour"] as? Int, let minute = body["minute"] as? Int, let weekday = body["weekday"] as? Int,
              let timezone = body["timezoneID"] as? String, timezone.count <= 100 else {
            model.workspaceStatus = "Check the schedule, name (80 characters) and instructions (12 KB)."; return
        }
        let onceAt = (body["onceAt"] as? String).flatMap { text -> Date? in
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        let schedule = PulseAutomationSchedule(repeatRule: repeatRule, hour: hour, minute: minute, weekday: weekday, timezoneID: timezone, onceAt: onceAt)
        var automation = PulseAutomation(title: title, instructions: instructions, schedule: schedule)
        if let id = body["id"] as? String {
            guard UUID(uuidString: id) != nil, AutomationModel.shared.automations.contains(where: { $0.id == id }) else { return }
            automation.id = id
            automation.enabled = AutomationModel.shared.automations.first(where: { $0.id == id })?.enabled ?? false
        }
        automation.notifyOnCompletion = body["notifyOnCompletion"] as? Bool ?? true
        do { try AutomationModel.shared.save(automation); model.workspaceStatus = "Automation saved." }
        catch { model.workspaceStatus = error.localizedDescription }
    }
}

extension AutomationModel {
    /// Closed, authenticated agent RPC; create/enable are separately approval-gated by the runtime.
    func agentCommand(_ arguments: [String]) -> (json: String, exitCode: Int32) {
        do {
            guard !Task.isCancelled else { return ("{\"error\":\"Run cancelled before automation command\"}", 1) }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            if arguments == ["automation", "list"] {
                let data = try encoder.encode(automations)
                return ("{\"automations\":" + (String(data: data, encoding: .utf8) ?? "[]") + "}", 0)
            }
            guard arguments.count == 3, arguments[2].utf8.count <= 4096,
                  let data = arguments[2].data(using: .utf8) else { return ("{\"error\":\"Invalid automation command\"}", 1) }
            if arguments[1] == "create" {
                struct Draft: Decodable { let title: String; let instructions: String; let repeatRule: String; let hour: Int; let minute: Int; let weekday: Int; let timezoneID: String; let onceAt: String? }
                let draft = try JSONDecoder().decode(Draft.self, from: data)
                guard let rule = PulseAutomationSchedule.RepeatRule(rawValue: draft.repeatRule), draft.instructions.utf8.count <= 2500 else { return ("{\"error\":\"Invalid automation fields\"}", 1) }
                let once = draft.onceAt.flatMap { ISO8601DateFormatter().date(from: $0) }
                let schedule = PulseAutomationSchedule(repeatRule: rule, hour: draft.hour, minute: draft.minute, weekday: draft.weekday, timezoneID: draft.timezoneID, onceAt: once)
                let automation = PulseAutomation(title: draft.title, instructions: draft.instructions, schedule: schedule)
                try save(automation)
                struct Receipt: Encodable { let status: String; let automation: PulseAutomation }
                let result = try encoder.encode(Receipt(status: "Created. Runs read-only while Pulse is open; provider charges may apply.", automation: automation))
                return (String(data: result, encoding: .utf8) ?? "{}", 0)
            }
            if arguments[1] == "set_enabled" {
                struct Update: Decodable { let id: String; let enabled: Bool }
                let update = try JSONDecoder().decode(Update.self, from: data)
                guard let current = automations.first(where: { $0.id == update.id }) else { return ("{\"error\":\"Automation unavailable\"}", 1) }
                if current.enabled != update.enabled { try toggle(update.id) }
                return ("{\"status\":\"Updated\"}", 0)
            }
            return ("{\"error\":\"Unknown automation command\"}", 1)
        } catch { return ("{\"error\":\"Automation could not save. Check fields and native Automations page for recovery.\"}", 1) }
    }
}
