import Foundation
import AppKit

/// Outcome of running one optimize task.
public struct OptimizeResult: Sendable, Equatable {
    public let success: Bool
    public let summary: String       // "Cleared 312 MB of saved app state"
    public let bytesFreed: Int64
    public let bytesMovedToTrash: Int64
    /// True when the task moved files to the Trash (drives the trash sound).
    public let trashed: Bool

    public init(success: Bool, summary: String, bytesFreed: Int64 = 0, trashed: Bool = false, bytesMovedToTrash: Int64 = 0) {
        self.success = success
        self.summary = summary
        self.bytesFreed = bytesFreed
        self.trashed = trashed
        self.bytesMovedToTrash = bytesMovedToTrash
    }
}

/// A single maintenance operation. Ported from mole's `lib/optimize/tasks.sh`
/// as a typed, dry-run-aware unit. Safe/non-privileged tasks run in-process;
/// `needsSudo` tasks run as root via an admin password prompt (PrivilegedRunner).
public struct OptimizeTask: Identifiable, Sendable {
    public enum Risk: String, Sendable, CaseIterable { case safe, careful, review }

    public let id: String
    public let label: String
    public let detail: String
    public let risk: Risk
    public let needsSudo: Bool
    /// Non-nil = skip this task, with the reason ("Spotlight already healthy").
    public let skipCheck: @Sendable () async -> String?
    /// Dry-run summary of what running would do ("Would clear ~312 MB").
    public let preview: @Sendable () async -> String
    /// Performs the operation. Only called for non-sudo tasks today.
    public let run: @Sendable () async throws -> OptimizeResult

    public init(
        id: String, label: String, detail: String, risk: Risk, needsSudo: Bool,
        skipCheck: @escaping @Sendable () async -> String? = { nil },
        preview: @escaping @Sendable () async -> String,
        run: @escaping @Sendable () async throws -> OptimizeResult
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.risk = risk
        self.needsSudo = needsSudo
        self.skipCheck = skipCheck
        self.preview = preview
        self.run = run
    }
}

public enum OptimizeEngine {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: Refusal manifest (mole tasks.sh:272-276, 582-585)

    /// Operations Pulse deliberately will NOT perform, with the reason —
    /// shown as a trust panel. Ported verbatim-intent from mole.
    public static let refusals: [(op: String, reason: String)] = [
        ("Swap / VM cleanup", "Direct virtual-memory ops risk a system crash."),
        ("Delete local Time Machine snapshots",
         "Destroys user recovery points and breaks backup continuity."),
        ("Update dyld shared cache", "Low benefit, slow, and auto-managed by macOS."),
        ("Delete startup items", "Risks removing legitimate app helpers."),
        ("Refresh radio / Wi-Fi / Bluetooth",
         "Interrupts active connections and degrades the user experience."),
    ]

    // MARK: Tasks

    public static let tasks: [OptimizeTask] = inProcessTasks + privilegedTasks

    /// Safe, user-owned, no elevation. Runnable today.
    static let inProcessTasks: [OptimizeTask] = [
        OptimizeTask(
            id: "saved_state_cleanup",
            label: "Remove saved window state",
            detail: "Move saved window state for closed apps to Trash. Those apps may stop reopening their previous windows. Restore before emptying Trash.",
            risk: .safe, needsSudo: false,
            skipCheck: {
                let bytes = await dirBytes(savedStateDir)
                return bytes == 0 ? "Nothing to clear" : nil
            },
            preview: {
                let bytes = await dirBytes(savedStateDir)
                return "Would move ~\(ByteFormat.string(UInt64(max(0, bytes)))) of saved state to Trash"
            },
            run: { await trashContents(of: savedStateDir, label: "saved app state") }),

        unavailableTask(id: "quicklook_cache", label: "Reset file previews",
            detail: "For blank Finder previews, reopen Finder or restart your Mac.", needsSudo: false),
        unavailableTask(id: "dns_flush", label: "Reset network name cache",
            detail: "For connection problems, review Internet readings and macOS Network settings.", needsSudo: false),
        unavailableTask(id: "launch_services_rebuild", label: "Repair the Open With menu",
            detail: "Review app associations in Finder’s Get Info window.", needsSudo: false),
    ]

    /// Kept visible with guidance, but never executes shell-backed maintenance.
    static let privilegedTasks: [OptimizeTask] = [
        unavailableTask(id: "memory_pressure_relief", label: "Release cached memory",
            detail: "macOS manages cached memory. Review busy apps before closing anything.", needsSudo: true),
        unavailableTask(id: "network_stack_optimize", label: "Reset network connections",
            detail: "This can interrupt active work. Use macOS Network settings when needed.", needsSudo: true),
        unavailableTask(id: "spotlight_index_optimize", label: "Rebuild Spotlight search",
            detail: "Use Spotlight privacy settings to control indexing. Reindexing can take time and energy.", needsSudo: true),
    ]

    private static func unavailableTask(id: String, label: String, detail: String, needsSudo: Bool) -> OptimizeTask {
        OptimizeTask(id: id, label: label, detail: detail, risk: needsSudo ? .careful : .safe, needsSudo: needsSudo,
            skipCheck: { "Unavailable: no supported native operation in Pulse." },
            preview: { detail },
            run: { OptimizeResult(success: false, summary: "Not run: no supported native operation in Pulse.") })
    }

    /// Runs all safe (no-sudo) tasks sequentially, skipping any that report
    /// nothing to do. Returns a human-readable summary.
    public static func runSafeTasks() async -> String {
        await MenuBarFlash.shared.flash("bolt.heart.fill")
        var completed: [String] = []
        var totalFreed: Int64 = 0
        var totalMoved: Int64 = 0
        for task in inProcessTasks {
            if let skip = await task.skipCheck() {
                completed.append("\(task.label): \(skip)")
                continue
            }
            do {
                let result = try await task.run()
                totalFreed += result.bytesFreed
                totalMoved += result.bytesMovedToTrash
                completed.append(result.summary)
            } catch {
                completed.append("\(task.label): failed")
            }
        }
        if totalMoved > 0 { return "Moved \(ByteFormat.string(UInt64(totalMoved))) to Trash · space remains allocated" }
        if totalFreed > 0 {
            return "Optimized · freed \(ByteFormat.string(UInt64(totalFreed)))"
        }
        let doneCount = completed.filter { !$0.contains("failed") && !$0.contains("Nothing") }.count
        return doneCount > 0 ? "Optimized \(doneCount) items" : "Already optimized"
    }

    // MARK: Helpers

    static var savedStateDir: URL {
        home.appendingPathComponent("Library/Saved Application State")
    }

    static func dirBytes(_ url: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let en = fm.enumerator(at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                options: []) else { return Int64(0) }
            var total: Int64 = 0
            while let f = en.nextObject() as? URL {
                let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
            }
            return total
        }.value
    }

    /// Journal every successful move; Trash is not reclaimed capacity.
    static func trashContents(of dir: URL, label: String) async -> OptimizeResult {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return OptimizeResult(success: false, summary: "Couldn't read \(label)")
        }
        var movedBytes: Int64 = 0, moved = 0, failed = 0
        let runningIDs = await MainActor.run { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
        var skipped = 0
        for entry in entries {
            let appID = entry.lastPathComponent.replacingOccurrences(of: ".savedState", with: "")
            if runningIDs.contains(appID) { skipped += 1; continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileAllocatedSizeKey])
            let bytes = values?.isDirectory == true ? await dirBytes(entry) : Int64(values?.fileAllocatedSize ?? 0)
            do {
                _ = try await UndoJournal.shared.trashItem(at: entry, operation: "Optimize (\(label))", bytes: UInt64(max(0, bytes)))
                moved += 1; movedBytes += bytes
            } catch { failed += 1 }
        }
        return OptimizeResult(success: failed == 0,
            summary: "Moved \(moved) \(label) item(s) to Trash; \(failed) failed; \(skipped) active app(s) skipped. Space remains allocated.",
            trashed: moved > 0, bytesMovedToTrash: movedBytes)
    }
}
