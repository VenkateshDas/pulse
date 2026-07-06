import Foundation
import Testing

@testable import PulseKit

@Suite("BatterySessionStore")
struct BatterySessionStoreTests {
    /// In-memory store (no file) at a fixed clock.
    private func store(now: Date) -> BatterySessionStore {
        BatterySessionStore(fileURL: nil, now: now)
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Load-time sanitation (phantom sessions from previous runs)

    @Test func staleLiveSessionClosesAtLastObservedSample() {
        // Pulse quit while unplugged: the open session must close at its last
        // accumulate sample, never at "now" (which charted 95h phantoms).
        let lastSeen = t0.addingTimeInterval(1800)
        let stale = BatterySession(
            startedAt: t0, endedAt: nil, startCharge: 90, endCharge: 80,
            apps: [AppEnergyShare(name: "Chrome", cpuTimeSeconds: 50, firstSeen: t0, lastSeen: lastSeen)])
        let repaired = BatterySessionStore.sanitized(stale, now: t0.addingTimeInterval(95 * 3600))
        #expect(repaired?.endedAt == lastSeen)
        #expect(repaired?.isLive == false)
    }

    @Test func staleLiveSessionWithoutSamplesIsDropped() {
        let stale = BatterySession(
            startedAt: t0, endedAt: nil, startCharge: 100, endCharge: 100)
        #expect(BatterySessionStore.sanitized(stale, now: t0.addingTimeInterval(95 * 3600)) == nil)
    }

    @Test func closedPhantomWithoutAppsIsDropped() {
        // Persisted by older builds: live-source, hours long, zero app samples.
        let phantom = BatterySession(
            startedAt: t0, endedAt: t0.addingTimeInterval(95 * 3600),
            startCharge: 100, endCharge: 100)
        #expect(BatterySessionStore.sanitized(phantom) == nil)
    }

    @Test func backfilledSessionSurvivesSanitation() {
        // Backfill legitimately has no apps — the pmset log has no such data.
        let backfill = BatterySession(
            startedAt: t0, endedAt: t0.addingTimeInterval(2 * 3600),
            startCharge: 90, endCharge: 70, source: .backfill)
        #expect(BatterySessionStore.sanitized(backfill) != nil)
    }

    @Test func opensASingleLiveSession() {
        let s = store(now: t0)
        s.beginSession(charge: 90, at: t0)
        s.beginSession(charge: 80, at: t0.addingTimeInterval(10)) // ignored — already live
        #expect(s.sessions.count == 1)
        #expect(s.liveSession?.startCharge == 90)
        #expect(s.liveSession?.isLive == true)
    }

    @Test func tracksChargeDropAndDuration() {
        let s = store(now: t0)
        s.beginSession(charge: 92, at: t0)
        s.accumulate(processes: [("Chrome", 50)], elapsed: 2, charge: 88, at: t0.addingTimeInterval(60))
        let end = t0.addingTimeInterval(3600)
        s.endSession(charge: 74, at: end)

        let session = s.sessions.last!
        #expect(session.startCharge == 92)
        #expect(session.endCharge == 74)
        #expect(session.chargeDrop == 18)
        #expect(session.isLive == false)
        #expect(session.duration(now: end) == 3600)
    }

    @Test func chargeDropClampsNonNegative() {
        let s = store(now: t0)
        s.beginSession(charge: 50, at: t0)
        s.endSession(charge: 52, at: t0.addingTimeInterval(3600)) // noise: ticked up
        #expect(s.sessions.last!.chargeDrop == 0)
    }

    @Test func discardsTooShortSessions() {
        let s = store(now: t0)
        s.beginSession(charge: 90, at: t0)
        s.endSession(charge: 89, at: t0.addingTimeInterval(30)) // < 90s
        #expect(s.sessions.isEmpty)
    }

    @Test func accumulatesPerAppCPUTimeWeights() {
        let s = store(now: t0)
        s.beginSession(charge: 100, at: t0)
        // Chrome twice (10+30 weight units), Xcode once (10).
        s.accumulate(processes: [("Chrome", 5), ("Xcode", 5)], elapsed: 2, charge: 98, at: t0.addingTimeInterval(2))
        s.accumulate(processes: [("Chrome", 15)], elapsed: 2, charge: 96, at: t0.addingTimeInterval(4))
        s.endSession(charge: 90, at: t0.addingTimeInterval(3600))

        let shares = s.sessions.last!.shares
        #expect(shares.count == 2)
        #expect(shares.first?.app.name == "Chrome")
        // Chrome 5*2 + 15*2 = 40; Xcode 5*2 = 10; total 50 → 0.8 / 0.2.
        #expect(abs((shares.first?.fraction ?? 0) - 0.8) < 0.001)
    }

    @Test func ignoresAccumulateWhenNoLiveSession() {
        let s = store(now: t0)
        s.accumulate(processes: [("Chrome", 50)], elapsed: 2, charge: 90, at: t0)
        #expect(s.sessions.isEmpty)
    }

    @Test func capsAppsToTopNPlusOther() {
        // 10 apps, descending weight; expect top-8 + one "Other".
        let many = (1...10).map {
            AppEnergyShare(name: "App\($0)", cpuTimeSeconds: Double(20 - $0),
                           firstSeen: t0, lastSeen: t0)
        }
        let capped = BatterySessionStore.capApps(many)
        #expect(capped.count == BatterySessionStore.topAppsPerSession + 1)
        #expect(capped.last?.name == "Other")
        // Other folds App9 (11) + App10 (10) = 21.
        #expect(capped.last?.cpuTimeSeconds == 21)
    }

    @Test func sharesAreCappedEvenWhileLive() {
        let s = store(now: t0)
        s.beginSession(charge: 100, at: t0)
        // More distinct apps than the cap; the live session's raw list is
        // uncapped, but `shares` must still fold the tail into "Other".
        let procs = (1...20).map { (name: "App\($0)", cpuPercent: Double(21 - $0)) }
        s.accumulate(processes: procs, elapsed: 2, charge: 99, at: t0.addingTimeInterval(2))

        let shares = s.liveSession!.shares
        #expect(shares.count == BatterySessionStore.topAppsPerSession + 1)
        #expect(shares.contains { $0.app.name == "Other" })
        #expect(abs(shares.reduce(0) { $0 + $1.fraction } - 1) < 0.001)
    }

    @Test func sleepGapAccumulatesAsScreenOffTime() {
        let s = store(now: t0)
        s.beginSession(charge: 80, at: t0)
        s.accumulate(processes: [("Chrome", 5)], elapsed: 2, charge: 79,
                     at: t0.addingTimeInterval(2))
        // Lid-closed gap: no processes, display asleep, wall-clock elapsed.
        s.accumulate(processes: [], elapsed: 3600, charge: 70,
                     at: t0.addingTimeInterval(3602), displayAsleep: true)

        let live = s.liveSession!
        #expect(live.screenOnSeconds == 2)
        #expect(live.screenOffSeconds == 3600)
        #expect(live.endCharge == 70)
    }

    @Test func capAppsIsIdempotent() {
        // A closed session's apps are already top-N + "Other"; re-capping (the
        // `shares` getter does) must merge into that bucket, never append a
        // second "Other" — duplicate names broke ForEach identity in the UI.
        let many = (1...12).map {
            AppEnergyShare(name: "App\($0)", cpuTimeSeconds: Double(20 - $0),
                           firstSeen: t0, lastSeen: t0)
        }
        let once = BatterySessionStore.capApps(many)
        let twice = BatterySessionStore.capApps(once)
        #expect(twice.filter { $0.name == "Other" }.count == 1)
        #expect(twice.count <= BatterySessionStore.topAppsPerSession + 1)
        // Total weight is conserved through both passes.
        let total = many.reduce(0) { $0 + $1.cpuTimeSeconds }
        #expect(twice.reduce(0) { $0 + $1.cpuTimeSeconds } == total)
    }

    @Test func capAppsLeavesSmallListsUntouched() {
        let few = (1...3).map {
            AppEnergyShare(name: "App\($0)", cpuTimeSeconds: Double($0), firstSeen: t0, lastSeen: t0)
        }
        #expect(BatterySessionStore.capApps(few).count == 3)
        #expect(!BatterySessionStore.capApps(few).contains { $0.name == "Other" })
    }

    @Test func pruningCapsSessionCount() {
        let s = store(now: t0)
        // Open + close more than the cap; each must clear minDuration.
        for i in 0..<(BatterySessionStore.maxSessions + 5) {
            let start = t0.addingTimeInterval(Double(i) * 7200)
            s.beginSession(charge: 100, at: start)
            s.endSession(charge: 99, at: start.addingTimeInterval(3600))
        }
        #expect(s.sessions.count == BatterySessionStore.maxSessions)
    }
}
