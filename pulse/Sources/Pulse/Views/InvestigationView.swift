import PulseKit
import SwiftUI

@MainActor @Observable
final class InvestigationModel {
    var report: ObservationReport?
    var previousReport: ObservationReport?
    var point: ObservationPoint?
    var network: NetworkDiagnostic?
    var history: DiagnosticHistory?
    var startup: StartupInventory?
    var assertions: [SleepAssertion] = []
    var assertionError: String?
    var feedback: String?
    var contextCapturedAt: Date?
    var observing = false
    var probing = false
    @ObservationIgnored private var observation: Task<Void, Never>?

    func load() async {
        do { network = try await NetworkDiagnostic.read() } catch { feedback = error.localizedDescription }
        let context = await Task.detached(priority: .utility) { (DiagnosticHistory.read(), StartupInventory.read()) }.value
        history = context.0; startup = context.1
        let snapshot = await PulseEngine(recordsHistory: false).sampleLite()
        contextCapturedAt = snapshot.timestamp
        assertions = snapshot.sleepAssertions
        assertionError = snapshot.activity.unavailable.first { $0.contains("Sleep assertions") }
    }
    func start(seconds: Int) {
        guard !observing else { return }
        previousReport = report; report = nil; point = nil; observing = true; feedback = nil
        observation = Task { [weak self] in
            do {
                let result = try await ObservationEngine.observe(seconds: seconds) { [weak self] point in
                    await self?.update(point)
                }
                self?.report = result
            } catch is CancellationError { self?.feedback = "Observation stopped; no completed report" }
            catch { self?.feedback = error.localizedDescription }
            self?.observing = false
        }
    }
    private func update(_ value: ObservationPoint) { point = value }
    func stop() { observation?.cancel() }
    func probe(_ url: String) async {
        guard !probing else { return }
        probing = true; defer { probing = false }
        do { network = try await NetworkDiagnostic.read(url: url); feedback = network?.probeError }
        catch { feedback = error.localizedDescription }
    }
    func copyReport() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let report, let data = try? encoder.encode(report), let string = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(string, forType: .string)
        feedback = "Copied observation report"
    }
}

struct InvestigationView: View {
    @State private var model = InvestigationModel()
    @State private var seconds = 30
    @State private var url = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Investigate performance").font(.title2.bold())
                Spacer()
                Button("Done") { model.stop(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                if let date = model.contextCapturedAt { Text("Context captured " + date.formatted()).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Refresh context") { Task { await model.load() } }
            }
            Text("Measure while the slowdown happens. Repeat after a targeted change to compare results.")
                .foregroundStyle(.secondary)
            TabView {
                observation.tabItem { Text("Observe") }
                network.tabItem { Text("Network") }
                history.tabItem { Text("History") }
                background.tabItem { Text("Background & sleep") }
            }
            if let feedback = model.feedback { Text(feedback).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(24).frame(minWidth: 760, minHeight: 590)
        .task { await model.load() }
        .onDisappear { model.stop() }
         .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            if let window = note.object as? NSWindow, window.title == "Pulse — Command Center", !window.occlusionState.contains(.visible) { model.stop() }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))) { _ in model.stop() }
    }

    private var observation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("Duration", selection: $seconds) {
                        Text("30 seconds").tag(30); Text("60 seconds").tag(60); Text("2 minutes").tag(120)
                    }.frame(width: 240).disabled(model.observing)
                    Button(model.observing ? "Stop" : "Observe") { model.observing ? model.stop() : model.start(seconds: seconds) }
                    Spacer()
                    if model.report != nil { Button("Copy report") { model.copyReport() } }
                }
                if model.observing { ProgressView("Observing… keep the affected app in use") }
                if let point = model.point {
                    Text("CPU " + percent(point.cpuPercent) + " · Pressure " + (point.memoryPressure ?? "Unavailable"))
                        .monospacedDigit()
                    Text("Processes readable: \(point.coverage.readable) / \(point.coverage.enumerated)").monospacedDigit()
                    HStack {
                        rate("Swap in", point.activity.swapInBytesPerSecond)
                        rate("Swap out", point.activity.swapOutBytesPerSecond)
                        rate("Disk read", point.activity.diskReadBytesPerSecond)
                        rate("Disk write", point.activity.diskWriteBytesPerSecond)
                    }
                    HStack {
                        rate("Compression", point.activity.compressionBytesPerSecond)
                        rate("Decompression", point.activity.decompressionBytesPerSecond)
                    }
                }
                if let report = model.report {
                    ForEach(report.findings, id: \.self) { Text($0).font(.headline) }
                    Text(String(format: "%.1fs measured", report.durationSeconds) + " · mean CPU " + percent(report.meanCPUPercent) + " · peak " + percent(report.peakCPUPercent)).monospacedDigit()
                    if let before = model.previousReport {
                        Text("Previous interval mean CPU " + percent(before.meanCPUPercent) + " → " + percent(report.meanCPUPercent) + ". Different workloads can affect this comparison.").foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Observed contributors").font(.headline)
                    ForEach(report.contributors.prefix(10), id: \.name) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.name); Spacer()
                                Text(String(format: "mean %.1f%% · peak %.1f%% · peak RSS %@", row.meanCPUPercent, row.peakCPUPercent, ByteFormat.string(row.peakResidentBytes))).monospacedDigit()
                            }
                            if let identity = row.representative {
                                Text("PID \(identity.pid) · \(identity.role)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Divider()
                    Text("Largest observed memory contributors").font(.headline)
                    ForEach(report.memoryContributors.prefix(5), id: \.name) { row in
                        HStack {
                            Text(row.name); Spacer()
                            Text("Peak RSS " + ByteFormat.string(row.peakResidentBytes)).monospacedDigit()
                        }
                    }
                    Text("Inspect a contributor in Monitor. For a browser renderer, match its PID in the browser’s Task Manager to find the tab or extension.").foregroundStyle(.secondary)
                    DisclosureGroup("Measurement limits") { ForEach(report.limitations, id: \.self) { Text($0).font(.caption) } }
                } else if !model.observing {
                    Text("Start an observation to distinguish brief spikes from persistent load. Missing measurements are shown as unavailable.").foregroundStyle(.secondary)
                }
            }.padding(16)
        }
    }
    private func rate(_ title: String, _ bytes: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytes.map { ByteFormat.string(UInt64(max(0, $0))) + "/s" } ?? "Unavailable").monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var network: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let network = model.network {
                    Text("Primary interface: \(network.primaryInterface ?? "Unavailable")")
                    Text("Proxy: " + (network.proxy.unavailable ?? (network.proxy.enabled ? network.proxy.details : "No configured proxy detected")))
                    if let wifi = network.wifi {
                        Text("Wi-Fi \(wifi.channelBand ?? "") · RSSI \(wifi.rssi.map(String.init) ?? "Unavailable") dBm · noise \(wifi.noise.map(String.init) ?? "Unavailable") dBm")
                        Text("Radio link rate: \(wifi.txRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "Unavailable") · channel \(wifi.channel.map(String.init) ?? "Unavailable")")
                    } else { Text("Wi-Fi metrics unavailable or disconnected") }
                    Divider()
                    Text("Check a destination").font(.headline)
                    Text("Enter the affected HTTP(S) URL. Pulse sends one HEAD request without browser cookies; it does not follow redirects or test bandwidth.").foregroundStyle(.secondary)
                    HStack {
                        TextField("https://example.com", text: $url)
                        Button(model.probing ? "Checking…" : "Check") { Task { await model.probe(url) } }.disabled(model.probing || url.isEmpty)
                    }
                    if let error = network.probeError { Text("Probe failed: " + error).foregroundStyle(.secondary) }
                    if let probe = network.probe {
                        Text("\(probe.host) · HTTP \(probe.statusCode) · \(Int(probe.elapsedMillis)) ms total")
                        Text("DNS \(milliseconds(probe.dnsMillis)) · connection \(milliseconds(probe.connectMillis)) · TLS \(milliseconds(probe.tlsMillis)) · response \(milliseconds(probe.responseMillis))").monospacedDigit()
                    }
                    ForEach(network.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }.padding(16)
        }
    }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "Unavailable" }
    private func milliseconds(_ value: Double?) -> String { value.map { "\(Int($0)) ms" } ?? "Unavailable" }
    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let history = model.history {
                    Text("Last 24 hours").font(.headline)
                    ForEach(history.metrics.keys.sorted(), id: \.self) { key in
                        Text("\(key.capitalized): \(history.metrics[key]?.count ?? 0) recorded minutes; unobserved time is unknown")
                        DisclosureGroup("Recent " + key + " readings") {
                            ForEach(Array((history.metrics[key] ?? []).suffix(12)), id: \.minute) { entry in
                                HStack {
                                    Text(Date(timeIntervalSince1970: Double(entry.minute * 60)).formatted())
                                    Spacer()
                                    Text(metric(entry.value, name: key)).monospacedDigit()
                                }.font(.caption)
                            }
                        }
                    }
                    Text("\(history.batterySessions.count) battery sessions · \(history.storage.count) storage snapshots")
                    ForEach(history.batterySessions.prefix(5), id: \.id) { session in
                        Text("\(session.startedAt.formatted()) · charge \(session.startCharge)% → \(session.endCharge)%")
                    }
                    Divider()
                    Text("\(history.anomalies.count) recorded anomalies").font(.headline)
                    ForEach(history.anomalies.prefix(30), id: \.id) { event in
                        Text("\(event.date.formatted()) · \(event.processName) · \(event.kind == .memoryLeak ? "memory growth" : "CPU") · \(Int(event.sustainedSeconds))s")
                    }
                    ForEach(history.unavailable, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    ForEach(history.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }.padding(16)
        }
    }
    private func metric(_ value: Double, name: String) -> String {
        switch name {
        case "memory-pressure": return String(format: "Avg. level %.1f (1 normal, 2 warning, 4 critical)", value)
        case "swap-bytes": return ByteFormat.string(UInt64(max(0, value)))
        case "cpu-temperature": return String(format: "%.1f °C", value)
        default: return String(format: "%.1f%%", value)
        }
    }
    private var background: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Currently preventing idle sleep").font(.headline)
                if let error = model.assertionError { Text(error) }
                else if model.assertions.isEmpty { Text("No blocking assertions observed") }
                ForEach(Array(model.assertions.enumerated()), id: \.offset) { _, assertion in
                    Text("\(assertion.processName) (\(assertion.pid)) · \(assertion.assertionName)")
                }
                Divider()
                if let inventory = model.startup {
                    Text("Configured startup helpers (read only)").font(.headline)
                    ForEach(inventory.items) { item in
                        VStack(alignment: .leading) {
                            Text(item.label + (item.disabled ? " · disabled" : "") + (item.executableExists == false ? " · executable missing" : ""))
                            Text(item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    ForEach(inventory.unreadablePaths, id: \.self) { Text("Unreadable: " + $0).font(.caption) }
                    ForEach(inventory.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }.padding(16)
        }
    }
}
