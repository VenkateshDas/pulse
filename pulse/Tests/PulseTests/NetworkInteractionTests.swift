import Foundation
import Testing
import PulseKit
@testable import Pulse

@Suite("Internet test choices")
@MainActor
struct NetworkInteractionTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PulseNetworkTests.\(UUID().uuidString)")!
    }

    @Test func automaticTestsRequireExplicitOptIn() {
        let defaults = isolatedDefaults()
        let model = NetworkModel(defaults: defaults, store: SpeedTestStore(fileURL: nil))
        model.start()
        #expect(!model.automaticTestsEnabled)
        #expect(!model.automaticTestingScheduled)
        model.setAutomaticTests(true)
        #expect(model.automaticTestsEnabled)
        #expect(model.automaticTestingScheduled)
        #expect(defaults.bool(forKey: "pulse.automaticSpeedTests"))
        model.setAutomaticTests(false)
        #expect(!model.automaticTestingScheduled)
    }

    @Test func failedTestPreservesThePreviousResult() async {
        let store = SpeedTestStore(fileURL: nil)
        let previous = SpeedTestResult(downloadMbps: 12, uploadMbps: 3, responsivenessRPM: nil, baseRTTMillis: 20)
        store.record(previous)
        let model = NetworkModel(defaults: isolatedDefaults(), store: store,
                                 performTest: { throw SpeedTestError.malformedOutput })
        let result = await model.runSpeedTestAwaiting()
        #expect(result == nil)
        #expect(model.lastResult == previous)
        #expect(model.history.count == 1)
        if case .failed = model.speedTestState {} else { Issue.record("Expected recoverable failure") }
    }

    @Test func cancellationStopsTheWorkerWithoutRecordingAResult() async {
        let store = SpeedTestStore(fileURL: nil)
        let model = NetworkModel(defaults: isolatedDefaults(), store: store, performTest: {
            try await Task.sleep(for: .seconds(30))
            return SpeedTestResult(downloadMbps: 1, uploadMbps: 1, responsivenessRPM: nil, baseRTTMillis: nil)
        })
        let operation = Task { await model.runSpeedTestAwaiting() }
        for _ in 0..<100 where !model.isTesting { await Task.yield() }
        #expect(model.isTesting)
        model.cancelSpeedTest()
        #expect(await operation.value == nil)
        #expect(model.speedTestState == .cancelled)
        #expect(store.results.isEmpty)
    }
}
