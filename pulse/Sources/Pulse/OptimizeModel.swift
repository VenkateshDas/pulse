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
    /// Registration state of the root daemon backing the ADMIN tasks.
    private(set) var helperStatus: PrivilegedHelperClient.Status = .unavailable

    func state(for id: String) -> TaskState { states[id] ?? TaskState() }

    /// Resolves skip reasons + previews once when the tab first appears.
    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        Task { [weak self] in
            let status = await PrivilegedHelperClient.shared.status()
            self?.helperStatus = status
        }
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

    /// Re-evaluates skip + preview for one task (after a run, things change).
    func refresh(_ task: OptimizeTask) async {
        let skip = await task.skipCheck()
        let preview = await task.preview()
        var s = states[task.id] ?? TaskState()
        s.skipReason = skip
        s.preview = preview
        states[task.id] = s
    }

    /// Registers/enables the privileged helper, then refreshes status. macOS
    /// typically returns `.requiresApproval` first — the user finishes in
    /// System Settings → General → Login Items.
    func enableHelper() async {
        helperStatus = await PrivilegedHelperClient.shared.register()
    }

    func run(_ task: OptimizeTask) async {
        guard state(for: task.id).skipReason == nil else { return }
        if task.needsSudo && helperStatus != .enabled { return }
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
        await refresh(task)
    }

    /// Runs every safe, non-skipped, in-process task in sequence.
    func runAllSafe() async {
        for task in tasks
        where task.risk == .safe && !task.needsSudo && state(for: task.id).skipReason == nil {
            await run(task)
        }
    }
}
