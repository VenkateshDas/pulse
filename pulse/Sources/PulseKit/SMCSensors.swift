import CPulse
import Foundation
import IOKit

/// Temperature/fan/power readings from the SMC. Every field optional —
/// key availability varies per Mac model, and honesty beats guessing.
public struct SensorReadings: Sendable, Equatable {
    public var cpuTempC: Double?
    public var gpuTempC: Double?
    public var batteryTempC: Double?
    public var fanCount: Int?
    public var fanRPM: Double?
    public var systemWatts: Double?

    public init(
        cpuTempC: Double? = nil, gpuTempC: Double? = nil, batteryTempC: Double? = nil,
        fanCount: Int? = nil, fanRPM: Double? = nil, systemWatts: Double? = nil
    ) {
        self.cpuTempC = cpuTempC
        self.gpuTempC = gpuTempC
        self.batteryTempC = batteryTempC
        self.fanCount = fanCount
        self.fanRPM = fanRPM
        self.systemWatts = systemWatts
    }
}

/// Decoders are separated from I/O so they're unit-testable without SMC.
enum SMCDecode {
    /// "flt " — little-endian IEEE 754 float32.
    static func flt(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let bits =
            UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24
        return Double(Float(bitPattern: bits))
    }

    /// "sp78" — big-endian signed 7.8 fixed point.
    static func sp78(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(raw) / 256.0
    }

    static func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func string(fromFourCC value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Sanity window for any temperature sensor on a running Mac.
    static func plausibleTemp(_ value: Double) -> Bool {
        value > 1 && value < 125
    }
}

/// Reads the SMC over IOKit — public user-client interface, no root needed.
/// Enumerates the key space once at init and caches which temperature keys
/// this specific Mac exposes (key sets differ per chip generation).
final class SMCSensors {
    private var connection: io_connect_t = 0
    private var cpuKeys: [UInt32] = []
    private var gpuKeys: [UInt32] = []
    private var batteryKeys: [UInt32] = []
    private var fanCount = 0
    private var hasSystemPower = false

    private static let systemPowerKey = SMCDecode.fourCC("PSTR")

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
        else { return nil }
        discoverKeys()
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func sample() -> SensorReadings {
        var readings = SensorReadings()
        readings.cpuTempC = averageTemp(of: cpuKeys)
        readings.gpuTempC = averageTemp(of: gpuKeys)
        readings.batteryTempC = averageTemp(of: batteryKeys)
        readings.fanCount = fanCount
        if fanCount > 0 {
            readings.fanRPM = readValue(SMCDecode.fourCC("F0Ac"))
        }
        if hasSystemPower {
            readings.systemWatts = readValue(Self.systemPowerKey)
        }
        return readings
    }

    // MARK: Key discovery

    private func discoverKeys() {
        let keyCount = Int(readValueRawUInt32(SMCDecode.fourCC("#KEY")) ?? 0)
        for index in 0..<keyCount {
            guard let key = keyAtIndex(UInt32(index)) else { continue }
            let name = SMCDecode.string(fromFourCC: key)
            switch true {
            case name.hasPrefix("Tp"): cpuKeys.append(key)
            case name.hasPrefix("Tg"): gpuKeys.append(key)
            case name.hasPrefix("TB") && name.hasSuffix("T"): batteryKeys.append(key)
            case name == "PSTR": hasSystemPower = true
            default: break
            }
        }
        if let fans = readValueRawUInt32(SMCDecode.fourCC("FNum")) {
            fanCount = Int(fans)
        }
        // Keep readouts cheap: a handful of sensors per group is plenty
        // for an average (some Macs expose 20+ per-core CPU keys).
        cpuKeys = Array(cpuKeys.prefix(12))
        gpuKeys = Array(gpuKeys.prefix(8))
        batteryKeys = Array(batteryKeys.prefix(4))
    }

    func dumpAll() -> [String: String] {
        var dump = [String: String]()
        let keyCount = Int(readValueRawUInt32(SMCDecode.fourCC("#KEY")) ?? 0)
        for index in 0..<keyCount {
            guard let key = keyAtIndex(UInt32(index)) else { continue }
            let name = SMCDecode.string(fromFourCC: key)
            if let val = readValue(key) {
                dump[name] = String(format: "%.2f", val)
            } else if let valInt = readValueRawUInt32(key) {
                dump[name] = "\(valInt)"
            } else if let (bytes, _) = readBytes(key) {
                let hex = bytes.map { String(format: "%02x", $0) }.joined()
                dump[name] = "0x\(hex)"
            } else {
                dump[name] = "ERR"
            }
        }
        return dump
    }

    private func averageTemp(of keys: [UInt32]) -> Double? {
        let values = keys.compactMap { readValue($0) }.filter(SMCDecode.plausibleTemp)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: Wire calls

    private func call(_ input: inout PulseSMCKeyData) -> PulseSMCKeyData? {
        var output = PulseSMCKeyData()
        var outputSize = MemoryLayout<PulseSMCKeyData>.size
        let result = IOConnectCallStructMethod(
            connection, UInt32(kPulseSMCHandleYPCEvent),
            &input, MemoryLayout<PulseSMCKeyData>.size,
            &output, &outputSize
        )
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private func keyInfo(_ key: UInt32) -> PulseSMCKeyInfo? {
        var input = PulseSMCKeyData()
        input.key = key
        input.data8 = UInt8(kPulseSMCGetKeyInfo)
        return call(&input)?.keyInfo
    }

    private func keyAtIndex(_ index: UInt32) -> UInt32? {
        var input = PulseSMCKeyData()
        input.data8 = UInt8(kPulseSMCGetKeyFromIndex)
        input.data32 = index
        return call(&input)?.key
    }

    private func readBytes(_ key: UInt32) -> (bytes: [UInt8], type: UInt32)? {
        guard let info = keyInfo(key) else { return nil }
        var input = PulseSMCKeyData()
        input.key = key
        input.keyInfo.dataSize = info.dataSize
        input.data8 = UInt8(kPulseSMCReadKey)
        guard let output = call(&input) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { raw in
            Array(raw.prefix(Int(min(info.dataSize, 32))))
        }
        return (bytes, info.dataType)
    }

    /// Reads a key and decodes by its declared type (flt / sp78).
    private func readValue(_ key: UInt32) -> Double? {
        guard let (bytes, type) = readBytes(key) else { return nil }
        switch SMCDecode.string(fromFourCC: type) {
        case "flt ": return SMCDecode.flt(bytes)
        case "sp78": return SMCDecode.sp78(bytes)
        default: return nil
        }
    }

    /// For integer keys like #KEY (big-endian ui32) and FNum (ui8).
    private func readValueRawUInt32(_ key: UInt32) -> UInt32? {
        guard let (bytes, _) = readBytes(key) else { return nil }
        switch bytes.count {
        case 1: return UInt32(bytes[0])
        case 2: return UInt32(bytes[0]) << 8 | UInt32(bytes[1])
        case 4...:
            return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        default: return nil
        }
    }
}
