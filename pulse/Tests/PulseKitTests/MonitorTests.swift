import Darwin
import Foundation
import Testing

@testable import PulseKit

@Suite("MonitorEngine")
struct MonitorEngineTests {
    @Test func sampleIncludesOwnProcessWithSaneFields() async {
        let engine = MonitorEngine()
        let rows = await engine.sample(sortKey: .pid, ascending: true)
        let own = rows.first { $0.pid == getpid() }
        #expect(own != nil)
        #expect(own!.threadCount >= 1)
        #expect(own!.residentBytes > 0)
        #expect(own!.virtualBytes >= own!.residentBytes)
        // First sample has no delta baseline — rates must read zero, not garbage.
        #expect(own!.cpuPercent == 0)
        #expect(own!.pageFaultRate == 0)
    }

    @Test func sortKeysProduceExpectedOrder() async {
        let engine = MonitorEngine()
        let byPID = await engine.sample(sortKey: .pid, ascending: true)
        #expect(byPID.map(\.pid) == byPID.map(\.pid).sorted())

        let byMemory = await engine.sample(sortKey: .memory, ascending: false)
        let memories = byMemory.map(\.residentBytes)
        #expect(memories == memories.sorted(by: >))

        let byName = await engine.sample(sortKey: .name, ascending: true)
        let names = byName.map { $0.name.lowercased() }
        #expect(names.count > 1)
        #expect(names.first! <= names.last!)

        let descending = await engine.sample(sortKey: .pid, ascending: false)
        #expect(descending.first?.pid == byPID.last?.pid)
    }

    @Test func treeContainsEveryPIDExactlyOnce() async {
        let engine = MonitorEngine()
        let rows = await engine.sample(sortKey: .pid, ascending: true)
        let roots = await engine.tree()

        var seen: Set<Int32> = []
        func walk(_ node: ProcessNode) {
            #expect(!seen.contains(node.id))
            seen.insert(node.id)
            for child in node.children { walk(child) }
        }
        for root in roots { walk(root) }

        #expect(seen.count == rows.count)
        #expect(seen.contains(getpid()))
    }

    @Test func parentsLinkOwnProcessToItsParent() async {
        let engine = MonitorEngine()
        _ = await engine.sample(sortKey: .cpu, ascending: false)
        let parents = await engine.parents()
        #expect(parents[getpid()] == getppid())
    }

    @Test func namesCoverParentsOutsideTheRowSet() async {
        let engine = MonitorEngine()
        let names = await engine.names()
        // launchd's task info is unreadable without root, but its name
        // must still resolve — it is almost every process's parent.
        #expect(names[1] == "launchd")
        #expect(names[getpid()] != nil)
    }

    @Test func networkDeltasStartAtZeroAndStayFinite() async {
        let engine = MonitorEngine()
        let first = await engine.networkDeltas()
        // No previous reading — every rate must be zero.
        for sample in first {
            #expect(sample.bytesIn == 0)
            #expect(sample.bytesOut == 0)
            #expect(sample.interfaceName.hasPrefix("en"))
        }
        try? await Task.sleep(for: .milliseconds(50))
        let second = await engine.networkDeltas()
        #expect(second.map(\.interfaceName) == first.map(\.interfaceName))
        // Rates over 50ms can't plausibly exceed 100 GB/s — guards
        // against unit mistakes (cumulative bytes leaking through).
        for sample in second {
            #expect(sample.bytesIn < 100_000_000_000)
            #expect(sample.bytesOut < 100_000_000_000)
        }
    }

    @Test func collectionIsSharedWithinHalfASecond() async {
        let engine = MonitorEngine()
        let first = await engine.sample(sortKey: .pid, ascending: true)
        let again = await engine.sample(sortKey: .pid, ascending: true)
        // Same cached collection → identical rows, not merely similar.
        #expect(first == again)
    }
}

@Suite("ProcessSampler")
struct ProcessSamplerTests {
    // proc_listallpids returns bytes written, not a pid count. Regression
    // guard: the sampler must convert correctly and never overrun its own
    // fixed pid buffer when slicing the result.
    @Test func sampleIncludesOwnProcessAndRespectsLimit() {
        let sampler = ProcessSampler()
        let rows = sampler.sample(limit: 20)
        #expect(rows.count <= 20)
        #expect(rows.contains { $0.pid == getpid() })
        #expect(rows.allSatisfy { $0.pid > 0 })
    }

    @Test func secondSampleComputesNonNegativeCPUPercent() {
        let sampler = ProcessSampler()
        _ = sampler.sample(limit: 200)
        let second = sampler.sample(limit: 200)
        #expect(second.allSatisfy { $0.cpuPercent >= 0 })
    }
}
