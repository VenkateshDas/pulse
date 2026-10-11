import CoreLocation
import Foundation
import Observation
import PulseKit
import os

private let log = Logger(subsystem: "com.pulse.app", category: "Network")

/// Owns the Network page's speed test — auto-run on an interval and cached
/// to disk so the page always has a recent result to show, plus a manual
/// "Run Test" for an on-demand refresh. Live signal/throughput come from
/// `DashboardModel`'s `SystemSnapshot` — no separate polling loop for those,
/// matching the lazy-pane rule.
@MainActor
@Observable
final class NetworkModel: NSObject {
    enum SpeedTestState: Equatable {
        case idle
        case running
        case cancelling
        case cancelled
        case failed(String)
    }

    private(set) var speedTestState: SpeedTestState = .idle
    private(set) var lastResult: SpeedTestResult?
    /// Most recent runs first, capped by `SpeedTestStore.maxCount`.
    private(set) var history: [SpeedTestResult] = []
    private(set) var locationAuthorized = false
    private(set) var automaticTestsEnabled: Bool
    private let defaults: UserDefaults
    @ObservationIgnored private var testTask: Task<SpeedTestResult?, Never>?
    var isTesting: Bool { speedTestState == .running || speedTestState == .cancelling }

    /// How often the background test re-runs. Real bandwidth is consumed
    /// each run, so this stays coarse — not a live-polled metric.
    static let autoInterval: Duration = .seconds(30 * 60)
    /// Grace period after launch before the first automatic run, so it
    /// doesn't compete with app startup for bandwidth/CPU.
    static let initialDelay: Duration = .seconds(20)

    private let performTest: @Sendable () async throws -> SpeedTestResult
    private let store: SpeedTestStore
    var automaticTestingScheduled: Bool { autoLoop != nil }
    @ObservationIgnored private var autoLoop: Task<Void, Never>?
    @ObservationIgnored private var locationManager: CLLocationManager?

    init(defaults: UserDefaults = .standard, store: SpeedTestStore = SpeedTestStore(),
         performTest: (@Sendable () async throws -> SpeedTestResult)? = nil) {
        self.defaults = defaults
        self.store = store
        let runner = SpeedTestRunner()
        self.performTest = performTest ?? { try await runner.run() }
        automaticTestsEnabled = defaults.bool(forKey: "pulse.automaticSpeedTests")
        super.init()
        history = store.results
        lastResult = history.first
    }

    /// Starts recurring tests only after a persisted, explicit opt-in.
    func start() {
        guard automaticTestsEnabled, autoLoop == nil else { return }
        autoLoop = Task { [weak self] in
            try? await Task.sleep(for: Self.initialDelay)
            while !Task.isCancelled {
                guard let self, self.automaticTestsEnabled else { return }
                if ConnectionTypeMonitor.shared.current != .none {
                    _ = await self.runSpeedTestAwaiting()
                }
                try? await Task.sleep(for: Self.autoInterval)
            }
        }
    }

    func setAutomaticTests(_ enabled: Bool) {
        automaticTestsEnabled = enabled
        defaults.set(enabled, forKey: "pulse.automaticSpeedTests")
        autoLoop?.cancel()
        autoLoop = nil
        if enabled { start() }
    }

    /// Requests Location only after the explicit Show network name action.
    func requestLocationAuthorizationIfNeeded() {
        let manager = locationManager ?? {
            let manager = CLLocationManager()
            manager.delegate = self
            locationManager = manager
            return manager
        }()
        let status = manager.authorizationStatus
        locationAuthorized = status == .authorizedAlways
        guard status == .notDetermined else { return }
        manager.requestAlwaysAuthorization()
    }

    /// Mark the operation running before scheduling work to prevent duplicate clicks.
    func runSpeedTest() { _ = beginTest() }

    func runSpeedTestAwaiting() async -> SpeedTestResult? {
        guard let task = beginTest() else { return nil }
        return await task.value
    }

    private func beginTest() -> Task<SpeedTestResult?, Never>? {
        guard !isTesting else { return nil }
        speedTestState = .running
        let task = Task { [weak self] () -> SpeedTestResult? in
            guard let self else { return nil }
            defer { self.testTask = nil }
            do {
                let result = try await self.performTest()
                try Task.checkCancellation()
                self.store.record(result)
                self.history = self.store.results
                self.lastResult = result
                self.speedTestState = .idle
                return result
            } catch {
                if Task.isCancelled || self.speedTestState == .cancelling {
                    self.speedTestState = .cancelled
                } else {
                    self.speedTestState = .failed("The test could not finish. Check your connection and try again. Your previous result is still available.")
                }
                return nil
            }
        }
        testTask = task
        return task
    }

    func cancelSpeedTest() {
        guard isTesting else { return }
        speedTestState = .cancelling
        testTask?.cancel()
    }

}

extension NetworkModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.locationAuthorized = status == .authorizedAlways
        }
    }
}
