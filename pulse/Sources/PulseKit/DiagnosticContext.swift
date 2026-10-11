import AppKit
import Foundation
import SystemConfiguration

public struct NetworkDiagnostic: Codable, Sendable {
    public let timestamp: Date
    public let wifi: WiFiInfo?
    public let proxy: ProxyStatus
    public let primaryInterface: String?
    public let probe: HTTPProbe?
    public let probeError: String?
    public let limitations: [String]

    public static func read(url: String? = nil) async throws -> NetworkDiagnostic {
        let wifi = await WiFiSampler().sample()
        let proxy = await ProxySampler().sample()
        let store = SCDynamicStoreCreate(nil, "Pulse diagnostics" as CFString, nil, nil)
        let route = store.flatMap { store in
            (SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any])
                ?? (SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any])
        }
        let primary = route?["PrimaryInterface"] as? String
        var probe: HTTPProbe?, probeError: String?
        if let url {
            do { probe = try await HTTPProbe.run(url) }
            catch is CancellationError { throw CancellationError() }
            catch { probeError = error.localizedDescription }
        }
        return NetworkDiagnostic(timestamp: .now, wifi: wifi, proxy: proxy, primaryInterface: primary, probe: probe, probeError: probeError,
            limitations: ["A tunnel interface is a clue, not proof of VPN use.", "Wi-Fi identity may require Location permission; unavailable radio fields stay absent.", "HTTP timing is one HEAD request to the selected host, not a speed test; DNS/TLS may be absent on a reused connection."])
    }
}

public struct HTTPProbe: Codable, Sendable {
    public let host: String
    public let statusCode: Int
    public let elapsedMillis: Double
    public let dnsMillis: Double?
    public let connectMillis: Double?
    public let tlsMillis: Double?
    public let responseMillis: Double?

    public static func run(_ raw: String) async throws -> HTTPProbe {
        guard raw.count <= 2048, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw NSError(domain: "Pulse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Select an HTTP(S) URL without credentials"])
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        let collector = ProbeMetrics()
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpMethod = "HEAD"
        let started = ProcessInfo.processInfo.systemUptime
        let (_, response) = try await session.data(for: request, delegate: collector)
        try Task.checkCancellation()
        let metrics = collector.transaction
        func millis(_ begin: Date?, _ end: Date?) -> Double? {
            guard let begin, let end, end >= begin else { return nil }; return end.timeIntervalSince(begin) * 1000
        }
        return HTTPProbe(host: host, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
            elapsedMillis: (ProcessInfo.processInfo.systemUptime - started) * 1000,
            dnsMillis: millis(metrics?.domainLookupStartDate, metrics?.domainLookupEndDate),
            connectMillis: millis(metrics?.connectStartDate, metrics?.connectEndDate),
            tlsMillis: millis(metrics?.secureConnectionStartDate, metrics?.secureConnectionEndDate),
            responseMillis: millis(metrics?.requestEndDate, metrics?.responseStartDate))
    }
}

private final class ProbeMetrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLSessionTaskTransactionMetrics?
    var transaction: URLSessionTaskTransactionMetrics? { lock.lock(); defer { lock.unlock() }; return stored }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock(); stored = metrics.transactionMetrics.last; lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}

public struct ConfiguredHelper: Codable, Sendable, Identifiable {
    public let path: String
    public let label: String
    public let executable: String?
    public let executableExists: Bool?
    public let disabled: Bool
    public let userOwned: Bool
    public var id: String { path }
}
public struct StartupInventory: Codable, Sendable {
    public let items: [ConfiguredHelper]
    public let unreadablePaths: [String]
    public let limitations: [String]
    public static func read() -> StartupInventory {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [home + "/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
        var items: [ConfiguredHelper] = [], unreadable: [String] = []
        for root in roots {
            guard FileManager.default.fileExists(atPath: root) else { continue }
            guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) else { unreadable.append(root); continue }
            for url in urls.sorted(by: { $0.path < $1.path }).prefix(1000) where url.lastPathComponent.hasSuffix(".plist") || url.lastPathComponent.hasSuffix(".plist.disabled") {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), values.isSymbolicLink != true,
                    let size = values.fileSize, size <= 1_048_576,
                    let parsed = HealthSampler.startupItem(at: url, kind: root.hasPrefix(home + "/") ? .userAgent : .globalAgent) else { unreadable.append(url.path); continue }
                let executable = parsed.program
                let exists = executable.flatMap { $0.hasPrefix("/") ? FileManager.default.fileExists(atPath: $0) : nil }
                items.append(ConfiguredHelper(path: url.path, label: parsed.label,
                    executable: executable, executableExists: exists,
                    disabled: !parsed.isEnabled, userOwned: root.hasPrefix(home + "/")))
            }
            if urls.count > 1000 { unreadable.append(root + " (1000-entry limit)") }
        }
        return StartupInventory(items: items, unreadablePaths: unreadable,
            limitations: ["Plist configuration only; not proof a job is loaded or consuming resources.", "Modern background/login items are not fully enumerated; relative executables remain unverified."])
    }
}

public struct DiagnosticHistory: Codable, Sendable {
    public let capturedAt: Date
    public let anomalies: [AnomalyRecord]
    public let unavailable: [String]
    public let metrics: [String: [MinuteHistoryStore.Entry]]
    public let storage: [TimelineSnapshot]
    public let batterySessions: [BatterySession]
    public let limitations: [String]
    public static func read(hours: Int = 24) -> DiagnosticHistory {
        let now = Date(), cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        var metrics: [String: [MinuteHistoryStore.Entry]] = [:]
        var unavailable: [String] = []
        func check<T: Decodable>(_ url: URL?, as type: T.Type) {
            guard let url, let data = try? Data(contentsOf: url) else { unavailable.append("History file unavailable: " + (url?.lastPathComponent ?? "unknown")); return }
            if (try? JSONDecoder().decode(type, from: data)) == nil { unavailable.append("History file could not be decoded: " + url.lastPathComponent) }
        }
        check(AnomalyStore.defaultFileURL(), as: [AnomalyRecord].self)
        check(TimelineStore.defaultFileURL(), as: [TimelineSnapshot].self)
        check(BatterySessionStore.defaultFileURL(), as: [BatterySession].self)
        for name in ["cpu", "memory-pressure", "swap-bytes", "cpu-temperature", "battery-level"] {
            check(MinuteHistoryStore.defaultFileURL(metric: name), as: [MinuteHistoryStore.Entry].self)
            metrics[name] = MinuteHistoryStore(fileURL: MinuteHistoryStore.defaultFileURL(metric: name)).entries.filter { Double($0.minute * 60) >= cutoff.timeIntervalSince1970 }
        }
        return DiagnosticHistory(capturedAt: now, anomalies: AnomalyStore().records.filter { $0.date >= cutoff }, unavailable: unavailable, metrics: metrics,
            storage: TimelineStore().snapshots.filter { $0.date >= cutoff },
            batterySessions: BatterySessionStore().sessions.filter { ($0.endedAt ?? now) >= cutoff },
            limitations: ["History exists only when the app observed it; missing minutes remain gaps.", "Old anomalies carry PID/name only; never use them as identity for a current action.", "Battery app shares are CPU-weighted estimates, not measured per-app energy."])
    }
}

public struct AppQuitResult: Codable, Sendable {
    public let dryRun: Bool
    public let identity: ProcessIdentity
    public let requested: Bool
    public let terminated: Bool
    public let message: String
}
public enum AppQuit {
    @MainActor public static func run(pid: Int32, startToken: String, dryRun: Bool) async throws -> AppQuitResult {
        guard let identity = ProcessIdentity.read(pid), identity.startToken == startToken,
            pid != getpid(), let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
            let bundleID = app.bundleIdentifier, !BundleGuard.isProtected(bundleID: bundleID), bundleID != "com.pulse.app" else {
            throw NSError(domain: "Pulse", code: 2, userInfo: [NSLocalizedDescriptionKey: "Only the exact inspected, regular non-protected application can be asked to quit"])
        }
        if dryRun { return AppQuitResult(dryRun: true, identity: identity, requested: false, terminated: false, message: "Would ask this application to quit; it may prompt to save work. No force quit.") }
        let requested = app.terminate()
        for _ in 0..<10 where !app.isTerminated { try await Task.sleep(for: .milliseconds(200)) }
        return AppQuitResult(dryRun: false, identity: identity, requested: requested, terminated: app.isTerminated,
            message: app.isTerminated ? "Application quit; repeat observation to verify impact" : "Quit not completed; application may need your attention. No force quit sent.")
    }
}
