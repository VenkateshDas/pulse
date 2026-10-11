import PulseKit
import SwiftUI

/// Network detail page: live signal + throughput (piggybacks DashboardModel's
/// existing sampling loop, no page-local polling) plus an auto-cached speed
/// test via NetworkModel. Visual language matches the Health page: a hero
/// ring + fact grid, big monospaced stat blocks, one capsule action.
struct NetworkView: View {
    @Environment(DashboardModel.self) private var dashboard
    @Environment(NetworkModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Halo.Space.lg) {
                header
                connectionCard
                speedTestCard
                DisclosureGroup("Network details and history") {
                    VStack(spacing: Halo.Space.lg) {
                        factGrid.premiumCard()
                        throughputChart
                        if model.history.count >= 2 { speedHistoryCard }
                    }.padding(.top, 12)
                }
            }
            .padding(Halo.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Halo.void)

    }

    private var header: some View {
        PageHeader(
            "Internet",
            subtitle: "Check your connection and estimate its speed when you need to."
        )
    }

    // MARK: Connection state

    private var connectionType: ConnectionType { dashboard.snapshot?.connectionType ?? .none }
    private var wifi: WiFiInfo? { dashboard.snapshot?.wifiInfo }

    private var qualityColor: Color {
        guard let wifi else { return Halo.textDim }
        return wifi.signalQualityFraction < 0.35 ? Halo.critical : wifi.signalQualityFraction < 0.65 ? Halo.amber : Halo.pulseGreen
    }

    private var connectionLabel: String {
        switch connectionType {
        case .wifi: wifi?.ssid ?? "Wi-Fi Network"
        case .ethernet: "Ethernet"
        case .cellular: "Cellular"
        case .other: "Connected"
        case .none: "No Connection"
        }
    }

    private var connectionSubtitle: String {
        switch connectionType {
        case .wifi: "Wi-Fi · \(wifi?.signalQualityLabel ?? "Signal unknown") signal"
        case .ethernet: "Connected by Ethernet"
        case .cellular: "Cellular data"
        case .other: "Active connection"
        case .none: "Join a network in macOS settings to continue"
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(dashboard.snapshot == nil ? "Checking connection…" : connectionLabel,
                  systemImage: connectionType == .wifi ? "wifi" : connectionType == .none ? "wifi.slash" : "network")
                .font(Halo.font(size: 18, weight: .semibold))
            Text(connectionSubtitle).font(Halo.font(size: 14)).foregroundStyle(Halo.textSecondary)
            Text("A connection to a network does not confirm that websites are reachable. Use the optional speed test if you want to check a remote service.")
                .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
            if connectionType == .wifi, !model.locationAuthorized, wifi?.ssid == nil {
                Text("macOS requires Location access to show the Wi-Fi network name. Speed tests work without this access.")
                    .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
                Button("Show Wi-Fi network name…") { model.requestLocationAuthorizationIfNeeded() }
                    .buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).premiumCard()
    }

    /// Two rows of three facts, BatteryCard style. Live throughput always
    /// present so the hero is useful on Ethernet too.
    private var factGrid: some View {
        let down = ByteFormat.string(dashboard.snapshot?.networkBytesInPerSecond ?? 0) + "/s"
        let up = ByteFormat.string(dashboard.snapshot?.networkBytesOutPerSecond ?? 0) + "/s"
        let cols = [GridItem(.adaptive(minimum: 160), alignment: .leading)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
            fact("Receiving now", down, Halo.ion)
            fact("Sending now", up, Halo.volt)
            if connectionType == .wifi {
                fact("Wi-Fi signal", wifi?.rssi.map { "\($0) dBm" } ?? "—", qualityColor)
                fact("Wi-Fi channel", channelText, Halo.textPrimary)
                fact("Wi-Fi security", wifi?.security ?? "—", Halo.textPrimary)
                fact("Local link rate", wifi?.txRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "—", Halo.textPrimary)
            }
        }
    }

    private var channelText: String {
        guard let channel = wifi?.channel else { return "—" }
        if let band = wifi?.channelBand { return "\(channel) · \(band)" }
        return "\(channel)"
    }

    private func fact(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Halo.font(size: 9, weight: .semibold))
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(Halo.font(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)

        }
    }

    // MARK: Speed test card

    private var speedTestCard: some View {
        let result = model.lastResult
        let running = model.isTesting

        return VStack(alignment: .leading, spacing: 14) {
            Text("Internet speed").font(Halo.font(size: 17, weight: .semibold))
            HStack {
                runButton(running: running)
                if let result {
                    Text("Last tested \(result.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
                }
            }
            Text("This test sends synthetic data to Cloudflare and transfers about 18 MB. Results estimate this connection to that service; they are not a guarantee for every website.")
                .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Test automatically every 30 minutes", isOn: Binding(get: { model.automaticTestsEnabled }, set: { model.setAutomaticTests($0) }))
                .font(Halo.font(size: 13))
            if model.speedTestState == .cancelled { FeedbackBadge(message: "Test stopped. Your previous result is still available.") }
            if running { Button("Stop test") { model.cancelSpeedTest() }.buttonStyle(.bordered) }
            if case .failed(let message) = model.speedTestState {
                Text(message)
                    .font(Halo.font(size: 11))
                    .foregroundStyle(Halo.flare)
            }

            if let result {
                if result.method != "bounded-https" {
                    Text("Saved result from the previous test method. New tests use bounded HTTPS estimates, so the results may differ.")
                        .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], spacing: 20) {
                    statBlock(icon: "arrow.down", title: "Download", value: String(format: "%.0f", result.downloadMbps), subtitle: "Mbps · receiving data", color: Halo.textPrimary)
                    statBlock(icon: "arrow.up", title: "Upload", value: String(format: "%.0f", result.uploadMbps), subtitle: "Mbps · sending data", color: Halo.textPrimary)
                }
                DisclosureGroup("Test details") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let time = result.baseRTTMillis {
                            Text(result.method == "bounded-https" ? String(format: "HTTPS request time: %.0f ms", time) : String(format: "Previous round-trip latency: %.0f ms", time))
                        }
                        if let rpm = result.responsivenessRPM { Text("Previous loaded responsiveness: \(rpm) round trips per minute") }
                    }.font(Halo.font(size: 13)).padding(.top, 8)
                }
            } else if running {
                measuringPlaceholder
            } else {
                Text("No speed test yet. Choose Test internet speed to measure this connection.")
                    .font(Halo.font(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var measuringPlaceholder: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Measuring download, upload and request time…")
                .font(Halo.font(size: 12))
                .foregroundStyle(Halo.textDim)
        }
        .padding(.vertical, 12)
    }

    private func runButton(running: Bool) -> some View {
        Button { model.runSpeedTest() } label: {
            Label(running ? "Testing…" : "Test internet speed", systemImage: "network")
        }.buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent)
            .disabled(running)
            .help("Uses about 18 MB of synthetic traffic to Cloudflare. You can stop the test.")
    }

    private var divider: some View {
        Rectangle()
            .fill(Halo.surface2)
            .frame(width: 1, height: 48)
    }

    private func statBlock(icon: String, title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(Halo.font(size: 10))
                    .foregroundStyle(color)
                Text(title)
                    .font(Halo.font(size: 9, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
            }
            Text(value)
                .font(Halo.font(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(subtitle)
                .font(Halo.font(size: 10))
                .foregroundStyle(Halo.textDim)
                .lineLimit(1)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Throughput

    private var throughputChart: some View {
        let maxIn = dashboard.networkInHistory.max() ?? 1024
        let maxOut = dashboard.networkOutHistory.max() ?? 1024
        let maxValue = max(maxIn, maxOut, 1024) * 1.2

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Data transfer · 30 minutes")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                legendDot(Halo.ion, "Download")
                legendDot(Halo.volt, "Upload")
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing) {
                    Text(ByteFormat.string(UInt64(maxValue)) + "/s")
                    Spacer()
                    Text("0 B/s")
                }
                .font(Halo.font(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 60, alignment: .trailing)

                ZStack {
                    HistoryChart(values: padded(dashboard.networkInHistory), color: Halo.ion, maxValue: maxValue)
                    HistoryChart(values: padded(dashboard.networkOutHistory), color: Halo.volt, maxValue: maxValue)
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(Halo.font(size: 9, weight: .semibold))
                .foregroundStyle(Halo.textDim)
        }
    }

    private func padded(_ buffer: [Double]) -> [Double?] {
        let missing = 900 - buffer.count
        if missing <= 0 { return buffer.map { $0 } }
        return Array(repeating: nil, count: missing) + buffer.map { $0 }
    }

    // MARK: Speed history

    /// Recent tests as paired download/upload bars — one discrete result per
    /// group (they're point-in-time tests, not a continuous series, so bars
    /// read more honestly than an interpolated line).
    private var speedHistoryCard: some View {
        let ordered = Array(model.history.prefix(16).reversed())
        let maxMbps = max(ordered.map { max($0.downloadMbps, $0.uploadMbps) }.max() ?? 100, 10)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Previous speed tests")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Text("\(ordered.count) tests")
                    .font(Halo.font(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.ion)
                Spacer()
                legendDot(Halo.ion, "Download")
                legendDot(Halo.volt, "Upload")
            }

            historyBars(ordered, scale: maxMbps)
                .frame(height: 110)

            HStack {
                if let first = ordered.first { Text(axisLabel(first.date)) }
                Spacer()
                if ordered.count > 1, let last = ordered.last { Text(axisLabel(last.date)) }
            }
            .font(Halo.font(size: 9, design: .monospaced))
            .foregroundStyle(Halo.textDim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func historyBars(_ results: [SpeedTestResult], scale: Double) -> some View {
        GeometryReader { geo in
            // Reserve a row for the value label so bars never clip it.
            let labelHeight: CGFloat = 13
            let barMax = max(geo.size.height - labelHeight, 8)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(results) { result in
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", result.downloadMbps))
                            .font(Halo.font(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Halo.ion)
                            .lineLimit(1)

                        HStack(alignment: .bottom, spacing: 2) {
                            bar(result.downloadMbps, scale: scale, maxHeight: barMax, color: Halo.ion)
                            bar(result.uploadMbps, scale: scale, maxHeight: barMax, color: Halo.volt)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .help(historyTooltip(result))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func bar(_ mbps: Double, scale: Double, maxHeight: CGFloat, color: Color) -> some View {
        let fraction = min(max(mbps / scale, 0), 1)
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(maxWidth: 14)
            .frame(height: max(maxHeight * fraction, 3))
    }

    private func historyTooltip(_ result: SpeedTestResult) -> String {
        var parts = [
            result.date.formatted(date: .abbreviated, time: .shortened),
            String(format: "%.0f ↓ / %.0f ↑ Mbps", result.downloadMbps, result.uploadMbps),
        ]
        if let rtt = result.baseRTTMillis { parts.append(String(format: "%.0f ms", rtt)) }
        return parts.joined(separator: " · ")
    }

    private func axisLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = cal.isDateInToday(date) ? "h:mm a" : "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

/// Circular quality gauge in the HealthScoreRing idiom: big rounded number
/// (or word) with a colored verdict caption beneath it.
private struct QualityRing: View {
    let fraction: Double
    let color: Color
    let headline: String
    let caption: String
    var diameter: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .stroke(Halo.surface2, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(headline)
                    .font(Halo.font(size: diameter * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(Halo.textPrimary)
                    .monospacedDigit()
                Text(caption)
                    .font(Halo.font(size: diameter * 0.1, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)

                    .padding(.horizontal, 12)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection quality \(headline), \(caption)")
    }
}
