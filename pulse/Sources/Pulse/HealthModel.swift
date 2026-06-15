import Foundation
import Observation
import PulseKit

/// Owns the Health page: battery state + 60-day capacity trend, startup
/// items, and on-demand benchmarks. Lazy pane — battery sampling runs only
/// while the page is on screen AND the window is visible.
@MainActor
@Observable
final class HealthModel {
    private(set) var battery: BatteryHealth?
    /// True once a sample came back nil — a desktop Mac, not "still loading".
    private(set) var batteryUnavailable = false
    private(set) var bluetoothDevices: [BluetoothDevice] = []
    private(set) var startupItems: [StartupItem] = []
    private(set) var benchmarkRunning = false
    private(set) var latestBenchmark: BenchmarkResult?
    private(set) var previousBenchmark: BenchmarkResult?
    /// All stored benchmark runs, oldest first. Used by Timeline to annotate days.
    private(set) var benchmarkHistory: [BenchmarkResult] = []
    /// Feedback from the last action ("Disabled Dropbox — applies at next login").
    var actionFeedback: String?

    /// Battery registry reads are ~2ms; 5s keeps the charge % feeling live.
    static let interval: Duration = .seconds(5)

    private let sampler = HealthSampler()
    private let btSampler = BluetoothSampler()
    private let benchmark = Benchmark()
    @ObservationIgnored private let benchmarkStore = BenchmarkStore()
    private var loop: Task<Void, Never>?
    @ObservationIgnored private var pageVisible = false
    @ObservationIgnored private var windowVisible = true
    /// Lock screen does NOT change NSWindow occlusion — gate on it directly.
    @ObservationIgnored private var screenLocked = false

    init() {
        latestBenchmark = benchmarkStore.latest
        previousBenchmark = benchmarkStore.previous
        benchmarkHistory = benchmarkStore.results
        observeScreenLock()
    }

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenLocked = true; self?.updateLoop() }
        }
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenLocked = false; self?.updateLoop() }
        }
    }

    // MARK: - Visibility

    func appeared() {
        pageVisible = true
        refreshStartupItems()
        updateLoop()
    }

    func disappeared() {
        pageVisible = false
        updateLoop()
    }

    func windowVisibilityChanged(_ visible: Bool) {
        windowVisible = visible
        updateLoop()
    }

    private func updateLoop() {
        let shouldRun = pageVisible && windowVisible && !screenLocked
        if shouldRun, loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.tick()
                    try? await Task.sleep(for: Self.interval)
                }
            }
        } else if !shouldRun {
            loop?.cancel()
            loop = nil
        }
    }

    private func tick() async {
        let sampled = await sampler.sampleBattery()
        battery = sampled
        batteryUnavailable = sampled == nil
        
        bluetoothDevices = await btSampler.sample(now: .now)
    }

    // MARK: - Startup items

    func refreshStartupItems() {
        Task {
            startupItems = await sampler.listStartupItems()
        }
    }

    func toggle(_ item: StartupItem) {
        Task {
            do {
                try await sampler.toggleStartupItem(item)
                actionFeedback =
                    "\(item.isEnabled ? "Disabled" : "Enabled") \(item.label) — applies at next login"
            } catch {
                actionFeedback = "Couldn't change \(item.label) — \(error.localizedDescription)"
            }
            startupItems = await sampler.listStartupItems()
        }
    }

    // MARK: - Benchmark

    func runBenchmark() {
        guard !benchmarkRunning else { return }
        benchmarkRunning = true
        Task {
            let result = await benchmark.run()
            benchmarkStore.record(result)
            latestBenchmark = benchmarkStore.latest
            previousBenchmark = benchmarkStore.previous
            benchmarkHistory = benchmarkStore.results
            benchmarkRunning = false
        }
    }
}
