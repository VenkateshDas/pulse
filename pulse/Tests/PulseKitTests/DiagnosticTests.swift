import CPulse
import Darwin
import Foundation
import Testing
@testable import PulseKit

@Suite(.serialized) struct DiagnosticTests {
    @Test func enumerationMatchesNativePIDCount() {
        var buffer = [pid_t](repeating: 0, count: 8192)
        let count = buffer.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        let expected = buffer.prefix(min(Int(count), buffer.count)).filter { $0 > 0 }.count
        let result = NativeProcesses.list()
        #expect(result.pids.contains(getpid()))
        #expect(result.pids.count >= expected - 20)
        #expect(result.pids.count <= expected + 20)
        let sampler = ProcessSampler()
        _ = sampler.sample(limit: Int.max)
        #expect(sampler.coverage.enumerated >= expected - 20)
        #expect(sampler.coverage.readable > 0)
    }

    @Test func nativeTaskTimeMatchesPOSIXCPUTime() {
        func taskTime() -> UInt64 {
            var info = proc_taskinfo()
            #expect(proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) > 0)
            return info.pti_total_user + info.pti_total_system
        }
        func posixCPU() -> Double {
            var usage = rusage(); _ = getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let before = posixCPU(), taskBefore = taskTime(), wall = mach_absolute_time()
        let end = ProcessInfo.processInfo.systemUptime + 0.2
        while ProcessInfo.processInfo.systemUptime < end { }
        let ticks = mach_absolute_time() - wall, delta = taskTime() - taskBefore
        let cpuSeconds = posixCPU() - before
        var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase)
        let wallSeconds = Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1e9
        let expected = cpuSeconds / wallSeconds * 100
        let actual = NativeProcesses.cpuPercent(taskDelta: delta, wallTicks: ticks)
        #expect(actual > expected * 0.7)
        #expect(actual < expected * 1.3)
    }

    @Test func observationUsesMeasuredIntervalsAndDisclosesUnknown() async throws {
        let report = try await ObservationEngine.observe(seconds: 2)
        #expect(report.durationSeconds >= 2)
        #expect(report.samples.count == 1)
        #expect(report.samples[0].coverage.readable > 0)
        #expect(report.meanCPUPercent?.isFinite == true)
        #expect(report.samples[0].activity.swapInBytesPerSecond != nil)
        #expect(!report.limitations.isEmpty)
        let task = Task { try await ObservationEngine.observe(seconds: 60) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled observation completed") }
        catch is CancellationError { }
    }

    @Test func exactIdentityAndBrowserRoles() throws {
        let identity = try #require(ProcessIdentity.read(getpid()))
        #expect(identity.pid == getpid())
        #expect(identity.parentPID == getppid())
        #expect(!identity.startToken.isEmpty)
        #expect(identity.footprintBytes != nil)
        #expect(ProcessIdentity.role(arguments: ["--type=renderer", "--extension-process"], executable: "browser") == "Extension renderer")
        #expect(ProcessIdentity.role(arguments: ["--type=utility", "--utility-sub-type=media.mojom.CdmServiceBroker"], executable: "browser") == "Media service")
    }

    @Test @MainActor func quitRejectsStaleIdentityAndSelf() async {
        do { _ = try await AppQuit.run(pid: getpid(), startToken: "wrong", dryRun: false); Issue.record("Quit accepted stale identity") }
        catch { }
        if let own = ProcessIdentity.read(getpid()) {
            do { _ = try await AppQuit.run(pid: getpid(), startToken: own.startToken, dryRun: true); Issue.record("Quit accepted self") }
            catch { }
        }
    }
    @Test func anomalyClockResetsOnSameNamePIDRestart() {
        var watcher = ProcessWatcher(window: 60)
        let start = Date()
        let old = ProcessSample(pid: 123, name: "Same app", cpuPercent: 90, residentBytes: 1, startToken: "old")
        let new = ProcessSample(pid: 123, name: "Same app", cpuPercent: 90, residentBytes: 1, startToken: "new")
        #expect(watcher.ingest([old], now: start).isEmpty)
        #expect(watcher.ingest([new], now: start.addingTimeInterval(61)).isEmpty)
        #expect(watcher.ingest([new], now: start.addingTimeInterval(122)).count == 1)
    }
    @Test func failedProbeRetainsConfigurationEvidence() async throws {
        let report = try await NetworkDiagnostic.read(url: "file:///etc/passwd")
        #expect(report.probe == nil)
        #expect(report.probeError != nil)
        #expect(!report.limitations.isEmpty)
    }
    @Test func memoryRepresentativeIsLargestMember() {
        let rows = [ProcessSample(pid: 123, name: "Busy", cpuPercent: 90, residentBytes: 1, appName: "App"),
                    ProcessSample(pid: 124, name: "Large", cpuPercent: 0, residentBytes: 1000, appName: "App")]
        #expect(ProcessGrouper.group(rows).first?.topPID == 123)
        #expect(ProcessGrouper.group(rows, byMemory: true).first?.topPID == 124)
    }
    @Test func invalidNetworkProbeNeverRuns() async {
        for url in ["file:///etc/passwd", "https://user:password@example.com", "not a URL"] {
            do { _ = try await HTTPProbe.run(url); Issue.record("Accepted invalid probe") }
            catch { }
        }
    }
}
