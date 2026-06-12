import Foundation

/// When and how the scheduled deep clean runs. Persisted as JSON so the
/// schedule survives app restarts (and is readable by the future helper).
public struct CleanSchedule: Codable, Sendable, Equatable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly

        /// Anchor hour for scheduled runs — 03:00, when the Mac is idle.
        static let runHour = 3

        /// First occurrence strictly after `date` at the anchor hour:
        /// daily → tomorrow, weekly → next Sunday, monthly → 1st of next month.
        public func nextRun(after date: Date, calendar: Calendar = .current) -> Date {
            var components = DateComponents()
            components.hour = Self.runHour
            components.minute = 0
            switch self {
            case .daily:
                break
            case .weekly:
                components.weekday = 1  // Sunday
            case .monthly:
                components.day = 1
            }
            return calendar.nextDate(
                after: date, matching: components, matchingPolicy: .nextTime)
                ?? date.addingTimeInterval(86400)
        }
    }

    public var frequency: Frequency
    public var lastRun: Date?
    public var nextRun: Date
    /// If true, due runs clean the safe tier without user confirmation.
    public var autoCleanSafeTier: Bool
    public var notifyOnCompletion: Bool

    public init(
        frequency: Frequency, lastRun: Date? = nil, nextRun: Date,
        autoCleanSafeTier: Bool, notifyOnCompletion: Bool
    ) {
        self.frequency = frequency
        self.lastRun = lastRun
        self.nextRun = nextRun
        self.autoCleanSafeTier = autoCleanSafeTier
        self.notifyOnCompletion = notifyOnCompletion
    }

    /// Conservative default: weekly, auto-clean off until the user opts in.
    public static func `default`(now: Date = .now) -> CleanSchedule {
        CleanSchedule(
            frequency: .weekly,
            nextRun: Frequency.weekly.nextRun(after: now),
            autoCleanSafeTier: false,
            notifyOnCompletion: true
        )
    }
}

/// One completed clean, appended to the JSONL history log.
public struct CleanRecord: Codable, Sendable, Identifiable, Equatable {
    public let date: Date
    public let itemsCleaned: Int
    public let bytesFreed: UInt64
    /// Links to the VaultSession holding the staged files — restore path.
    public let sessionID: UUID

    public var id: UUID { sessionID }

    public init(date: Date, itemsCleaned: Int, bytesFreed: UInt64, sessionID: UUID) {
        self.date = date
        self.itemsCleaned = itemsCleaned
        self.bytesFreed = bytesFreed
        self.sessionID = sessionID
    }
}

/// Scheduled deep-clean coordinator: owns the schedule file, the append-only
/// history log, and the run itself (SmartScanner safe tier → SafetyVault).
/// Pure logic + persistence — notifications and OS scheduling live in the
/// app layer, keeping PulseKit UI- and framework-independent.
public actor CleanScheduler {
    public static let scheduleFileName = "clean_schedule.json"
    public static let historyFileName = "clean_history.jsonl"

    private let directory: URL
    private let vault: SafetyVault
    private let home: URL
    private var schedule: CleanSchedule

    public static func defaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Pulse")
    }

    public init(
        directory: URL = CleanScheduler.defaultDirectory(),
        vault: SafetyVault = SafetyVault(rootURL: SafetyVault.defaultRootURL()),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now
    ) {
        self.directory = directory
        self.vault = vault
        self.home = home
        self.schedule = Self.loadSchedule(from: directory) ?? .default(now: now)
    }

    // MARK: - Schedule

    public func currentSchedule() -> CleanSchedule { schedule }

    public func setSchedule(_ newSchedule: CleanSchedule) {
        var updated = newSchedule
        // Frequency change recomputes the next slot; never keep a stale date.
        if updated.frequency != schedule.frequency || updated.nextRun <= .now {
            updated.nextRun = updated.frequency.nextRun(after: .now)
        }
        schedule = updated
        saveSchedule()
    }

    /// True when the next run is due (the app layer decides whether to run
    /// automatically or just notify, based on `autoCleanSafeTier`).
    public func isDue(now: Date = .now) -> Bool {
        now >= schedule.nextRun
    }

    /// Runs the due clean if auto mode is enabled. Returns the record when
    /// a clean actually ran, nil otherwise — the app layer notifies on it.
    public func scheduleIfNeeded(now: Date = .now) async -> CleanRecord? {
        guard isDue(now: now), schedule.autoCleanSafeTier else { return nil }
        return runNow(autoMode: true, now: now)
    }

    // MARK: - Running

    /// Scans, stages every safe-tier item into the Vault, logs the record,
    /// and advances the schedule. Blocking I/O — call off the main actor.
    @discardableResult
    public func runNow(autoMode: Bool, now: Date = .now) -> CleanRecord {
        let items = SmartScanner(home: home, now: now).scan()
            .items.filter { $0.grade == .safe }

        var record = CleanRecord(
            date: now, itemsCleaned: 0, bytesFreed: 0, sessionID: UUID())
        if !items.isEmpty {
            let payload = items.map { (path: $0.path, label: $0.label, sizeBytes: $0.sizeBytes) }
            let title = autoMode ? "Auto Clean — safe tier" : "Clean — safe tier"
            if let session = try? vault.stage(items: payload, title: title, date: now) {
                record = CleanRecord(
                    date: now,
                    itemsCleaned: session.items.count,
                    bytesFreed: session.totalBytes,
                    sessionID: session.id
                )
            }
        }
        appendHistory(record)
        schedule.lastRun = now
        schedule.nextRun = schedule.frequency.nextRun(after: now)
        saveSchedule()
        return record
    }

    /// Safe-tier items the next run would clean. Blocking scan.
    public func preview(now: Date = .now) -> [CleanItem] {
        SmartScanner(home: home, now: now).scan().items.filter { $0.grade == .safe }
    }

    // MARK: - History

    /// All records, newest first.
    public func history() -> [CleanRecord] {
        guard
            let text = try? String(
                contentsOf: directory.appendingPathComponent(Self.historyFileName),
                encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n")
            .compactMap { try? decoder.decode(CleanRecord.self, from: Data($0.utf8)) }
            .sorted { $0.date > $1.date }
    }

    private func appendHistory(_ record: CleanRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A)
        let url = directory.appendingPathComponent(Self.historyFileName)
        ensureDirectory()
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Persistence

    private static func loadSchedule(from directory: URL) -> CleanSchedule? {
        guard
            let data = try? Data(
                contentsOf: directory.appendingPathComponent(scheduleFileName))
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CleanSchedule.self, from: data)
    }

    private func saveSchedule() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(schedule) else { return }
        ensureDirectory()
        try? data.write(
            to: directory.appendingPathComponent(Self.scheduleFileName), options: .atomic)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }
}
