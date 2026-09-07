import Foundation
import PulseKit

public struct SensorsDTO: Codable, Sendable {
    public let cpuTempC: Double?
    public let gpuTempC: Double?
    public let batteryTempC: Double?
    public let fanRPM: Double?
    public let fanCount: Int?
    public let systemWatts: Double?
    public let gpuDeviceUtilization: Double?
    public let gpuRendererUtilization: Double?
    public let batteryLevel: Int?
    public let batteryHealth: Int?
    public let batteryCycles: Int?

    public init(sensors: SensorReadings, gpu: GPUUsage?, battery: BatteryHealth?) {
        self.cpuTempC = sensors.cpuTempC.map { ($0 * 10).rounded() / 10 }
        self.gpuTempC = sensors.gpuTempC.map { ($0 * 10).rounded() / 10 }
        self.batteryTempC = sensors.batteryTempC.map { ($0 * 10).rounded() / 10 }
        self.fanRPM = sensors.fanRPM.map { $0.rounded() }
        self.fanCount = sensors.fanCount
        self.systemWatts = sensors.systemWatts.map { ($0 * 10).rounded() / 10 }
        self.gpuDeviceUtilization = gpu?.deviceUtilization
        self.gpuRendererUtilization = gpu?.rendererUtilization
        self.batteryLevel = battery?.currentChargePercent
        self.batteryHealth = battery?.capacityPercent
        self.batteryCycles = battery?.cycleCount
    }
}

public enum SensorsCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let snapshot = await PulseEngine(recordsHistory: false).sampleLite()
        let dto = SensorsDTO(sensors: snapshot.sensors, gpu: snapshot.gpuUsage, battery: snapshot.battery)

        if output.isJSON {
            output.emitJSON(dto)
        } else {
            output.printHeader("Hardware Sensors & Power")
            if let cpuT = dto.cpuTempC {
                output.printRow(label: "CPU Temperature", value: "\(cpuT) °C")
            }
            if let gpuT = dto.gpuTempC {
                output.printRow(label: "GPU Temperature", value: "\(gpuT) °C")
            }
            if let batT = dto.batteryTempC {
                output.printRow(label: "Battery Temp", value: "\(batT) °C")
            }
            if let rpm = dto.fanRPM {
                let fans = dto.fanCount.map { " (\($0) fan(s))" } ?? ""
                output.printRow(label: "Fan Speed", value: "\(Int(rpm)) RPM\(fans)")
            }
            if let w = dto.systemWatts {
                output.printRow(label: "Power Draw", value: "\(w) W")
            }
            if let dev = dto.gpuDeviceUtilization {
                output.printRow(label: "GPU Utilization", value: "\(dev)%")
            }
            if let bat = dto.batteryLevel {
                let hStr = dto.batteryHealth.map { ", Health: \($0)%" } ?? ""
                let cStr = dto.batteryCycles.map { ", \($0) cycles" } ?? ""
                output.printRow(label: "Battery Status", value: "\(bat)%\(hStr)\(cStr)")
            }
        }
    }
}
