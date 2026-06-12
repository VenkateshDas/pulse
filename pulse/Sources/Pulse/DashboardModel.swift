import Darwin
import Foundation
import Observation
import PulseKit

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

        if let battery = snapshot.battery, !battery.isOnAC {
            if let lastUptime = lastIngestUptime {
                let duration = snapshot.uptime - lastUptime
                // Filter out sleep gaps (>10s between 2s samples)
                if duration > 0 && duration < 10 {
                    batteryHistory.addTimeOnBattery(duration, at: snapshot.timestamp)
                }
            }
        }
        lastIngestUptime = snapshot.uptime

        let rounded = Int(snapshot.cpuTotalPercent.rounded())
        if rounded != menuBarCPUPercent {
            menuBarCPUPercent = rounded
        }
        if visibleViews > 0 && !screenLocked {
            publishLatest()
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
        alerts = latestAlerts
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
