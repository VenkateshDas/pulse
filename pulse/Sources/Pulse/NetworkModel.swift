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
        case failed(String)
    }

struct IPLocation: Decodable, Equatable {
    let ip: String
    let city: String
    let country: String
}

    private(set) var speedTestState: SpeedTestState = .idle
    private(set) var lastResult: SpeedTestResult?
    /// Most recent runs first, capped by `SpeedTestStore.maxCount`.
    private(set) var history: [SpeedTestResult] = []
    private(set) var locationAuthorized = false
    private(set) var ipLocation: IPLocation?

    /// How often the background test re-runs. Real bandwidth is consumed
    /// each run, so this stays coarse — not a live-polled metric.
    static let autoInterval: Duration = .seconds(30 * 60)
    /// Grace period after launch before the first automatic run, so it
    /// doesn't compete with app startup for bandwidth/CPU.
    static let initialDelay: Duration = .seconds(20)

    private let runner = SpeedTestRunner()
    private let store = SpeedTestStore()
    @ObservationIgnored private var autoLoop: Task<Void, Never>?
    @ObservationIgnored private var locationManager: CLLocationManager?

    override init() {
        super.init()
        history = store.results
        lastResult = history.first
    }

    /// Starts the recurring background test. Called once at app launch
    /// (`PulseApp`), independent of whether the Network page is open — the
    /// point is a cached result is always ready when the user does open it.
    func start() {
        guard autoLoop == nil else { return }
        autoLoop = Task { [weak self] in
            try? await Task.sleep(for: Self.initialDelay)
            while !Task.isCancelled {
                guard let self else { return }
                if ConnectionTypeMonitor.shared.current != .none {
                    await self.fetchIPLocation()
                    await self.performTest()
                }
                try? await Task.sleep(for: Self.autoInterval)
            }
        }
    }

    /// Requests Location authorization on first Network page visit (not app
    /// launch) — CoreWLAN needs it to return SSID/BSSID.
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

    /// Manual "Run Test" — same path as the auto-run, just user-triggered.
    func runSpeedTest() {
        guard speedTestState != .running else { return }
        Task { 
            await fetchIPLocation()
            await performTest() 
        }
    }

    /// Hotkey variant: runs the same test but hands the result back so the
    /// caller can post a notification. Returns nil on failure or if a test
    /// is already in flight.
    func runSpeedTestAwaiting() async -> SpeedTestResult? {
        guard speedTestState != .running else { return nil }
        await fetchIPLocation()
        await performTest()
        guard speedTestState == .idle else { return nil }
        return lastResult
    }

    func cancelSpeedTest() {
        Task { await runner.cancel() }
        speedTestState = .idle
    }

    private func performTest() async {
        speedTestState = .running
        do {
            let result = try await runner.run()
            store.record(result)
            history = store.results
            lastResult = result
            speedTestState = .idle
        } catch SpeedTestError.toolUnavailable {
            speedTestState = .failed("networkQuality isn't available on this Mac")
        } catch {
            speedTestState = .failed("Speed test failed — check your connection")
        }
    }

    private func fetchIPLocation() async {
        guard let url = URL(string: "https://ipwho.is/") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            ipLocation = try? JSONDecoder().decode(IPLocation.self, from: data)
        } catch {
            // Expected when offline — debug, not error.
            log.debug("IP location fetch failed: \(error, privacy: .public)")
        }
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
