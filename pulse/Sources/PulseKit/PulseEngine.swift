import Darwin
import Foundation

/// Single entry point for system sampling. One call produces one
/// `SystemSnapshot`; no subprocesses, no polling threads of its own.
/// Actor isolation protects the samplers' delta state.
public actor PulseEngine {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let diskActivity = DiskActivitySampler()
    private let network = NetworkSampler()
    private let processes = ProcessSampler()
    private let sleepAssertions = SleepAssertionReader()
    private let diskHistory = DiskHistoryStore()
    private let health = HealthSampler()
    private let gpu = GPUSampler()
    private let wifi = WiFiSampler()
    // lazy: key-space enumeration takes a beat; runs on first sample
    // (actor context, off the main thread), not at app init.
    private lazy var smc = SMCSensors()

    private let recordsHistory: Bool
    public init(recordsHistory: Bool = true) { self.recordsHistory = recordsHistory }

    /// Lightweight sample: skips process enumeration entirely.
    public func sampleLite() async -> SystemSnapshot {
        await sample(includeProcesses: false)
    }

    public func sample(topProcessLimit: Int = 30) async -> SystemSnapshot {
        await sample(includeProcesses: true, topProcessLimit: topProcessLimit)
    }

    private func sample(includeProcesses: Bool, topProcessLimit: Int = 30) async -> SystemSnapshot {
        let cpuSample = cpu.sample()
        let (app, wired, comp, swapUsed, pressure) = memory.sample()
        let memUsed = app + wired + comp
        let (diskFree, diskTotal) = disk.sample()
        let (netIn, netOut) = network.sample()
        let allProcesses = includeProcesses ? processes.sample(limit: Int.max) : []
        let top = Array(allProcesses.prefix(topProcessLimit))
        let contributors = Array(ProcessGrouper.group(allProcesses, byMemory: true).prefix(10))
        var activity = memory.activity
        if cpuSample.perCore.isEmpty { activity.unavailable.append("CPU counters unavailable") }
        if diskTotal == 0 { activity.unavailable.append("Disk capacity unavailable") }
        let io = diskActivity.sample()
        activity.diskReadBytesPerSecond = io.read
        activity.diskWriteBytesPerSecond = io.write
        if let error = io.error { activity.unavailable.append(error) }
        let batteryHealth = await health.sampleBattery()
        let gpuUsage = await gpu.sample()
        let connectionType = ConnectionTypeMonitor.shared.current
        let wifiInfo = connectionType == .wifi ? await wifi.sample() : nil

        let diskUsed = diskTotal > diskFree ? diskTotal - diskFree : 0
        if recordsHistory && diskTotal > 0 { diskHistory.record(usedBytes: diskUsed) }

        let assertions = sleepAssertions.sample()
        if let error = sleepAssertions.unavailable { activity.unavailable.append(error) }

        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)

        return SystemSnapshot(
            timestamp: Date(),
            cpuTotalPercent: cpuSample.total,
            cpuPerCore: cpuSample.perCore,
            cpuEfficiencyPercent: cpuSample.efficiency,
            cpuPerformancePercent: cpuSample.performance,
            loadAverage1m: load[0],
            memoryUsedBytes: memUsed,
            memoryTotalBytes: memory.totalBytes,
            memoryAppBytes: app,
            memoryWiredBytes: wired,
            memoryCompressedBytes: comp,
            swapUsedBytes: swapUsed,
            memoryPressure: pressure,
            diskFreeBytes: diskFree,
            diskTotalBytes: diskTotal,
            diskWeeklyGrowthBytes: diskTotal > 0 ? diskHistory.weeklyGrowth(currentUsedBytes: diskUsed) : nil,
            networkBytesInPerSecond: netIn,
            networkBytesOutPerSecond: netOut,
            connectionType: connectionType,
            wifiInfo: wifiInfo,
            thermal: ThermalLevel(rawValue: ProcessInfo.processInfo.thermalState.rawValue)
                ?? .nominal,
            sensors: smc?.sample() ?? SensorReadings(),
            sleepAssertions: assertions,
            topProcesses: top,
            uptime: ProcessInfo.processInfo.systemUptime,
            battery: batteryHealth,
            gpuUsage: gpuUsage, activity: activity,
            processCoverage: includeProcesses ? processes.coverage : ProcessCoverage(), memoryContributors: contributors,
            memoryProcesses: Array(allProcesses.sorted { $0.residentBytes > $1.residentBytes }.prefix(30))
        )
    }
}
