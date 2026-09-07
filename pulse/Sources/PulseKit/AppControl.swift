import AppKit

/// Per-login-session control. Closed, non-destructive verbs; no arbitrary files or code.
public enum AppControl {
    public static let requestName = Notification.Name("com.pulse.cli.control.v1")
    public struct Request: Codable, Sendable {
        public let id: UUID
        public let action: String
        public let value: Double?
        public let displayID: UInt32?
        public init(action: String, value: Double? = nil, displayID: UInt32? = nil) {
            self.id = UUID(); self.action = action; self.value = value; self.displayID = displayID
        }
    }
    public struct Display: Codable, Sendable {
        public let id: UInt32
        public let name: String
        public let isBuiltIn: Bool
        public let brightness: Double
    }
    public struct Reply: Codable, Sendable {
        public var error: String?
        public var isKeepAwakeActive: Bool?
        public var expiresAt: Date?
        public var displays: [Display]?
        public init(error: String? = nil) { self.error = error }
    }
    public static func responseName(_ id: UUID) -> Notification.Name { Notification.Name("com.pulse.cli.reply.\(id.uuidString)") }
    @MainActor private final class Pending { var reply: Reply? }

    /// No retries for mutations: a timeout may mean the app applied the request.
    @MainActor public static func send(_ request: Request) async throws -> Reply {
        let center = DistributedNotificationCenter.default()
        let pending = Pending()
        let observer = center.addObserver(forName: responseName(request.id), object: nil, queue: .main) { notification in
            guard let payload = notification.userInfo?["payload"] as? String,
                  let reply = try? JSONDecoder().decode(Reply.self, from: Data(payload.utf8)) else { return }
            MainActor.assumeIsolated { pending.reply = reply }
        }
        defer { center.removeObserver(observer) }
        let payload = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        center.postNotificationName(requestName, object: nil, userInfo: ["payload": payload], deliverImmediately: true)
        for _ in 0..<100 {
            if let reply = pending.reply { return reply }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "PulseCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "No acknowledgement from Pulse.app. Launch the rebuilt app. If an action timed out, inspect status before retrying."])
    }
}

/// Retained by the app delegate. Idle cost is one notification observer, no polling.
@MainActor public final class AppControlServer {
    private var observer: NSObjectProtocol?
    public init() {
        observer = DistributedNotificationCenter.default().addObserver(forName: AppControl.requestName, object: nil, queue: .main) { notification in
            guard let payload = notification.userInfo?["payload"] as? String, payload.utf8.count < 4096,
                  let request = try? JSONDecoder().decode(AppControl.Request.self, from: Data(payload.utf8)) else { return }
            Task { @MainActor in
                let reply = await Self.handle(request)
                guard let data = try? JSONEncoder().encode(reply) else { return }
                DistributedNotificationCenter.default().postNotificationName(AppControl.responseName(request.id), object: nil, userInfo: ["payload": String(decoding: data, as: UTF8.self)], deliverImmediately: true)
            }
        }
    }
    public static func handle(_ request: AppControl.Request) async -> AppControl.Reply {
        var reply = AppControl.Reply()
        switch request.action {
        case "sleep.status", "sleep.prevent", "sleep.allow":
            let controller = KeepAwakeController.shared
            if request.action == "sleep.prevent" {
                if let value = request.value, !value.isFinite || value <= 0 || value > 31_536_000 { return .init(error: "Invalid sleep duration") }
                controller.activate(for: request.value)
                if controller.lastActivationFailed { return .init(error: "IOKit refused the sleep assertion") }
            } else if request.action == "sleep.allow" { controller.deactivate() }
            reply.isKeepAwakeActive = controller.isActive
            reply.expiresAt = controller.expiresAt
        case "display.get", "display.set":
            let engine = BrightnessEngine.shared
            let monitors = engine.monitors.filter { request.displayID == nil || $0.id == request.displayID }
            guard !monitors.isEmpty else { return .init(error: "No matching displays") }
            if request.action == "display.set" {
                guard let value = request.value, value.isFinite, (-1...1).contains(value) else { return .init(error: "Brightness must be from -1 to 1") }
                engine.isAdaptiveModeEnabled = false
                for monitor in monitors { engine.setBrightness(for: monitor, to: value, showOSD: false) }
                guard await engine.waitForPendingWrites() else { return .init(error: "Display write still pending; inspect display state before retrying") }
                let errors = monitors.compactMap { engine.lastWriteErrors[$0.id] }
                if !errors.isEmpty { return .init(error: errors.joined(separator: "; ")) }
                MenuBarFlash.shared.flash("sun.max.fill")
            }
            reply.displays = monitors.map { AppControl.Display(id: $0.id, name: $0.name, isBuiltIn: $0.isBuiltIn, brightness: engine.brightnessMap[$0.id] ?? engine.getBrightness(for: $0)) }
        default: return .init(error: "Unknown control action")
        }
        return reply
    }
}
