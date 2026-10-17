import Foundation

/// Starts the explicitly permitted local Agno sidecar only when Agent needs it.
public actor AgentDaemonManager {
    public static let shared = AgentDaemonManager()
    private var isStarting = false
    private var process: Process?
    private var nativePort: UInt16?
    private var nativeToken = ""
    private let token = UUID().uuidString + UUID().uuidString
    /// Random loopback port avoids colliding with stale development servers.
    private let port = Int.random(in: 38_000...47_999)
    private init() {}

    public func configureNativeBridge(port: UInt16, token: String) {
        nativePort = port; nativeToken = token
    }

    public func shutdown() {
        process?.terminate(); process = nil
    }

    public func ensureRunning(apiKey: String? = nil) async -> Bool {
        await AgentClient.shared.configure(bearerToken: token, port: port)
        if await AgentClient.shared.checkStatus().isOnline { return true }
        guard !isStarting else { return await waitForStatus() }
        isStarting = true; defer { isStarting = false }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let script = Self.agentScriptURL(bundleResourceURL: Bundle.main.resourceURL, currentDirectoryURL: root) else { return false }
        let runtimeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pulse/agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let selectedKey: String
        if let apiKey { selectedKey = apiKey } else { selectedKey = await AgentConfiguration.loadAPIKey() }
        let process = Process()
        process.executableURL = script; process.currentDirectoryURL = script.deletingLastPathComponent()
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PULSE_PARENT_PID": String(ProcessInfo.processInfo.processIdentifier),
            "PULSE_AGENT_TOKEN": token,
            "PULSE_AGENT_PORT": "\(port)",
            "OPENAI_API_KEY": selectedKey,
            "OPENAI_BASE_URL": AgentConfiguration.baseURL,
            "PULSE_MODEL_ID": AgentConfiguration.model,
            "PULSE_PROVIDER": AgentConfiguration.provider,
            "PULSE_CONTEXT_TOKENS": String(AgentConfiguration.contextTokens),
            "PULSE_OUTPUT_TOKENS": String(AgentConfiguration.outputTokens),
            "PULSE_MEMORY_ENABLED": AgentConfiguration.memoryEnabled ? "true" : "false",
            "PULSE_NATIVE_PORT": nativePort.map(String.init) ?? "",
            "PULSE_NATIVE_TOKEN": nativeToken,
            "PULSE_AGENT_RUNTIME_DIR": runtimeDirectory.path,
            "PULSE_SKILL_DIR": Self.skillDirectory(bundleResourceURL: Bundle.main.resourceURL, currentDirectoryURL: root),
        ]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        let logURL = runtimeDirectory.appendingPathComponent("runtime.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        process.standardError = (try? FileHandle(forWritingTo: logURL)) ?? FileHandle.nullDevice
        do { try process.run() } catch { return false }
        self.process = process
        return await waitForStatus()
    }

    private func waitForStatus() async -> Bool {
        // First launch may create the isolated Python environment and install
        // dependencies. Keep the UI in its existing "Starting" state until it
        // either becomes healthy or this bounded one-minute setup window ends.
        for _ in 0..<240 {
            if let process, !process.isRunning { return false }
            try? await Task.sleep(for: .milliseconds(250))
            if await AgentClient.shared.checkStatus().isOnline { return true }
        }
        return false
    }

    nonisolated static func skillDirectory(bundleResourceURL: URL?, currentDirectoryURL: URL) -> String {
        let candidates = [bundleResourceURL?.appendingPathComponent("skills/pulse"), currentDirectoryURL.appendingPathComponent(".agents/skills/pulse"), currentDirectoryURL.deletingLastPathComponent().appendingPathComponent(".agents/skills/pulse")].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }?.path ?? ""
    }

    /// Production uses the bundled runtime. Source-tree fallbacks keep local
    /// SwiftPM development working without embedding a second copy.
    nonisolated static func agentScriptURL(bundleResourceURL: URL?, currentDirectoryURL: URL) -> URL? {
        let candidates = [
            bundleResourceURL?.appendingPathComponent("pulse-agent/start.sh"),
            currentDirectoryURL.appendingPathComponent("pulse-agent/start.sh"),
            currentDirectoryURL.deletingLastPathComponent().appendingPathComponent("pulse-agent/start.sh"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
