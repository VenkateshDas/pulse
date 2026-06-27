import Darwin
import Foundation

/// Single entry point for system sampling. One call produces one
/// `SystemSnapshot`; no subprocesses, no polling threads of its own.
/// Actor isolation protects the samplers' delta state.
public actor PulseEngine {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()
    private let processes = ProcessSampler()
    private let sleepAssertions = SleepAssertionReader()
    private let diskHistory = DiskHistoryStore()
    private let health = HealthSampler()
    private let gpu = GPUSampler()
    // lazy: key-space enumeration takes a beat; runs on first sample
    // (actor context, off the main thread), not at app init.
    private lazy var smc = SMCSensors()

    public init() {}

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
        let top = includeProcesses ? processes.sample(limit: topProcessLimit) : []
        let batteryHealth = await health.sampleBattery()
        let gpuUsage = await gpu.sample()

        let diskUsed = diskTotal > diskFree ? diskTotal - diskFree : 0
        diskHistory.record(usedBytes: diskUsed)

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
            diskWeeklyGrowthBytes: diskHistory.weeklyGrowth(currentUsedBytes: diskUsed),
            networkBytesInPerSecond: netIn,
            networkBytesOutPerSecond: netOut,
            thermal: ThermalLevel(rawValue: ProcessInfo.processInfo.thermalState.rawValue)
                ?? .nominal,
            sensors: smc?.sample() ?? SensorReadings(),
            sleepAssertions: sleepAssertions.sample(),
            topProcesses: top,
            uptime: ProcessInfo.processInfo.systemUptime,
            battery: batteryHealth,
            gpuUsage: gpuUsage
        )
    }
}
