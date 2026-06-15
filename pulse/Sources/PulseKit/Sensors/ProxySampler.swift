import Foundation

public struct ProxyStatus: Sendable, Equatable {
    public let enabled: Bool
    public let details: String
}

public actor ProxySampler {
    public init() {}

    public func sample() async -> ProxyStatus {
        guard let out = try? await Shell.run("/usr/sbin/scutil", ["--proxy"]) else {
            return ProxyStatus(enabled: false, details: "")
        }
        
        let stdout = out.stdout
        var types: [String] = []
        if stdout.contains("HTTPEnable : 1") { types.append("HTTP") }
        if stdout.contains("HTTPSEnable : 1") { types.append("HTTPS") }
        if stdout.contains("SOCKSEnable : 1") { types.append("SOCKS") }
        if stdout.contains("ExceptionsList :") { types.append("PAC") }

        if !types.isEmpty {
            return ProxyStatus(enabled: true, details: types.joined(separator: ", "))
        }

        return ProxyStatus(enabled: false, details: "")
    }
}
