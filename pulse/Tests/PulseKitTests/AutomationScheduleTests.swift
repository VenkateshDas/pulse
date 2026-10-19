import Foundation
import Testing
@testable import PulseKit

struct AutomationScheduleTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test func weekdaysSkipWeekendAndExactPreviousDeadline() {
        let schedule = PulseAutomationSchedule(repeatRule: .weekdays, hour: 9, timezoneID: "UTC")
        let friday = date("2026-10-16T09:00:00Z")
        #expect(schedule.next(after: friday) == date("2026-10-19T09:00:00Z"))
        #expect(schedule.next(after: date("2026-10-18T10:00:00Z")) == date("2026-10-19T09:00:00Z"))
    }

    @Test func springGapUsesNextValidTimeAndFallRepeatFiresOnce() {
        let spring = PulseAutomationSchedule(hour: 2, minute: 30, timezoneID: "America/Los_Angeles")
        #expect(spring.next(after: date("2026-03-08T08:00:00Z")) == date("2026-03-08T10:00:00Z"))
        let fall = PulseAutomationSchedule(hour: 1, minute: 30, timezoneID: "America/Los_Angeles")
        let first = date("2026-11-01T08:30:00Z")
        #expect(fall.next(after: date("2026-11-01T07:00:00Z")) == first)
        #expect(fall.next(after: first) == date("2026-11-02T09:30:00Z"))
    }

    @Test func weeklyUsesPinnedTimezone() {
        let schedule = PulseAutomationSchedule(repeatRule: .weekly, hour: 9, weekday: 2, timezoneID: "Asia/Kolkata")
        let next = date("2026-10-19T03:30:00Z")
        #expect(schedule.next(after: date("2026-10-18T23:00:00Z")) == next)
        #expect(schedule.next(after: next) == date("2026-10-26T03:30:00Z"))
    }

    @Test func onceRequiresFutureDateAndAllFieldsValid() {
        let now = date("2026-10-18T00:00:00Z")
        var schedule = PulseAutomationSchedule(repeatRule: .once, timezoneID: "UTC")
        #expect(schedule.next(after: now) == nil)
        schedule.onceAt = now
        #expect(schedule.next(after: now) == nil)
        schedule.onceAt = now.addingTimeInterval(60)
        #expect(schedule.next(after: now) == schedule.onceAt)
        schedule.hour = 24
        #expect(schedule.next(after: now) == nil)
        schedule.hour = 9; schedule.minute = -1
        #expect(schedule.next(after: now) == nil)
        schedule.minute = 0; schedule.weekday = 0
        #expect(schedule.next(after: now) == nil)
        schedule.weekday = 2; schedule.timezoneID = "invalid/timezone"
        #expect(schedule.next(after: now) == nil)
    }

    @Test func automationRoundTripPreservesDeadlineAndIdentity() throws {
        let now = date("2026-10-18T00:00:00Z")
        let schedule = PulseAutomationSchedule(hour: 9, timezoneID: "UTC")
        let automation = PulseAutomation(title: "Morning check", instructions: "Inspect Mac health", schedule: schedule, now: now)
        let restored = try JSONDecoder().decode(PulseAutomation.self, from: JSONEncoder().encode(automation))
        #expect(restored == automation)
        #expect(UUID(uuidString: restored.id) != nil)
        #expect(restored.nextRun == date("2026-10-18T09:00:00Z"))
        #expect(restored.lastRun == nil && restored.runCount == 0 && restored.enabled)
    }
}
