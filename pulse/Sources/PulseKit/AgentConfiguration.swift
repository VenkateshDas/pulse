import Foundation
import Security

/// User-selected provider fields. The API key remains in Keychain; UserDefaults
/// stores only non-secret endpoint and model selections.
public enum AgentConfiguration {
    /// Provider credentials require TLS except for a service on this Mac.
    public static func providerURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard components.scheme?.lowercased() == "https" || (components.scheme?.lowercased() == "http" && local) else { return nil }
        return components.url
    }

    private static let service = "com.pulse.app.agent"
    private static let account = "provider-api-key"
    private static let baseURLKey = "PulseAgentBaseURL"
    private static let modelKey = "PulseAgentModel"

    public static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "https://openrouter.ai/api/v1" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLKey) }
    }

    public static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "openai/gpt-4.1-mini" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelKey) }
    }

    public static var apiKey: String {
        get {
            let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                           kSecAttrAccount: account, kSecReturnData: true]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
        set {
            let data = Data(newValue.utf8)
            let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                           kSecAttrAccount: account]
            if newValue.isEmpty {
                SecItemDelete(query as CFDictionary)
                return
            }
            let update = [kSecValueData: data] as CFDictionary
            if SecItemUpdate(query as CFDictionary, update) == errSecItemNotFound {
                var insert = query; insert[kSecValueData] = data
                insert[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                SecItemAdd(insert as CFDictionary, nil)
            }
        }
    }
}
