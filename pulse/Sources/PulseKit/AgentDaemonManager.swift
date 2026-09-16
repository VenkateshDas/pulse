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
        let candidates = [root.appendingPathComponent("pulse-agent/start.sh"), root.deletingLastPathComponent().appendingPathComponent("pulse-agent/start.sh")]
        guard let script = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return false }
        let process = Process()
        process.executableURL = script; process.currentDirectoryURL = script.deletingLastPathComponent()
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PULSE_AGENT_TOKEN": token,
            "PULSE_AGENT_PORT": "\(port)",
            "OPENAI_API_KEY": AgentConfiguration.apiKey,
            "OPENAI_BASE_URL": AgentConfiguration.baseURL,
            "PULSE_MODEL_ID": AgentConfiguration.model,
        ]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        return await waitForStatus()
    }

    private func waitForStatus() async -> Bool {
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            if await AgentClient.shared.checkStatus().isOnline { return true }
        }
        return false
    }
}
