import Testing
import PulseKit
@testable import Pulse

@Suite("Monitor grouped quit target")
@MainActor
struct MonitorGroupingTests {
    @Test func busyRendererStillSelectsMainApplication() {
        let members = [
            ProcessExtendedSample(pid: 20, name: "Brave Helper (Renderer)", cpuPercent: 30,
                residentBytes: 300, virtualBytes: 300, threadCount: 3, pageFaultRate: 2, appName: "Brave Browser"),
            ProcessExtendedSample(pid: 10, name: "Brave Browser", cpuPercent: 1,
                residentBytes: 100, virtualBytes: 100, threadCount: 1, pageFaultRate: 1, appName: "Brave Browser")
        ]
        for key in [MonitorEngine.SortKey.cpu, .memory] {
            let group = MonitorModel.appRows(members, sortKey: key, ascending: false, regularAppPIDs: [10]).first
            #expect(group?.pid == 10)
            #expect(group?.cpuPercent == 31)
            #expect(group?.residentBytes == 400)
            #expect(group?.name == "Brave Browser (2)")
            let fallback = MonitorModel.appRows(members, sortKey: key, ascending: false, regularAppPIDs: []).first
            #expect(fallback?.pid == 20)
        }
    }
}
