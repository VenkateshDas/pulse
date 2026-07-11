import Foundation

/// One process as seen at sample time.
public struct ProcessSample: Sendable, Identifiable, Equatable {
    public let pid: Int32
    public let name: String
    /// CPU usage over the last sampling interval, 0–100 (can exceed 100 on multi-core).
    public let cpuPercent: Double
    public let residentBytes: UInt64
    /// Owning-app name from the first "*.app" bundle in the executable path
    /// (helpers live inside the parent bundle); nil when not app-hosted.
    public let appName: String?

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double, residentBytes: UInt64,
                appName: String? = nil) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.appName = appName
    }
}

/// Kernel memory pressure level (kern.memorystatus_vm_pressure_level).
public enum MemoryPressure: Int, Sendable, Equatable {
    case normal = 1
    case warning = 2
    case critical = 4

    public init(rawLevel: Int32) {
        self = MemoryPressure(rawValue: Int(rawLevel)) ?? .normal
    }
}

/// System thermal state (mirrors ProcessInfo.ThermalState, decoupled from Foundation).
public enum ThermalLevel: Int, Sendable, Comparable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A power-management assertion currently preventing system sleep.
public struct SleepAssertion: Sendable, Equatable {
    public let pid: Int32
    public let processName: String
    public let assertionName: String

    public init(pid: Int32, processName: String, assertionName: String) {
        self.pid = pid
        self.processName = processName
        self.assertionName = assertionName
    }
}

/// Point-in-time view of the whole system. Immutable value handed to the UI.
public struct SystemSnapshot: Sendable, Equatable {
    public let timestamp: Date

    /// Total CPU usage across all cores, 0–100.
    public let cpuTotalPercent: Double
    /// Per-core usage, 0–100 each.
    public let cpuPerCore: [Double]
    /// Average usage of efficiency cores, 0–100. nil when E/P split is unknown.
    public let cpuEfficiencyPercent: Double?
    /// Average usage of performance cores, 0–100. nil when E/P split is unknown.
    public let cpuPerformancePercent: Double?
    public let loadAverage1m: Double

    public let memoryUsedBytes: UInt64
    public let memoryAppBytes: UInt64
    public let memoryWiredBytes: UInt64
    public let memoryCompressedBytes: UInt64
    public let memoryTotalBytes: UInt64
    public let swapUsedBytes: UInt64
    public let memoryPressure: MemoryPressure

    public let diskFreeBytes: UInt64
    public let diskTotalBytes: UInt64
    /// Change in used disk space over the trailing week (positive = grew).
    /// nil until enough history has been recorded.
    public let diskWeeklyGrowthBytes: Int64?
    
    public let networkBytesInPerSecond: UInt64
    public let networkBytesOutPerSecond: UInt64
    public let connectionType: ConnectionType
    public let wifiInfo: WiFiInfo?

    public let thermal: ThermalLevel
    /// SMC sensor readings; fields are nil where this Mac lacks the key.
    public let sensors: SensorReadings
    public let sleepAssertions: [SleepAssertion]

    public let topProcesses: [ProcessSample]
    public let uptime: TimeInterval
    public let battery: BatteryHealth?
    public let gpuUsage: GPUUsage?

    public var memoryUsedFraction: Double {
        memoryTotalBytes == 0 ? 0 : Double(memoryUsedBytes) / Double(memoryTotalBytes)
    }

    public func withProcesses(_ processes: [ProcessSample]) -> SystemSnapshot {
        SystemSnapshot(
            timestamp: timestamp, cpuTotalPercent: cpuTotalPercent,
            cpuPerCore: cpuPerCore, cpuEfficiencyPercent: cpuEfficiencyPercent,
            cpuPerformancePercent: cpuPerformancePercent, loadAverage1m: loadAverage1m,
            memoryUsedBytes: memoryUsedBytes, memoryTotalBytes: memoryTotalBytes,
            memoryAppBytes: memoryAppBytes, memoryWiredBytes: memoryWiredBytes,
            memoryCompressedBytes: memoryCompressedBytes, swapUsedBytes: swapUsedBytes,
            memoryPressure: memoryPressure, diskFreeBytes: diskFreeBytes,
            diskTotalBytes: diskTotalBytes, diskWeeklyGrowthBytes: diskWeeklyGrowthBytes,
            networkBytesInPerSecond: networkBytesInPerSecond,
            networkBytesOutPerSecond: networkBytesOutPerSecond,
            connectionType: connectionType, wifiInfo: wifiInfo,
            thermal: thermal, sensors: sensors, sleepAssertions: sleepAssertions,
            topProcesses: processes, uptime: uptime, battery: battery, gpuUsage: gpuUsage)
    }

    public var diskUsedFraction: Double {
        diskTotalBytes == 0 ? 0 : Double(diskTotalBytes - diskFreeBytes) / Double(diskTotalBytes)
    }

    public init(
        timestamp: Date,
        cpuTotalPercent: Double,
        cpuPerCore: [Double],
        cpuEfficiencyPercent: Double?,
        cpuPerformancePercent: Double?,
        loadAverage1m: Double,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        memoryAppBytes: UInt64,
        memoryWiredBytes: UInt64,
        memoryCompressedBytes: UInt64,
        swapUsedBytes: UInt64,
        memoryPressure: MemoryPressure,
        diskFreeBytes: UInt64,
        diskTotalBytes: UInt64,
        diskWeeklyGrowthBytes: Int64?,
        networkBytesInPerSecond: UInt64,
        networkBytesOutPerSecond: UInt64,
        connectionType: ConnectionType = .none,
        wifiInfo: WiFiInfo? = nil,
        thermal: ThermalLevel,
        sensors: SensorReadings = SensorReadings(),
        sleepAssertions: [SleepAssertion],
        topProcesses: [ProcessSample],
        uptime: TimeInterval,
        battery: BatteryHealth? = nil,
        gpuUsage: GPUUsage? = nil
    ) {
        self.timestamp = timestamp
        self.cpuTotalPercent = cpuTotalPercent
        self.cpuPerCore = cpuPerCore
        self.cpuEfficiencyPercent = cpuEfficiencyPercent
        self.cpuPerformancePercent = cpuPerformancePercent
        self.loadAverage1m = loadAverage1m
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryAppBytes = memoryAppBytes
        self.memoryWiredBytes = memoryWiredBytes
        self.memoryCompressedBytes = memoryCompressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.memoryPressure = memoryPressure
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.diskWeeklyGrowthBytes = diskWeeklyGrowthBytes
        self.networkBytesInPerSecond = networkBytesInPerSecond
        self.networkBytesOutPerSecond = networkBytesOutPerSecond
        self.connectionType = connectionType
        self.wifiInfo = wifiInfo
        self.thermal = thermal
        self.sensors = sensors
        self.sleepAssertions = sleepAssertions
        self.topProcesses = topProcesses
        self.uptime = uptime
        self.battery = battery
        self.gpuUsage = gpuUsage
    }
}
