import Foundation
import Testing
@testable import PulseKit

struct AgentDaemonManagerTests {
    @Test func prefersBundledRuntimeOverWorkingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = directory.appendingPathComponent("Resources")
        let script = resources.appendingPathComponent("pulse-agent/start.sh")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: directory) }

        let found = AgentDaemonManager.agentScriptURL(bundleResourceURL: resources, currentDirectoryURL: directory)
        #expect(found == script)
    }
}
