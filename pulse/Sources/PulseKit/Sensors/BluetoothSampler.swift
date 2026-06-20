import Foundation
import IOBluetooth
import IOKit

public struct BluetoothDevice: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let batteryPercent: Int?
}

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

        let devices = await Task.detached(priority: .utility) {
            return Self.getConnectedDevices()
        }.value

        self.cachedDevices = devices
        self.lastScan = now
        return devices
    }

    private static func getConnectedDevices() -> [BluetoothDevice] {
        // macOS 26+ crashes without NSBluetoothAlwaysUsageDescription in Info.plist.
        // SwiftPM debug builds have no plist, so check the key exists before calling.
        if Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") == nil {
            return []
        }

        var devices: [BluetoothDevice] = []

        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        
        for device in paired where device.isConnected() {
            let name = device.name ?? "Unknown Device"
            var batteryStr: Int? = nil
            
            // Attempt to read from IORegistry for battery
            var iterator: io_iterator_t = 0
            let matchingDict = IOServiceMatching("AppleDeviceManagementHIDEventService")
            if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS {
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    if let p = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
                        if let n = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String, n == name {
                            batteryStr = p
                            IOObjectRelease(service)
                            break
                        }
                    }
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                IOObjectRelease(iterator)
            }
            
            devices.append(BluetoothDevice(name: name, batteryPercent: batteryStr))
        }
        
        return devices
    }
}
