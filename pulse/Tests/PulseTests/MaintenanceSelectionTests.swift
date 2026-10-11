import Testing
import PulseKit
@testable import Pulse

private actor MaintenanceRecorder {
    var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
    func recorded() -> [String] { ids }
}

@Suite("Reviewed maintenance selection")
@MainActor
struct MaintenanceSelectionTests {
    private func task(_ id: String, recorder: MaintenanceRecorder, unavailable: Bool = false) -> OptimizeTask {
        OptimizeTask(id: id, label: id, detail: "Fixture task", risk: .safe, needsSudo: false,
            skipCheck: { unavailable ? "Unavailable" : nil }, preview: { "Fixture preview" },
            run: {
                await recorder.record(id)
                return OptimizeResult(success: true, summary: "Completed fixture")
            })
    }

    @Test func onlyReviewedTasksRunAndSelectionClears() async {
        let recorder = MaintenanceRecorder()
        let first = task("first", recorder: recorder)
        let second = task("second", recorder: recorder)
        let model = OptimizeModel(tasks: [first, second])
        await model.refresh(first)
        await model.refresh(second)
        #expect(model.selectedTasks.isEmpty)
        model.setSelected(true, id: second.id)
        await model.runSelected()
        #expect(await recorder.recorded() == ["second"])
        #expect(model.selectedIDs.isEmpty)
        #expect(!model.isAnyRunning)
    }

    @Test func unavailableTasksCannotBeSelected() async {
        let recorder = MaintenanceRecorder()
        let unavailable = task("unavailable", recorder: recorder, unavailable: true)
        let model = OptimizeModel(tasks: [unavailable])
        model.setSelected(true, id: unavailable.id)
        #expect(model.selectedTasks.isEmpty)
        await model.refresh(unavailable)
        model.setSelected(true, id: unavailable.id)
        await model.runSelected()
        #expect(await recorder.recorded().isEmpty)
    }
}
