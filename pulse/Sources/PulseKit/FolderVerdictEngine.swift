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
        case identity, owner, staleness, spotlight, shellHistory, observer, references
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
    /// The observer's opinion only counts once it has actually watched for a
    /// while — "observed today" during the first hours after install is just
    /// the initial burst of ambient system activity.
    static let minObservationDays = 3

    private let referenceScanner: UsageGraphScanner
    private let activityStore: ActivityStore
    private let historyProbe: ShellHistoryProbe
    private let ownerProbe: OwnerLivenessProbe
    private let fileManager: FileManager
    private let now: Date

    public init(
        referenceScanner: UsageGraphScanner = UsageGraphScanner(),
        activityStore: ActivityStore = UsageObserver.shared.store,
        historyProbe: ShellHistoryProbe = ShellHistoryProbe(),
        ownerProbe: OwnerLivenessProbe = OwnerLivenessProbe(),
        fileManager: FileManager = .default,
        now: Date = .now
    ) {
        self.referenceScanner = referenceScanner
        self.activityStore = activityStore
        self.historyProbe = historyProbe
        self.ownerProbe = ownerProbe
        self.fileManager = fileManager
        self.now = now
    }

    public func verdict(for target: URL) async -> FolderVerdict {
        let species = FingerprintCatalog.identify(target, fileManager: fileManager)
        let home = fileManager.homeDirectoryForCurrentUser.path

        async let referencesTask = referenceScanner.referrers(for: target)
        async let activityTask = activityStore.summary(under: target.path)
        let staleness = StalenessProbe.scan(target)
        let spotlightDays = StalenessProbe.spotlightLastUsedDays(target, now: now)
        let isDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]))?
            .isDirectory ?? true
        let commandNames = ShellHistoryProbe.commandNames(for: target, fileManager: fileManager)
        let historyHits = historyProbe.hits(names: commandNames, targetPath: target.path)
        let liveness = ownerProbe.liveness(for: target, home: home)
        let references = await referencesTask
        let activity = await activityTask

        return Self.synthesize(
            targetPath: target.path, species: species, staleness: staleness,
            spotlightDays: spotlightDays, targetIsDirectory: isDirectory,
            historyHits: historyHits, liveness: liveness,
            references: references, activity: activity, now: now)
    }

    // MARK: - Synthesis (pure, tested directly)

    // swiftlint:disable:next function_body_length
    static func synthesize(
        targetPath: String, species: FolderSpecies?, staleness: StalenessProbe.Result,
        spotlightDays: Int?, targetIsDirectory: Bool,
        historyHits: [ShellHistoryProbe.Hit], liveness: OwnerLivenessProbe.Liveness,
        references: [UsageEdge], activity: ActivitySummary?, now: Date
    ) -> FolderVerdict {
        var evidence: [VerdictEvidence] = []
        func days(_ date: Date?) -> Int? {
            date.map { max(0, Int(now.timeIntervalSince($0) / 86400)) }
        }

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
        } else if case .missing(let tool) = liveness {
            evidence.append(
                VerdictEvidence(
                    kind: .identity, headline: "Data folder for the tool “\(tool)”",
                    detail: "Settings/state a tool keeps in your home folder. The tool recreates defaults if reinstalled.",
                    favorsDeletion: nil))
        } else {
            evidence.append(
                VerdictEvidence(
                    kind: .identity, headline: "Unrecognized folder type",
                    detail: "No marker files matched a known species — treat contents as potentially irreplaceable.",
                    favorsDeletion: nil))
        }

        // Owner liveness — the uninstall-leftover check.
        switch liveness {
        case .missing(let tool):
            evidence.append(
                VerdictEvidence(
                    kind: .owner, headline: "Owning tool “\(tool)” is not installed",
                    detail: "No executable, app bundle or Homebrew formula named “\(tool)” found — this looks like an uninstall leftover.",
                    favorsDeletion: true))
        case .installed(let path):
            evidence.append(
                VerdictEvidence(
                    kind: .owner, headline: "Owning tool is installed",
                    detail: "Found at \(path) — the tool may still read this folder.",
                    favorsDeletion: false))
        case .notApplicable:
            break
        }

        // Staleness — content mtime drives the verdict; housekeeping churn
        // (.DS_Store, logs, caches) is reported separately, never counted.
        let contentDays = days(staleness.newestContent)
        let anyDays = days(staleness.newestAny)
        if let cDays = contentDays {
            var detail = staleness.newestContentName.map { "Newest real file: \($0)." } ?? ""
            if let aDays = anyDays, aDays < cDays {
                detail += " Housekeeping files (logs/.DS_Store) changed more recently — ignored, that churn continues even after an app is deleted."
            }
            if staleness.truncated {
                detail += " Large tree — scan capped at \(staleness.fileCount) items."
            }
            evidence.append(
                VerdictEvidence(
                    kind: .staleness,
                    headline: cDays == 0
                        ? "Content changed today"
                        : "No real content changed for \(cDays) days",
                    detail: detail.trimmingCharacters(in: .whitespaces),
                    favorsDeletion: cDays >= staleDays))
        } else if anyDays != nil {
            evidence.append(
                VerdictEvidence(
                    kind: .staleness, headline: "Only housekeeping files inside",
                    detail: "Nothing but logs/caches/Finder metadata — no substantive content found.",
                    favorsDeletion: true))
        }

        // Spotlight last-used. For folders this mostly records Finder/Pulse
        // *browsing* — including the browsing that led here — so a recent
        // date is meaningless for directories. Only staleness is signal.
        if let sDays = spotlightDays {
            let recentDirNoise = targetIsDirectory && sDays < staleDays
            evidence.append(
                VerdictEvidence(
                    kind: .spotlight,
                    headline: "Last opened \(sDays == 0 ? "today" : "\(sDays) days ago") (Spotlight)",
                    detail: recentDirNoise
                        ? "For folders this includes just browsing to it (even in Pulse) — not counted as real use."
                        : "Finder/app opens only — command-line access is not tracked here.",
                    favorsDeletion: sDays >= staleDays ? true : nil))
        }

        // Shell history — running the tool is evidence; merely mentioning
        // the path (an old cd, a stale export) is not.
        let ranHits = historyHits.filter { $0.kind == .ran }
        if let top = historyHits.first {
            let when: String
            if let last = top.lastUsed {
                let hitDays = days(last) ?? 0
                when = hitDays == 0 ? "today" : "\(hitDays) days ago"
            } else {
                when = "date unknown"
            }
            let verb = top.kind == .ran ? "ran" : "was mentioned"
            let total = historyHits.reduce(0) { $0 + $1.count }
            evidence.append(
                VerdictEvidence(
                    kind: .shellHistory,
                    headline: "`\(top.command)` \(verb) \(when) — \(total) history hits",
                    detail: top.kind == .ran
                        ? historyHits.prefix(4).map { "\($0.command) ×\($0.count)" }
                            .joined(separator: ", ")
                        : "Path mentions only (cd, old exports) — doesn't prove the tool still runs.",
                    favorsDeletion: top.kind == .ran ? false : nil))
        } else if !targetPath.isEmpty {
            evidence.append(
                VerdictEvidence(
                    kind: .shellHistory, headline: "Never seen in shell history",
                    detail: "Absence is weak evidence — scripts, Makefiles and app launches don't reach shell history.",
                    favorsDeletion: nil))
        }

        // Resident observation. Only process-attributed opens (system noise
        // already filtered) count toward "in use", and only once Pulse has
        // watched long enough for absence/presence to mean anything.
        var observedOpenDays: Int?
        if let activity {
            let watchedDays = days(activity.trackingSince) ?? 0
            let windowValid = watchedDays >= minObservationDays
            if let open = activity.lastOpen {
                let openDays = days(open) ?? 0
                if windowValid { observedOpenDays = openDays }
                let by = activity.lastOpenProcess.map { " by \($0)" } ?? ""
                evidence.append(
                    VerdictEvidence(
                        kind: .observer,
                        headline: "Held open \(openDays == 0 ? "today" : "\(openDays) days ago")\(by)",
                        detail: windowValid
                            ? "Watching for \(watchedDays) days. System indexers/backup daemons are filtered out."
                            : "Watching for only \(watchedDays) days — too early to weigh; verdicts firm up as Pulse keeps observing.",
                        favorsDeletion: windowValid && openDays >= staleDays))
            } else if let write = activity.lastWrite {
                // FSEvents writes can't be attributed to a process (Finder's
                // .DS_Store looks the same as a real write) — informational.
                let writeDays = days(write) ?? 0
                evidence.append(
                    VerdictEvidence(
                        kind: .observer,
                        headline: "Something wrote here \(writeDays == 0 ? "today" : "\(writeDays) days ago")",
                        detail: "Writer unknown (could be Finder metadata). Not counted toward the verdict.",
                        favorsDeletion: nil))
            } else {
                evidence.append(
                    VerdictEvidence(
                        kind: .observer,
                        headline: windowValid
                            ? "No activity observed in \(watchedDays) days of watching"
                            : "No activity observed yet (watching \(watchedDays) days)",
                        detail: windowValid
                            ? "No real process wrote to or held open anything here since Pulse started watching."
                            : "Verdicts firm up as Pulse keeps observing.",
                        favorsDeletion: windowValid ? true : nil))
            }
        }

        // Static references. When the owner is uninstalled, remaining
        // references are themselves leftovers (a stale PATH export, a
        // dangling symlink) — cleanup pointers, not keep-signals.
        let ownerMissing: Bool
        if case .missing = liveness { ownerMissing = true } else { ownerMissing = false }
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
                    kind: .references,
                    headline: ownerMissing
                        ? "\(references.count) leftover references — clean these too"
                        : "\(references.count) references found",
                    detail: names.prefix(5).joined(separator: ", ")
                        + (ownerMissing
                            ? " — with the tool gone these are stale; update .zshrc/symlinks after deleting."
                            : ""),
                    favorsDeletion: ownerMissing ? true : false))
        }

        // ---- Verdict ----
        // Real use signals only: content mtime, process-attributed opens
        // (valid window), dated `ran` history hits. Spotlight-recent and
        // unattributed writes never block deletion.
        let ranRecent = ranHits.contains {
            guard let last = $0.lastUsed else { return false }
            return now.timeIntervalSince(last) < Double(recentActivityDays) * 86400
        }
        let fileSpotlightDays = targetIsDirectory ? nil : spotlightDays
        let useDays = [contentDays, observedOpenDays, fileSpotlightDays].compactMap { $0 }.min()
        let recentlyUsed = ranRecent || (useDays.map { $0 < recentActivityDays } ?? false)
        // No recency evidence at all (no mtime, no observed opens, no
        // Spotlight hit) means "unknown", not "stale" — defaulting to stale
        // let a folder Pulse has zero signal about reach safeToDelete.
        let stale = useDays.map { $0 >= staleDays } ?? false

        let verdict: VerdictClass
        let headline: String
        // A dotfile/rc reference is *executed* every shell start (`.nvm`
        // sourced from .zshrc has no binary, yet is in daily use) — it must
        // block "safe to trash" even when no owning executable exists.
        // Symlinks/dylib links, by contrast, just dangle once the owner is
        // gone.
        let liveTextRefs = references.contains { $0.signal == .textRef }
        if recentlyUsed {
            verdict = .inUse
            headline = "In use — keep it"
        } else if ownerMissing, species == nil || species?.regenerable == true {
            if case .missing(let tool) = liveness, stale, !liveTextRefs {
                verdict = .safeToDelete
                headline = "Leftover from uninstalled “\(tool)” — safe to trash"
            } else if liveTextRefs {
                verdict = .likelyUnused
                headline = "Probably leftover — but your shell config still references it"
            } else {
                verdict = .likelyUnused
                headline = "Owner uninstalled, but changed recently — probably leftover"
            }
        } else if let species, species.regenerable {
            if stale && references.isEmpty {
                verdict = .safeToDelete
                headline = "Safe to delete — regenerable and unused"
            } else {
                verdict = .likelyUnused
                headline = "Likely unused — regenerable if wrong"
            }
        } else if useDays.map({ $0 >= reviewDays }) ?? false {
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
