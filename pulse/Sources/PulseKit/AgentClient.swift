import Foundation

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
    public init(sessionId: String, name: String, createdAt: Int? = nil, updatedAt: Int? = nil) {
        self.sessionId = sessionId; self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct AgentHistoryMessage: Codable, Sendable {
    public let role: String
    public let content: String
}

public struct AgentHistoryPage: Codable, Sendable {
    public let messages: [AgentHistoryMessage]
    public let nextOffset: Int?

    enum CodingKeys: String, CodingKey { case messages; case nextOffset = "next_offset" }
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

    public func run(message: String, sessionId: String?) -> AsyncThrowingStream<AgentEnvelope, Error> {
        stream(path: "/runs", body: ["message": message, "session_id": sessionId ?? ""])
    }

    public func continueRun(runId: String, approved: Bool) -> AsyncThrowingStream<AgentEnvelope, Error> {
        stream(path: "/runs/\(runId)/continue", body: ["approved": approved])
    }

    public func cancel(runId: String) async throws {
        _ = try await URLSession.shared.data(for: request(path: "/runs/\(runId)/cancel", method: "POST"))
    }

    public func updateConfiguration(baseURL: String, apiKey: String, model: String) async throws {
        let body: [String: Any] = ["base_url": baseURL, "api_key": apiKey, "model": model]
        var request = request(path: "/config", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    public func fetchSessions() async throws -> [AgentSessionItem] {
        let (data, _) = try await URLSession.shared.data(for: request(path: "/sessions"))
        struct Response: Decodable { let sessions: [Session]; struct Session: Decodable { let session_id: String; let name: String; let created_at: Int?; let updated_at: Int? } }
        return try JSONDecoder.agent.decode(Response.self, from: data).sessions.map {
            .init(sessionId: $0.session_id, name: $0.name, createdAt: $0.created_at, updatedAt: $0.updated_at)
        }
    }

    public func fetchHistory(sessionId: String, offset: Int = 0) async throws -> AgentHistoryPage {
        let (data, _) = try await URLSession.shared.data(for: request(path: "/sessions/\(sessionId)/history?offset=\(offset)"))
        return try JSONDecoder.agent.decode(AgentHistoryPage.self, from: data)
    }

    private func stream(path: String, body: [String: Any]) -> AsyncThrowingStream<AgentEnvelope, Error> {
        let token = bearerToken, url = URL(string: path, relativeTo: baseURL)!
        let encodedBody = try? JSONSerialization.data(withJSONObject: body)
        return AsyncThrowingStream { continuation in
            let requestTask = Task {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"; request.timeoutInterval = 120
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                request.httpBody = encodedBody
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let text = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let data = text.data(using: .utf8) else { continue }
                        continuation.yield(try JSONDecoder.agent.decode(AgentEnvelope.self, from: data))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in requestTask.cancel() }
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
