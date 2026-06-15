import Foundation

public struct BluetoothDevice: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let batteryPercent: Int?
}

/// Polls connected Bluetooth devices for battery percentages.
/// Relies on `system_profiler SPBluetoothDataType` which can be slow,
/// so it caches results and only runs in a background task.
public actor BluetoothSampler {
    private var lastScan: Date = .distantPast
    private var cachedDevices: [BluetoothDevice] = []
    private var isScanning = false

    public init() {}

    public func sample(now: Date = .now) async -> [BluetoothDevice] {
        if now.timeIntervalSince(lastScan) < 30 || isScanning {
            return cachedDevices
        }
        isScanning = true
        defer { isScanning = false }

        // Run in detached task so it never blocks an actor executor
        let devices = await Task.detached(priority: .utility) {
            guard let out = try? await Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType"]) else {
                return [BluetoothDevice]()
            }
            return Self.parse(out.stdout)
        }.value

        self.cachedDevices = devices
        self.lastScan = now
        return devices
    }

    static func parse(_ output: String) -> [BluetoothDevice] {
        var devices: [BluetoothDevice] = []
        let lines = output.split(separator: "\n")
        
        var currentDevice: String?
        var isConnectedSection = false
        var deviceHasBattery = false
        var currentBattery: Int?

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Connected:" {
                isConnectedSection = true
                continue
            }
            if trimmed == "Not Connected:" {
                isConnectedSection = false
                continue
            }
            guard isConnectedSection else { continue }
            
            let indentCount = line.prefix(while: { $0 == " " }).count
            if indentCount == 10 {
                // New device block
                if let name = currentDevice, deviceHasBattery {
                    devices.append(BluetoothDevice(name: name, batteryPercent: currentBattery))
                }
                currentDevice = String(trimmed.dropLast(1)) // Remove trailing colon
                deviceHasBattery = false
                currentBattery = nil
            } else if indentCount > 10 {
                // Device property
                if trimmed.contains("Battery Level:") {
                    deviceHasBattery = true
                    if let percentStr = trimmed.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
                       let percent = Int(percentStr.dropLast().trimmingCharacters(in: .whitespaces)) {
                        currentBattery = percent
                    }
                }
            }
        }
        if let name = currentDevice, deviceHasBattery {
            devices.append(BluetoothDevice(name: name, batteryPercent: currentBattery))
        }
        return devices
    }
}
