import CoreWLAN
import Foundation
import Network
import os

/// How the Mac is currently reaching the network. Backed by `NWPathMonitor`,
/// which is event-driven (kernel notifies on change) — no polling cost.
public enum ConnectionType: String, Sendable, Equatable {
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case cellular = "Cellular"
    case other = "Other"
    case none = "No Connection"
}

/// Live Wi-Fi radio info for the connected network. Fields stay nil where
/// the value isn't available on this Mac or this macOS version.
public struct WiFiInfo: Sendable, Equatable {
    /// nil unless the app holds Location authorization (CoreWLAN gate).
    public let ssid: String?
    public let rssi: Int?
    public let noise: Int?
    public let channel: Int?
    public let channelBand: String?
    public let txRateMbps: Double?
    public let security: String?
    public let interfaceName: String?

    public init(
        ssid: String? = nil, rssi: Int? = nil, noise: Int? = nil, channel: Int? = nil,
        channelBand: String? = nil, txRateMbps: Double? = nil, security: String? = nil,
        interfaceName: String? = nil
    ) {
        self.ssid = ssid
        self.rssi = rssi
        self.noise = noise
        self.channel = channel
        self.channelBand = channelBand
        self.txRateMbps = txRateMbps
        self.security = security
        self.interfaceName = interfaceName
    }

    /// 0–1 signal quality from RSSI: −90 dBm (unusable) maps to 0, −30 dBm
    /// (excellent, standing next to the router) maps to 1.
    public var signalQualityFraction: Double {
        guard let rssi else { return 0 }
        return min(max((Double(rssi) + 90) / 60, 0), 1)
    }

    /// 0–100 user-facing signal quality score, same scale as `signalQualityFraction`.
    public var signalQualityPercent: Int { Int((signalQualityFraction * 100).rounded()) }

    /// Plain-language read of `signalQualityFraction` — what people actually
    /// understand, instead of a raw dBm number or an arbitrary bar count.
    public var signalQualityLabel: String {
        switch signalQualityPercent {
        case 80...: "Excellent"
        case 60..<80: "Good"
        case 35..<60: "Fair"
        case 15..<35: "Weak"
        default: "Poor"
        }
    }
}

/// Reads the active Wi-Fi interface via CoreWLAN. RSSI/channel/security work
/// without extra authorization; SSID/BSSID require Location Services auth
/// (requested by the Network page on first visit, not at launch).
public actor WiFiSampler {
    public init() {}

    public func sample() -> WiFiInfo? {
        guard let interface = CWWiFiClient.shared().interface(),
            interface.powerOn(), interface.ssid() != nil || interface.bssid() != nil
        else {
            return nil
        }

        let band: String? =
            switch interface.wlanChannel()?.channelBand {
            case .band2GHz: "2.4 GHz"
            case .band5GHz: "5 GHz"
            case .band6GHz: "6 GHz"
            default: nil
            }

        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        let rate = interface.transmitRate()

        return WiFiInfo(
            ssid: interface.ssid(),
            rssi: rssi != 0 ? rssi : nil,
            noise: noise != 0 ? noise : nil,
            channel: interface.wlanChannel()?.channelNumber,
            channelBand: band,
            txRateMbps: rate > 0 ? rate : nil,
            security: Self.securityDescription(interface.security()),
            interfaceName: interface.interfaceName)
    }

    private static func securityDescription(_ mode: CWSecurity) -> String {
        switch mode {
        case .none, .unknown: "Open"
        case .WEP: "WEP"
        case .wpaPersonal, .wpaPersonalMixed: "WPA Personal"
        case .wpa2Personal, .personal: "WPA2 Personal"
        case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise: "WPA2 Enterprise"
        case .wpa3Personal: "WPA3 Personal"
        case .wpa3Enterprise: "WPA3 Enterprise"
        case .wpa3Transition: "WPA3 Transition"
        case .dynamicWEP: "Dynamic WEP"
        case .OWE: "Enhanced Open"
        case .oweTransition: "Enhanced Open (Transition)"
        @unknown default: "Unknown"
        }
    }
}

/// Tracks the active connection type from kernel path-change notifications.
/// Singleton: one `NWPathMonitor` for the whole app, started lazily on first
/// read — cheaper and simpler than threading a monitor through every sampler
/// that wants to know if it's on Wi-Fi.
public final class ConnectionTypeMonitor: @unchecked Sendable {
    public static let shared = ConnectionTypeMonitor()

    private let monitor = NWPathMonitor()
    private let lock = OSAllocatedUnfairLock()
    private var currentType: ConnectionType = .none

    public var current: ConnectionType {
        lock.withLock { currentType }
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let type: ConnectionType =
                if path.status != .satisfied {
                    .none
                } else if path.usesInterfaceType(.wifi) {
                    .wifi
                } else if path.usesInterfaceType(.wiredEthernet) {
                    .ethernet
                } else if path.usesInterfaceType(.cellular) {
                    .cellular
                } else {
                    .other
                }
            self.lock.withLock {
                self.currentType = type
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.pulse.network-path-monitor"))
    }
}
