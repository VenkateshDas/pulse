import Foundation
import os

private let log = Logger(subsystem: "com.pulse.app", category: "Battery")

/// Persists one battery-capacity reading per day so the Health page can
/// chart the 60-day degradation trend across launches. JSON file in
/// Application Support, same pattern as DiskHistoryStore.
public final class BatteryHistoryStore {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public let date: Date
        public var timeOnBattery: TimeInterval
        /// Maximum-capacity ratio (% of design) on this day. nil until a
        /// reading is recorded — older entries decode to nil.
        public var capacityPercent: Int?
        /// Earliest and latest timestamps of battery-on activity this day.
        /// Used to show "9:00 AM – 11:30 PM" in the consumption card.
        public var firstActiveAt: Date?
        public var lastActiveAt: Date?
        public var id: Date { date }

        public init(
            date: Date, timeOnBattery: TimeInterval, capacityPercent: Int? = nil,
            firstActiveAt: Date? = nil, lastActiveAt: Date? = nil
        ) {
            self.date = Calendar.current.startOfDay(for: date)
            self.timeOnBattery = timeOnBattery
            self.capacityPercent = capacityPercent
            self.firstActiveAt = firstActiveAt
            self.lastActiveAt = lastActiveAt
        }
    }

    public static let maxAge: TimeInterval = 60 * 24 * 3600

    public private(set) var entries: [Entry]
    private let fileURL: URL?
    /// Time-on-battery accrues every sample tick (3–30s); persisting each
    /// tick meant an atomic disk write that often, which itself costs battery.
    /// Same-day accrual is throttled; a new day's first entry writes at once.
    /// A crash loses at most this window of on-battery time.
    private static let persistThrottle: TimeInterval = 60
    private var lastTimePersist = Date.distantPast

    public init(fileURL: URL? = BatteryHistoryStore.defaultFileURL(), now: Date = .now) {
        self.fileURL = fileURL
        if let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([Entry].self, from: data)
        {
            entries = stored.filter { now.timeIntervalSince($0.date) <= Self.maxAge }
        } else {
            entries = []
        }
    }

    /// Adds time spent on battery to the current calendar day's entry.
    /// Also tracks the earliest and latest active timestamps for the day so
    /// the UI can display a "9:00 AM – 11:30 PM" usage window.
    public func addTimeOnBattery(_ duration: TimeInterval, at date: Date = .now) {
        guard duration > 0 else { return }
        let sessionStart = date.addingTimeInterval(-duration)
        // A tick can span midnight (sleep/wake over a long gap) — split it
        // across day boundaries the same way the pmset-log backfill path does,
        // so live-recorded and backfilled totals for a given day agree.
        let splits = splitBatterySession(start: sessionStart, end: date)
        let isNewDay = splits.contains { day, _ in !entries.contains { $0.date == day } }

        for (day, dur) in splits {
            let spanStart = max(sessionStart, day)
            let spanEnd = min(date, day.addingTimeInterval(86400))
            if let index = entries.firstIndex(where: { $0.date == day }) {
                entries[index].timeOnBattery += dur
                entries[index].firstActiveAt = entries[index].firstActiveAt.map {
                    min($0, spanStart)
                } ?? spanStart
                entries[index].lastActiveAt = max(entries[index].lastActiveAt ?? spanEnd, spanEnd)
            } else {
                entries.append(
                    Entry(
                        date: day, timeOnBattery: dur,
                        firstActiveAt: spanStart, lastActiveAt: spanEnd))
            }
        }
        entries.sort { $0.date < $1.date }
        entries.removeAll { date.timeIntervalSince($0.date) > Self.maxAge }
        if isNewDay || Date().timeIntervalSince(lastTimePersist) >= Self.persistThrottle {
            persist()
            lastTimePersist = Date()
        }
    }

    /// Records the day's battery capacity once — overwrites if already set so
    /// the latest reading wins. Persists only when the value changes, keeping
    /// the 60-day degradation series at one point per day.
    public func recordCapacity(_ capacityPercent: Int, at date: Date = .now) {
        guard capacityPercent > 0 else { return }
        let startOfDay = Calendar.current.startOfDay(for: date)
        if let index = entries.firstIndex(where: { $0.date == startOfDay }) {
            guard entries[index].capacityPercent != capacityPercent else { return }
            entries[index].capacityPercent = capacityPercent
        } else {
            entries.append(Entry(date: startOfDay, timeOnBattery: 0, capacityPercent: capacityPercent))
            entries.sort { $0.date < $1.date }
        }
        entries.removeAll { date.timeIntervalSince($0.date) > Self.maxAge }
        persist()
    }

    @MainActor
    public func backfillFromSystemLog() async {
        let parsedEntries = await backfillBatteryHistoryFromSystemLog()
        self.mergeParsedEntries(parsedEntries)
    }

    @MainActor
    private func mergeParsedEntries(_ parsed: [Date: TimeInterval]) {
        let now = Date()
        for (day, duration) in parsed {
            updateEntry(for: day, duration: duration, maxAgeDate: now) { current, new in
                current = max(current, new)
            }
        }
        persist()
    }

    private func updateEntry(for date: Date, duration: TimeInterval, maxAgeDate: Date, combine: (inout TimeInterval, TimeInterval) -> Void) {
        guard maxAgeDate.timeIntervalSince(date) <= Self.maxAge else { return }
        let startOfDay = Calendar.current.startOfDay(for: date)
        
        if let index = entries.firstIndex(where: { $0.date == startOfDay }) {
            combine(&entries[index].timeOnBattery, duration)
        } else {
            entries.append(Entry(date: startOfDay, timeOnBattery: duration))
        }
        
        entries.sort { $0.date < $1.date }
        entries.removeAll { maxAgeDate.timeIntervalSince($0.date) > Self.maxAge }
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse/battery-history.json")
    }
}

// MARK: - Global Concurrency Helpers (to avoid Swift 6 region isolation compiler bugs)

func backfillBatteryHistoryFromSystemLog() async -> [Date: TimeInterval] {
    await Task.detached(priority: .background) { () -> [Date: TimeInterval] in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = try pipe.fileHandleForReading.readToEnd()
            process.waitUntilExit()
            if let data = data, let logContent = String(data: data, encoding: .utf8) {
                return parseLogContent(logContent)
            }
        } catch {
            log.error("pmset history backfill failed: \(error, privacy: .public)")
        }
        return [:]
    }.value
}

func parseLogContent(_ log: String) -> [Date: TimeInterval] {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    
    var isAwake = false
    var isOnBattery = false
    var sessionStart: Date? = nil
    var dailyUsage: [Date: TimeInterval] = [:]
    
    let lines = log.components(separatedBy: .newlines)
    // Match a leading "yyyy-MM-dd HH:mm:ss ±ZZZZ" timestamp rather than slicing
    // a fixed 25 chars — tolerant of leading whitespace and offset-width drift.
    let stampRegex = try? NSRegularExpression(
        pattern: #"^\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4})"#)

    for line in lines {
        guard let regex = stampRegex,
            let match = regex.firstMatch(
                in: line, range: NSRange(line.startIndex..., in: line)),
            let stampRange = Range(match.range(at: 1), in: line),
            let date = dateFormatter.date(from: String(line[stampRange]))
        else { continue }

        let lowerLine = line.lowercased()
        
        if lowerLine.contains("using ac") {
            isOnBattery = false
        } else if lowerLine.contains("using batt") {
            isOnBattery = true
        }
        
        // Check sleep/darkwake FIRST: "DarkWake from …" also contains the
        // substring "wake from", so matching wake first would wrongly count a
        // dark wake (a brief maintenance wake) as awake-on-battery time.
        if lowerLine.contains("entering sleep") || lowerLine.contains("darkwake from") || lowerLine.contains("entering darkwake") {
            isAwake = false
        } else if lowerLine.contains("wake from") {
            isAwake = true
        }
        
        if isAwake && isOnBattery {
            if sessionStart == nil {
                sessionStart = date
            }
        } else {
            if let start = sessionStart {
                let duration = date.timeIntervalSince(start)
                if duration > 0 && duration < 86400 {
                    let splits = splitBatterySession(start: start, end: date)
                    for (day, dur) in splits {
                        dailyUsage[day, default: 0] += dur
                    }
                }
                sessionStart = nil
            }
        }
    }
    
    if let start = sessionStart {
        let duration = Date().timeIntervalSince(start)
        if duration > 0 && duration < 86400 {
            let splits = splitBatterySession(start: start, end: Date())
            for (day, dur) in splits {
                dailyUsage[day, default: 0] += dur
            }
        }
    }
    
    return dailyUsage
}

func splitBatterySession(start: Date, end: Date) -> [(Date, TimeInterval)] {
    var result: [(Date, TimeInterval)] = []
    let calendar = Calendar.current

    var currentStart = start
    while currentStart < end {
        let startOfDay = calendar.startOfDay(for: currentStart)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            break
        }

        let currentEnd = min(end, nextDay)
        let duration = currentEnd.timeIntervalSince(currentStart)
        result.append((startOfDay, duration))

        currentStart = nextDay
    }
    return result
}

// MARK: - Session backfill (unplug→replug windows + charge drop from pmset)

/// Reconstructs discrete on-battery sessions from the pmset log: each unplug
/// (`Using Batt`) to the following replug (`Using AC`), with the battery charge
/// read off the log at both ends. No per-app data — that history doesn't exist
/// in the log — so these come back with empty `apps` and `source == .backfill`.
func parseBatterySessions(_ log: String) -> [BatterySession] {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")

    let stampRegex = try? NSRegularExpression(
        pattern: #"^\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4})"#)
    // "Charge: 84", "Charge:84%", case-insensitive.
    let chargeRegex = try? NSRegularExpression(pattern: #"(?i)charge:?\s*(\d{1,3})"#)

    // A session longer than this is almost certainly a missed `Using AC` line,
    // not a real unplug — drop it rather than chart a bogus span. 48h covers a
    // lid-closed laptop sipping power over a weekend.
    let maxSessionSeconds: TimeInterval = 48 * 3600
    let minSessionSeconds: TimeInterval = 60
    // A multi-hour stretch with zero charge change isn't a real discharge (the
    // battery was likely off/hibernated, or the replug line was lost) — skip it.
    let flatChargeGraceSeconds: TimeInterval = 2 * 3600

    var sessionStart: Date?
    var sessionStartCharge: Int?
    var lastCharge: Int?
    var lastBatteryDate: Date?
    var lastBatteryCharge: Int?
    var sessions: [BatterySession] = []

    func close(at end: Date, endCharge: Int?) {
        guard let start = sessionStart else { return }
        defer { sessionStart = nil; sessionStartCharge = nil }
        let duration = end.timeIntervalSince(start)
        guard duration >= minSessionSeconds, duration <= maxSessionSeconds else { return }
        let startC = sessionStartCharge ?? lastCharge ?? 0
        let endC = endCharge ?? startC
        // Drop implausible flat-charge spans (battery off/hibernated or a lost
        // replug line) — a real unplug of this length always drains something.
        if startC - endC <= 0 && duration > flatChargeGraceSeconds { return }
        // Drop mostly-asleep windows: an in-use discharge loses well over
        // 1%/h, while a lid-closed day sips a couple of %. A 31h window that
        // drained 2% was sleep, not a session worth charting.
        let hours = duration / 3600
        if hours > 3, Double(startC - endC) / hours < 1 { return }
        sessions.append(
            BatterySession(
                startedAt: start, endedAt: end,
                startCharge: startC, endCharge: endC, source: .backfill))
    }

    for line in log.components(separatedBy: .newlines) {
        guard let regex = stampRegex,
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let stampRange = Range(match.range(at: 1), in: line),
            let date = dateFormatter.date(from: String(line[stampRange]))
        else { continue }

        if let cRegex = chargeRegex,
            let cMatch = cRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let cRange = Range(cMatch.range(at: 1), in: line),
            let value = Int(line[cRange])
        {
            lastCharge = min(max(value, 0), 100)
        }

        let lower = line.lowercased()
        if lower.contains("using batt") {
            if sessionStart == nil {
                sessionStart = date
                sessionStartCharge = lastCharge
            }
            lastBatteryDate = date
            lastBatteryCharge = lastCharge
        } else if lower.contains("using ac") {
            close(at: date, endCharge: lastCharge)
        }
    }

    // Log ends mid-battery (currently unplugged): close at the last battery
    // sample. A live session, if any, will supersede this on merge.
    if sessionStart != nil {
        close(at: lastBatteryDate ?? Date(), endCharge: lastBatteryCharge)
    }
    return sessions
}

/// Background read of `pmset -g log`, parsed into backfilled sessions.
public func backfillBatterySessionsFromSystemLog() async -> [BatterySession] {
    await Task.detached(priority: .background) { () -> [BatterySession] in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = try pipe.fileHandleForReading.readToEnd()
            process.waitUntilExit()
            if let data, let logContent = String(data: data, encoding: .utf8) {
                return parseBatterySessions(logContent)
            }
        } catch {
            log.error("pmset session backfill failed: \(error, privacy: .public)")
        }
        return []
    }.value
}
