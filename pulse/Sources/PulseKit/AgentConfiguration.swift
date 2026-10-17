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

    private static let credentialEndpointKey = "PulseAgentCredentialEndpoint"
    private static let credentials = AgentCredentialStore(read: readAPIKey, write: writeAPIKey)
    private static let credentialLog = Logger(subsystem: "com.pulse.app", category: "AgentCredentials")

    public static func credentialsMatch(selectedEndpoint: String, storedEndpoint: String) -> Bool {
        selectedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == storedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Compatibility flag retained; routine credential access never presents authentication UI.
    public static func loadAPIKey(interactive: Bool = false, endpoint: String? = nil) async -> String {
        await credentials.load(endpoint: endpoint ?? baseURL)
    }

    /// Captured before awaits; never pair an old key with newly edited settings.
    public static var runtimeEnvironment: [String: String] {
        ["OPENAI_BASE_URL": baseURL, "PULSE_MODEL_ID": model, "PULSE_PROVIDER": provider,
         "PULSE_CONTEXT_TOKENS": String(contextTokens), "PULSE_OUTPUT_TOKENS": String(outputTokens),
         "PULSE_MEMORY_ENABLED": memoryEnabled ? "true" : "false"]
    }

    public static func saveAPIKey(_ value: String, endpoint: String? = nil) async -> Bool {
        let selectedEndpoint = endpoint ?? baseURL
        return await Task.detached(priority: .userInitiated) {
            credentials.save(value, endpoint: selectedEndpoint)
        }.value
    }

    private static func readAPIKey(endpoint: String) -> String? {
        // Legacy keys stay bound to the endpoint recorded when saved.
        let persisted = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.pulse.app")
        let savedEndpoint = UserDefaults.standard.string(forKey: credentialEndpointKey) ?? persisted?[baseURLKey] as? String ?? "https://openrouter.ai/api/v1"
        guard credentialsMatch(selectedEndpoint: endpoint, storedEndpoint: savedEndpoint) else { return nil }
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true, kSecUseAuthenticationUI: kSecUseAuthenticationUIFail]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound { credentialLog.error("Silent credential read failed status=\(status)") }
        guard status == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func writeAPIKey(_ value: String, endpoint: String) -> Bool {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecUseAuthenticationUI: kSecUseAuthenticationUIFail]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { credentialLog.error("Credential delete failed status=\(status)"); return false }
            UserDefaults.standard.removeObject(forKey: credentialEndpointKey)
            return true
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData] = data
            insert[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { credentialLog.error("Credential save failed status=\(status)"); return false }
        UserDefaults.standard.set(endpoint, forKey: credentialEndpointKey)
        return true
    }

    public static var apiKey: String {
        get { credentials.loadSynchronously(endpoint: baseURL) }
        set { _ = credentials.save(newValue, endpoint: baseURL) }
    }
}

/// Instance-owned seam keeps credential tests away from the user's Keychain.
/// Security calls run outside the state lock; generations reject superseded reads.
final class AgentCredentialStore: Sendable {
    private struct PendingRead: Sendable {
        let id = UUID()
        let generation: UInt64
        let task: Task<String?, Never>
    }
    private struct State {
        var generation: UInt64 = 0
        var cache: (endpoint: String, value: String)?
        var pending: [String: PendingRead] = [:]
        var writing = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let writes = OSAllocatedUnfairLock(initialState: false)
    private let read: @Sendable (String) -> String?
    private let write: @Sendable (String, String) -> Bool

    init(read: @escaping @Sendable (String) -> String?, write: @escaping @Sendable (String, String) -> Bool) {
        self.read = read
        self.write = write
    }

    private func cached(_ endpoint: String, in state: State) -> String? {
        guard let cache = state.cache,
              AgentConfiguration.credentialsMatch(selectedEndpoint: endpoint, storedEndpoint: cache.endpoint) else { return nil }
        return cache.value
    }

    func load(endpoint: String) async -> String {
        let selection = state.withLock { state -> (String?, PendingRead?) in
            if let value = cached(endpoint, in: state) { return (value, nil) }
            guard !state.writing else { return ("", nil) }
            if let pending = state.pending[endpoint] { return (nil, pending) }
            guard state.pending.count < 8 else { return ("", nil) }
            let read = self.read
            let pending = PendingRead(generation: state.generation,
                task: Task.detached(priority: .userInitiated) { read(endpoint) })
            state.pending[endpoint] = pending
            return (nil, pending)
        }
        if let cached = selection.0 { return cached }
        guard let pending = selection.1 else { return "" }
        // Even no-UI securityd requests can stall. Keep UI startup bounded.
        return await withCheckedContinuation { continuation in
            let completed = OSAllocatedUnfairLock(initialState: false)
            Task {
                let value = await pending.task.value
                let accepted = state.withLock { state -> String in
                    if state.pending[endpoint]?.id == pending.id { state.pending[endpoint] = nil }
                    guard state.generation == pending.generation, !state.writing else { return "" }
                    if let value { state.cache = (endpoint, value) }
                    return value ?? ""
                }
                if completed.withLock({ done in if done { return false }; done = true; return true }) {
                    continuation.resume(returning: accepted)
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                if completed.withLock({ done in if done { return false }; done = true; return true }) {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    func loadSynchronously(endpoint: String) -> String {
        let snapshot = state.withLock { state in (cached(endpoint, in: state), state.generation, state.writing) }
        if let value = snapshot.0 { return value }
        guard !snapshot.2 else { return "" }
        let value = read(endpoint)
        return state.withLock { state in
            guard state.generation == snapshot.1, !state.writing else { return "" }
            if let value { state.cache = (endpoint, value) }
            return value ?? ""
        }
    }

    func save(_ value: String, endpoint: String) -> Bool {
        // Serialize writes while allowing an older securityd read to finish independently.
        writes.withLock { _ in
            state.withLock { state in
                state.generation &+= 1
                state.writing = true
                state.cache = nil
                state.pending.removeAll()
            }
            let succeeded = write(value, endpoint)
            state.withLock { state in
                state.writing = false
                if succeeded { state.cache = (endpoint, value) }
            }
            return succeeded
        }
    }
}
