import Foundation
import AppKit
import CoreGraphics
import CPulse

public struct Monitor: Equatable, Identifiable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltIn: Bool

    public init(id: CGDirectDisplayID, name: String, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

@MainActor
public class BrightnessEngine: ObservableObject {
    public static let shared = BrightnessEngine()

    @Published public private(set) var monitors: [Monitor] = []
    @Published public var brightnessMap: [CGDirectDisplayID: Double] = [:]
    private var ddcFailures: [CGDirectDisplayID: Int] = [:]

    private var screenObserver: Any?

    private init() {
        loadBrightnessMap()
        refreshMonitors()
        // Display IDs are reassigned on sleep/wake and connect/disconnect. Without
        // this, `monitors` goes stale and the media-key router can't resolve the
        // display under the cursor — brightness keys then miss external monitors.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshMonitors() }
        }
    }
    
    public func saveBrightnessMap() {
        let stringKeyedMap = Dictionary(uniqueKeysWithValues: brightnessMap.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stringKeyedMap, forKey: "PulseBrightnessMap")
    }
    
    private func loadBrightnessMap() {
        if let savedMap = UserDefaults.standard.dictionary(forKey: "PulseBrightnessMap") as? [String: Double] {
            brightnessMap = Dictionary(uniqueKeysWithValues: savedMap.compactMap { key, value in
                guard let id = CGDirectDisplayID(key) else { return nil }
                return (id, value)
            })
        }
    }

    public func refreshMonitors() {
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        guard CGGetActiveDisplayList(UInt32(activeDisplays.count), &activeDisplays, &displayCount) == .success else {
            return
        }
        
        let orderedIDs = Array(activeDisplays.prefix(Int(displayCount)))
        let activeIDs = Set(orderedIDs)
        monitors = orderedIDs.map { id in
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let name = isBuiltIn ? "Built-in Display" : "External Display"
            return Monitor(id: id, name: name, isBuiltIn: isBuiltIn)
        }

        // Prune stale entries for disconnected displays.
        for id in brightnessMap.keys where !activeIDs.contains(id) {
            brightnessMap.removeValue(forKey: id)
            ddcFailures.removeValue(forKey: id)
            SoftwareDimmer.shared.setBrightness(for: id, brightness: 1.0)
        }

        for monitor in monitors {
            let hwBrightness = getBrightness(for: monitor)
            let canReadHardware = DisplayServicesCanChangeBrightness(monitor.id) != 0
            
            if let saved = brightnessMap[monitor.id] {
                let expectedHw = max(0.0, saved)
                
                if canReadHardware && hwBrightness > 0.0 && abs(hwBrightness - expectedHw) > 0.05 {
                    // Hardware was changed externally (e.g., Apple Control Center)
                    brightnessMap[monitor.id] = hwBrightness
                } else if saved < 0.0 {
                    // Restore sub-zero overlay state
                    setBrightness(for: monitor, to: saved)
                } else {
                    // For external monitors, we trust our saved map over the fake 1.0 hardware value
                    // For internal monitors, if the change was negligible, we just keep the saved map to prevent rounding jitter
                }
            } else {
                // Initial launch with no saved value
                brightnessMap[monitor.id] = hwBrightness
            }
        }
    }

    nonisolated public func getBrightness(for monitor: Monitor) -> Double {
        if DisplayServicesCanChangeBrightness(monitor.id) != 0 {
            var brightness: Float = 0
            if DisplayServicesGetBrightness(monitor.id, &brightness) == 0 {
                return Double(brightness)
            }
        }
        
        return CoreDisplay_Display_GetUserBrightness(monitor.id)
    }

    public func setBrightness(for monitor: Monitor, to value: Double) {
        guard monitors.contains(where: { $0.id == monitor.id }) else { return }
        let clampedValue = max(-1.0, min(1.0, value))

        let hardwareBrightness = clampedValue >= 0.0 ? clampedValue : 0.0
        let softwareBrightness = clampedValue >= 0.0 ? 1.0 : (1.0 + clampedValue)
        
        if DisplayServicesCanChangeBrightness(monitor.id) != 0 {
            _ = DisplayServicesSetBrightness(monitor.id, Float(hardwareBrightness))
            _ = DisplayServicesSetLinearBrightness(monitor.id, Float(hardwareBrightness))
        } else {
            CoreDisplay_Display_SetUserBrightness(monitor.id, hardwareBrightness)
        }
        
        brightnessMap[monitor.id] = clampedValue
        
        var ddcSuccess = true // Assume true for built-in or if we don't need DDC
        if !monitor.isBuiltIn {
            ddcSuccess = false
            var command = DDCWriteCommand(control_id: 0x10, new_value: UInt16(hardwareBrightness * 100))
            #if arch(arm64)
            ddcSuccess = writeDDC_M1(monitor: monitor, control_id: 0x10, new_value: UInt16(hardwareBrightness * 100))
            #else
            let fb = IOFramebufferPortFromCGDisplayID(monitor.id, nil)
            if fb != 0 {
                ddcSuccess = DDCWriteIntel(fb, &command, 0x51)
            }
            #endif
        }
        
        if !monitor.isBuiltIn {
            if !ddcSuccess {
                ddcFailures[monitor.id, default: 0] += 1
            } else {
                ddcFailures[monitor.id] = 0
            }
        }
        
        let isDDCDead = (ddcFailures[monitor.id] ?? 0) >= 3
        
        // Apply Software Dimming if Sub-zero is engaged, OR if Hardware DDC completely fails multiple times
        if softwareBrightness < 1.0 {
            SoftwareDimmer.shared.setBrightness(for: monitor.id, brightness: softwareBrightness)
        } else if isDDCDead {
            // Hardware DDC failed on external monitor consistently, use software dimming for the full range
            SoftwareDimmer.shared.setBrightness(for: monitor.id, brightness: hardwareBrightness)
        } else {
            // Hardware dimming works and we're not in sub-zero range, ensure software dimming is off
            SoftwareDimmer.shared.setBrightness(for: monitor.id, brightness: 1.0)
        }
    }
    
    public func adjustBrightness(for monitor: Monitor, delta: Double) {
        if isAdaptiveModeEnabled && !monitor.isBuiltIn {
            isAdaptiveModeEnabled = false
        }
        let current = brightnessMap[monitor.id] ?? getBrightness(for: monitor)
        let newBrightness = max(-1.0, min(1.0, current + delta))
        setBrightness(for: monitor, to: newBrightness)
        saveBrightnessMap()
    }
    
    // MARK: - Intelligent Adaptive Brightness (Sync Mode)
    
    @Published public var isAdaptiveModeEnabled: Bool = false {
        didSet {
            if isAdaptiveModeEnabled {
                startAdaptiveSync()
            } else {
                stopAdaptiveSync()
            }
        }
    }
    
    private var syncTask: Task<Void, Never>?
    
    private func startAdaptiveSync() {
        guard syncTask == nil else { return }
        syncTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                
                let (builtIn, externals, currentMap) = await MainActor.run { 
                    (
                        self.monitors.first { $0.isBuiltIn }, 
                        self.monitors.filter { !$0.isBuiltIn },
                        self.brightnessMap
                    ) 
                }
                
                if let builtIn = builtIn, !externals.isEmpty {
                    let sourceBrightness = currentMap[builtIn.id] ?? self.getBrightness(for: builtIn)
                    for ext in externals {
                        let currentExt = currentMap[ext.id] ?? self.getBrightness(for: ext)
                        if abs(currentExt - sourceBrightness) > 0.02 {
                            await MainActor.run {
                                self.setBrightness(for: ext, to: sourceBrightness)
                            }
                        }
                    }
                }
                
                try? await Task.sleep(nanoseconds: 2_000_000_000) // check every 2 seconds
            }
        }
    }
    
    private func stopAdaptiveSync() {
        syncTask?.cancel()
        syncTask = nil
    }
    
    private struct DDCPayload {
        var length: UInt8 = 0x84
        var command: UInt8 = 0x03
        var control_id: UInt8
        var val_high: UInt8
        var val_low: UInt8
        var checksum: UInt8
        
        init(control_id: UInt8, new_value: UInt16) {
            self.control_id = control_id
            self.val_high = UInt8((new_value >> 8) & 0xFF)
            self.val_low = UInt8(new_value & 0xFF)
            self.checksum = 0x50 ^ 0x51 ^ self.length ^ self.command ^ self.control_id ^ self.val_high ^ self.val_low
        }
    }

    #if arch(arm64)
    private func writeDDC_M1(monitor: Monitor, control_id: UInt8, new_value: UInt16) -> Bool {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return false }
        
        var serv: io_service_t = 0
        var foundService: io_service_t = 0
        
        // Retrieve the EDID UUID or display attributes to match CGDirectDisplayID
        // Lunar does a massive tree traversal. For safety and brevity, we assume 
        // a 1:1 mapping if there's only one external monitor, but we'll try to match by 
        // display serial or just pick the first external for now until full tree mapping is needed.
        while true {
            serv = IOIteratorNext(iter)
            if serv == 0 { break }
            if let loc = IORegistryEntryCreateCFProperty(serv, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String, loc == "External" {
                // Ideally we check IODisplayConnectFlags or IOMobileFramebuffer to match the monitor.id
                foundService = serv
                break 
            }
            IOObjectRelease(serv)
        }
        IOObjectRelease(iter)
        
        guard foundService != 0 else { return false }
        
        guard let avServiceUnmanaged = IOAVServiceCreateWithService(kCFAllocatorDefault, foundService) else {
            IOObjectRelease(foundService)
            return false
        }
        let avService = avServiceUnmanaged.takeRetainedValue()
        IOObjectRelease(foundService)
        
        var payload = DDCPayload(control_id: control_id, new_value: new_value)
        let result = withUnsafeMutablePointer(to: &payload) { ptr in
            IOAVServiceWriteI2C(avService, 0x37, 0x51, UnsafeMutableRawPointer(ptr), UInt32(MemoryLayout<DDCPayload>.size))
        }
        
        return result == kIOReturnSuccess
    }
    #endif
}

#if arch(arm64)
@_silgen_name("IOAVServiceCreate")
func IOAVServiceCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<AnyObject>?

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: AnyObject, _ chipAddress: UInt32, _ dataAddress: UInt32, _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32) -> IOReturn
#endif
