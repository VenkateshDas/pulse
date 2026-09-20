import Testing
@testable import Pulse

struct AgentMarkdownParserTests {
    @Test func transcriptMutationNeverRequestsProgrammaticScrolling() {
        #expect(!AgentTimelineScrollPolicy.shouldScroll(for: .transcriptMutation))
    }

    @Test func parsesAgentAnswerBlocks() {
        let source = """
        ## Top CPU Consumers

        Good news — **nothing is running hot.**

        | App | CPU |
        | --- | --- |
        | Pulse | 8.1% |

        - No sustained anomaly
        - Memory is stable
        """

        #expect(AgentMarkdownParser.parse(source) == [
            .heading(2, "Top CPU Consumers"),
            .paragraph("Good news — **nothing is running hot.**"),
            .table(["App", "CPU"], [["Pulse", "8.1%"]]),
            .bullets(["No sustained anomaly", "Memory is stable"])
        ])
    }

    @Test func hugeAnswerUsesBoundedPreviewUntilExpanded() {
        let source = String(repeating: "x", count: AgentAnswerPresentation.previewLimit + 1)
        let preview = AgentAnswerPresentation.visibleSource(source, isExpanded: false)

        #expect(AgentAnswerPresentation.needsExpansion(source))
        #expect(preview.count < AgentAnswerPresentation.previewLimit + 64)
        #expect(AgentAnswerPresentation.visibleSource(source, isExpanded: true) == source)
    }
}
