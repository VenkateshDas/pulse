import Foundation
import Network
import PulseCommands

/// Loopback, length-bounded JSON RPC for the authenticated Agno sidecar.
/// The browser never receives this credential. Commands execute in this process.
actor AgentNativeBridge {
    static let shared = AgentNativeBridge()
    private var listener: NWListener?
    private var credential = ""
    private var tasks: [String: Task<Void, Never>] = [:]
    private var taskRuns: [String: String] = [:]
    private var requestIDs: [String: Date] = [:]
    private var connections: [UUID: NWConnection] = [:]
    private var cancelledRuns: [String: Date] = [:]
    private var contextProvider: (@MainActor @Sendable () -> String)?
    private let queue = DispatchQueue(label: "com.pulse.agent.native")

    struct Request: Decodable, Sendable {
        let version: Int
        let token: String
        let requestID: String
        let runID: String
        let sessionID: String
        let arguments: [String]
        let cancel: Bool?
        enum CodingKeys: String, CodingKey {
            case version, token, arguments, cancel
            case requestID = "request_id", runID = "run_id", sessionID = "session_id"
        }
    }
    struct Response: Encodable { let request_id: String; let json: String; let exit_code: Int32 }

    func configureContext(_ provider: @escaping @MainActor @Sendable () -> String) { contextProvider = provider }

    func start(token: String) async throws -> UInt16 {
        if let port = listener?.port?.rawValue { return port }
        credential = token
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let service = try NWListener(using: parameters)
        listener = service
        service.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            service.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    service.stateUpdateHandler = nil
                    if let port = service.port?.rawValue { continuation.resume(returning: port) }
                    else { continuation.resume(throwing: URLError(.cannotConnectToHost)) }
                case .failed(let error):
                    service.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            service.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        for task in tasks.values { task.cancel() }; tasks.removeAll()
        for connection in connections.values { connection.cancel() }; connections.removeAll()
        cancelledRuns.removeAll(); requestIDs.removeAll(); taskRuns.removeAll(); credential = ""
    }

    private func accept(_ connection: NWConnection) {
        let cutoff = Date.now.addingTimeInterval(-900)
        requestIDs = requestIDs.filter { $0.value > cutoff }
        cancelledRuns = cancelledRuns.filter { $0.value > cutoff }
        guard connections.count < 8 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: queue)
        receive(connection, id: id, buffer: Data())
        // Slow/incomplete senders cannot occupy all connections indefinitely.
        queue.asyncAfter(deadline: .now() + 660) { [weak connection] in connection?.cancel() }
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { await self?.received(connection, id: id, buffer: buffer, data: data, complete: complete, failed: error != nil) }
        }
    }

    private func received(_ connection: NWConnection, id: UUID, buffer: Data, data: Data?, complete: Bool, failed: Bool) {
        var bytes = buffer; if let data { bytes.append(data) }
        guard bytes.count <= 16_384, !failed else { close(connection, id: id); return }
        if let end = bytes.firstIndex(of: 10) {
            guard let request = try? JSONDecoder().decode(Request.self, from: bytes[..<end]),
                  request.version == 1, !credential.isEmpty, request.token == credential,
                  UUID(uuidString: request.runID) != nil, UUID(uuidString: request.requestID) != nil,
                  request.sessionID.count <= 128, request.arguments.count <= 20,
                  request.arguments.allSatisfy({ $0.utf8.count <= 4096 }) else {
                close(connection, id: id); return
            }
            if request.cancel == true {
                cancelledRuns[request.runID] = .now
                for (id, runID) in taskRuns where runID == request.runID { tasks[id]?.cancel() }
                reply(connection, id: id, request: request, result: .init(json: "{\"cancelled\":true}", exitCode: 0))
                return
            }
            guard tasks.count < 4, requestIDs[request.requestID] == nil, cancelledRuns[request.runID] == nil, requestIDs.count < 4096 else {
                reply(connection, id: id, request: request, result: .init(json: "{\"error\":\"Run cancelled or native operation already active\"}", exitCode: 1)); return
            }
            requestIDs[request.requestID] = .now
            taskRuns[request.requestID] = request.runID
            let contextProvider = self.contextProvider
            tasks[request.requestID] = Task.detached { [weak self] in
                let result: NativeCommandExecutor.Result
                if request.arguments == ["context"] {
                    result = .init(json: await contextProvider?() ?? "{\"unavailable\":\"No current snapshot\"}", exitCode: 0)
                } else { result = await NativeCommandExecutor.execute(request.arguments) }
                await self?.finished(connection, id: id, request: request, result: result)
            }
        } else if complete { close(connection, id: id) }
        else { receive(connection, id: id, buffer: bytes) }
    }

    private func finished(_ connection: NWConnection, id: UUID, request: Request, result: NativeCommandExecutor.Result) {
        tasks[request.requestID] = nil; taskRuns[request.requestID] = nil
        reply(connection, id: id, request: request, result: result)
    }
    private func reply(_ connection: NWConnection, id: UUID, request: Request, result: NativeCommandExecutor.Result) {
        let bounded = result.json.utf8.count <= 4_000_000 ? result : .init(json: "{\"error\":\"Native result exceeds 4 MB. Request a narrower scan.\"}", exitCode: 1)
        guard var data = try? JSONEncoder().encode(Response(request_id: request.requestID, json: bounded.json, exit_code: bounded.exitCode)) else { close(connection, id: id); return }
        data.append(10)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            connection.cancel(); Task { await self?.removeConnection(id) }
        })
    }
    private func close(_ connection: NWConnection, id: UUID) { connection.cancel(); connections[id] = nil }
    private func removeConnection(_ id: UUID) { connections[id] = nil }
}
