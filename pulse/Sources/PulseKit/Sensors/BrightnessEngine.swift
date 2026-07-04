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
                // Migrate values persisted by the old -1...1 sub-zero range.
                return (id, max(0.0, min(1.0, value)))
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
                if canReadHardware && hwBrightness > 0.0 && abs(hwBrightness - saved) > 0.05 {
                    // Hardware was changed externally (e.g., Apple Control Center)
                    brightnessMap[monitor.id] = hwBrightness
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

    public func setBrightness(for monitor: Monitor, to value: Double, showOSD: Bool = true) {
        guard monitors.contains(where: { $0.id == monitor.id }) else { return }
        // Plain 0...1 range. The old -1...0 "sub-zero" software-dimming zone
        // is gone: it doubled every mapping in the app and made 50% on the
        // slider mean 100% hardware.
        let clampedValue = max(0.0, min(1.0, value))

        if DisplayServicesCanChangeBrightness(monitor.id) != 0 {
            _ = DisplayServicesSetBrightness(monitor.id, Float(clampedValue))
            _ = DisplayServicesSetLinearBrightness(monitor.id, Float(clampedValue))
        } else {
            CoreDisplay_Display_SetUserBrightness(monitor.id, clampedValue)
        }

        brightnessMap[monitor.id] = clampedValue

        if !monitor.isBuiltIn {
            // DDC/CI over I2C takes tens of ms per round trip. Calling it
            // synchronously here — on every drag pixel, unthrottled — blocked
            // the main thread long enough that queued drag events landed out
            // of order, which looked like brightness jumping up then back
            // down mid-drag on external monitors (built-in uses the fast
            // DisplayServices/CoreDisplay calls above, so it never showed
            // this). Serialize and coalesce writes off the main thread
            // instead; only the latest value survives if several pile up
            // before the in-flight write finishes.
            scheduleDDCWrite(for: monitor, controlValue: UInt16((clampedValue * 100).rounded()))
        }

        let isDDCDead = !monitor.isBuiltIn && (ddcFailures[monitor.id] ?? 0) >= 3

        if isDDCDead {
            // Hardware control is unreachable — the overlay stands in for the
            // whole 0...1 range so the slider still does something.
            SoftwareDimmer.shared.setBrightness(for: monitor.id, brightness: clampedValue)
        } else {
            // Hardware dimming works — ensure software dimming is off.
            SoftwareDimmer.shared.setBrightness(for: monitor.id, brightness: 1.0)
        }

        if showOSD {
            BrightnessOSD.shared.show(fraction: clampedValue, on: monitor.id)
        }
    }

    // MARK: - Async DDC writes

    private var pendingDDCValue: [CGDirectDisplayID: UInt16] = [:]
    private var ddcWriteInFlight: Set<CGDirectDisplayID> = []

    /// Queues `controlValue` as the latest write for this monitor and, if no
    /// write loop is already running for it, starts one. The loop drains to
    /// whatever is newest each time it's free, so a fast drag collapses to a
    /// single trailing write instead of one per pixel, and writes to the
    /// same monitor never overlap on the I2C bus.
    private func scheduleDDCWrite(for monitor: Monitor, controlValue: UInt16) {
        let id = monitor.id
        pendingDDCValue[id] = controlValue
        guard !ddcWriteInFlight.contains(id) else { return }
        ddcWriteInFlight.insert(id)

        Task.detached(priority: .userInitiated) { [weak self] in
            while let self {
                guard let value = await MainActor.run(body: { self.pendingDDCValue.removeValue(forKey: id) })
                else { break }
                let success = Self.performDDCWrite(monitor: monitor, controlID: 0x10, newValue: value)
                await MainActor.run {
                    self.ddcFailures[id] = success ? 0 : (self.ddcFailures[id] ?? 0) + 1
                }
                // Most external monitors' I2C controllers can't keep up with
                // back-to-back commands — hammering them without a gap was
                // producing real write failures (NAK/timeout), which tripped
                // the isDDCDead fallback mid-drag. This is the same order of
                // throttle DDC control apps (Lunar, MonitorControl) use.
                try? await Task.sleep(for: .milliseconds(20))
            }
            _ = await MainActor.run { [weak self] in self?.ddcWriteInFlight.remove(id) }
        }
    }

    /// The actual blocking I2C round trip — must never run on the main
    /// thread. `nonisolated` so it executes directly on the background task
    /// that calls it instead of hopping back to MainActor.
    nonisolated private static func performDDCWrite(monitor: Monitor, controlID: UInt8, newValue: UInt16) -> Bool {
        #if arch(arm64)
        return writeDDC_M1(monitor: monitor, control_id: controlID, new_value: newValue)
        #else
        var command = DDCWriteCommand(control_id: controlID, new_value: newValue)
        let fb = IOFramebufferPortFromCGDisplayID(monitor.id, nil)
        guard fb != 0 else { return false }
        return DDCWriteIntel(fb, &command, 0x51)
        #endif
    }

    public func adjustBrightness(for monitor: Monitor, delta: Double) {
        if isAdaptiveModeEnabled && !monitor.isBuiltIn {
            isAdaptiveModeEnabled = false
        }
        let current = brightnessMap[monitor.id] ?? getBrightness(for: monitor)
        let newBrightness = max(0.0, min(1.0, current + delta))
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
                                self.setBrightness(for: ext, to: sourceBrightness, showOSD: false)
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
    nonisolated private static func writeDDC_M1(monitor: Monitor, control_id: UInt8, new_value: UInt16) -> Bool {
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
