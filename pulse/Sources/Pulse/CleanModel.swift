import AppKit
import PulseKit
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class CleanModel {
    private(set) var schedule: CleanSchedule = .default()
    private(set) var preview: [CleanItem] = []
    private(set) var isPreviewLoading = false
    private(set) var isRunning = false
    private(set) var report: String?

    private let scheduler = CleanScheduler()
    private var activity: NSBackgroundActivityScheduler?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task {
            schedule = await scheduler.currentSchedule()
            registerBackgroundActivity()
            await checkDue()
        }
    }

    func appeared() {
        Task {
            schedule = await scheduler.currentSchedule()
        }
        loadPreview()
    }

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
        schedule = updated
        Task {
            await scheduler.setSchedule(updated)
            schedule = await scheduler.currentSchedule()
            registerBackgroundActivity()
        }
    }

    func runNow() {
        guard !isRunning else { return }
        isRunning = true
        report = nil
        Task {
            let result = await scheduler.runNow(autoMode: false)
            self.finish(itemsCleaned: result.itemsCleaned, bytesFreed: result.bytesFreed, notify: false)
        }
    }

    private func checkDue() async {
        guard let result = await scheduler.scheduleIfNeeded() else { return }
        finish(itemsCleaned: result.itemsCleaned, bytesFreed: result.bytesFreed, notify: schedule.notifyOnCompletion)
    }

    private func finish(itemsCleaned: Int, bytesFreed: UInt64, notify: Bool) {
        isRunning = false
        report =
            itemsCleaned > 0
            ? "Moved \(itemsCleaned) items (\(ByteFormat.string(bytesFreed))) to Trash"
            : "Nothing to clean — the safe tier is already empty"
        Task {
            schedule = await scheduler.currentSchedule()
        }
        loadPreview(force: true)
        if notify, itemsCleaned > 0 {
            postNotification(
                title: "Pulse cleaned \(ByteFormat.string(bytesFreed))",
                body: "\(itemsCleaned) safe items moved to Trash."
            )
        }
    }

    func loadPreview(force: Bool = false) {
        guard !isPreviewLoading, force || preview.isEmpty else { return }
        isPreviewLoading = true
        Task {
            let items = await scheduler.preview()
            self.preview = items
            self.isPreviewLoading = false
        }
    }

    var previewTotalBytes: UInt64 {
        preview.reduce(0) { $0 + $1.sizeBytes }
    }

    func releasePreview() {
        preview = []
    }

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
            Task {
                await self?.checkDue()
                completion(.finished)
            }
        }
        activity = scheduler
    }

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
