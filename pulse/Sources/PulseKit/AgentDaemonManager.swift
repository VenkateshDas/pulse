import Foundation

/// Starts the explicitly permitted local Agno sidecar only when Agent needs it.
public actor AgentDaemonManager {
    public static let shared = AgentDaemonManager()
    private var isStarting = false
    private let token = UUID().uuidString + UUID().uuidString
    /// Random loopback port avoids colliding with stale development servers.
    private let port = Int.random(in: 38_000...47_999)
    private init() {}

    public func ensureRunning() async -> Bool {
        await AgentClient.shared.configure(bearerToken: token, port: port)
        if await AgentClient.shared.checkStatus().isOnline { return true }
        guard !isStarting else { return await waitForStatus() }
        isStarting = true; defer { isStarting = false }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let script = Self.agentScriptURL(bundleResourceURL: Bundle.main.resourceURL, currentDirectoryURL: root) else { return false }
        let runtimeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pulse/agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let cliPath = Bundle.main.resourceURL?.appendingPathComponent("pulse").path ?? ""
        let process = Process()
        process.executableURL = script; process.currentDirectoryURL = script.deletingLastPathComponent()
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PULSE_AGENT_TOKEN": token,
            "PULSE_AGENT_PORT": "\(port)",
            "OPENAI_API_KEY": AgentConfiguration.apiKey,
            "OPENAI_BASE_URL": AgentConfiguration.baseURL,
            "PULSE_MODEL_ID": AgentConfiguration.model,
            "PULSE_AGENT_RUNTIME_DIR": runtimeDirectory.path,
            "PULSE_CLI_PATH": cliPath,
            "PULSE_SKILL_DIR": Bundle.main.resourceURL?.appendingPathComponent("pulse-skill").path ?? "",
        ]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        return await waitForStatus()
    }

    private func waitForStatus() async -> Bool {
        // First launch may create the isolated Python environment and install
        // dependencies. Keep the UI in its existing "Starting" state until it
        // either becomes healthy or this bounded one-minute setup window ends.
        for _ in 0..<240 {
            try? await Task.sleep(for: .milliseconds(250))
            if await AgentClient.shared.checkStatus().isOnline { return true }
        }
        return false
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
