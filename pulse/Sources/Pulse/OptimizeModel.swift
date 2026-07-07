import Foundation
import Observation
import PulseKit

/// Drives the Optimize tab: resolves each task's skip reason + dry-run preview
/// lazily, runs the safe (non-privileged) ones, and records results.
@MainActor
@Observable
final class OptimizeModel {
    struct TaskState {
        var skipReason: String?
        var preview: String = "…"
        var isRunning = false
        var result: OptimizeResult?
        var loaded = false
    }

    let tasks = OptimizeEngine.tasks
    let refusals = OptimizeEngine.refusals
    private(set) var states: [String: TaskState] = [:]
    private(set) var didLoad = false
    private(set) var totalBytesFreed: Int64 = 0

    func state(for id: String) -> TaskState { states[id] ?? TaskState() }

    /// Resolves skip reasons + previews once when the tab first appears.
    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        for task in tasks {
            states[task.id] = TaskState()
            Task { [weak self] in
                let skip = await task.skipCheck()
                let preview = await task.preview()
                guard let self else { return }
                var s = self.states[task.id] ?? TaskState()
                s.skipReason = skip
                s.preview = preview
                s.loaded = true
                self.states[task.id] = s
            }
        }
    }

    /// Manual refresh: re-evaluates skip + preview for every task.
    func refreshAllStatuses() {
        for task in tasks {
            Task { await refresh(task) }
        }
    }

    /// Re-evaluates skip + preview for one task (after a run, things change).
    func refresh(_ task: OptimizeTask) async {
        let skip = await task.skipCheck()
        let preview = await task.preview()
        var s = states[task.id] ?? TaskState()
        s.skipReason = skip
        s.preview = preview
        states[task.id] = s
    }

    func run(_ task: OptimizeTask) async {
        guard state(for: task.id).skipReason == nil else { return }
        var s = states[task.id] ?? TaskState()
        s.isRunning = true
        states[task.id] = s

        let result = (try? await task.run())
            ?? OptimizeResult(success: false, summary: "Task failed to run")

        s = states[task.id] ?? TaskState()
        s.isRunning = false
        s.result = result
        states[task.id] = s
        if result.success { totalBytesFreed += result.bytesFreed }
        if result.trashed { TrashSound.moveToTrash() }
        await refresh(task)
    }

    var isAnyRunning: Bool { states.values.contains { $0.isRunning } }

    /// Runs every non-skipped task in sequence — admin ones included, each
    /// raising its own macOS password prompt via PrivilegedRunner.
    func runAll() async {
        for task in tasks where state(for: task.id).skipReason == nil {
            await run(task)
        }
    }
}
