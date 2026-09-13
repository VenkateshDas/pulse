import Foundation
import PulseKit

public struct VitalsDTO: Codable, Sendable {
    public struct CPUInfo: Codable, Sendable {
        public let totalPercent: Double
        public let efficiencyPercent: Double?
        public let performancePercent: Double?
        public let loadAverage1m: Double
        public let perCore: [Double]
    }
    public struct MemoryInfo: Codable, Sendable {
        public let usedBytes: UInt64
        public let totalBytes: UInt64
        public let appBytes: UInt64
        public let wiredBytes: UInt64
        public let compressedBytes: UInt64
        public let swapUsedBytes: UInt64
        public let pressure: String
        public let usedFraction: Double
    }
    public struct DiskInfo: Codable, Sendable {
        public let freeBytes: UInt64
        public let totalBytes: UInt64
        public let usedFraction: Double
        public let weeklyGrowthBytes: Int64?
    }
    public struct NetworkInfo: Codable, Sendable {
        public let bytesInPerSec: UInt64
        public let bytesOutPerSec: UInt64
        public let connectionType: String
    }
    public struct GPUInfo: Codable, Sendable {
        public let deviceUtilization: Double?
        public let rendererUtilization: Double?
        public let tilerUtilization: Double?
    }
    public struct BatteryInfo: Codable, Sendable {
        public let levelPercent: Int?
        public let isCharging: Bool?
        public let healthPercent: Int?
        public let cycleCount: Int?
    }

    public let timestamp: Date
    public let uptimeSeconds: Double
    public let thermal: String
    public let cpu: CPUInfo
    public let memory: MemoryInfo
    public let disk: DiskInfo
    public let network: NetworkInfo
    public let gpu: GPUInfo
    public let battery: BatteryInfo?

    public init(snapshot: SystemSnapshot) {
        self.timestamp = snapshot.timestamp
        self.uptimeSeconds = snapshot.uptime
        self.thermal = "\(snapshot.thermal)"
        self.cpu = CPUInfo(
            totalPercent: (snapshot.cpuTotalPercent * 10).rounded() / 10,
            efficiencyPercent: snapshot.cpuEfficiencyPercent.map { ($0 * 10).rounded() / 10 },
            performancePercent: snapshot.cpuPerformancePercent.map { ($0 * 10).rounded() / 10 },
            loadAverage1m: (snapshot.loadAverage1m * 100).rounded() / 100,
            perCore: snapshot.cpuPerCore.map { ($0 * 10).rounded() / 10 }
        )
        self.memory = MemoryInfo(
            usedBytes: snapshot.memoryUsedBytes,
            totalBytes: snapshot.memoryTotalBytes,
            appBytes: snapshot.memoryAppBytes,
            wiredBytes: snapshot.memoryWiredBytes,
            compressedBytes: snapshot.memoryCompressedBytes,
            swapUsedBytes: snapshot.swapUsedBytes,
            pressure: "\(snapshot.memoryPressure)",
            usedFraction: (snapshot.memoryUsedFraction * 1000).rounded() / 1000
        )
        self.disk = DiskInfo(
            freeBytes: snapshot.diskFreeBytes,
            totalBytes: snapshot.diskTotalBytes,
            usedFraction: (snapshot.diskUsedFraction * 1000).rounded() / 1000,
            weeklyGrowthBytes: snapshot.diskWeeklyGrowthBytes
        )
        self.network = NetworkInfo(
            bytesInPerSec: snapshot.networkBytesInPerSecond,
            bytesOutPerSec: snapshot.networkBytesOutPerSecond,
            connectionType: "\(snapshot.connectionType)"
        )
        self.gpu = GPUInfo(
            deviceUtilization: snapshot.gpuUsage?.deviceUtilization,
            rendererUtilization: snapshot.gpuUsage?.rendererUtilization,
            tilerUtilization: snapshot.gpuUsage?.tilerUtilization
        )
        if let bat = snapshot.battery {
            self.battery = BatteryInfo(
                levelPercent: bat.currentChargePercent,
                isCharging: bat.isCharging,
                healthPercent: bat.capacityPercent,
                cycleCount: bat.cycleCount
            )
        } else {
            self.battery = nil
        }
    }
}

public enum VitalsCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let isLite = parser.hasFlag("lite")
        let engine = PulseEngine(recordsHistory: false)
        _ = isLite ? await engine.sampleLite() : await engine.sample(topProcessLimit: 10)
        try? await Task.sleep(for: .milliseconds(250))
        let snapshot = isLite ? await engine.sampleLite() : await engine.sample(topProcessLimit: 10)
        let dto = VitalsDTO(snapshot: snapshot)

        if output.isJSON {
            output.emitJSON(dto)
        } else {
            output.printHeader("Pulse System Vitals")
            output.printRow(label: "CPU Total", value: "\(dto.cpu.totalPercent)% (Load 1m: \(dto.cpu.loadAverage1m))")
            if let e = dto.cpu.efficiencyPercent, let p = dto.cpu.performancePercent {
                output.printRow(label: "E/P Split", value: "E: \(e)% · P: \(p)%")
            }
            let memUsedStr = CLIOutput.bytes(Int64(dto.memory.usedBytes))
            let memTotalStr = CLIOutput.bytes(Int64(dto.memory.totalBytes))
            let memPct = Int((dto.memory.usedFraction * 100).rounded())
            output.printRow(label: "Memory", value: "\(memUsedStr) / \(memTotalStr) (\(memPct)%) [Pressure: \(dto.memory.pressure)]")
            if dto.memory.swapUsedBytes > 0 {
                output.printRow(label: "Swap Used", value: CLIOutput.bytes(Int64(dto.memory.swapUsedBytes)))
            }
            let diskFreeStr = CLIOutput.bytes(Int64(dto.disk.freeBytes))
            let diskTotalStr = CLIOutput.bytes(Int64(dto.disk.totalBytes))
            let diskPct = Int((dto.disk.usedFraction * 100).rounded())
            output.printRow(label: "Disk", value: "\(diskFreeStr) free of \(diskTotalStr) (\(diskPct)% used)")
            if let growth = dto.disk.weeklyGrowthBytes {
                let sign = growth >= 0 ? "+" : ""
                output.printRow(label: "7d Growth", value: "\(sign)\(CLIOutput.bytes(growth))")
            }
            if let gpuDev = dto.gpu.deviceUtilization {
                output.printRow(label: "GPU Usage", value: "\(gpuDev)% (Renderer: \(dto.gpu.rendererUtilization ?? 0)%)")
            }
            output.printRow(label: "Thermal State", value: dto.thermal)
            if let bat = dto.battery, let lvl = bat.levelPercent {
                let chargingStr = bat.isCharging == true ? " (Charging)" : ""
                let healthStr = bat.healthPercent.map { " · Health: \($0)%" } ?? ""
                output.printRow(label: "Battery", value: "\(lvl)%\(chargingStr)\(healthStr)")
            }
            output.printRow(label: "Network I/O", value: "↓ \(CLIOutput.bytes(Int64(dto.network.bytesInPerSec)))/s · ↑ \(CLIOutput.bytes(Int64(dto.network.bytesOutPerSec)))/s")
        }
    }
}
