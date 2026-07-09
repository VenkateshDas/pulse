import CPulse
import CoreServices
import Darwin
import Foundation

/// What Pulse has observed happening to one folder since tracking began.
public struct FolderActivity: Codable, Sendable, Equatable {
    public var lastWrite: Date?
    public var lastOpen: Date?
    public var lastOpenProcess: String?
}

/// Roll-up of observed activity for a whole subtree, plus how long we've
/// been watching — "nothing touched this" only means something relative to
/// the observation window.
public struct ActivitySummary: Sendable, Equatable {
    public let lastWrite: Date?
    public let lastOpen: Date?
    public let lastOpenProcess: String?
    public let trackingSince: Date
}

/// Persistent folder-level activity log — the usage history macOS doesn't
/// keep. Paths are rolled up to a bounded depth so the store stays small
/// (a write to `~/p/a/b/c/deep/file` records under `~/p/a/b/c`).
public actor ActivityStore {
    private struct Snapshot: Codable {
        var trackingSince: Date
        var folders: [String: FolderActivity]
    }

    public static let maxEntries = 20_000
    /// Path components kept below the home directory (or below / for
    /// system-side paths like /opt/homebrew).
    static let rollupDepth = 4

    private let storeURL: URL
    private let homePath: String
    private var folders: [String: FolderActivity] = [:]
    public private(set) var trackingSince: Date = .now
    private var dirty = false

    public static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Pulse/usage_activity.json")
    }

    public init(
        storeURL: URL = ActivityStore.defaultStoreURL(),
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.storeURL = storeURL
        self.homePath = homePath
        if let data = try? Data(contentsOf: storeURL),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        {
            trackingSince = snapshot.trackingSince
            folders = snapshot.folders
        }
    }

    /// Truncates a file path to its storage key: `rollupDepth` components
    /// below home (or below /) — nil for paths not worth recording.
    public nonisolated func rollupKey(for path: String) -> String? {
        let base: String
        if path.hasPrefix(homePath + "/") {
            base = homePath
        } else if path.hasPrefix("/") {
            base = ""
        } else {
            return nil
        }
        let rest = path.dropFirst(base.count).split(separator: "/")
        guard !rest.isEmpty else { return nil }
        return base + "/" + rest.prefix(Self.rollupDepth).joined(separator: "/")
    }

    public func recordWrites(paths: [String], at date: Date = .now) {
        for path in paths {
            guard let key = rollupKey(for: path) else { continue }
            var activity = folders[key] ?? FolderActivity()
            activity.lastWrite = date
            folders[key] = activity
        }
        dirty = true
        pruneIfNeeded()
    }

    public func recordOpens(paths: [(path: String, process: String)], at date: Date = .now) {
        for entry in paths {
            guard let key = rollupKey(for: entry.path) else { continue }
            var activity = folders[key] ?? FolderActivity()
            activity.lastOpen = date
            activity.lastOpenProcess = entry.process
            folders[key] = activity
        }
        dirty = true
        pruneIfNeeded()
    }

    /// Most recent observed activity anywhere under `path` (including the
    /// roll-up bucket that *contains* it — a deep target inherits its
    /// bucket's activity, which can only over-report use, never under-report).
    public func summary(under path: String) -> ActivitySummary {
        var lastWrite: Date?
        var lastOpen: Date?
        var lastProcess: String?
        let prefix = path.hasSuffix("/") ? path : path + "/"
        for (key, activity) in folders {
            let related = key == path || key.hasPrefix(prefix)
                || path.hasPrefix(key + "/")
            guard related else { continue }
            if let write = activity.lastWrite, lastWrite.map({ write > $0 }) ?? true {
                lastWrite = write
            }
            if let open = activity.lastOpen, lastOpen.map({ open > $0 }) ?? true {
                lastOpen = open
                lastProcess = activity.lastOpenProcess
            }
        }
        return ActivitySummary(
            lastWrite: lastWrite, lastOpen: lastOpen, lastOpenProcess: lastProcess,
            trackingSince: trackingSince)
    }

    public func saveIfDirty() {
        guard dirty else { return }
        dirty = false
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshot = Snapshot(trackingSince: trackingSince, folders: folders)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    /// Drops the least-recently-active buckets once past the cap.
    private func pruneIfNeeded() {
        guard folders.count > Self.maxEntries else { return }
        let sorted = folders.sorted {
            let a = max($0.value.lastWrite ?? .distantPast, $0.value.lastOpen ?? .distantPast)
            let b = max($1.value.lastWrite ?? .distantPast, $1.value.lastOpen ?? .distantPast)
            return a > b
        }
        folders = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(Self.maxEntries * 3 / 4)))
    }
}

/// Resident usage observer. Two cheap, entitlement-free sources feed the
/// ActivityStore:
///  - FSEvents on the home dir + common install roots — folder-granularity
///    *write* events, essentially free.
///  - A sparse open-file-handle sample (libproc, same pattern as
///    MonitorEngine) every 10 minutes — catches *reads* held open by live
///    processes (a venv's python, a played video). Brief opens between
///    samples are missed; the store is honest positive evidence, not a
///    complete audit log.
public final class UsageObserver: @unchecked Sendable {
    public static let shared = UsageObserver()

    public let store: ActivityStore
    private var stream: FSEventStreamRef?
    private var samplerTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "com.pulse.usage-observer", qos: .utility)
    public static let sampleInterval: Duration = .seconds(600)

    /// Never record activity in these — Pulse's own store writes would
    /// otherwise observe themselves forever.
    static let ignoredSubstrings = [
        "/Library/Application Support/Pulse", "/.Trash/", "/Library/Caches/com.apple.",
    ]

    public init(store: ActivityStore = ActivityStore()) {
        self.store = store
    }

    public func start() {
        startFSEvents()
        startHandleSampler()
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        samplerTask?.cancel()
        samplerTask = nil
    }

    // MARK: - FSEvents (writes)

    private func startFSEvents() {
        guard stream == nil else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var roots = [home]
        for extra in ["/opt/homebrew", "/usr/local", "/Applications"]
        where FileManager.default.fileExists(atPath: extra) {
            roots.append(extra)
        }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let observer = Unmanaged<UsageObserver>.fromOpaque(info).takeUnretainedValue()
            guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String]
            else { return }
            let paths = Array(cfPaths.prefix(Int(count)))
                .filter { path in
                    !UsageObserver.ignoredSubstrings.contains { path.contains($0) }
                }
            guard !paths.isEmpty else { return }
            let store = observer.store
            Task { await store.recordWrites(paths: paths) }
        }

        // 30s latency: heavy coalescing — we only care about "touched today",
        // not the exact second, and it keeps the callback rate near zero.
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, roots as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 30,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagIgnoreSelf))
        else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    // MARK: - Open-handle sampling (reads)

    private func startHandleSampler() {
        guard samplerTask == nil else { return }
        samplerTask = Task.detached(priority: .utility) { [store] in
            // First sample soon after launch so a fresh install has data today.
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                let opens = UsageObserver.sampleOpenFiles()
                if !opens.isEmpty {
                    await store.recordOpens(paths: opens)
                }
                await store.saveIfDirty()
                try? await Task.sleep(for: UsageObserver.sampleInterval)
            }
        }
    }

    /// One sweep over this user's processes: every open vnode's path, with
    /// the owning process name. Other users' pids fail EPERM and are skipped.
    /// Cost is bounded: fd walks are capped per process.
    static func sampleOpenFiles(maxFDsPerProcess: Int = 1024) -> [(path: String, process: String)] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let byteCount = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard byteCount > 0 else { return [] }

        var out: [(path: String, process: String)] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let interestingPrefixes = [home, "/opt/homebrew", "/usr/local", "/Applications"]

        for pid in pids[0..<Int(byteCount)] where pid > 0 {
            let fdBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard fdBytes > 0 else { continue }
            let fdCount = min(Int(fdBytes) / MemoryLayout<proc_fdinfo>.size, maxFDsPerProcess)
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
            let got = fds.withUnsafeMutableBytes { buffer in
                proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
            }
            guard got > 0 else { continue }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let processName = nameLength > 0 ? String(nullTerminated: nameBuffer) : "pid \(pid)"

            for fd in fds[0..<(Int(got) / MemoryLayout<proc_fdinfo>.size)]
            where fd.proc_fdtype == PROX_FDTYPE_VNODE {
                var vnodeInfo = vnode_fdinfowithpath()
                let size = proc_pidfdinfo(
                    pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnodeInfo,
                    Int32(MemoryLayout<vnode_fdinfowithpath>.size))
                guard size == Int32(MemoryLayout<vnode_fdinfowithpath>.size) else { continue }
                let path = withUnsafeBytes(of: &vnodeInfo.pvip.vip_path) { raw in
                    String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
                }
                guard interestingPrefixes.contains(where: { path.hasPrefix($0) }),
                    !ignoredSubstrings.contains(where: { path.contains($0) })
                else { continue }
                out.append((path, processName))
            }
        }
        return out
    }
}
