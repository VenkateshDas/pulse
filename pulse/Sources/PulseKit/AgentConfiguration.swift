import Foundation
import Security
import os

/// User-selected provider fields. The API key remains in Keychain; UserDefaults
/// stores only non-secret endpoint and model selections.
public enum AgentConfiguration {
    public static var provider: String {
        get { UserDefaults.standard.string(forKey: "PulseAgentProvider") ?? "openai-chat" }
        set { UserDefaults.standard.set(newValue, forKey: "PulseAgentProvider") }
    }
    public static var contextTokens: Int {
        get { UserDefaults.standard.object(forKey: "PulseAgentContextTokens") as? Int ?? 32768 }
        set { UserDefaults.standard.set(newValue, forKey: "PulseAgentContextTokens") }
    }
    public static var outputTokens: Int {
        get { UserDefaults.standard.object(forKey: "PulseAgentOutputTokens") as? Int ?? 4096 }
        set { UserDefaults.standard.set(newValue, forKey: "PulseAgentOutputTokens") }
    }
    public static var memoryEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "PulseAgentMemory") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "PulseAgentMemory") }
    }
    public static func isReady(baseURL: String, apiKey: String, provider: String) -> Bool {
        guard let url = providerURL(baseURL) else { return false }
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? "")
        return !apiKey.isEmpty || (local && ["openai-chat", "ollama"].contains(provider))
    }
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

    private struct CredentialRead: Sendable {
        let id = UUID()
        let task: Task<String, Never>
    }
    private static let pendingReads = OSAllocatedUnfairLock(initialState: [String: CredentialRead]())
    private static let credentialEndpointKey = "PulseAgentCredentialEndpoint"

    public static func credentialsMatch(selectedEndpoint: String, storedEndpoint: String) -> Bool {
        selectedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == storedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public static func loadAPIKey(interactive: Bool = false) async -> String {
        let endpoint = baseURL + (interactive ? "#interactive" : "#silent")
        let read = pendingReads.withLock { reads -> CredentialRead? in
            if let existing = reads[endpoint] { return existing }
            guard reads.count < 8 else { return nil }
            let item = CredentialRead(task: Task.detached(priority: .userInitiated) { readAPIKey(interactive: interactive) })
            reads[endpoint] = item; return item
        }
        guard let read else { return "" }
        // Legacy macOS Keychain calls can wait for securityd despite no-UI.
        // Coalesce pending reads and bound UI startup without blocking an actor.
        return await withCheckedContinuation { continuation in
            let completed = OSAllocatedUnfairLock(initialState: false)
            Task {
                let value = await read.task.value
                pendingReads.withLock { if $0[endpoint]?.id == read.id { $0[endpoint] = nil } }
                if completed.withLock({ done in if done { return false }; done = true; return true }) { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                if completed.withLock({ done in if done { return false }; done = true; return true }) { continuation.resume(returning: "") }
            }
        }
    }
    public static func saveAPIKey(_ value: String) async -> Bool {
        await Task.detached(priority: .userInitiated) { apiKey = value; return apiKey == value }.value
    }

    private static func readAPIKey(interactive: Bool) -> String {
        // Never forward a saved provider's secret to a newly selected endpoint.
        // Legacy keys belong to the endpoint in the persisted app settings.
        let persisted = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.pulse.app")
        let savedEndpoint = UserDefaults.standard.string(forKey: credentialEndpointKey) ?? persisted?[baseURLKey] as? String ?? "https://openrouter.ai/api/v1"
        guard credentialsMatch(selectedEndpoint: baseURL, storedEndpoint: savedEndpoint) else { return "" }
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                       kSecAttrAccount: account, kSecReturnData: true]
        if !interactive { query[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public static var apiKey: String {
        get { readAPIKey(interactive: false) }
        set {
            let data = Data(newValue.utf8)
            let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                           kSecAttrAccount: account]
            if newValue.isEmpty {
                if SecItemDelete(query as CFDictionary) == errSecSuccess { UserDefaults.standard.removeObject(forKey: credentialEndpointKey) }
                return
            }
            let update = [kSecValueData: data] as CFDictionary
            var status = SecItemUpdate(query as CFDictionary, update)
            if status == errSecItemNotFound {
                var insert = query; insert[kSecValueData] = data
                insert[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(insert as CFDictionary, nil)
            }
            if status == errSecSuccess { UserDefaults.standard.set(baseURL, forKey: credentialEndpointKey) }
        }
    }
}
