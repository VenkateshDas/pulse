import Darwin
import Foundation
import Observation
import PulseKit
import UserNotifications

/// Configurable menu-bar label metrics. Order here is display order.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu, memory, diskFree, temperature, battery
    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .diskFree: "Disk free"
        case .temperature: "Temperature"
        case .battery: "Battery"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .diskFree: "internaldrive"
        case .temperature: "thermometer.medium"
        case .battery: "battery.100"
        }
    }

    private static let key = "PulseMenuBarMetrics"

    static func loadVisible() -> Set<MenuBarMetric> {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else {
            return [.cpu]  // default: CPU only, matching prior behavior
        }
        let metrics = raw.compactMap(MenuBarMetric.init(rawValue:))
        return metrics.isEmpty ? [.cpu] : Set(metrics)
    }

    static func saveVisible(_ metrics: Set<MenuBarMetric>) {
        UserDefaults.standard.set(metrics.map(\.rawValue), forKey: key)
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
    private(set) var cpuHistory: [Double] = []
    /// Minute-averaged CPU over the trailing 24h (nil = no data for that
    /// minute); persisted across launches by MinuteHistoryStore.
    private(set) var cpuDayHistory: [Double?] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var loadHistory: [Double] = []
    private(set) var tempHistory: [Double] = []
    private(set) var gpuTempHistory: [Double] = []
    private(set) var networkInHistory: [Double] = []
    private(set) var networkOutHistory: [Double] = []
    private(set) var powerHistory: [Double] = []
    private(set) var batteryTrend: [BatteryHistoryStore.Entry] = []
    /// Rounded CPU for the menu bar label. Separate property so the status
    /// item only re-renders when the displayed integer actually changes —
    /// re-rendering it every sample costs measurable CPU.
    private(set) var menuBarCPUPercent: Int = 0
    /// Companion gated integers for the other configurable menu-bar metrics.
    /// Each updates only when its displayed value changes (no jitter).
    private(set) var menuBarMemPercent: Int = 0
    private(set) var menuBarDiskFreeGB: Int = 0
    private(set) var menuBarTempC: Int = 0
    private(set) var menuBarBatteryPercent: Int = 0
    /// Which metrics the menu-bar label shows, in display order. Persisted.
    var menuBarMetrics: Set<MenuBarMetric> = MenuBarMetric.loadVisible() {
        didSet { MenuBarMetric.saveVisible(menuBarMetrics) }
    }
    /// Feedback from the last alert action ("Sent Quit to Chrome Helper").
    var actionFeedback: String?

    static let historyLength = 900 // 900 samples * 2s = 30 minutes
    static let interval: Duration = .seconds(2)

    private let engine = PulseEngine()
    private var loop: Task<Void, Never>?

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
    @ObservationIgnored private var networkInBuffer: [Double] = []
    @ObservationIgnored private var networkOutBuffer: [Double] = []
    @ObservationIgnored private var powerBuffer: [Double] = []
    @ObservationIgnored private var latest: SystemSnapshot?
    @ObservationIgnored private var latestAlerts: [PulseAlert] = []
    @ObservationIgnored private let batteryHistory = BatteryHistoryStore()
    @ObservationIgnored private var lastIngestUptime: TimeInterval?
    /// Per-alert-id last fire time — enforces the 30-min notification cooldown
    /// so a sustained condition notifies once, not every 2s.
    @ObservationIgnored private var lastNotified: [String: Date] = [:]
    @ObservationIgnored private static let notificationCooldown: TimeInterval = 30 * 60
    /// Alert ids the user dismissed — hidden and not re-notified until the
    /// condition clears and recurs. Persisted across launches.
    @ObservationIgnored private var dismissedAlerts: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "PulseDismissedAlerts") ?? [])

    /// Hides an alert card and silences its notifications until it recurs.
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
        requestNotificationAuthorization()
        
        // Trigger background backfill on launch
        Task { [weak self] in
            guard let self else { return }
            await self.batteryHistory.backfillFromSystemLog()
            self.batteryTrend = self.batteryHistory.entries
        }

        loop = Task { [weak self, engine] in
            while !Task.isCancelled {
                let snapshot = await engine.sample()
                guard let self else { return }
                self.ingest(snapshot)
                try? await Task.sleep(for: Self.interval)
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

    private func ingest(_ snapshot: SystemSnapshot) {
        latest = snapshot
        latestAlerts = AlertsEngine.evaluate(snapshot, ownPID: getpid())
        // A dismissed alert resets once its condition clears, so a fresh
        // occurrence shows (and notifies) again.
        let activeIDs = Set(latestAlerts.map(\.id))
        let cleared = dismissedAlerts.subtracting(activeIDs)
        if !cleared.isEmpty {
            dismissedAlerts.subtract(cleared)
            UserDefaults.standard.set(Array(dismissedAlerts), forKey: "PulseDismissedAlerts")
        }
        fireCriticalNotifications(latestAlerts)

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
        append(Double(snapshot.networkBytesInPerSecond), to: &networkInBuffer)
        append(Double(snapshot.networkBytesOutPerSecond), to: &networkOutBuffer)
        if let watts = snapshot.sensors.systemWatts {
            append(watts, to: &powerBuffer)
        }

        if let battery = snapshot.battery {
            if !battery.isOnAC, let lastUptime = lastIngestUptime {
                let duration = snapshot.uptime - lastUptime
                // Filter out sleep gaps (>10s between 2s samples)
                if duration > 0 && duration < 10 {
                    batteryHistory.addTimeOnBattery(duration, at: snapshot.timestamp)
                }
            }
            // One capacity reading per day feeds the 60-day degradation chart.
            batteryHistory.recordCapacity(battery.capacityPercent, at: snapshot.timestamp)
        }
        lastIngestUptime = snapshot.uptime

        let rounded = Int(snapshot.cpuTotalPercent.rounded())
        if rounded != menuBarCPUPercent {
            menuBarCPUPercent = rounded
        }
        let mem = Int((snapshot.memoryUsedFraction * 100).rounded())
        if mem != menuBarMemPercent { menuBarMemPercent = mem }
        let diskGB = Int(snapshot.diskFreeBytes / 1_000_000_000)
        if diskGB != menuBarDiskFreeGB { menuBarDiskFreeGB = diskGB }
        let temp = Int(([snapshot.sensors.cpuTempC, snapshot.sensors.gpuTempC]
            .compactMap { $0 }.max() ?? 0).rounded())
        if temp != menuBarTempC { menuBarTempC = temp }
        let batt = snapshot.battery?.currentChargePercent ?? 0
        if batt != menuBarBatteryPercent { menuBarBatteryPercent = batt }
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
        guard notificationsAvailable else { return }
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
            }
        }
    }

    private func publishLatest() {
        snapshot = latest
        alerts = latestAlerts.filter { !dismissedAlerts.contains($0.id) }
        cpuHistory = cpuBuffer
        cpuDayHistory = cpuDayStore.series()
        memoryHistory = memoryBuffer
        loadHistory = loadBuffer
        tempHistory = tempBuffer
        gpuTempHistory = gpuTempBuffer
        networkInHistory = networkInBuffer
        networkOutHistory = networkOutBuffer
        powerHistory = powerBuffer
        batteryTrend = batteryHistory.entries
    }

    private func append(_ value: Double, to buffer: inout [Double]) {
        buffer.append(value)
        if buffer.count > Self.historyLength {
            buffer.removeFirst(buffer.count - Self.historyLength)
        }
    }
}
