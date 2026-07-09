import Foundation

/// The decision classes a verdict card can reach. Ordered safest-to-delete
/// first. `inUse` means "keep it"; `staleReview` means "old but
/// irreplaceable — archive, don't delete".
public enum VerdictClass: String, Sendable, Codable {
    case safeToDelete, likelyUnused, inUse, staleReview, unknown
}

/// One evidence row on the card: what was checked, what was found, and
/// whether the finding leans toward deletion (nil = neutral/informational).
public struct VerdictEvidence: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case identity, staleness, spotlight, shellHistory, observer, references
    }

    public var id: String { "\(kind.rawValue)|\(headline)" }
    public let kind: Kind
    public let headline: String
    public let detail: String
    public let favorsDeletion: Bool?

    public init(kind: Kind, headline: String, detail: String, favorsDeletion: Bool?) {
        self.kind = kind
        self.headline = headline
        self.detail = detail
        self.favorsDeletion = favorsDeletion
    }
}

/// The complete answer to "can I delete this?": species, verdict, and every
/// piece of evidence it rests on — shown, never hidden, because opaque
/// "safe to delete" claims are exactly where competing cleaners burn users.
public struct FolderVerdict: Sendable, Equatable {
    public let targetPath: String
    public let species: FolderSpecies?
    public let verdict: VerdictClass
    public let headline: String
    public let evidence: [VerdictEvidence]
    public let sizeBytes: UInt64
    public let regenCommand: String?
}

/// Gathers all probes concurrently and synthesizes the verdict. Static
/// signals (fingerprint, mtime, Spotlight, history, references) always run;
/// observer evidence appears once the resident `UsageObserver` has data.
public actor FolderVerdictEngine {
    /// Activity considered "recent" — anything observed inside this window
    /// blocks a delete recommendation.
    static let recentActivityDays = 14
    /// Staleness threshold for recommending deletion of regenerable folders.
    static let staleDays = 30
    /// Threshold for flagging irreplaceable folders as worth a review.
    static let reviewDays = 180

    private let referenceScanner: UsageGraphScanner
    private let activityStore: ActivityStore
    private let historyProbe: ShellHistoryProbe
    private let fileManager: FileManager
    private let now: Date

    public init(
        referenceScanner: UsageGraphScanner = UsageGraphScanner(),
        activityStore: ActivityStore = UsageObserver.shared.store,
        historyProbe: ShellHistoryProbe = ShellHistoryProbe(),
        fileManager: FileManager = .default,
        now: Date = .now
    ) {
        self.referenceScanner = referenceScanner
        self.activityStore = activityStore
        self.historyProbe = historyProbe
        self.fileManager = fileManager
        self.now = now
    }

    public func verdict(for target: URL) async -> FolderVerdict {
        let species = FingerprintCatalog.identify(target, fileManager: fileManager)

        async let referencesTask = referenceScanner.referrers(for: target)
        async let activityTask = activityStore.summary(under: target.path)
        let staleness = StalenessProbe.scan(target)
        let spotlightDays = StalenessProbe.spotlightLastUsedDays(target, now: now)
        let commandNames = ShellHistoryProbe.commandNames(for: target, fileManager: fileManager)
        let historyHits = historyProbe.hits(names: commandNames, targetPath: target.path)
        let references = await referencesTask
        let activity = await activityTask

        return Self.synthesize(
            targetPath: target.path, species: species, staleness: staleness,
            spotlightDays: spotlightDays, historyHits: historyHits,
            references: references, activity: activity, now: now)
    }

    // MARK: - Synthesis (pure, tested directly)

    static func synthesize(
        targetPath: String, species: FolderSpecies?, staleness: StalenessProbe.Result,
        spotlightDays: Int?, historyHits: [ShellHistoryProbe.Hit],
        references: [UsageEdge], activity: ActivitySummary?, now: Date
    ) -> FolderVerdict {
        var evidence: [VerdictEvidence] = []

        // Identity.
        if let species {
            var detail = species.explanation
            if let caveat = species.regenCaveat { detail += " (\(caveat))" }
            evidence.append(
                VerdictEvidence(
                    kind: .identity,
                    headline: species.regenerable
                        ? "\(species.name) — regenerable" : "\(species.name) — not regenerable",
                    detail: detail, favorsDeletion: species.regenerable))
        } else {
            evidence.append(
                VerdictEvidence(
                    kind: .identity, headline: "Unrecognized folder type",
                    detail: "No marker files matched a known species — treat contents as potentially irreplaceable.",
                    favorsDeletion: nil))
        }

        // Staleness (mtime).
        let modifiedDays = staleness.newestModified.map {
            max(0, Int(now.timeIntervalSince($0) / 86400))
        }
        if let days = modifiedDays {
            evidence.append(
                VerdictEvidence(
                    kind: .staleness,
                    headline: days == 0
                        ? "Contents changed today" : "Nothing inside changed for \(days) days",
                    detail: staleness.truncated
                        ? "Newest of the first \(staleness.fileCount) items scanned (large tree, scan capped)."
                        : "Newest modification date across all \(staleness.fileCount) items.",
                    favorsDeletion: days >= staleDays))
        }

        // Spotlight last-used.
        if let days = spotlightDays {
            evidence.append(
                VerdictEvidence(
                    kind: .spotlight,
                    headline: "Last opened \(days == 0 ? "today" : "\(days) days ago") (Spotlight)",
                    detail: "Finder/app opens only — command-line access is not tracked here.",
                    favorsDeletion: days >= staleDays))
        }

        // Shell history.
        if let top = historyHits.first {
            let when: String
            if let last = top.lastUsed {
                let days = max(0, Int(now.timeIntervalSince(last) / 86400))
                when = days == 0 ? "today" : "\(days) days ago"
            } else {
                when = "date unknown"
            }
            let total = historyHits.reduce(0) { $0 + $1.count }
            evidence.append(
                VerdictEvidence(
                    kind: .shellHistory,
                    headline: "`\(top.command)` ran \(when) — \(total) shell history hits",
                    detail: historyHits.prefix(4).map { "\($0.command) ×\($0.count)" }
                        .joined(separator: ", "),
                    favorsDeletion: false))
        } else if !targetPath.isEmpty {
            evidence.append(
                VerdictEvidence(
                    kind: .shellHistory, headline: "Never seen in shell history",
                    detail: "Absence is weak evidence — scripts, Makefiles and app launches don't reach shell history.",
                    favorsDeletion: nil))
        }

        // Resident observation.
        var observedDays: Int?
        if let activity {
            let lastSeen = [activity.lastWrite, activity.lastOpen].compactMap { $0 }.max()
            let watchedDays = max(0, Int(now.timeIntervalSince(activity.trackingSince) / 86400))
            if let lastSeen {
                let days = max(0, Int(now.timeIntervalSince(lastSeen) / 86400))
                observedDays = days
                let by = activity.lastOpenProcess.map { " by \($0)" } ?? ""
                evidence.append(
                    VerdictEvidence(
                        kind: .observer,
                        headline: "Observed in use \(days == 0 ? "today" : "\(days) days ago")\(by)",
                        detail: "Pulse has been watching file activity for \(watchedDays) days.",
                        favorsDeletion: days >= staleDays))
            } else {
                evidence.append(
                    VerdictEvidence(
                        kind: .observer,
                        headline: "No activity observed in \(watchedDays) days of watching",
                        detail: "Pulse's resident monitor never saw a process write to or hold open anything here.",
                        favorsDeletion: watchedDays >= 7 ? true : nil))
            }
        }

        // Static references.
        if references.isEmpty {
            evidence.append(
                VerdictEvidence(
                    kind: .references, headline: "Nothing on disk references it",
                    detail: "No symlinks, dotfile mentions, Homebrew dependents or linked binaries found.",
                    favorsDeletion: true))
        } else {
            let names = Set(references.map { $0.source.lastPathComponent }).sorted()
            evidence.append(
                VerdictEvidence(
                    kind: .references, headline: "\(references.count) references found",
                    detail: names.prefix(5).joined(separator: ", "),
                    favorsDeletion: false))
        }

        // Verdict synthesis. Recency wins over everything; then
        // regenerability decides between "delete" and "review".
        let recencyDays = [modifiedDays, spotlightDays, observedDays].compactMap { $0 }.min()
        let historyRecent = historyHits.contains {
            guard let last = $0.lastUsed else { return false }
            return now.timeIntervalSince(last) < Double(recentActivityDays) * 86400
        }

        let verdict: VerdictClass
        let headline: String
        if historyRecent || (recencyDays.map { $0 < recentActivityDays } ?? false) {
            verdict = .inUse
            headline = "In use — keep it"
        } else if let species, species.regenerable {
            if (recencyDays.map { $0 >= staleDays } ?? false) && references.isEmpty {
                verdict = .safeToDelete
                headline = "Safe to delete — regenerable and unused"
            } else {
                verdict = .likelyUnused
                headline = "Likely unused — regenerable if wrong"
            }
        } else if recencyDays.map({ $0 >= reviewDays }) ?? false {
            verdict = .staleReview
            headline = "Stale but irreplaceable — review, don't just delete"
        } else {
            verdict = .unknown
            headline = "Not enough evidence — review manually"
        }

        return FolderVerdict(
            targetPath: targetPath, species: species, verdict: verdict, headline: headline,
            evidence: evidence, sizeBytes: staleness.sizeBytes,
            regenCommand: species?.regenCommand)
    }
}
