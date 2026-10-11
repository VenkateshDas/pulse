import Darwin
import Foundation
import Observation
import PulseKit

/// Owns the Monitor page: process list/tree, the selected-process detail
/// (with its own 60-tick CPU history), and per-interface network rates.
/// Sampling runs only while the page is on screen AND the window is
/// visible — the lazy-pane rule; an idle Monitor page costs nothing.
@MainActor
@Observable
final class MonitorModel {
    private(set) var rows: [ProcessExtendedSample] = []
    private(set) var coverage = ProcessCoverage()
    private(set) var roots: [ProcessNode] = []
    private(set) var networks: [NetworkSample] = []
    /// 60-tick rate history (bytes/sec) summed across interfaces.
    private(set) var networkInHistory: [Double] = []
    private(set) var networkOutHistory: [Double] = []
    private(set) var selectedPID: Int32?
    /// 60-tick CPU history for the selected process only.
    private(set) var selectedCPUHistory: [Double] = []
    /// Current selected identity and feedback from a graceful application quit.
    private(set) var selectedIdentity: ProcessIdentity?
    var actionFeedback: String?

    var sortKey: MonitorEngine.SortKey = .cpu { didSet { resample() } }
    var sortAscending = false { didSet { resample() } }
    var groupMode = false
    var treeMode = false { didSet { resample() } }
    var filter = ""

    static let historyLength = 60  // 60 ticks * 2s = 2 minutes
    static let interval: Duration = .seconds(2)

    private let engine = MonitorEngine()
    private var loop: Task<Void, Never>?
    @ObservationIgnored private var pageVisible = false
    @ObservationIgnored private var windowVisible = true
    /// Lock screen does NOT change NSWindow occlusion, so it needs its own
    /// signal — otherwise this pane keeps sampling all night while locked.
    @ObservationIgnored private var screenLocked = false
    @ObservationIgnored private var observingLock = false
    @ObservationIgnored private var byPID: [Int32: ProcessExtendedSample] = [:]
    @ObservationIgnored private var parents: [Int32: Int32] = [:]
    @ObservationIgnored private var names: [Int32: String] = [:]

    // MARK: - Visibility

    func appeared() {
        observeScreenLock()
        pageVisible = true
        updateLoop()
    }

    func disappeared() {
        pageVisible = false
        updateLoop()
    }

    /// Mirrors NSWindow occlusion (lock screen / hidden window) so the
    /// page stops sampling when nobody can see it.
    func windowVisibilityChanged(_ visible: Bool) {
        windowVisible = visible
        updateLoop()
    }

    private func observeScreenLock() {
        guard !observingLock else { return }
        observingLock = true
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

    // MARK: - Sampling

    private func tick() async {
        let sampled = await engine.sample(sortKey: sortKey, ascending: sortAscending)
        let sampledRoots = treeMode ? await engine.tree() : []
        let sampledParents = await engine.parents()
        let sampledNames = await engine.names()
        let sampledNetworks = await engine.networkDeltas()

        coverage = await engine.coverage
        rows = sampled
        roots = sampledRoots
        parents = sampledParents
        names = sampledNames
        byPID = Dictionary(uniqueKeysWithValues: sampled.map { ($0.pid, $0) })
        networks = sampledNetworks

        append(
            sampledNetworks.reduce(0) { $0 + Double($1.bytesIn) }, to: &networkInHistory)
        append(
            sampledNetworks.reduce(0) { $0 + Double($1.bytesOut) }, to: &networkOutHistory)

        if let pid = selectedPID {
            if let row = byPID[pid] {
                let current = ProcessIdentity.read(pid)
                if current?.startToken != selectedIdentity?.startToken { selectedCPUHistory = [] }
                selectedIdentity = current
                append(row.cpuPercent, to: &selectedCPUHistory)
            } else {
                // Process exited — keep the selection honest.
                selectedPID = nil
                selectedCPUHistory = []
            }
        }
    }

    /// Re-sorts/rebuilds immediately on a control change instead of waiting
    /// out the 2s tick — the page must feel responsive to its own controls.
    private func resample() {
        guard loop != nil else { return }
        Task { await tick() }
    }

    // MARK: - Selection

    func select(_ pid: Int32) {
        guard pid != selectedPID else { selectedIdentity = ProcessIdentity.read(pid); return }
        selectedPID = pid
        selectedIdentity = ProcessIdentity.read(pid)
        selectedCPUHistory = byPID[pid].map { [$0.cpuPercent] } ?? []
    }

    var selectedProcess: ProcessExtendedSample? {
        selectedPID.flatMap { byPID[$0] }
    }

    /// Parent process name for the detail card, when the parent is known.
    var selectedParentName: String? {
        guard let pid = selectedPID, let ppid = parents[pid], ppid > 0 else { return nil }
        return byPID[ppid]?.name ?? names[ppid] ?? "PID \(ppid)"
    }

    /// Flat rows matching the filter (case-insensitive substring).
    var filteredRows: [ProcessExtendedSample] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var appRows: [ProcessExtendedSample] {
        Dictionary(grouping: filteredRows, by: { $0.appName ?? $0.name }).map { name, members in
            let top = members.max { sortKey == .memory ? $0.residentBytes < $1.residentBytes : $0.cpuPercent < $1.cpuPercent }!
            return ProcessExtendedSample(pid: top.pid, name: name + " (\(members.count))",
                cpuPercent: members.reduce(0) { $0 + $1.cpuPercent }, residentBytes: members.reduce(0) { $0 + $1.residentBytes },
                virtualBytes: members.reduce(0) { $0 + $1.virtualBytes }, threadCount: members.reduce(0) { $0 + $1.threadCount },
                pageFaultRate: members.reduce(0) { $0 + $1.pageFaultRate }, appName: name)
        }.sorted {
            switch sortKey {
            case .cpu: return sortAscending ? $0.cpuPercent < $1.cpuPercent : $0.cpuPercent > $1.cpuPercent
            case .memory: return sortAscending ? $0.residentBytes < $1.residentBytes : $0.residentBytes > $1.residentBytes
            case .threads: return sortAscending ? $0.threadCount < $1.threadCount : $0.threadCount > $1.threadCount
            case .pageFaults: return sortAscending ? $0.pageFaultRate < $1.pageFaultRate : $0.pageFaultRate > $1.pageFaultRate
            case .name: return sortAscending ? $0.name < $1.name : $0.name > $1.name
            case .pid: return sortAscending ? $0.pid < $1.pid : $0.pid > $1.pid
            }
        }
    }

    // MARK: - Actions

    /// Native application quit, bound to the inspected start token.
    func quitProcess(pid: Int32, name: String) {
        guard let identity = selectedIdentity, identity.pid == pid else {
            actionFeedback = "Inspect this application again before quitting"; return
        }
        Task {
            do {
                let result = try await AppQuit.run(pid: pid, startToken: identity.startToken, dryRun: false)
                actionFeedback = result.message
            } catch { actionFeedback = error.localizedDescription }
        }
    }

    private func append(_ value: Double, to buffer: inout [Double]) {
        buffer.append(value)
        if buffer.count > Self.historyLength {
            buffer.removeFirst(buffer.count - Self.historyLength)
        }
    }
}
