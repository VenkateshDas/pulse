import Foundation

public struct AgentUsageSnapshot: Codable, Sendable, Equatable {
    public let context: AgentContextUsage?
    public let totals: AgentUsageTotals
    public let historical: Bool
}
public struct AgentContextUsage: Codable, Sendable, Equatable {
    public struct Category: Codable, Sendable, Equatable { public let label: String; public let tokens: Int }
    public let estimatedTokens: Int
    public let limit: Int
    public let outputReserve: Int
    public let purpose: String
    public let model: String
    public let measuredAt: Int
    public let categories: [Category]
    public let reportedTokens: Int?
}
public struct AgentUsageTotals: Codable, Sendable, Equatable {
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let totalTokens: Int
    public let requests: Int
    public let missingUsage: Int
    public let missingCost: Int
    public let costUSD: String?
    public let compactionTokens: Int
}

/// Pulse-owned event contract. Python runtime detail never reaches SwiftUI.
public struct AgentEnvelope: Codable, Identifiable, Sendable {
    public let version: Int
    public let eventId: String
    public let sequence: Int
    public let runId: String
    public let sessionId: String
    public let timestamp: Date
    public let kind: String
    public let payload: [String: String]
    public var id: String { eventId }

    enum CodingKeys: String, CodingKey {
        case version, sequence, timestamp, kind, payload
        case eventId = "event_id"
        case runId = "run_id"
        case sessionId = "session_id"
    }

    public init(version: Int = 1, eventId: String = UUID().uuidString, sequence: Int,
                runId: String, sessionId: String, timestamp: Date = .now,
                kind: String, payload: [String: String] = [:]) {
        self.version = version; self.eventId = eventId; self.sequence = sequence
        self.runId = runId; self.sessionId = sessionId; self.timestamp = timestamp
        self.kind = kind; self.payload = payload
    }
}

public struct AgentDaemonStatus: Sendable {
    public let isOnline: Bool
    public let hasApiKey: Bool
    public let summary: String?
    public init(isOnline: Bool, hasApiKey: Bool, summary: String? = nil) {
        self.isOnline = isOnline; self.hasApiKey = hasApiKey; self.summary = summary
    }
}

public struct AgentSessionItem: Identifiable, Codable, Sendable {
    public var id: String { sessionId }
    public let sessionId: String
    public let name: String
    public let createdAt: Int?
    public let updatedAt: Int?
    public let pinned: Bool?
    public let archived: Bool?
    public init(sessionId: String, name: String, createdAt: Int? = nil, updatedAt: Int? = nil, pinned: Bool? = nil, archived: Bool? = nil) {
        self.sessionId = sessionId; self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt; self.pinned = pinned; self.archived = archived
    }
}

public struct AgentHistoryMessage: Codable, Sendable {
    public let role: String
    public let content: String
    public var id: String? = nil
    public var name: String? = nil
    public var status: String? = nil
}

/// Local authenticated SSE client. No UI types belong here.
public actor AgentClient {
    public static let shared = AgentClient()
    private var baseURL = URL(string: "http://127.0.0.1:7777")!
    private var bearerToken: String?

    public func configure(bearerToken: String, port: Int) {
        self.bearerToken = bearerToken
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    public func checkStatus() async -> AgentDaemonStatus {
        do {
            let (data, response) = try await URLSession.shared.data(for: request(path: "/status"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .init(isOnline: false, hasApiKey: false) }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return .init(isOnline: true, hasApiKey: json?["has_api_key"] as? Bool ?? false,
                         summary: json?["summary"] as? String)
        } catch { return .init(isOnline: false, hasApiKey: false) }
    }

    public func run(message: String, sessionId: String?, runId: String = UUID().uuidString, readOnly: Bool = false, specialist: String = "general") -> AsyncThrowingStream<AgentEnvelope, Error> {
        return stream(path: "/runs", body: ["message": message, "session_id": sessionId ?? UUID().uuidString, "request_id": runId, "mode": readOnly ? "investigate" : "interactive", "specialist": specialist], runId: runId)
    }

    public func continueRun(runId: String, approved: Bool, approvalId: String, afterSequence: Int = 0) -> AsyncThrowingStream<AgentEnvelope, Error> {
        stream(path: "/runs/\(runId)/continue", body: ["approved": approved, "approval_id": approvalId], runId: runId, afterSequence: afterSequence)
    }

    public func answerQuestion(runId: String, approvalId: String, answer: String, afterSequence: Int) -> AsyncThrowingStream<AgentEnvelope, Error> {
        stream(path: "/runs/\(runId)/continue", body: ["answer": answer, "approval_id": approvalId], runId: runId, afterSequence: afterSequence)
    }

    public func cancel(runId: String) async throws {
        let (_, response) = try await URLSession.shared.data(for: request(path: "/runs/\(runId)/cancel", method: "POST"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    public func updateConfiguration(baseURL: String, apiKey: String, model: String, configuration: [String: String]? = nil) async throws {
        let selection = configuration ?? AgentConfiguration.runtimeEnvironment
        let body: [String: Any] = ["base_url": baseURL, "api_key": apiKey, "model": model,
                                 "provider": selection["PULSE_PROVIDER"] ?? "openai-chat", "memory_enabled": selection["PULSE_MEMORY_ENABLED"] == "true",
                                 "context_tokens": Int(selection["PULSE_CONTEXT_TOKENS"] ?? "32768") ?? 32768,
                                 "output_tokens": Int(selection["PULSE_OUTPUT_TOKENS"] ?? "4096") ?? 4096]
        var request = request(path: "/config", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    public func fetchSessions(query: String = "", archived: Bool = false) async throws -> [AgentSessionItem] {
        var parts = URLComponents(); parts.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "archived", value: archived ? "true" : "false")]
        let data = try await workspaceRequest(path: "/sessions?" + (parts.percentEncodedQuery ?? ""))
        struct Response: Decodable { let sessions: [Session]; struct Session: Decodable { let session_id: String; let name: String; let created_at: Int?; let updated_at: Int?; let pinned: Bool?; let archived: Bool? } }
        return try JSONDecoder.agent.decode(Response.self, from: data).sessions.map {
            .init(sessionId: $0.session_id, name: $0.name, createdAt: $0.created_at, updatedAt: $0.updated_at, pinned: $0.pinned, archived: $0.archived)
        }
    }

    public func awaitTitle(sessionId: String) async {
        var request = request(path: "/sessions/\(sessionId)/title"); request.timeoutInterval = 68
        _ = try? await URLSession.shared.data(for: request)
    }

    public func workspaceRequest(path: String, method: String = "GET", body: [String: String]? = nil, flags: [String: Bool] = [:]) async throws -> Data {
        var request = request(path: path, method: method)
        if body != nil || !flags.isEmpty {
            var value: [String: Any] = body ?? [:]
            for (key, flag) in flags { value[key] = flag }
            // Revision is numeric in the authenticated schema.
            if let revision = body?["revision"], let number = Int(revision) { value["revision"] = number }
            request.httpBody = try JSONSerialization.data(withJSONObject: value)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard data.count <= 512_000 else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }

    public func fetchUsage(sessionId: String) async throws -> AgentUsageSnapshot {
        let (data, response) = try await URLSession.shared.data(for: request(path: "/sessions/\(sessionId)/usage"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder.agent.decode(AgentUsageSnapshot.self, from: data)
    }

    public func fetchHistory(sessionId: String) async throws -> [AgentHistoryMessage] {
        let (data, _) = try await URLSession.shared.data(for: request(path: "/sessions/\(sessionId)/history"))
        struct Response: Decodable { let messages: [AgentHistoryMessage] }
        return try JSONDecoder.agent.decode(Response.self, from: data).messages
    }

    public struct HistoryPage: Decodable, Sendable {
        public let messages: [AgentHistoryMessage]
        public let hasMore: Bool
        public let interrupted: Bool?
        enum CodingKeys: String, CodingKey { case messages, interrupted; case hasMore = "has_more" }
    }
    public func fetchHistoryPage(sessionId: String, page: Int) async throws -> HistoryPage {
        let (data, response) = try await URLSession.shared.data(for: request(path: "/sessions/\(sessionId)/history?page=\(page)"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder.agent.decode(HistoryPage.self, from: data)
    }

    public func memoryRequest(path: String = "/memory", method: String = "GET") async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path: path, method: method))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private func stream(path: String, body: [String: Any], runId: String, afterSequence: Int = 0) -> AsyncThrowingStream<AgentEnvelope, Error> {
        let token = bearerToken, baseURL = baseURL
        let encodedBody = try? JSONSerialization.data(withJSONObject: body)
        return AsyncThrowingStream { continuation in
            let streamTask = Task {
                var sequence = afterSequence
                var lastError: Error = URLError(.networkConnectionLost)
                for attempt in 0..<4 {
                    guard !Task.isCancelled else { break }
                    let route = attempt == 0 ? path : "/runs/\(runId)/stream?after_sequence=\(sequence)"
                    var request = URLRequest(url: URL(string: route, relativeTo: baseURL)!)
                    request.httpMethod = attempt == 0 ? "POST" : "GET"
                    request.timeoutInterval = 120
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    if attempt == 0 { request.httpBody = encodedBody }
                    do {
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        if (response as? HTTPURLResponse)?.statusCode == 404 && attempt > 0 {
                            // The original POST may still be constructing its run.
                            try? await Task.sleep(for: .milliseconds(750)); continue
                        }
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                            // Include HTTP/replay failures in bounded recovery and
                            // eventual cancellation; never abandon an unseen run.
                            throw URLError(.badServerResponse)
                        }
                        for try await line in bytes.lines where line.hasPrefix("data:") {
                            let text = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            guard let data = text.data(using: .utf8) else { continue }
                            let event = try JSONDecoder.agent.decode(AgentEnvelope.self, from: data)
                            guard event.sequence > sequence else { continue }
                            sequence = event.sequence; continuation.yield(event)
                            if ["run.completed", "run.failed", "run.cancelled", "run.paused"].contains(event.kind) {
                                continuation.finish(); return
                            }
                        }
                    } catch { lastError = error }
                    if attempt < 3 { try? await Task.sleep(for: .milliseconds(250 * (attempt + 1))) }
                    }
                if !Task.isCancelled {
                    // Never leave a request that failed before its first event running unseen.
                    var stop = URLRequest(url: URL(string: "/runs/\(runId)/cancel", relativeTo: baseURL)!)
                    stop.httpMethod = "POST"; stop.timeoutInterval = 5
                    if let token { stop.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    _ = try? await URLSession.shared.data(for: stop)
                }
                continuation.finish(throwing: lastError)
            }
            continuation.onTermination = { @Sendable _ in streamTask.cancel() }
        }
    }

    private func request(path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method; request.timeoutInterval = 5
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        return request
    }
}

private extension JSONDecoder {
    static let agent: JSONDecoder = { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }()
}
