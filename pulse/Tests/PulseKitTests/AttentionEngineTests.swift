import Foundation
import Testing

@testable import PulseKit

private func makeAlert(
    id: String, severity: PulseAlert.Severity = .warning,
    actions: [PulseAlert.Action] = []
) -> PulseAlert {
    PulseAlert(
        id: id, severity: severity, symbol: "bolt", title: "\(id) title",
        subtitle: "\(id) subtitle", actions: actions)
}

private let clearDiagnosis = Diagnosis(line: "All clear", severity: .clear, culpritPID: nil, factor: nil)

@Suite("AttentionEngine ranking")
struct AttentionEngineRankingTests {
    @Test func emptyInputProducesEmptyOutput() {
        let items = AttentionEngine.rank(diagnosis: clearDiagnosis, alerts: [])
        #expect(items.isEmpty)
    }

    @Test func rankingOrderMatchesDiagnosisPriority() {
        // Diagnosis says CPU is the top-priority problem; a memory alert is
        // also active but must rank behind the CPU-derived item.
        let diagnosis = Diagnosis(
            line: "Chrome high CPU", severity: .critical, culpritPID: 111, factor: .cpu)
        let cpuAlert = makeAlert(
            id: "cpu-hog", severity: .warning,
            actions: [.quitProcess(pid: 111, name: "Chrome")])
        let memAlert = makeAlert(id: "memory-pressure", severity: .critical)

        let items = AttentionEngine.rank(diagnosis: diagnosis, alerts: [cpuAlert, memAlert])

        #expect(items.count == 2)
        #expect(items[0].id == "cpu-hog")
        #expect(items[1].id == "memory-pressure")
    }

    @Test func dedupesDiagnosisCulpritAgainstOverlappingAlert() {
        // Same cause (CPU) surfaced by both the diagnosis cascade and the
        // alerts engine must collapse into a single item, not two.
        let diagnosis = Diagnosis(
            line: "Chrome high CPU", severity: .critical, culpritPID: 111, factor: .cpu)
        let cpuAlert = makeAlert(
            id: "cpu-hog", severity: .warning,
            actions: [.quitProcess(pid: 111, name: "Chrome")])

        let items = AttentionEngine.rank(diagnosis: diagnosis, alerts: [cpuAlert])

        #expect(items.count == 1)
        #expect(items[0].id == "cpu-hog")
        #expect(items[0].action == .quitProcess(pid: 111, name: "Chrome"))
    }

    @Test func capsAtThreeItems() {
        let alerts = [
            makeAlert(id: "a", severity: .critical),
            makeAlert(id: "b", severity: .critical),
            makeAlert(id: "c", severity: .warning),
            makeAlert(id: "d", severity: .warning),
            makeAlert(id: "e", severity: .info),
        ]
        let items = AttentionEngine.rank(diagnosis: clearDiagnosis, alerts: alerts)
        #expect(items.count == 3)
    }

    @Test func diagnosisOnlyItemUsedWhenNoMatchingAlertExists() {
        let diagnosis = Diagnosis(
            line: "Running hot", severity: .warn, culpritPID: nil, factor: .thermal)
        let items = AttentionEngine.rank(diagnosis: diagnosis, alerts: [])
        #expect(items.count == 1)
        #expect(items[0].id == "diagnosis-thermal")
        #expect(items[0].severity == .warn)
    }
}

@Suite("AttentionEngine snooze filtering")
struct AttentionEngineSnoozeTests {
    private func makeTempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-attention-tests-\(UUID().uuidString).json")
    }

    @Test func snoozedItemsExcludedFromOutput() async {
        let engine = AttentionEngine(snoozeStore: SnoozeStore(storeURL: makeTempStoreURL()))
        let alert = makeAlert(id: "low-disk", severity: .critical)

        let before = await engine.currentItems(diagnosis: clearDiagnosis, alerts: [alert])
        #expect(before.map(\.id) == ["low-disk"])

        await engine.snooze("low-disk", until: Date.now.addingTimeInterval(3600))
        let after = await engine.currentItems(diagnosis: clearDiagnosis, alerts: [alert])
        #expect(after.isEmpty)
    }

    @Test func emptyInputProducesEmptyOutputViaActor() async {
        let engine = AttentionEngine(snoozeStore: SnoozeStore(storeURL: makeTempStoreURL()))
        let items = await engine.currentItems(diagnosis: clearDiagnosis, alerts: [])
        #expect(items.isEmpty)
    }
}
