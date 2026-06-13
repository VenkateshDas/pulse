import AppKit
import Foundation
import Observation
import PulseKit
import UserNotifications

/// Owns the scheduled deep clean: schedule state, history, the dry-run
/// preview, OS background scheduling, and completion notifications.
/// All blocking work (scan, stage) runs on detached background tasks.
@MainActor
@Observable
final class CleanModel {
    private(set) var schedule: CleanSchedule = .default()
    private(set) var history: [CleanRecord] = []
    /// Safe-tier items the next run would clean (dry-run preview).
    private(set) var preview: [CleanItem] = []
    private(set) var isPreviewLoading = false
    private(set) var isRunning = false
    /// Honesty line after a run ("1.2 GB staged in Vault…").
    private(set) var report: String?
    /// Vault sessions still restorable, keyed by id — drives history buttons.
    private(set) var restorableSessions: [UUID: VaultSession] = [:]
    /// Sessions restored this app run — history rows say "restored", not
    /// the dishonest "vault expired".
    private(set) var restoredSessionIDs: Set<UUID> = []

    private let scheduler = CleanScheduler()
    private let vault = SafetyVault(rootURL: SafetyVault.defaultRootURL())
    private var activity: NSBackgroundActivityScheduler?
    private var started = false

    /// Called once at app start: restores persisted schedule, registers the
    /// OS background activity, and runs any clean that came due while the
    /// app was closed.
    func start() {
        guard !started else { return }
        started = true
        Task {
            schedule = await scheduler.currentSchedule()
            history = await scheduler.history()
            refreshRestorable()
            registerBackgroundActivity()
            await checkDue()
        }
    }

    func appeared() {
        Task {
            schedule = await scheduler.currentSchedule()
            history = await scheduler.history()
            refreshRestorable()
        }
        loadPreview()
    }

    // MARK: - Schedule edits

    func setFrequency(_ frequency: CleanSchedule.Frequency) {
        var updated = schedule
        updated.frequency = frequency
        apply(updated)
    }

    func setTimePreference(_ preference: CleanSchedule.TimePreference) {
        var updated = schedule
        updated.timePreference = preference
        apply(updated)
    }

    func setAutoClean(_ enabled: Bool) {
        var updated = schedule
        updated.autoCleanSafeTier = enabled
        apply(updated)
    }

    func setNotify(_ enabled: Bool) {
        var updated = schedule
        updated.notifyOnCompletion = enabled
        apply(updated)
        if enabled { requestNotificationAuthorization() }
    }

    private func apply(_ updated: CleanSchedule) {
        schedule = updated  // optimistic; actor confirms below
        Task {
            await scheduler.setSchedule(updated)
            schedule = await scheduler.currentSchedule()
            registerBackgroundActivity()
        }
    }

    // MARK: - Running

    func runNow() {
        guard !isRunning else { return }
        isRunning = true
        report = nil
        Task.detached(priority: .userInitiated) { [scheduler] in
            let record = await scheduler.runNow(autoMode: false)
            await MainActor.run { [weak self] in
                self?.finish(record, notify: false)
            }
        }
    }

    /// Checks whether a scheduled run came due and executes it (auto mode
    /// only stages the safe tier — the schedule's own contract).
    private func checkDue() async {
        guard let record = await scheduler.scheduleIfNeeded() else { return }
        finish(record, notify: schedule.notifyOnCompletion)
    }

    private func finish(_ record: CleanRecord, notify: Bool) {
        isRunning = false
        history.insert(record, at: 0)
        report =
            record.itemsCleaned > 0
            ? "\(ByteFormat.string(record.bytesFreed)) staged in Vault — restore anytime for 7 days"
            : "Nothing to clean — the safe tier is already empty"
        Task {
            schedule = await scheduler.currentSchedule()
            refreshRestorable()
        }
        loadPreview(force: true)
        if notify, record.itemsCleaned > 0 {
            postNotification(
                title: "Pulse cleaned \(ByteFormat.string(record.bytesFreed))",
                body: "\(record.itemsCleaned) safe items staged in the Vault. Restore anytime for 7 days."
            )
        }
    }

    // MARK: - Preview

    func loadPreview(force: Bool = false) {
        guard !isPreviewLoading, force || preview.isEmpty else { return }
        isPreviewLoading = true
        Task.detached(priority: .utility) { [scheduler] in
            let items = await scheduler.preview()
            await MainActor.run { [weak self] in
                self?.preview = items
                self?.isPreviewLoading = false
            }
        }
    }

    var previewTotalBytes: UInt64 {
        preview.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Frees the dry-run preview results when the Clean page goes off screen —
    /// lazy eviction keeps the resident footprint down (P0-6).
    func releasePreview() {
        preview = []
    }

    // MARK: - History restore

    func restore(_ record: CleanRecord) {
        guard let session = restorableSessions[record.sessionID] else { return }
        Task.detached(priority: .userInitiated) { [vault] in
            let restored = (try? vault.restore(session)) ?? 0
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.report =
                    restored > 0
                    ? "Restored \(restored) items to their original locations"
                    : "Restore failed — vault contents may have been removed"
                if restored > 0 { self.restoredSessionIDs.insert(record.sessionID) }
                self.refreshRestorable()
            }
        }
    }

    func purge(_ record: CleanRecord) {
        guard let session = restorableSessions[record.sessionID] else { return }
        Task.detached(priority: .userInitiated) { [vault] in
            vault.purge(session)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.report = "Vault session purged — \(ByteFormat.string(session.totalBytes)) freed"
                self.refreshRestorable()
            }
        }
    }

    private func refreshRestorable() {
        let sessions = vault.sessions()
        restorableSessions = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    // MARK: - OS scheduling

    /// NSBackgroundActivityScheduler survives sleep/wake correctly — the
    /// spec's chosen trigger. Interval = half the schedule period so a due
    /// run is caught within hours, not a full period late.
    private func registerBackgroundActivity() {
        activity?.invalidate()
        let scheduler = NSBackgroundActivityScheduler(
            identifier: "com.pulse.app.scheduled-clean")
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.tolerance = 30 * 60
        scheduler.interval =
            switch schedule.frequency {
            case .daily: 6 * 3600
            case .weekly, .monthly: 12 * 3600
            }
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.checkDue()
                completion(.finished)
            }
        }
        activity = scheduler
    }

    // MARK: - Notifications

    /// UNUserNotificationCenter traps when the process has no bundle (bare
    /// SwiftPM `make run` builds) — every call must stay behind this guard.
    private var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func requestNotificationAuthorization() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        guard notificationsAvailable, schedule.notifyOnCompletion else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
