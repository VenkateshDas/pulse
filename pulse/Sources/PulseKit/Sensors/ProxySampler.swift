import Foundation
import SystemConfiguration

public struct ProxyStatus: Sendable, Equatable {
    public let enabled: Bool
    public let details: String
}

public actor ProxySampler {
    public init() {}

    public func sample() async -> ProxyStatus {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return ProxyStatus(enabled: false, details: "")
        }
        
        var types: [String] = []
        if proxySettings[kCFNetworkProxiesHTTPEnable as String] as? Int == 1 { types.append("HTTP") }
        if proxySettings[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1 { types.append("HTTPS") }
        if proxySettings[kCFNetworkProxiesSOCKSEnable as String] as? Int == 1 { types.append("SOCKS") }
        if let exceptions = proxySettings[kCFNetworkProxiesExceptionsList as String] as? [String], !exceptions.isEmpty { types.append("PAC") }

        if !types.isEmpty {
            return ProxyStatus(enabled: true, details: types.joined(separator: ", "))
        }

        return ProxyStatus(enabled: false, details: "")
    }
}
