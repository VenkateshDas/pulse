import Foundation
import Testing

@testable import PulseKit

private func makeTempStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-snooze-tests-\(UUID().uuidString).json")
}

@Suite("SnoozeStore")
struct SnoozeStoreTests {
    @Test func snoozeThenIsSnoozedRoundTrips() async {
        let store = SnoozeStore(storeURL: makeTempStoreURL())
        #expect(await store.isSnoozed("cpu-hog") == false)

        await store.snooze("cpu-hog", until: Date.now.addingTimeInterval(3600))
        #expect(await store.isSnoozed("cpu-hog") == true)
    }

    @Test func expiredSnoozeIsNotConsideredSnoozed() async {
        let store = SnoozeStore(storeURL: makeTempStoreURL())
        let now = Date.now
        await store.snooze("low-disk", until: now.addingTimeInterval(60))

        #expect(await store.isSnoozed("low-disk", now: now.addingTimeInterval(120)) == false)
    }

    @Test func expiredEntriesArePrunedOnLoad() async {
        let url = makeTempStoreURL()
        let now = Date.now
        let firstLoad = SnoozeStore(storeURL: url, now: now)
        await firstLoad.snooze("memory-pressure", until: now.addingTimeInterval(30))
        await firstLoad.snooze("thermal", until: now.addingTimeInterval(3600))

        // Reload after the first entry's snooze window has passed — mirrors
        // AnomalyStore's maxAge pruning applied at init time.
        let reloaded = SnoozeStore(storeURL: url, now: now.addingTimeInterval(90))
        #expect(await reloaded.isSnoozed("memory-pressure", now: now.addingTimeInterval(90)) == false)
        #expect(await reloaded.isSnoozed("thermal", now: now.addingTimeInterval(90)) == true)
    }

    @Test func persistsAcrossStoreReload() async {
        let url = makeTempStoreURL()
        let store = SnoozeStore(storeURL: url)
        await store.snooze("sleep-blockers", until: Date.now.addingTimeInterval(3600))

        let reloaded = SnoozeStore(storeURL: url)
        #expect(await reloaded.isSnoozed("sleep-blockers") == true)
    }
}
