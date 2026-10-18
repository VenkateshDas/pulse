import AppKit
import Observation
import PulseKit
import UserNotifications

struct AutomationRunRecord: Codable, Identifiable, Equatable {
    var id: String
    var automationID: String
    var sessionID: String
    var title: String
    var status: String
    var startedAt: Date
    var finishedAt: Date?
    var summary: String
}

struct AutomationOutcome: Sendable {
    var status: String
    var summary: String
}

@MainActor @Observable
final class AutomationModel {
    static let shared = AutomationModel()
    private(set) var automations: [PulseAutomation] = []
    private(set) var runs: [AutomationRunRecord] = []
    private(set) var status = ""
    var activeIDs: Set<String> { Set(tasks.keys) }

    private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var runner: (@MainActor (PulseAutomation, String, String) async -> AutomationOutcome)?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let scheduleTimers: Bool
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var storageError: String?

    private struct Saved: Codable {
        var automations: [PulseAutomation]
        var runs: [AutomationRunRecord]
    }
    enum Failure: LocalizedError {
        case invalid(String), unavailable(String)
        var errorDescription: String? {
            switch self { case .invalid(let text), .unavailable(let text): text }
        }
    }

    init(fileURL: URL? = nil, scheduleTimers: Bool = true) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse/automations.json")
        self.scheduleTimers = scheduleTimers
        load()
        if scheduleTimers { observeClockChanges() }
    }

    func configure(runner: @escaping @MainActor (PulseAutomation, String, String) async -> AutomationOutcome) {
        self.runner = runner
        reconcile()
    }

    func save(_ automation: PulseAutomation) throws {
        try requireStorage()
        var value = automation
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.instructions = value.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date.now
        guard UUID(uuidString: value.id) != nil, !value.title.isEmpty, value.title.count <= 80,
              !value.instructions.isEmpty, value.instructions.utf8.count <= 12_000,
              let next = value.schedule.next(after: now) else {
            throw Failure.invalid("Enter a title (1–80 characters), instructions (up to 12,000 bytes), and a valid future schedule.")
        }
        var updated = automations
        if let index = updated.firstIndex(where: { $0.id == value.id }) {
            let previous = updated[index]
            value.createdAt = previous.createdAt; value.runCount = previous.runCount
            value.lastRun = previous.lastRun; value.lastStatus = previous.lastStatus
            value.nextRun = value.enabled ? next : nil
            updated[index] = value
        } else {
            guard !updated.contains(where: { $0.title == value.title && $0.instructions == value.instructions && $0.schedule == value.schedule && $0.enabled == value.enabled }) else {
                throw Failure.invalid("An identical automation already exists. Edit it instead of creating another run schedule.")
            }
            guard updated.count < 100 else { throw Failure.invalid("Pulse supports up to 100 automations.") }
            value.createdAt = now; value.runCount = 0; value.lastRun = nil; value.lastStatus = nil
            value.nextRun = value.enabled ? next : nil
            updated.append(value)
        }
        try persist(updated, runs)
        automations = updated
        reconcile()
    }

    func toggle(_ id: String) throws {
        try requireStorage()
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return }
        var updated = automations
        updated[index].enabled.toggle()
        if updated[index].enabled {
            guard let next = updated[index].schedule.next(after: .now) else {
                throw Failure.invalid("Choose a future date before enabling this automation.")
            }
            updated[index].nextRun = next
        } else { updated[index].nextRun = nil }
        try persist(updated, runs)
        automations = updated
        reconcile()
    }

    func runNow(_ id: String, now: Date = .now) {
        guard storageError == nil, runner != nil,
              let automation = automations.first(where: { $0.id == id }) else { return }
        guard tasks[id] == nil else { status = "This automation is already running."; return }
        guard tasks.count < 2 else { status = "Two automations are running. Try again when one finishes."; return }
        claim(automation, now: now, scheduled: false)
        scheduleDeadline(now: now)
    }

    func cancel(_ id: String) { tasks[id]?.cancel() }

    /// Claims one catch-up occurrence, then advances directly to the next future deadline.
    func reconcile(now: Date = .now) {
        timer?.invalidate(); timer = nil
        guard storageError == nil, runner != nil else { return }
        let due = automations.filter { $0.enabled && ($0.nextRun.map { $0 <= now } ?? false) }
            .sorted { $0.nextRun! < $1.nextRun! }
        for automation in due {
            if tasks[automation.id] != nil {
                var updated = automations
                guard let index = updated.firstIndex(where: { $0.id == automation.id }) else { continue }
                updated[index].nextRun = automation.schedule.next(after: now)
                do { try persist(updated, runs); automations = updated }
                catch { return }
                continue
            }
            // Pending deadlines stay durable until an active run frees capacity.
            guard tasks.count < 2 else { continue }
            claim(automation, now: now, scheduled: true)
            if storageError != nil { return }
        }
        scheduleDeadline(now: now)
    }

    private func claim(_ automation: PulseAutomation, now: Date, scheduled: Bool) {
        guard let runner, tasks[automation.id] == nil,
              let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        let record = AutomationRunRecord(id: UUID().uuidString, automationID: automation.id, sessionID: UUID().uuidString,
                                         title: automation.title, status: "running", startedAt: now, summary: "")
        var updated = automations
        guard updated[index].runCount < Int.max else { suspend("Automation run count is invalid. Scheduling paused."); return }
        updated[index].runCount += 1; updated[index].lastRun = now; updated[index].lastStatus = "running"
        if scheduled || (updated[index].nextRun.map { $0 <= now } ?? false) { updated[index].nextRun = automation.schedule.next(after: now) }
        var history = runs; history.insert(record, at: 0)
        if history.count > 200, let expired = history.lastIndex(where: { $0.status != "running" }) {
            history.remove(at: expired)
        }
        do { try persist(updated, history) }
        catch { return }
        automations = updated; runs = history; status = ""
        tasks[automation.id] = Task { [weak self] in
            let outcome: AutomationOutcome
            if Task.isCancelled { outcome = .init(status: "cancelled", summary: "Stopped before starting.") }
            else { outcome = await runner(automation, record.sessionID, record.id) }
            guard let self else { return }
            self.finish(record, outcome: outcome, cancelled: Task.isCancelled, notify: automation.notifyOnCompletion)
        }
    }

    private func finish(_ record: AutomationRunRecord, outcome: AutomationOutcome, cancelled: Bool, notify: Bool) {
        tasks[record.automationID] = nil
        var history = runs
        guard let index = history.firstIndex(where: { $0.id == record.id }) else {
            suspend("Automation run history is missing. Scheduling paused."); return
        }
        history[index].status = cancelled ? "cancelled" : String(outcome.status.prefix(80))
        history[index].summary = String(decoding: outcome.summary.utf8.prefix(4000), as: UTF8.self)
        history[index].finishedAt = .now
        var updated = automations
        if let index = updated.firstIndex(where: { $0.id == record.automationID }) {
            updated[index].lastStatus = cancelled ? "cancelled" : String(outcome.status.prefix(80))
        }
        do { try persist(updated, history) }
        catch { return }
        automations = updated; runs = history
        if notify { postNotification(history[index]) }
        reconcile()
    }

    private func scheduleDeadline(now: Date) {
        timer?.invalidate(); timer = nil
        guard scheduleTimers, runner != nil, storageError == nil,
              let deadline = automations.filter({ $0.enabled })
                .compactMap(\.nextRun).filter({ $0 > now }).min() else { return }
        let timer = Timer(timeInterval: max(0.05, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        timer.tolerance = 1
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func requireStorage() throws {
        if let storageError { throw Failure.unavailable(storageError) }
    }

    private func persist(_ automations: [PulseAutomation], _ runs: [AutomationRunRecord]) throws {
        try requireStorage()
        do {
            let data = try JSONEncoder().encode(Saved(automations: automations, runs: runs))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            suspend("Automations could not be saved. Scheduling paused: \(error.localizedDescription)")
            throw error
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
            guard let size, size.intValue <= 4_000_000 else { throw Failure.invalid("Automation storage exceeds its size limit.") }
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: fileURL))
            guard saved.automations.count <= 100, saved.runs.count <= 200,
                  Set(saved.automations.map(\.id)).count == saved.automations.count,
                  Set(saved.runs.map(\.id)).count == saved.runs.count,
                  saved.automations.allSatisfy({
                      UUID(uuidString: $0.id) != nil && !$0.title.isEmpty && $0.title.count <= 80 &&
                      !$0.instructions.isEmpty && $0.instructions.utf8.count <= 12_000 && $0.runCount >= 0 &&
                      (0...23).contains($0.schedule.hour) && (0...59).contains($0.schedule.minute) &&
                      (1...7).contains($0.schedule.weekday) && TimeZone(identifier: $0.schedule.timezoneID) != nil &&
                      ($0.schedule.repeatRule != .once || $0.schedule.onceAt != nil)
                  }), saved.runs.allSatisfy({ UUID(uuidString: $0.id) != nil && UUID(uuidString: $0.automationID) != nil &&
                      UUID(uuidString: $0.sessionID) != nil && $0.summary.count <= 4000 && $0.title.count <= 80 && $0.status.count <= 80 }) else {
                throw Failure.invalid("Invalid automation storage records.")
            }
            var recovered = saved
            for index in recovered.runs.indices where recovered.runs[index].status == "running" {
                recovered.runs[index].status = "interrupted"; recovered.runs[index].finishedAt = .now
                recovered.runs[index].summary = "Pulse stopped before this run finished. Review its conversation before running again."
                if let task = recovered.automations.firstIndex(where: { $0.id == recovered.runs[index].automationID }) {
                    recovered.automations[task].lastStatus = "interrupted"
                }
            }
            if recovered.runs != saved.runs { try persist(recovered.automations, recovered.runs) }
            automations = recovered.automations; runs = recovered.runs
        } catch {
            suspend("Automations could not be loaded. Existing file preserved; scheduling paused: \(error.localizedDescription)")
        }
    }

    private func suspend(_ message: String) {
        storageError = message; status = message
        timer?.invalidate(); timer = nil
    }

    private func observeClockChanges() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, Notification.Name.NSSystemClockDidChange] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reconcile() }
            }
            observers.append((center, observer))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let observer = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        observers.append((workspace, observer))
    }

    func stop() {
        timer?.invalidate(); timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        for task in tasks.values { task.cancel() }
        runner = nil
    }

    private func postNotification(_ run: AutomationRunRecord) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = run.title; content.body = run.status == "completed" ? "Automation finished. Open Pulse to review." : "Automation \(run.status). Open Pulse to review."
            content.userInfo = ["sessionID": run.sessionID, "automationID": run.automationID]
            try? await center.add(UNNotificationRequest(identifier: "automation-\(run.id)", content: content, trigger: nil))
        }
    }
}
