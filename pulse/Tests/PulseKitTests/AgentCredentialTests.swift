import Dispatch
import Foundation
import os
import Testing
@testable import PulseKit

@Suite("Agent credential lifecycle")
struct AgentCredentialTests {
    private let endpoint = "https://provider.example/v1"

    @Test func successfulSaveCachesWithoutReadback() async {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let saved = OSAllocatedUnfairLock(initialState: [(String, String)]())
        let store = AgentCredentialStore(read: { _ in
            reads.withLock { $0 += 1 }
            return "unexpected"
        }, write: { value, endpoint in
            saved.withLock { $0.append((value, endpoint)) }
            return true
        })
        #expect(store.save("fixture-key", endpoint: endpoint))
        #expect(await store.load(endpoint: endpoint) == "fixture-key")
        #expect(await store.load(endpoint: endpoint + "/") == "fixture-key")
        #expect(reads.withLock { $0 } == 0)
        #expect(saved.withLock { $0.first?.1 } == endpoint)
    }

    @Test func failedWriteIsReportedAndDoesNotCacheNewSecret() async {
        let store = AgentCredentialStore(read: { _ in "old-fixture" }, write: { _, _ in false })
        #expect(!store.save("new-fixture", endpoint: endpoint))
        #expect(await store.load(endpoint: endpoint) == "old-fixture")
        #expect(!store.save("", endpoint: endpoint))
        #expect(await store.load(endpoint: endpoint) == "old-fixture")
    }

    @Test func cacheDoesNotCrossEndpoints() async {
        let requested = OSAllocatedUnfairLock(initialState: [String]())
        let store = AgentCredentialStore(read: { endpoint in
            requested.withLock { $0.append(endpoint) }
            return nil
        }, write: { _, _ in true })
        #expect(store.save("fixture-key", endpoint: endpoint))
        let other = "https://other.example/v1"
        #expect(await store.load(endpoint: other) == "")
        #expect(requested.withLock { $0 } == [other])
        #expect(await store.load(endpoint: endpoint) == "fixture-key")
    }

    @Test func unavailableReadCanBeRetried() async {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let store = AgentCredentialStore(read: { _ in
            attempts.withLock { count in
                count += 1
                return count == 1 ? nil : "unlocked-fixture"
            }
        }, write: { _, _ in true })
        #expect(await store.load(endpoint: endpoint) == "")
        #expect(await store.load(endpoint: endpoint) == "unlocked-fixture")
    }

    @Test(arguments: ["new-fixture", ""])
    func pendingReadCannotResurrectSecretAfterSaveOrDelete(replacement: String) async {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let store = AgentCredentialStore(read: { _ in
            started.signal()
            _ = release.wait(timeout: .now() + 5)
            return "stale-fixture"
        }, write: { _, _ in true })
        let capturedEndpoint = endpoint
        let pending = Task { await store.load(endpoint: capturedEndpoint) }
        let waitForStart: @Sendable () -> Bool = { started.wait(timeout: .now() + 3) == .success }
        let didStart = await Task.detached { waitForStart() }.value
        #expect(didStart)
        guard didStart else { release.signal(); return }
        #expect(store.save(replacement, endpoint: endpoint))
        release.signal()
        #expect(await pending.value == "")
        #expect(await store.load(endpoint: endpoint) == replacement)
    }
}
