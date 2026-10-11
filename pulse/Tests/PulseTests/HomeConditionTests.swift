import Testing
import PulseKit
@testable import Pulse

@Suite("Home condition explanations")
struct HomeConditionTests {
    private let clear = Diagnosis(line: "All clear", severity: .clear, culpritPID: nil, factor: nil)

    @Test func recordedAttentionIsNotPresentedAsAllClear() {
        let condition = HomeCondition(diagnosis: clear, hasSnapshot: true, hasAttention: true)
        #expect(condition.title == "There is something to review")
        #expect(condition.symbol == "exclamationmark.circle")
        #expect(condition.explanation.contains("recorded"))
        #expect(condition.destination == nil)
    }

    @Test func initialCheckDoesNotInventACondition() {
        let condition = HomeCondition(diagnosis: clear, hasSnapshot: false, hasAttention: true)
        #expect(condition.title == "Checking your Mac…")
        #expect(condition.symbol == "clock")
        #expect(condition.destination == nil)
    }

    @Test func currentProblemKeepsSpecificExplanation() {
        let diagnosis = Diagnosis(line: "Memory pressure", severity: .warn, culpritPID: nil, factor: .memory)
        let condition = HomeCondition(diagnosis: diagnosis, hasSnapshot: true, hasAttention: true)
        #expect(condition.destination == .monitor)
        #expect(condition.explanation.contains("memory under pressure"))
    }
}
