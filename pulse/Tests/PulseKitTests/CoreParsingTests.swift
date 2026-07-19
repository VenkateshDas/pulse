import Foundation
import Testing

@testable import PulseKit

@Suite("CString")
struct CStringTests {
    @Test func decodesAsciiUpToNull() {
        // "hi" then a null and trailing garbage that must be ignored.
        let buf: [CChar] = [104, 105, 0, 122, 122]
        #expect(String(nullTerminated: buf) == "hi")
    }

    @Test func emptyBufferIsEmptyString() {
        #expect(String(nullTerminated: []) == "")
    }

    @Test func leadingNullIsEmptyString() {
        #expect(String(nullTerminated: [0, 104, 105]) == "")
    }

    @Test func bufferWithoutTrailingNullUsesAllBytes() {
        let buf: [CChar] = [104, 105]  // no terminator
        #expect(String(nullTerminated: buf) == "hi")
    }

    @Test func decodesMultiByteUTF8() {
        // "é" = U+00E9 → UTF-8 0xC3 0xA9. As CChar (Int8): bitPattern of 195, 169.
        let buf: [CChar] = [CChar(bitPattern: 0xC3), CChar(bitPattern: 0xA9), 0]
        #expect(String(nullTerminated: buf) == "é")
    }
}

@Suite("splitBatterySession")
struct SplitBatterySessionTests {
    private let cal = Calendar.current
    /// A fixed local midnight to anchor day-boundary math in the test's own
    /// timezone (matches the production code's `Calendar.current`).
    private var midnight: Date {
        cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func singleDaySessionIsOneSlice() {
        let start = midnight.addingTimeInterval(9 * 3600)   // 09:00
        let end = start.addingTimeInterval(3600)            // 10:00
        let slices = splitBatterySession(start: start, end: end)
        #expect(slices.count == 1)
        #expect(slices[0].0 == midnight)
        #expect(slices[0].1 == 3600)
    }

    @Test func midnightSpanningSessionSplitsAtDayBoundary() {
        let start = midnight.addingTimeInterval(23 * 3600)  // 23:00 day 0
        let end = midnight.addingTimeInterval(25 * 3600)    // 01:00 day 1
        let slices = splitBatterySession(start: start, end: end)
        #expect(slices.count == 2)
        // 1h before midnight, 1h after — total preserved.
        #expect(slices.reduce(0) { $0 + $1.1 } == 7200)
        #expect(slices[0].0 == midnight)
        #expect(slices[1].0 == cal.date(byAdding: .day, value: 1, to: midnight))
        #expect(slices[0].1 == 3600)
        #expect(slices[1].1 == 3600)
    }

    @Test func multiDaySpanPreservesTotalDuration() {
        let start = midnight.addingTimeInterval(12 * 3600)
        let end = midnight.addingTimeInterval((48 + 12) * 3600)  // +2.5 days
        let slices = splitBatterySession(start: start, end: end)
        #expect(slices.count == 3)
        #expect(slices.reduce(0) { $0 + $1.1 } == end.timeIntervalSince(start))
    }
}

@Suite("parseLogContent")
struct ParseLogContentTests {
    /// Total seconds across every day bucket — timezone-robust (a +0000 stamp
    /// may land on either side of local midnight, so we never assert on keys).
    private func total(_ usage: [Date: TimeInterval]) -> TimeInterval {
        usage.values.reduce(0, +)
    }

    @Test func countsAwakeOnBatteryStretch() {
        // Wake → on battery from 10:00 to 12:00 → sleep. Two hours credited.
        let log = """
        2026-06-20 10:00:00 +0000 Wake from Normal Sleep
        2026-06-20 10:00:00 +0000 Using Batt (Charge:80%)
        2026-06-20 12:00:00 +0000 Entering Sleep
        """
        #expect(total(parseLogContent(log)) == 7200)
    }

    @Test func acTimeIsNotCounted() {
        // Awake the whole time but on AC → nothing credited.
        let log = """
        2026-06-20 10:00:00 +0000 Wake from Normal Sleep
        2026-06-20 10:00:00 +0000 Using AC (Charge:100%)
        2026-06-20 12:00:00 +0000 Entering Sleep
        """
        #expect(total(parseLogContent(log)) == 0)
    }

    @Test func switchingToACClosesTheBatterySession() {
        // On battery 10:00–11:00, then plugged in. Only the first hour counts.
        let log = """
        2026-06-20 10:00:00 +0000 Wake from Normal Sleep
        2026-06-20 10:00:00 +0000 Using Batt
        2026-06-20 11:00:00 +0000 Using AC
        2026-06-20 12:00:00 +0000 Entering Sleep
        """
        #expect(total(parseLogContent(log)) == 3600)
    }

    @Test func darkwakeEndsTheAwakeSession() {
        let log = """
        2026-06-20 10:00:00 +0000 Wake from Normal Sleep
        2026-06-20 10:00:00 +0000 Using Batt
        2026-06-20 10:30:00 +0000 DarkWake from Standby
        """
        #expect(total(parseLogContent(log)) == 1800)
    }

    @Test func linesWithoutTimestampsAreIgnored() {
        let log = """
        garbage header with no timestamp
        2026-06-20 10:00:00 +0000 Wake from Normal Sleep
        another junk line
        2026-06-20 10:00:00 +0000 Using Batt
        2026-06-20 11:00:00 +0000 Entering Sleep
        """
        #expect(total(parseLogContent(log)) == 3600)
    }

    @Test func emptyLogYieldsNothing() {
        #expect(parseLogContent("").isEmpty)
    }

    @Test func implausiblyLongSessionIsDropped() {
        // > 24h between boundaries → filtered out as noise.
        let log = """
        2026-06-20 10:00:00 +0000 Wake from Normal Sleep
        2026-06-20 10:00:00 +0000 Using Batt
        2026-06-22 11:00:00 +0000 Entering Sleep
        """
        #expect(total(parseLogContent(log)) == 0)
    }
}

@Suite("parseBatterySessions")
struct ParseBatterySessionsTests {
    @Test func reconstructsUnplugWindowWithChargeDrop() {
        let log = """
        2026-06-20 10:00:00 +0000 Assertions Using Batt (Charge:90%)
        2026-06-20 11:30:00 +0000 DarkWake from Idle Using BATT (Charge:85%)
        2026-06-20 12:00:00 +0000 Assertions Using AC (Charge:74%)
        """
        let sessions = parseBatterySessions(log)
        #expect(sessions.count == 1)
        let s = sessions[0]
        #expect(s.startCharge == 90)
        #expect(s.endCharge == 74)
        #expect(s.chargeDrop == 16)
        #expect(s.duration() == 7200)          // 10:00 → 12:00
        #expect(s.isLive == false)
        #expect(s.isBackfilled)
        #expect(s.apps.isEmpty)
    }

    @Test func acOnlyYieldsNoSession() {
        let log = """
        2026-06-20 10:00:00 +0000 Using AC (Charge:100%)
        2026-06-20 12:00:00 +0000 Using AC (Charge:100%)
        """
        #expect(parseBatterySessions(log).isEmpty)
    }

    @Test func handlesSpaceChargeFormat() {
        // "Charge: 84" (space, no percent) as seen in Assertions summaries.
        let log = """
        2026-06-20 10:00:00 +0000 Using Batt(Charge: 84)
        2026-06-20 11:00:00 +0000 Using AC(Charge: 77)
        """
        let s = parseBatterySessions(log)[0]
        #expect(s.startCharge == 84)
        #expect(s.endCharge == 77)
    }

    @Test func separatesMultipleUnplugs() {
        let log = """
        2026-06-20 08:00:00 +0000 Using Batt (Charge:95%)
        2026-06-20 09:00:00 +0000 Using AC (Charge:90%)
        2026-06-20 14:00:00 +0000 Using Batt (Charge:100%)
        2026-06-20 15:00:00 +0000 Using AC (Charge:88%)
        """
        let sessions = parseBatterySessions(log)
        let discharges = sessions.filter { !$0.isCharge }
        #expect(discharges.count == 2)
        #expect(discharges[0].chargeDrop == 5)
        #expect(discharges[1].chargeDrop == 12)
        // The 09:00→14:00 AC stretch (90→100) is a charge session.
        let charges = sessions.filter(\.isCharge)
        #expect(charges.count == 1)
        #expect(charges[0].chargeGain == 10)
    }

    @Test func reconstructsChargeSession() {
        let log = """
        2026-06-20 09:00:00 +0000 Using AC (Charge:42%)
        2026-06-20 10:00:00 +0000 Using AC (Charge:88%)
        2026-06-20 10:30:00 +0000 Using Batt (Charge:100%)
        """
        let charges = parseBatterySessions(log).filter(\.isCharge)
        #expect(charges.count == 1)
        let s = charges[0]
        #expect(s.startCharge == 42)
        #expect(s.endCharge == 100)
        #expect(s.chargeGain == 58)
        #expect(s.duration() == 5400)          // 09:00 → 10:30
        #expect(s.isBackfilled)
    }

    @Test func chargeSessionClosesAtLogEndOnAC() {
        // Still plugged in at log's end → closed at the last AC line.
        let log = """
        2026-06-20 09:00:00 +0000 Using AC (Charge:42%)
        2026-06-20 10:00:00 +0000 Using AC (Charge:88%)
        """
        let charges = parseBatterySessions(log).filter(\.isCharge)
        #expect(charges.count == 1)
        #expect(charges[0].chargeGain == 46)
        #expect(charges[0].duration() == 3600)
    }

    @Test func flatACStretchYieldsNoChargeSession() {
        // Plugged in at 100% for hours: gain < 2 → not a charge session.
        let log = """
        2026-06-20 09:00:00 +0000 Using AC (Charge:100%)
        2026-06-20 15:00:00 +0000 Using Batt (Charge:100%)
        """
        #expect(parseBatterySessions(log).filter(\.isCharge).isEmpty)
    }

    @Test func closesTrailingOpenSessionAtLastBatterySample() {
        // Still unplugged at log's end → closed at the last battery line.
        let log = """
        2026-06-20 10:00:00 +0000 Using Batt (Charge:90%)
        2026-06-20 10:30:00 +0000 Using Batt (Charge:80%)
        """
        let s = parseBatterySessions(log)[0]
        #expect(s.duration() == 1800)
        #expect(s.startCharge == 90)
        #expect(s.endCharge == 80)
    }

    @Test func dropsBlinkUnplug() {
        // < 60s on battery → noise, discarded.
        let log = """
        2026-06-20 10:00:00 +0000 Using Batt (Charge:90%)
        2026-06-20 10:00:30 +0000 Using AC (Charge:90%)
        """
        #expect(parseBatterySessions(log).isEmpty)
    }

    @Test func emptyLogYieldsNoSessions() {
        #expect(parseBatterySessions("").isEmpty)
    }

    @Test func dropsLongFlatChargeSession() {
        // 1% → 1% across 3h → battery off/hibernated or lost replug line, not
        // a real discharge. Must be discarded.
        let log = """
        2026-06-16 00:30:00 +0000 Using Batt (Charge:1%)
        2026-06-16 03:30:00 +0000 Using Batt (Charge:1%)
        """
        #expect(parseBatterySessions(log).isEmpty)
    }

    @Test func keepsShortFlatChargeSession() {
        // A brief unplug with no measurable drop (< grace window) is plausible.
        let log = """
        2026-06-16 10:00:00 +0000 Using Batt (Charge:90%)
        2026-06-16 10:05:00 +0000 Using AC (Charge:90%)
        """
        #expect(parseBatterySessions(log).count == 1)
    }

    @Test func dropsSessionLongerThanCap() {
        // > 48h between unplug and replug → missed AC line, discard.
        let log = """
        2026-06-16 10:00:00 +0000 Using Batt (Charge:90%)
        2026-06-19 10:00:00 +0000 Using AC (Charge:40%)
        """
        #expect(parseBatterySessions(log).isEmpty)
    }

    @Test func dropsMostlyAsleepLowDrainWindow() {
        // 32h unplugged draining 2% (0.06%/h) — a lid-closed sleep, not a
        // session worth charting.
        let log = """
        2026-06-16 10:00:00 +0000 Using Batt (Charge:100%)
        2026-06-17 18:00:00 +0000 Using AC (Charge:98%)
        """
        #expect(parseBatterySessions(log).isEmpty)
    }

    @Test func keepsRealMultiHourDischarge() {
        // 5h at ~8%/h is genuine in-use drain.
        let log = """
        2026-06-16 10:00:00 +0000 Using Batt (Charge:90%)
        2026-06-16 15:00:00 +0000 Using AC (Charge:50%)
        """
        #expect(parseBatterySessions(log).count == 1)
    }
}

@Suite("BatterySession backfill merge")
struct BatterySessionMergeTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func backfilledSessionsAppearInAllSessions() {
        let store = BatterySessionStore(fileURL: nil, now: t0)
        let bf = BatterySession(
            startedAt: t0, endedAt: t0.addingTimeInterval(3600),
            startCharge: 90, endCharge: 80, source: .backfill)
        store.mergeBackfilled([bf], now: t0.addingTimeInterval(7200))
        #expect(store.allSessions.count == 1)
        #expect(store.sessions.isEmpty)  // not persisted
    }

    @Test func liveSessionSupersedesOverlappingBackfill() {
        let store = BatterySessionStore(fileURL: nil, now: t0)
        // Live session 10:00–11:00.
        store.beginSession(charge: 100, at: t0)
        store.endSession(charge: 90, at: t0.addingTimeInterval(3600))
        // Backfill overlapping the same window must be dropped.
        let overlapping = BatterySession(
            startedAt: t0.addingTimeInterval(600), endedAt: t0.addingTimeInterval(1800),
            startCharge: 99, endCharge: 95, source: .backfill)
        store.mergeBackfilled([overlapping], now: t0.addingTimeInterval(7200))
        #expect(store.allSessions.count == 1)
        #expect(store.allSessions[0].source != .backfill)
    }

    @Test func staleBackfillBeyondRetentionDropped() {
        let store = BatterySessionStore(fileURL: nil, now: t0)
        let old = BatterySession(
            startedAt: t0, endedAt: t0.addingTimeInterval(3600),
            startCharge: 90, endCharge: 80, source: .backfill)
        // "now" far past the 60-day window relative to the session.
        store.mergeBackfilled([old], now: t0.addingTimeInterval(BatterySessionStore.maxAge + 86400))
        #expect(store.allSessions.isEmpty)
    }
}
