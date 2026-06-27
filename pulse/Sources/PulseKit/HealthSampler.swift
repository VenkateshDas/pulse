import Foundation
import IOKit

/// Battery state and health, read from the AppleSmartBattery IOKit service.
/// Raw registry reads take ~2ms; never shell out to system_profiler (~2s).
public struct BatteryHealth: Sendable, Equatable {
    /// Full-charge capacity as % of design capacity (AppleRawMaxCapacity / DesignCapacity).
    public let capacityPercent: Int
    public let cycleCount: Int
    public let isCharging: Bool
    public let isOnAC: Bool
    public let currentChargePercent: Int
    /// Seconds to full (charging) or to empty (discharging); nil when the
    /// gauge reports unknown (0xFFFF) or the battery is idle on AC.
    public let timeToEvent: TimeInterval?
    /// "Normal" or "Service Recommended" — derived from permanent-failure
    /// status and the <80% capacity threshold Apple uses in System Settings.
    public let condition: String
    /// Instantaneous battery power draw in watts (|amps| × volts / 1e6).
    /// nil when idle on AC or when IOKit doesn't report the keys.
    public let powerWatts: Double?
    /// Cycles left before the Apple 1000-cycle service threshold.
    public let cyclesRemaining: Int

    public init(
        capacityPercent: Int, cycleCount: Int, isCharging: Bool, isOnAC: Bool,
        currentChargePercent: Int, timeToEvent: TimeInterval?, condition: String,
        powerWatts: Double? = nil, cyclesRemaining: Int = 0
    ) {
        self.capacityPercent = capacityPercent
        self.cycleCount = cycleCount
        self.isCharging = isCharging
        self.isOnAC = isOnAC
        self.currentChargePercent = currentChargePercent
        self.timeToEvent = timeToEvent
        self.condition = condition
        self.powerWatts = powerWatts
        self.cyclesRemaining = cyclesRemaining
    }
}

/// Pure decode of an AppleSmartBattery property dictionary — unit-testable
/// without IOKit, same pattern as SMCDecode.
public enum BatteryDecode {
    /// Gauge sentinel for "time unknown" (also seen as 65535 minutes).
    static let unknownMinutes = 65535
    static let serviceCapacityThreshold = 80

    public static func battery(from props: [String: Any]) -> BatteryHealth? {
        guard let design = props["DesignCapacity"] as? Int, design > 0,
            let rawMax = props["AppleRawMaxCapacity"] as? Int,
            let current = props["CurrentCapacity"] as? Int,
            let max = props["MaxCapacity"] as? Int, max > 0
        else { return nil }

        let isCharging = props["IsCharging"] as? Bool ?? false
        let isOnAC = props["ExternalConnected"] as? Bool ?? false
        let capacityPercent = Int((Double(rawMax) / Double(design) * 100).rounded())
        // Apple Silicon reports CurrentCapacity already as a percentage
        // (MaxCapacity pinned to 100); Intel reports raw mAh.
        let chargePercent =
            max == 100 ? current : Int((Double(current) / Double(max) * 100).rounded())

        var minutes: Int?
        if isCharging {
            minutes = props["AvgTimeToFull"] as? Int
        } else if !isOnAC {
            minutes = (props["TimeRemaining"] as? Int) ?? (props["AvgTimeToEmpty"] as? Int)
        }
        if let value = minutes, value <= 0 || value >= unknownMinutes { minutes = nil }

        let failed = (props["PermanentFailureStatus"] as? Int ?? 0) != 0
        let condition =
            failed || capacityPercent < serviceCapacityThreshold
            ? "Service Recommended" : "Normal"

        let cycleCount = props["CycleCount"] as? Int ?? 0
        let cyclesRemaining = Swift.max(0, 1000 - cycleCount)

        // Instantaneous power draw: |InstantAmperage mA| × Voltage mV → watts.
        let amps = props["InstantAmperage"] as? Int ?? 0
        let volts = props["Voltage"] as? Int ?? 0
        let rawWatts = volts > 0 ? Double(abs(amps)) * Double(volts) / 1_000_000.0 : 0
        let powerWatts: Double? = rawWatts > 0.5 ? rawWatts : nil

        return BatteryHealth(
            capacityPercent: capacityPercent,
            cycleCount: cycleCount,
            isCharging: isCharging,
            isOnAC: isOnAC,
            currentChargePercent: chargePercent,
            timeToEvent: minutes.map { TimeInterval($0 * 60) },
            condition: condition,
            powerWatts: powerWatts,
            cyclesRemaining: cyclesRemaining
        )
    }
}

/// One launchd agent plist found in a LaunchAgents directory.
///
/// Login items are intentionally absent: macOS has no public API to
/// enumerate third-party login items (SMAppService only manages the calling
/// app's own; the BTM store is private). Pulse shows what it can truthfully
/// read — launch agents — and says so in the UI.
public struct StartupItem: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// ~/Library/LaunchAgents — user-owned, Pulse can toggle these.
        case userAgent
        /// /Library/LaunchAgents — installed system-wide, read-only without sudo.
        case globalAgent
    }

    /// Stable identity: the plist path with any .disabled suffix stripped,
    /// so an item keeps its row identity across toggles.
    public let id: String
    public let label: String
    public let path: String
    public let kind: Kind
    public let isEnabled: Bool
    /// What the agent runs (Program or first ProgramArguments entry).
    public let program: String?

    public init(
        id: String, label: String, path: String, kind: Kind, isEnabled: Bool, program: String?
    ) {
        self.id = id
        self.label = label
        self.path = path
        self.kind = kind
        self.isEnabled = isEnabled
        self.program = program
    }
}

public enum StartupItemError: Error, Equatable {
    case notToggleable(String)
    case fileMissing(String)
}

/// Battery, startup items, and toggle actions for the Health page.
public actor HealthSampler {
    /// Suffix appended to a plist to disable it — launchd only loads
    /// `*.plist`, so the rename takes effect at next login. The standard
    /// trick used by login-item managers; fully reversible.
    public static let disabledSuffix = ".disabled"

    private let userAgentsURL: URL
    private let globalAgentsURL: URL

    public init(
        userAgentsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents"),
        globalAgentsURL: URL = URL(fileURLWithPath: "/Library/LaunchAgents")
    ) {
        self.userAgentsURL = userAgentsURL
        self.globalAgentsURL = globalAgentsURL
    }

    // MARK: - Battery

    private var cachedBattery: BatteryHealth?
    private var batteryCachedAt: Date = .distantPast

    /// nil on desktop Macs (no AppleSmartBattery service).
    public func sampleBattery() -> BatteryHealth? {
        let now = Date()
        if now.timeIntervalSince(batteryCachedAt) < 5 { return cachedBattery }
        batteryCachedAt = now
        let result = readBatteryFromIOKit()
        cachedBattery = result
        return result
    }

    private func readBatteryFromIOKit() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(
                service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let props = propsRef?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return BatteryDecode.battery(from: props)
    }

    // MARK: - Startup items

    /// User agents first (actionable), then global ones, each name-sorted.
    public func listStartupItems() -> [StartupItem] {
        scan(userAgentsURL, kind: .userAgent) + scan(globalAgentsURL, kind: .globalAgent)
    }

    /// Enables/disables a user agent by renaming `foo.plist` ⇄
    /// `foo.plist.disabled`. Takes effect at next login. Global agents
    /// would need sudo — refused, not faked.
    public func toggleStartupItem(_ item: StartupItem) throws {
        guard item.kind == .userAgent else {
            throw StartupItemError.notToggleable(item.label)
        }
        let from = URL(fileURLWithPath: item.path)
        // Flip on the filename, not isEnabled: an item disabled via its
        // plist Disabled key has no suffix to strip.
        let to = URL(
            fileURLWithPath: item.path.hasSuffix(Self.disabledSuffix)
                ? String(item.path.dropLast(Self.disabledSuffix.count))
                : item.path + Self.disabledSuffix)
        guard FileManager.default.fileExists(atPath: from.path) else {
            throw StartupItemError.fileMissing(item.path)
        }
        try FileManager.default.moveItem(at: from, to: to)
    }

    private func scan(_ directory: URL, kind: StartupItem.Kind) -> [StartupItem] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter {
                $0.lastPathComponent.hasSuffix(".plist")
                    || $0.lastPathComponent.hasSuffix(".plist" + Self.disabledSuffix)
            }
            .compactMap { Self.startupItem(at: $0, kind: kind) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Pure-ish parse of one agent plist (only touches the given file).
    static func startupItem(at url: URL, kind: StartupItem.Kind) -> StartupItem? {
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any]
        else { return nil }

        let path = url.path
        let disabledByName = path.hasSuffix(disabledSuffix)
        let canonicalPath = disabledByName ? String(path.dropLast(disabledSuffix.count)) : path
        let fallbackLabel = url.deletingPathExtension().lastPathComponent
        let program =
            (plist["Program"] as? String)
            ?? (plist["ProgramArguments"] as? [String])?.first

        return StartupItem(
            id: canonicalPath,
            label: plist["Label"] as? String ?? fallbackLabel,
            path: path,
            kind: kind,
            // The plist Disabled key also stops launchd from loading it.
            isEnabled: !disabledByName && (plist["Disabled"] as? Bool ?? false) == false,
            program: program
        )
    }
}
