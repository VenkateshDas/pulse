import Foundation

/// Persists one battery-capacity reading per day so the Health page can
/// chart the 60-day degradation trend across launches. JSON file in
/// Application Support, same pattern as DiskHistoryStore.
public final class BatteryHistoryStore {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public let date: Date
        public var timeOnBattery: TimeInterval
        public var id: Date { date }

        public init(date: Date, timeOnBattery: TimeInterval) {
            self.date = Calendar.current.startOfDay(for: date)
            self.timeOnBattery = timeOnBattery
        }
    }

    public static let maxAge: TimeInterval = 60 * 24 * 3600

    public private(set) var entries: [Entry]
    private let fileURL: URL?

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
    public func addTimeOnBattery(_ duration: TimeInterval, at date: Date = .now) {
        guard duration > 0 else { return }
        updateEntry(for: date, duration: duration, maxAgeDate: date) { current, new in
            current += new
        }
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
        } catch {}
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
    
    for line in lines {
        guard line.count >= 25 else { continue }
        let dateStr = String(line.prefix(25))
        guard let date = dateFormatter.date(from: dateStr) else { continue }
        
        let lowerLine = line.lowercased()
        
        if lowerLine.contains("using ac") {
            isOnBattery = false
        } else if lowerLine.contains("using batt") {
            isOnBattery = true
        }
        
        if lowerLine.contains("wake from") {
            isAwake = true
        } else if lowerLine.contains("entering sleep") || lowerLine.contains("darkwake from") || lowerLine.contains("entering darkwake") {
            isAwake = false
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
