import AppKit
import Darwin
import Foundation
import Observation
import PulseKit
import UserNotifications

/// Which system notifications Pulse is allowed to post, independent of the OS
/// notification permission itself (that's the Permissions page's job — this
/// is per-notification-type opt-out for a user who granted permission but
/// wants fewer pings).
enum NotificationPreferences {
    private static let criticalKey = "PulseNotifyCriticalAlerts"
    private static let weeklyKey = "PulseNotifyWeeklyReport"

    static var notifyCriticalAlerts: Bool {
        get { UserDefaults.standard.object(forKey: criticalKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: criticalKey) }
    }

    static var notifyWeeklyReport: Bool {
        get { UserDefaults.standard.object(forKey: weeklyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: weeklyKey) }
    }
}

/// Owns the sampling loop and publishes the latest snapshot to the UI.
/// One loop for the whole app (menu bar + dashboard share it) — sampling
/// cost stays constant no matter how many views are open.
@MainActor
@Observable
final class DashboardModel {
    private(set) var snapshot: SystemSnapshot?
    private(set) var alerts: [PulseAlert] = []
    /// One-line verdict + culprit, recomputed every sample (F1).
    private(set) var diagnosis = Diagnosis(line: "Sampling…", severity: .clear,
                                           culpritPID: nil, factor: nil)
    /// Weighted 0–100 health score with per-factor breakdown (F1).
    private(set) var healthScore = HealthScore(value: 100, band: .excellent, breakdown: [:])
    /// Sustained-CPU anomaly history, newest first (F5).
    private(set) var recentAnomalies: [AnomalyRecord] = []
    /// Guided-focus items: up to 3 ranked, actionable things worth a look.
    private(set) var attentionItems: [AttentionItem] = []
    private(set) var cpuHistory: [Double] = []
    /// Minute-averaged CPU over the trailing 24h (nil = no data for that
    /// minute); persisted across launches by MinuteHistoryStore.
    private(set) var cpuDayHistory: [Double?] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var loadHistory: [Double] = []
    private(set) var tempHistory: [Double] = []
    private(set) var gpuTempHistory: [Double] = []
    private(set) var gpuUtilHistory: [Double] = []
    private(set) var networkInHistory: [Double] = []
    private(set) var networkOutHistory: [Double] = []
    private(set) var powerHistory: [Double] = []
    private(set) var batteryTrend: [BatteryHistoryStore.Entry] = []
    /// On-battery sessions (newest last): time on battery, charge drop, and
    /// per-app energy share. Published for the Health page.
    private(set) var batterySessions: [BatterySession] = []
    /// Rounded CPU for the menu bar label. Separate property so the status
    /// item only re-renders when the displayed integer actually changes —
    /// re-rendering it every sample costs measurable CPU.
    private(set) var menuBarCPUPercent: Int = 0
    /// Feedback from the last alert action ("Sent Quit to Chrome Helper").
    var actionFeedback: String?

    static let historyLength = 900
    static let activeInterval: Duration = .seconds(3)
    static let idleInterval: Duration = .seconds(5)
    /// Screen locked: nobody can see the menu bar or any window, so the loop
    /// drops to a slow keep-alive tick that only maintains battery bookkeeping.
    static let lockedInterval: Duration = .seconds(30)
    static let processEveryNTicks = 3
    /// No window open: the menu bar integer is the only consumer, so process
    /// enumeration (~every pid × proc_pidinfo) can run less often.
    static let idleProcessEveryNTicks = 5
    /// Sample gap accepted as continuous live use for battery crediting.
    /// Must exceed the longest sampling interval (locked, 30s) with margin.
    static let maxSampleGapSeconds: TimeInterval = 45
    /// Uptime gap above which an on-battery break is treated as real sleep
    /// (ends the session), not a transient sampling stall.
    static let sleepGapSeconds: TimeInterval = 90

    private let engine = PulseEngine()
    private var loop: Task<Void, Never>?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var lastProcesses: [ProcessSample] = []

    // Closed SwiftUI windows keep their NSHostingView alive, and every
    // observable mutation re-runs its layout (~4% CPU measured). So full
    // snapshots are only published while at least one view is visible;
    // the menu bar integer updates regardless.
    @ObservationIgnored private var visibleViews = 0
    /// Lock screen does NOT change NSWindow occlusion state, so it needs
    /// its own signal — otherwise the dashboard burns CPU all night.
    @ObservationIgnored private var screenLocked = false
    @ObservationIgnored private var cpuBuffer: [Double] = []
    @ObservationIgnored private let cpuDayStore = MinuteHistoryStore(
        fileURL: MinuteHistoryStore.defaultFileURL(metric: "cpu"))
    @ObservationIgnored private var memoryBuffer: [Double] = []
    @ObservationIgnored private var loadBuffer: [Double] = []
    @ObservationIgnored private var tempBuffer: [Double] = []
    @ObservationIgnored private var gpuTempBuffer: [Double] = []
    @ObservationIgnored private var gpuUtilBuffer: [Double] = []
    @ObservationIgnored private var networkInBuffer: [Double] = []
    @ObservationIgnored private var networkOutBuffer: [Double] = []
    @ObservationIgnored private var powerBuffer: [Double] = []
    @ObservationIgnored private var latest: SystemSnapshot?
    @ObservationIgnored private var latestAlerts: [PulseAlert] = []
    @ObservationIgnored private var latestDiagnosis = Diagnosis(
        line: "Sampling…", severity: .clear, culpritPID: nil, factor: nil)
    @ObservationIgnored private var latestHealth = HealthScore(
        value: 100, band: .excellent, breakdown: [:])
    /// Windowed CPU-anomaly detector (replaces the instant cpu-hog alert).
    @ObservationIgnored private var processWatcher = ProcessWatcher()
    /// Sustained-RSS-growth detector ("X leaking memory, restart it").
    @ObservationIgnored private var leakWatcher = LeakWatcher()
    @ObservationIgnored private let anomalyStore = AnomalyStore()
    @ObservationIgnored private let attentionEngine = AttentionEngine()
    @ObservationIgnored private var latestAttentionItems: [AttentionItem] = []
    @ObservationIgnored private let batteryHistory = BatteryHistoryStore()
    @ObservationIgnored private let batterySessionStore = BatterySessionStore()
    @ObservationIgnored private var lastIngestUptime: TimeInterval?
    /// Timestamp of the last valid on-battery sample, used to end a session at
    /// the right moment when a sleep gap (not a replug) interrupts it.
    @ObservationIgnored private var lastBatterySampleAt: Date?
    /// Wall-clock time of the last ingested sample — sleep detection pairs
    /// this with the (sleep-pausing) uptime delta.
    @ObservationIgnored private var lastIngestDate: Date?
    @ObservationIgnored private var displayAsleep = false
    /// Per-alert-id last fire time — enforces the 30-min notification cooldown
    /// so a sustained condition notifies once, not every 2s.
    @ObservationIgnored private var lastNotified: [String: Date] = [:]
    @ObservationIgnored private static let notificationCooldown: TimeInterval = 30 * 60
    /// Alert ids the user dismissed — hidden and not re-notified until the
    /// condition clears and recurs. Persisted across launches.
    @ObservationIgnored private var dismissedAlerts: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "PulseDismissedAlerts") ?? [])

    /// Hides an alert (from `alerts` and the sidebar/status severity) and
    /// silences its notifications until the condition clears and recurs.
    /// Called directly, and via `snoozeAttentionItem` when the id matches.
    func dismissAlert(id: String) {
        dismissedAlerts.insert(id)
        UserDefaults.standard.set(Array(dismissedAlerts), forKey: "PulseDismissedAlerts")
        alerts = latestAlerts.filter { !dismissedAlerts.contains($0.id) }
    }

    func viewAppeared() {
        visibleViews += 1
        publishLatest()
    }

    func viewDisappeared() {
        visibleViews = max(0, visibleViews - 1)
    }

    func start() {
        guard loop == nil else { return }
        observeScreenLock()
        observeDisplaySleep()
        requestNotificationAuthorization()
        
        // Trigger background backfill on launch: daily totals + reconstructed
        // unplug sessions (times + charge drop) from the pmset log.
        Task { [weak self] in
            guard let self else { return }
            await self.batteryHistory.backfillFromSystemLog()
            self.batteryTrend = self.batteryHistory.entries
            let sessions = await backfillBatterySessionsFromSystemLog()
            self.batterySessionStore.mergeBackfilled(sessions)
            self.batterySessions = self.batterySessionStore.allSessions
        }

        startSamplingLoop()
    }

    private func startSamplingLoop() {
        loop = Task { [weak self, engine] in
            while !Task.isCancelled {
                guard let self else { return }
                let locked = self.screenLocked
                let dashboardOpen = self.visibleViews > 0 && !locked
                self.tickCount += 1
                // Locked: skip process enumeration entirely — nobody can see
                // the result, and it's the most expensive part of a sample.
                let cadence = dashboardOpen ? Self.processEveryNTicks : Self.idleProcessEveryNTicks
                let needsProcesses = !locked && self.tickCount % cadence == 0

                let snapshot: SystemSnapshot
                if needsProcesses {
                    snapshot = await engine.sample()
                    self.lastProcesses = snapshot.topProcesses
                } else {
                    let lite = await engine.sampleLite()
                    snapshot = lite.withProcesses(self.lastProcesses)
                }

                await self.ingest(snapshot)
                let interval =
                    locked ? Self.lockedInterval
                    : dashboardOpen ? Self.activeInterval : Self.idleInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Sends SIGTERM — the polite quit. Returns user-facing feedback.
    func quitProcess(pid: Int32, name: String) {
        actionFeedback =
            kill(pid, SIGTERM) == 0
            ? "Sent Quit to \(name)"
            : "Couldn't quit \(name) — it may be a system process"
    }

    /// Hides an attention item until `until`. Removed from the published list
    /// immediately for instant feedback; persisted via `AttentionEngine`.
    func snoozeAttentionItem(_ id: String, until: Date) {
        attentionItems.removeAll { $0.id == id }
        // AttentionEngine ids are alert ids 1:1 (diagnosis-only ids are
        // synthetic and never match, so this is a harmless no-op for those).
        // Reuses the existing dismiss path so a snoozed item also stops
        // repeating its critical notification, not just the card.
        dismissAlert(id: id)
        Task { await attentionEngine.snooze(id, until: until) }
    }

    private func ingest(_ snapshot: SystemSnapshot) async {
        latest = snapshot
        // Locked ticks carry stale processes (enumeration is skipped), so the
        // whole alert/diagnosis/attention pipeline pauses — its outputs are
        // invisible until unlock anyway, and pausing it (plus notifications)
        // is what makes the 30s locked tick nearly free.
        if !screenLocked {
            // Replace AlertsEngine's instantaneous cpu-hog with a windowed one:
            // a process must stay hot for the full window before it alerts.
            var evaluated = AlertsEngine.evaluate(snapshot, ownPID: getpid())
            evaluated.removeAll { $0.id == "cpu-hog" }
            let sustained = processWatcher.ingest(
                snapshot.topProcesses.filter { $0.pid != getpid() }, now: snapshot.timestamp)
            if let hog = sustained.first {
                evaluated.insert(Self.windowedCPUAlert(hog), at: 0)
            }
            for anomaly in sustained where anomaly.isNewlySustained {
                anomalyStore.record(AnomalyRecord(
                    processName: anomaly.name, pid: anomaly.pid, cpuPercent: anomaly.cpuPercent,
                    date: snapshot.timestamp, sustainedSeconds: anomaly.sustainedSeconds))
            }
            let leaks = leakWatcher.ingest(
                snapshot.topProcesses.filter { $0.pid != getpid() }, now: snapshot.timestamp)
            if let leak = leaks.first {
                evaluated.insert(Self.memoryLeakAlert(leak), at: 0)
            }
            for leak in leaks where leak.isNewlySustained {
                anomalyStore.record(AnomalyRecord(
                    processName: leak.name, pid: leak.pid, cpuPercent: 0,
                    date: snapshot.timestamp, sustainedSeconds: leak.windowSeconds,
                    kind: .memoryLeak, growthBytes: leak.growthBytes))
            }
            latestAlerts = evaluated
            latestDiagnosis = DiagnosisEngine.evaluate(snapshot, leak: leaks.first)
            latestHealth = HealthScore.evaluate(snapshot)
            latestAttentionItems = await attentionEngine.currentItems(
                diagnosis: latestDiagnosis, alerts: latestAlerts)
            // A dismissed alert resets once its condition clears, so a fresh
            // occurrence shows (and notifies) again.
            let activeIDs = Set(latestAlerts.map(\.id))
            let cleared = dismissedAlerts.subtracting(activeIDs)
            if !cleared.isEmpty {
                dismissedAlerts.subtract(cleared)
                UserDefaults.standard.set(Array(dismissedAlerts), forKey: "PulseDismissedAlerts")
            }
            fireCriticalNotifications(latestAlerts)
        }

        append(snapshot.cpuTotalPercent, to: &cpuBuffer)
        cpuDayStore.record(snapshot.cpuTotalPercent, at: snapshot.timestamp)
        append(snapshot.memoryUsedFraction * 100, to: &memoryBuffer)
        append(snapshot.loadAverage1m, to: &loadBuffer)
        if let temp = [snapshot.sensors.cpuTempC, snapshot.sensors.gpuTempC]
            .compactMap({ $0 }).max()
        {
            append(temp, to: &tempBuffer)
        }
        if let gpuTemp = snapshot.sensors.gpuTempC {
            append(gpuTemp, to: &gpuTempBuffer)
        }
        if let gpu = snapshot.gpuUsage {
            append(gpu.deviceUtilization, to: &gpuUtilBuffer)
        }
        append(Double(snapshot.networkBytesInPerSecond), to: &networkInBuffer)
        append(Double(snapshot.networkBytesOutPerSecond), to: &networkOutBuffer)
        if let watts = snapshot.sensors.systemWatts {
            append(watts, to: &powerBuffer)
        }

        if let battery = snapshot.battery {
            let charge = battery.currentChargePercent
            let elapsed = lastIngestUptime.map { snapshot.uptime - $0 } ?? 0
            // `uptime` (systemUptime) pauses while the Mac sleeps, so a sleep
            // is invisible in `elapsed` — the wall clock keeps running. A wall
            // gap far beyond the awake gap means the Mac slept between samples.
            let wallElapsed =
                lastIngestDate.map { snapshot.timestamp.timeIntervalSince($0) } ?? 0
            let slept = wallElapsed - elapsed >= Self.sleepGapSeconds
            // A gap beyond the slowest sampling tick (or a sleep) means not
            // live use.
            let validDelta = elapsed > 0 && elapsed < Self.maxSampleGapSeconds && !slept

            if !battery.isOnAC {
                // Time-on-battery crediting: only count gaps that look like
                // live use (within one sampling tick of the slowest cadence).
                if validDelta {
                    batteryHistory.addTimeOnBattery(elapsed, at: snapshot.timestamp)
                }
                if batterySessionStore.liveSession == nil {
                    batterySessionStore.beginSession(charge: charge, at: snapshot.timestamp)
                    lastBatterySampleAt = snapshot.timestamp
                } else if validDelta {
                    let procs = snapshot.topProcesses.map {
                        (name: $0.name, cpuPercent: $0.cpuPercent)
                    }
                    batterySessionStore.accumulate(
                        processes: procs, elapsed: elapsed, charge: charge,
                        at: snapshot.timestamp, displayAsleep: displayAsleep)
                    lastBatterySampleAt = snapshot.timestamp
                } else if slept || elapsed >= Self.sleepGapSeconds {
                    // Slept while unplugged (lid closed). The Mac kept draining,
                    // so credit the wall-clock gap to the live session as
                    // screen-off time and keep it continuous — ending it here
                    // made lid-closed drain invisible and fragmented sessions.
                    // Split only when the gap is implausibly long or the charge
                    // rose (it was plugged in while asleep); ±1% tolerates
                    // charge-read noise without fragmenting.
                    let lastCharge = batterySessionStore.liveSession?.endCharge ?? charge
                    if wallElapsed < 24 * 3600, charge <= lastCharge + 1 {
                        batterySessionStore.accumulate(
                            processes: [], elapsed: wallElapsed, charge: charge,
                            at: snapshot.timestamp, displayAsleep: true)
                    } else {
                        batterySessionStore.endSession(
                            charge: charge, at: lastBatterySampleAt ?? snapshot.timestamp)
                        batterySessionStore.beginSession(charge: charge, at: snapshot.timestamp)
                    }
                    lastBatterySampleAt = snapshot.timestamp
                }
            } else if batterySessionStore.liveSession != nil {
                // Plugged back in — close the session.
                batterySessionStore.endSession(charge: charge, at: snapshot.timestamp)
            }

            // One capacity reading per day feeds the 60-day degradation chart.
            batteryHistory.recordCapacity(battery.capacityPercent, at: snapshot.timestamp)
        }
        lastIngestUptime = snapshot.uptime
        lastIngestDate = snapshot.timestamp

        let rounded = Int(snapshot.cpuTotalPercent.rounded())
        if rounded != menuBarCPUPercent {
            menuBarCPUPercent = rounded
        }
        if visibleViews > 0 && !screenLocked {
            publishLatest()
        }
    }

    /// UNUserNotificationCenter traps when the process has no bundle (bare
    /// SwiftPM `make run`) — every call stays behind this guard.
    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationAuthorization() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    /// Posts a system notification for each critical alert, rate-limited to
    /// once per 30 min per alert id so a sustained condition doesn't spam.
    private func fireCriticalNotifications(_ alerts: [PulseAlert]) {
        guard notificationsAvailable, NotificationPreferences.notifyCriticalAlerts else { return }
        let now = Date.now
        for alert in alerts where alert.severity == .critical && !dismissedAlerts.contains(alert.id) {
            if let last = lastNotified[alert.id], now.timeIntervalSince(last) < Self.notificationCooldown {
                continue
            }
            lastNotified[alert.id] = now
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.subtitle
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: "alert-\(alert.id)", content: content, trigger: nil))
        }
    }

    @ObservationIgnored private var displaySleepObservers: [Any] = []

    private func observeDisplaySleep() {
        let ws = NSWorkspace.shared.notificationCenter
        let sleepObs = ws.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: OperationQueue.main
        ) { [weak self] (_: Notification) in
            Task { @MainActor in self?.displayAsleep = true }
        }
        let wakeObs = ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: OperationQueue.main
        ) { [weak self] (_: Notification) in
            Task { @MainActor in self?.displayAsleep = false }
        }
        displaySleepObservers = [sleepObs, wakeObs]
    }

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenLocked = true }
        }
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.screenLocked = false
                if self.visibleViews > 0 { self.publishLatest() }
                // The loop may be mid-30s locked sleep — restart it so the
                // menu bar integer refreshes promptly on unlock.
                if self.loop != nil {
                    self.loop?.cancel()
                    self.startSamplingLoop()
                }
            }
        }
    }

    private func publishLatest() {
        snapshot = latest
        alerts = latestAlerts.filter { !dismissedAlerts.contains($0.id) }
        diagnosis = latestDiagnosis
        healthScore = latestHealth
        recentAnomalies = anomalyStore.records
        attentionItems = latestAttentionItems
        cpuHistory = cpuBuffer
        cpuDayHistory = cpuDayStore.series()
        memoryHistory = memoryBuffer
        loadHistory = loadBuffer
        tempHistory = tempBuffer
        gpuTempHistory = gpuTempBuffer
        gpuUtilHistory = gpuUtilBuffer
        networkInHistory = networkInBuffer
        networkOutHistory = networkOutBuffer
        powerHistory = powerBuffer
        batteryTrend = batteryHistory.entries
        batterySessions = batterySessionStore.allSessions
    }

    /// Builds the windowed CPU-hog alert card from a sustained anomaly.
    static func windowedCPUAlert(_ hog: ProcessAlert) -> PulseAlert {
        let mins = Int((hog.sustainedSeconds / 60).rounded())
        let duration = mins >= 1 ? "\(mins) min" : "\(Int(hog.sustainedSeconds))s"
        return PulseAlert(
            id: "cpu-hog",
            severity: .warning,
            symbol: "thermometer.high",
            title: "\(hog.name) has held \(Int(hog.cpuPercent))% CPU for \(duration)",
            subtitle: "pid \(hog.pid) · sustained, not a momentary spike",
            actions: [.quitProcess(pid: hog.pid, name: hog.name)])
    }

    /// Builds the memory-leak alert card from a leak verdict.
    static func memoryLeakAlert(_ leak: LeakAlert) -> PulseAlert {
        let growth = ByteFormat.string(UInt64(max(leak.growthBytes, 0)))
        return PulseAlert(
            id: "memory-leak",
            severity: .warning,
            symbol: "memorychip",
            title: "\(leak.name) grew \(growth) in \(Int(leak.windowSeconds / 60)) min",
            subtitle: "pid \(leak.pid) · steady growth, possible leak",
            actions: [.quitProcess(pid: leak.pid, name: leak.name)])
    }

    private func append(_ value: Double, to buffer: inout [Double]) {
        buffer.append(value)
        if buffer.count > Self.historyLength {
            buffer.removeFirst(buffer.count - Self.historyLength)
        }
    }
}
