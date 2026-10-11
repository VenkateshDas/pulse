import Foundation
import SystemConfiguration

public struct ProxyStatus: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let details: String
    public var unavailable: String? = nil
}

public actor ProxySampler {
    public init() {}

    public func sample() async -> ProxyStatus {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return ProxyStatus(enabled: false, details: "", unavailable: "Proxy configuration unavailable")
        }
        
        var types: [String] = []
        if proxySettings[kCFNetworkProxiesHTTPEnable as String] as? Int == 1 { types.append("HTTP") }
        if proxySettings[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1 { types.append("HTTPS") }
        if proxySettings[kCFNetworkProxiesSOCKSEnable as String] as? Int == 1 { types.append("SOCKS") }
        if proxySettings[kCFNetworkProxiesProxyAutoConfigEnable as String] as? Int == 1 { types.append("PAC") }
        if proxySettings[kCFNetworkProxiesProxyAutoDiscoveryEnable as String] as? Int == 1 { types.append("Auto discovery") }

        if !types.isEmpty {
            return ProxyStatus(enabled: true, details: types.joined(separator: ", "))
        }

        return ProxyStatus(enabled: false, details: "")
    }
}
