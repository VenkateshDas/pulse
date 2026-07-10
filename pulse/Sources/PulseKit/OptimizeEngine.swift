import Foundation

/// Outcome of running one optimize task.
public struct OptimizeResult: Sendable, Equatable {
    public let success: Bool
    public let summary: String       // "Cleared 312 MB of saved app state"
    public let bytesFreed: Int64
    /// True when the task moved files to the Trash (drives the trash sound).
    public let trashed: Bool

    public init(success: Bool, summary: String, bytesFreed: Int64 = 0, trashed: Bool = false) {
        self.success = success
        self.summary = summary
        self.bytesFreed = bytesFreed
        self.trashed = trashed
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

    // MARK: VPN detection (mole tasks.sh:119-131)

    /// Bare utun presence over-reports VPNs (iCloud Private Relay, Continuity
    /// also create utun). Use two narrow signals: an scutil network service
    /// reporting Connected, OR the default route running over utun*.
    public static func vpnActive() async -> Bool {
        if let out = try? await Shell.run("/usr/sbin/scutil", ["--nc", "list"]),
           out.stdout.contains("(Connected)") {
            return true
        }
        if let out = try? await Shell.run("/sbin/route", ["-n", "get", "default"]) {
            for line in out.stdout.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("interface:"), t.contains("utun") { return true }
            }
        }
        return false
    }

    // MARK: Tasks

    public static let tasks: [OptimizeTask] = inProcessTasks + privilegedTasks

    /// Safe, user-owned, no elevation. Runnable today.
    static let inProcessTasks: [OptimizeTask] = [
        OptimizeTask(
            id: "saved_state_cleanup",
            label: "Clear old saved app state",
            detail: "Move stale ~/Library/Saved Application State windows to the Trash (reversible).",
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

        OptimizeTask(
            id: "quicklook_cache",
            label: "Reset QuickLook thumbnails",
            detail: "Rebuild the QuickLook thumbnail cache (fixes blank/stale previews).",
            risk: .safe, needsSudo: false,
            preview: { "Would run: qlmanage -r cache" },
            run: {
                let out = try await Shell.run("/usr/bin/qlmanage", ["-r", "cache"])
                return OptimizeResult(success: out.ok,
                                      summary: out.ok ? "QuickLook cache reset" : "qlmanage failed")
            }),

        OptimizeTask(
            id: "dns_flush",
            label: "Flush DNS cache",
            detail: "Clear the directory-services DNS cache (dscacheutil).",
            risk: .safe, needsSudo: false,
            preview: { "Would run: dscacheutil -flushcache" },
            run: {
                let out = try await Shell.run("/usr/bin/dscacheutil", ["-flushcache"])
                return OptimizeResult(success: out.ok,
                                      summary: out.ok ? "DNS cache flushed" : "Flush failed")
            }),

        OptimizeTask(
            id: "launch_services_rebuild",
            label: "Rebuild \u{201C}Open With\u{201D} menu",
            detail: "Re-register apps so the Launch Services database drops duplicate/stale entries.",
            risk: .safe, needsSudo: false,
            preview: { "Would run: lsregister -kill -r (user domain)" },
            run: {
                let out = try await Shell.run(lsregisterPath,
                    ["-kill", "-r", "-domain", "local", "-domain", "user"])
                return OptimizeResult(success: out.ok,
                                      summary: out.ok ? "Launch Services rebuilt" : "Rebuild failed")
            }),
    ]

    /// Elevation-required. Routed through Authorization Services (an admin
    /// password prompt) via PrivilegedRunner — works in any signed/unsigned build.
    static let privilegedTasks: [OptimizeTask] = [
        OptimizeTask(
            id: "memory_pressure_relief",
            label: "Free inactive memory",
            detail: "Run `purge` to release inactive/cached memory back to the OS.",
            risk: .careful, needsSudo: true,
            preview: { "Would run: sudo purge (asks for your password)" },
            run: { await PrivilegedRunner.run(.purgeMemory) }),

        OptimizeTask(
            id: "network_stack_optimize",
            label: "Optimize network stack",
            detail: "Flush the route table and ARP cache. Skipped while a VPN is active.",
            risk: .careful, needsSudo: true,
            skipCheck: { await vpnActive() ? "VPN active — network reset skipped" : nil },
            preview: { "Would flush routes + arp -a -d (asks for your password)" },
            run: { await PrivilegedRunner.run(.flushNetworkStack) }),

        OptimizeTask(
            id: "spotlight_index_optimize",
            label: "Rebuild Spotlight index",
            detail: "Reindex the boot volume — only when Spotlight reports slow or disabled.",
            risk: .careful, needsSudo: true,
            skipCheck: {
                guard let out = try? await Shell.run("/usr/bin/mdutil", ["-s", "/"]) else { return nil }
                // "Indexing enabled." means healthy → skip.
                return out.stdout.contains("Indexing enabled") ? "Spotlight already healthy" : nil
            },
            preview: { "Would run: sudo mdutil -E / (asks for your password)" },
            run: { await PrivilegedRunner.run(.rebuildSpotlightIndex) }),
    ]

    /// Runs all safe (no-sudo) tasks sequentially, skipping any that report
    /// nothing to do. Returns a human-readable summary.
    public static func runSafeTasks() async -> String {
        await MenuBarFlash.shared.flash("bolt.heart.fill")
        var completed: [String] = []
        var totalFreed: Int64 = 0
        for task in inProcessTasks {
            if let skip = await task.skipCheck() {
                completed.append("\(task.label): \(skip)")
                continue
            }
            do {
                let result = try await task.run()
                totalFreed += result.bytesFreed
                completed.append(result.summary)
            } catch {
                completed.append("\(task.label): failed")
            }
        }
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

    /// CoreServices lsregister — stable path across recent macOS releases.
    static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
        + "LaunchServices.framework/Support/lsregister"

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

    /// Moves every entry in `dir` to the Trash (reversible). Returns bytes freed.
    static func trashContents(of dir: URL, label: String) async -> OptimizeResult {
        let bytes = await dirBytes(dir)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else {
            return OptimizeResult(success: false, summary: "Couldn't read \(label)")
        }
        var moved = 0
        var trashedItems: [TrashedItem] = []
        for entry in entries {
            var trashedURL: NSURL?
            if (try? fm.trashItem(at: entry, resultingItemURL: &trashedURL)) != nil {
                moved += 1
                if let trashPath = trashedURL?.path {
                    trashedItems.append(TrashedItem(originalPath: entry.path, trashPath: trashPath))
                }
            }
        }
        if !trashedItems.isEmpty {
            await UndoJournal.shared.record(UndoEntry(op: "Optimize (\(label))", items: trashedItems, bytesFreed: bytes))
        }
        let ok = moved > 0 || entries.isEmpty
        return OptimizeResult(
            success: ok,
            summary: "Moved \(moved) \(label) item(s) to Trash",
            bytesFreed: ok ? bytes : 0,
            trashed: moved > 0)
    }
}
