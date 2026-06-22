import Foundation

/// One app's share of active compute during a battery session. Energy is
/// approximated by accumulated CPU-time (cpuPercent × elapsed seconds), since
/// macOS exposes no measured per-process battery drain to a non-root app.
/// `cpuTimeSeconds` is a relative weight, not wall-clock seconds.
public struct AppEnergyShare: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public var cpuTimeSeconds: Double
    public var firstSeen: Date
    public var lastSeen: Date
    public var id: String { name }

    public init(name: String, cpuTimeSeconds: Double, firstSeen: Date, lastSeen: Date) {
        self.name = name
        self.cpuTimeSeconds = cpuTimeSeconds
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

/// One contiguous on-battery stretch: when it ran, the charge it cost, and the
/// apps that did the work. `endedAt` is nil while the session is live.
public struct BatterySession: Codable, Equatable, Sendable, Identifiable {
    /// Where the session came from. `live` is captured by Pulse while running
    /// (carries per-app energy); `backfill` is reconstructed from the pmset log
    /// (accurate times + charge, but no per-app data — that history doesn't
    /// exist). Optional so sessions persisted before this field decode as live.
    public enum Source: String, Codable, Sendable { case live, backfill }

    public let id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var startCharge: Int
    public var endCharge: Int
    /// CPU-time weight per app, highest first. Capped to top-N + "Other" once
    /// the session closes so the stored file stays bounded.
    public var apps: [AppEnergyShare]
    public var source: Source?

    public init(
        id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil,
        startCharge: Int, endCharge: Int, apps: [AppEnergyShare] = [],
        source: Source = .live
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startCharge = startCharge
        self.endCharge = endCharge
        self.apps = apps
        self.source = source
    }

    public var isLive: Bool { endedAt == nil }
    public var isBackfilled: Bool { source == .backfill }
    /// % drained over the session (clamped ≥ 0; charge can tick up on noise).
    public var chargeDrop: Int { Swift.max(0, startCharge - endCharge) }
    public func duration(now: Date = .now) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }

    /// Apps as fractions of total CPU-time weight (0–1), highest first.
    public var shares: [(app: AppEnergyShare, fraction: Double)] {
        let total = apps.reduce(0) { $0 + $1.cpuTimeSeconds }
        guard total > 0 else { return [] }
        return apps
            .map { ($0, $0.cpuTimeSeconds / total) }
            .sorted { $0.1 > $1.1 }
    }
}

/// Persists battery sessions (time on battery, charge drop, per-app energy
/// share) to JSON in Application Support. Same single-threaded, MainActor-
/// driven pattern as `BatteryHistoryStore`; not an actor.
public final class BatterySessionStore {
    /// Drop sessions older than this (matches the 60-day Health window).
    public static let maxAge: TimeInterval = 60 * 24 * 3600
    /// Hard cap on stored sessions so the file can't grow without bound.
    public static let maxSessions = 200
    /// Sessions shorter than this are noise (a brief unplug) — discarded on close.
    public static let minDurationToKeep: TimeInterval = 90
    /// Apps kept per closed session; the rest fold into an "Other" bucket.
    public static let topAppsPerSession = 8
    static let otherBucketName = "Other"

    public private(set) var sessions: [BatterySession]
    private let fileURL: URL?

    public init(fileURL: URL? = BatterySessionStore.defaultFileURL(), now: Date = .now) {
        self.fileURL = fileURL
        if let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([BatterySession].self, from: data)
        {
            sessions = stored.filter { now.timeIntervalSince($0.startedAt) <= Self.maxAge }
        } else {
            sessions = []
        }
    }

    /// Index of the open (live) session, if one exists. Only the last entry can
    /// be live, but search defensively.
    private var liveIndex: Int? {
        sessions.lastIndex(where: { $0.isLive })
    }

    public var liveSession: BatterySession? {
        liveIndex.map { sessions[$0] }
    }

    /// Sessions reconstructed from the pmset log. Held separately from the
    /// persisted `sessions` because they're recomputed from the log every
    /// launch — never written to disk, so they can't accumulate or drift.
    private var backfilled: [BatterySession] = []

    /// Persisted live sessions plus non-overlapping backfilled ones, oldest
    /// first. This is what the UI shows.
    public var allSessions: [BatterySession] {
        (sessions + backfilled).sorted { $0.startedAt < $1.startedAt }
    }

    /// Replaces the backfilled set with freshly parsed sessions, dropping any
    /// that overlap a live-captured session (live wins — it has per-app data)
    /// or fall outside the retention window.
    public func mergeBackfilled(_ parsed: [BatterySession], now: Date = .now) {
        backfilled = parsed.filter { candidate in
            now.timeIntervalSince(candidate.startedAt) <= Self.maxAge
                && !sessions.contains { overlaps($0, candidate) }
        }
    }

    private func overlaps(_ a: BatterySession, _ b: BatterySession) -> Bool {
        let aEnd = a.endedAt ?? .distantFuture
        let bEnd = b.endedAt ?? .distantFuture
        return a.startedAt < bEnd && b.startedAt < aEnd
    }

    /// Opens a session at unplug. No-ops if one is already live.
    public func beginSession(charge: Int, at date: Date = .now) {
        guard liveIndex == nil else { return }
        sessions.append(
            BatterySession(startedAt: date, startCharge: charge, endCharge: charge))
        persist()
    }

    /// Folds one on-battery sample into the live session: bumps each app's
    /// CPU-time weight by `cpuPercent × elapsed` and tracks the latest charge.
    /// No-op when no session is live (e.g. on AC).
    public func accumulate(
        processes: [(name: String, cpuPercent: Double)],
        elapsed: TimeInterval, charge: Int, at date: Date = .now
    ) {
        guard let index = liveIndex, elapsed > 0 else { return }
        var session = sessions[index]
        session.endCharge = charge
        session.endedAt = nil

        // uniquingKeysWith (not uniqueKeysWithValues) so a stray duplicate name
        // can never trap — live sessions hold unique names by construction, but
        // this stays safe if that ever changes.
        var byName = Dictionary(session.apps.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for proc in processes where proc.cpuPercent > 0 {
            let weight = proc.cpuPercent * elapsed
            if var existing = byName[proc.name] {
                existing.cpuTimeSeconds += weight
                existing.lastSeen = date
                byName[proc.name] = existing
            } else {
                byName[proc.name] = AppEnergyShare(
                    name: proc.name, cpuTimeSeconds: weight,
                    firstSeen: date, lastSeen: date)
            }
        }
        session.apps = Array(byName.values)
        sessions[index] = session
        // Don't persist every tick — endSession and begin handle durability;
        // a crash mid-session loses at most the in-flight weights.
    }

    /// Closes the live session at replug (or sleep gap). Discards too-short
    /// sessions; caps the app list to top-N + "Other"; prunes + persists.
    public func endSession(charge: Int, at date: Date = .now) {
        guard let index = liveIndex else { return }
        var session = sessions[index]
        session.endCharge = charge
        session.endedAt = date

        if session.duration(now: date) < Self.minDurationToKeep {
            sessions.remove(at: index)
        } else {
            session.apps = Self.capApps(session.apps)
            sessions[index] = session
        }
        prune(now: date)
        persist()
    }

    /// Sorts apps by weight, keeps the top N, and rolls the remainder into a
    /// single "Other" entry so shares still sum to 100%.
    static func capApps(_ apps: [AppEnergyShare]) -> [AppEnergyShare] {
        let sorted = apps.sorted { $0.cpuTimeSeconds > $1.cpuTimeSeconds }
        guard sorted.count > topAppsPerSession else { return sorted }
        let kept = Array(sorted.prefix(topAppsPerSession))
        let rest = sorted.dropFirst(topAppsPerSession)
        let otherWeight = rest.reduce(0) { $0 + $1.cpuTimeSeconds }
        guard otherWeight > 0 else { return kept }
        let other = AppEnergyShare(
            name: otherBucketName,
            cpuTimeSeconds: otherWeight,
            firstSeen: rest.map(\.firstSeen).min() ?? Date(),
            lastSeen: rest.map(\.lastSeen).max() ?? Date())
        return kept + [other]
    }

    private func prune(now: Date) {
        sessions.removeAll { now.timeIntervalSince($0.startedAt) > Self.maxAge }
        if sessions.count > Self.maxSessions {
            sessions.removeFirst(sessions.count - Self.maxSessions)
        }
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse/battery-sessions.json")
    }
}
