import Foundation

/// Defines when and how often the scheduled clean runs.
public struct CleanSchedule: Codable, Sendable, Equatable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly
        
        public func nextRun(after date: Date, hour: Int) -> Date {
            var comps = Calendar.current.dateComponents(
                [.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = 0
            comps.second = 0
            let target = Calendar.current.date(from: comps)!
            
            // If the target for *today* is already past, we need the *next* occurrence.
            let start = target <= date ? Calendar.current.date(byAdding: .day, value: 1, to: target)! : target
            
            switch self {
            case .daily: return start
            case .weekly: return Calendar.current.date(byAdding: .day, value: 7, to: start)!
            case .monthly: return Calendar.current.date(byAdding: .month, value: 1, to: start)!
            }
        }
    }

    public enum TimePreference: String, Codable, Sendable, CaseIterable {
        case night, morning, anytime
        
        public var runHour: Int {
            switch self {
            case .night: return 3
            case .morning: return 9
            case .anytime: return 12 // Best effort background
            }
        }
    }

    public var frequency: Frequency
    public var timePreference: TimePreference
    public var lastRun: Date?
    public var nextRun: Date
    public var autoCleanSafeTier: Bool
    public var notifyOnCompletion: Bool

    public init(
        frequency: Frequency, timePreference: TimePreference, lastRun: Date? = nil,
        nextRun: Date, autoCleanSafeTier: Bool, notifyOnCompletion: Bool
    ) {
        self.frequency = frequency
        self.timePreference = timePreference
        self.lastRun = lastRun
        self.nextRun = nextRun
        self.autoCleanSafeTier = autoCleanSafeTier
        self.notifyOnCompletion = notifyOnCompletion
    }

    private enum CodingKeys: String, CodingKey {
        case frequency, timePreference, lastRun, nextRun, autoCleanSafeTier, notifyOnCompletion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try c.decode(Frequency.self, forKey: .frequency)
        timePreference = try c.decodeIfPresent(TimePreference.self, forKey: .timePreference) ?? .night
        lastRun = try c.decodeIfPresent(Date.self, forKey: .lastRun)
        nextRun = try c.decode(Date.self, forKey: .nextRun)
        autoCleanSafeTier = try c.decode(Bool.self, forKey: .autoCleanSafeTier)
        notifyOnCompletion = try c.decode(Bool.self, forKey: .notifyOnCompletion)
    }

    public static func `default`(now: Date = .now) -> CleanSchedule {
        CleanSchedule(
            frequency: .weekly,
            timePreference: .night,
            nextRun: Frequency.weekly.nextRun(after: now, hour: TimePreference.night.runHour),
            autoCleanSafeTier: false,
            notifyOnCompletion: true
        )
    }
}

public actor CleanScheduler {
    public static let scheduleFileName = "clean_schedule.json"

    private let directory: URL
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
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now
    ) {
        self.directory = directory
        self.home = home
        self.schedule = Self.loadSchedule(from: directory) ?? .default(now: now)
    }

    // MARK: - Schedule

    public func currentSchedule() -> CleanSchedule { schedule }

    public func setSchedule(_ newSchedule: CleanSchedule) {
        var updated = newSchedule
        if updated.frequency != schedule.frequency
            || updated.timePreference != schedule.timePreference
            || updated.nextRun <= .now
        {
            updated.nextRun = updated.frequency.nextRun(
                after: .now, hour: updated.timePreference.runHour)
        }
        schedule = updated
        saveSchedule()
    }

    public func isDue(now: Date = .now) -> Bool {
        now >= schedule.nextRun
    }

    public func scheduleIfNeeded(now: Date = .now) async -> (itemsCleaned: Int, bytesFreed: UInt64)? {
        guard isDue(now: now), schedule.autoCleanSafeTier else { return nil }
        return runNow(autoMode: true, now: now)
    }

    // MARK: - Running

    @discardableResult
    public func runNow(autoMode: Bool, now: Date = .now) -> (itemsCleaned: Int, bytesFreed: UInt64) {
        let items = SmartScanner(home: home, now: now).scan()
            .items.filter { $0.grade == .safe }

        var itemsCleaned = 0
        var bytesFreed: UInt64 = 0
        if !items.isEmpty {
            for item in items {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    itemsCleaned += 1
                    bytesFreed += item.sizeBytes
                } catch {
                    // ignore
                }
            }
        }
        
        schedule.lastRun = now
        schedule.nextRun = schedule.frequency.nextRun(
            after: now, hour: schedule.timePreference.runHour)
        saveSchedule()
        return (itemsCleaned, bytesFreed)
    }

    public func preview(now: Date = .now) -> [CleanItem] {
        SmartScanner(home: home, now: now).scan().items.filter { $0.grade == .safe }
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
