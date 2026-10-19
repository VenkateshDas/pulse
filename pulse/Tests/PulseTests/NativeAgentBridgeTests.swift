import Foundation
import Network
import Testing
import PulseCommands
@testable import Pulse

@Suite(.serialized)
struct NativeAgentBridgeTests {
    @Test func invalidNativeGrammarReturnsErrorWithoutExitingApp() async {
        let result = await NativeCommandExecutor.execute(["clean", "--force", "--yes"])
        #expect(result.exitCode == 2)
        #expect(result.json.contains("Unknown option"))
        let second = await NativeCommandExecutor.execute(["version"])
        #expect(second.exitCode == 2)
    }
    @Test func bridgeServesCachedContextAndRejectsCancelledRun() async throws {
        let bridge = AgentNativeBridge.shared
        await bridge.configureContext { "{\"timestamp\":\"fixture\",\"cpu\":12}" }
        let port = try await bridge.start(token: "fixture-token")
        let runID = UUID().uuidString
        let first = try await rpc(port: port, runID: runID, cancel: false)
        #expect(first.contains("fixture"))
        _ = try await rpc(port: port, runID: runID, cancel: true)
        let after = try await rpc(port: port, runID: runID, cancel: false)
        #expect(after.contains("cancelled"))
        await bridge.stop()
    }
    private func rpc(port: UInt16, runID: String, cancel: Bool) async throws -> String {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let body: [String: Any] = ["version": 1, "token": "fixture-token", "request_id": UUID().uuidString,
            "run_id": runID, "session_id": "fixture", "arguments": ["context"], "cancel": cancel]
        var data = try JSONSerialization.data(withJSONObject: body); data.append(10)
        let payload = data
        defer { connection.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.stateUpdateHandler = nil
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error { continuation.resume(throwing: error); return }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume(returning: String(decoding: data ?? Data(), as: UTF8.self)) }
                        }
                    })
                } else if case .failed(let error) = state {
                    connection.stateUpdateHandler = nil; continuation.resume(throwing: error)
                }
            }
            connection.start(queue: DispatchQueue(label: "pulse.agent.fixture"))
        }
    }
}
