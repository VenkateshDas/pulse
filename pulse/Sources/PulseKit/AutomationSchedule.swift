import Foundation

/// Calendar-based deadlines pinned to the timezone chosen when the schedule is saved.
public struct PulseAutomationSchedule: Codable, Sendable, Equatable {
    public enum RepeatRule: String, Codable, Sendable, CaseIterable {
        case once, daily, weekdays, weekly
    }

    public var repeatRule: RepeatRule
    public var hour: Int
    public var minute: Int
    public var weekday: Int
    public var timezoneID: String
    public var onceAt: Date?

    public init(repeatRule: RepeatRule = .daily, hour: Int = 9, minute: Int = 0,
                weekday: Int = 2, timezoneID: String = TimeZone.current.identifier, onceAt: Date? = nil) {
        self.repeatRule = repeatRule; self.hour = hour; self.minute = minute
        self.weekday = weekday; self.timezoneID = timezoneID; self.onceAt = onceAt
    }

    /// Strictly later than `after`; DST gaps advance to the next valid time,
    /// and a repeated wall-clock time fires only on its first occurrence.
    public func next(after: Date) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute), (1...7).contains(weekday),
              after.timeIntervalSinceReferenceDate.isFinite,
              let timezone = TimeZone(identifier: timezoneID) else { return nil }
        if repeatRule == .once {
            guard let onceAt, onceAt.timeIntervalSinceReferenceDate.isFinite, onceAt > after else { return nil }
            return onceAt
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let weekdays: [Int?] = switch repeatRule {
        case .weekdays: (2...6).map { Optional($0) }
        case .weekly: [weekday]
        default: [nil]
        }
        return weekdays.compactMap { day in
            var components = DateComponents()
            components.hour = hour; components.minute = minute; components.second = 0
            components.weekday = day
            return calendar.nextDate(after: after, matching: components,
                                     matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }.min()
    }
}

/// Native app-owned automation metadata; execution history lives separately.
public struct PulseAutomation: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var instructions: String
    public var schedule: PulseAutomationSchedule
    public var enabled: Bool
    public var notifyOnCompletion: Bool
    public var createdAt: Date
    public var nextRun: Date?
    public var lastRun: Date?
    public var lastStatus: String?
    public var runCount: Int

    public init(title: String, instructions: String, schedule: PulseAutomationSchedule, now: Date = .now) {
        id = UUID().uuidString; self.title = title; self.instructions = instructions; self.schedule = schedule
        enabled = true; notifyOnCompletion = true; createdAt = now; nextRun = schedule.next(after: now)
        lastRun = nil; lastStatus = nil; runCount = 0
    }
}
