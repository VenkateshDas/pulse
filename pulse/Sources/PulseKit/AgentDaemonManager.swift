import Foundation

/// Starts the explicitly permitted local OpenWorker sidecar only when Ask Pulse needs it.
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

    public func ensureRunning(apiKey: String? = nil, providerEnvironment: [String: String]? = nil) async -> Bool {
        let selection = providerEnvironment ?? AgentConfiguration.runtimeEnvironment
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
        if let apiKey { selectedKey = apiKey } else { selectedKey = await AgentConfiguration.loadAPIKey(endpoint: selection["OPENAI_BASE_URL"]) }
        let process = Process()
        process.executableURL = script; process.currentDirectoryURL = script.deletingLastPathComponent()
        process.environment = ProcessInfo.processInfo.environment.merging(selection) { _, new in new }.merging([
            "PULSE_PARENT_PID": String(ProcessInfo.processInfo.processIdentifier),
            "PULSE_AGENT_TOKEN": token,
            "PULSE_AGENT_PORT": "\(port)",
            "OPENAI_API_KEY": selectedKey,
            "PULSE_NATIVE_PORT": nativePort.map(String.init) ?? "",
            "PULSE_NATIVE_TOKEN": nativeToken,
            "PULSE_AGENT_RUNTIME_DIR": runtimeDirectory.path,
            "PULSE_SKILL_DIR": Self.skillDirectory(bundleResourceURL: Bundle.main.resourceURL, currentDirectoryURL: root),
        ]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        let logURL = runtimeDirectory.appendingPathComponent("runtime.log")
        if let size = try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber, size.intValue > 1_000_000 {
            let previous = runtimeDirectory.appendingPathComponent("runtime.previous.log")
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: logURL, to: previous)
        }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let logHandle = try? FileHandle(forWritingTo: logURL)
        _ = try? logHandle?.seekToEnd()
        process.standardError = logHandle ?? FileHandle.nullDevice
        defer { try? logHandle?.close() }
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
