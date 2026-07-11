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
                throughputChart
                if model.history.count >= 2 {
                    speedHistoryCard
                }
            }
            .padding(Halo.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear { model.requestLocationAuthorizationIfNeeded() }
    }

    private var header: some View {
        PageHeader(
            "Network",
            subtitle: "Signal strength, throughput, and connection quality."
        )
    }

    // MARK: Connection state

    private var connectionType: ConnectionType { dashboard.snapshot?.connectionType ?? .none }
    private var wifi: WiFiInfo? { dashboard.snapshot?.wifiInfo }

    /// 0–1, matching the dashboard card's semantics: real Wi-Fi quality, a
    /// flat "fine" reading for other connected types, zero when offline.
    private var quality: Double {
        switch connectionType {
        case .wifi: wifi?.signalQualityFraction ?? 0
        case .ethernet, .cellular, .other: 1.0
        case .none: 0
        }
    }

    private var qualityColor: Color {
        connectionType == .none
            ? Halo.textDim
            : (quality < 0.35 ? Halo.flare : (quality < 0.65 ? Halo.amber : Halo.pulseGreen))
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
        case .ethernet: "Wired · stable connection"
        case .cellular: "Cellular data"
        case .other: "Active connection"
        case .none: "Join a network to see live details"
        }
    }

    /// Ring caption word: the quality verdict for Wi-Fi, the medium otherwise.
    private var ringCaption: String {
        switch connectionType {
        case .wifi: (wifi?.signalQualityLabel ?? "—").uppercased()
        case .ethernet: "WIRED"
        case .cellular: "CELLULAR"
        case .other: "ONLINE"
        case .none: "OFFLINE"
        }
    }

    private var ringHeadline: String {
        connectionType == .wifi ? "\(wifi?.signalQualityPercent ?? 0)" : (connectionType == .none ? "—" : "OK")
    }

    // MARK: Connection card (hero)

    private var connectionCard: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(spacing: 8) {
                QualityRing(
                    fraction: quality, color: qualityColor,
                    headline: ringHeadline, caption: ringCaption)
                if connectionType == .wifi {
                    Text("Signal quality")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Halo.textDim)
                }
            }
            .frame(width: 150)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                    Text(connectionSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textDim)
                }

                if connectionType != .none {
                    factGrid
                }

                if connectionType == .wifi, !model.locationAuthorized, wifi?.ssid == nil {
                    Text("Grant Location access in System Settings to see the network name.")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    /// Two rows of three facts, BatteryCard style. Live throughput always
    /// present so the hero is useful on Ethernet too.
    private var factGrid: some View {
        let down = ByteFormat.string(dashboard.snapshot?.networkBytesInPerSecond ?? 0) + "/s"
        let up = ByteFormat.string(dashboard.snapshot?.networkBytesOutPerSecond ?? 0) + "/s"
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
            fact("DOWNLOAD", down, Halo.ion)
            fact("UPLOAD", up, Halo.volt)
            if connectionType == .wifi {
                fact("SIGNAL", wifi?.rssi.map { "\($0) dBm" } ?? "—", qualityColor)
                fact("CHANNEL", channelText, Halo.textPrimary)
                fact("SECURITY", wifi?.security ?? "—", Halo.textPrimary)
                fact("LINK RATE", wifi?.txRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "—", Halo.textPrimary)
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
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: Speed test card

    private var speedTestCard: some View {
        let result = model.lastResult
        let running = model.speedTestState == .running

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("INTERNET SPEED")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if let result {
                    Text("Tested \(result.date, style: .relative) ago · auto every 30 min")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Halo.textDim.opacity(0.8))
                }
                runButton(running: running)
            }

            if case .failed(let message) = model.speedTestState {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.flare)
            }

            if let result {
                HStack(alignment: .center, spacing: 0) {
                    statBlock(
                        icon: "arrow.down.circle.fill", title: "DOWNLOAD",
                        value: String(format: "%.0f", result.downloadMbps),
                        subtitle: "Mbps", color: Halo.ion)
                    divider
                    statBlock(
                        icon: "arrow.up.circle.fill", title: "UPLOAD",
                        value: String(format: "%.0f", result.uploadMbps),
                        subtitle: "Mbps", color: Halo.volt)
                    divider
                    statBlock(
                        icon: "timer", title: "LATENCY",
                        value: result.baseRTTMillis.map { String(format: "%.0f", $0) } ?? "—",
                        subtitle: "ms round-trip", color: Halo.textPrimary)
                    divider
                    statBlock(
                        icon: "dot.radiowaves.left.and.right", title: "RESPONSIVENESS",
                        value: result.responsivenessRPM.map { "\($0)" } ?? "—",
                        subtitle: "RPM under load · higher is better", color: Halo.textPrimary)
                }
            } else if running {
                measuringPlaceholder
            } else {
                Text("First test runs shortly after launch, then automatically every 30 minutes.")
                    .font(.system(size: 12))
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
            Text("Measuring download, upload, and responsiveness — about 20 seconds…")
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
        }
        .padding(.vertical, 12)
    }

    private func runButton(running: Bool) -> some View {
        Button {
            model.runSpeedTest()
        } label: {
            HStack(spacing: 6) {
                if running {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(running ? "Testing…" : "Run Test")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(running ? Halo.textDim : Halo.void)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                running ? AnyShapeStyle(Halo.surface2) : AnyShapeStyle(Halo.ion),
                in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(running)
        .help("Runs Apple's networkQuality test — uses real bandwidth for ~20 seconds")
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
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.textDim)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: Throughput

    private var throughputChart: some View {
        let maxIn = dashboard.networkInHistory.max() ?? 1024
        let maxOut = dashboard.networkOutHistory.max() ?? 1024
        let maxValue = max(maxIn, maxOut, 1024) * 1.2

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("LIVE THROUGHPUT · 30 MIN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
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
                .font(.system(size: 9, design: .monospaced))
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
                .font(.system(size: 9, weight: .semibold))
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
                Text("SPEED HISTORY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("\(ordered.count) tests")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
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
            .font(.system(size: 9, design: .monospaced))
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
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Halo.ion)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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
                .shadow(color: color.opacity(0.4), radius: 12)
                .animation(Halo.Motion.ring, value: fraction)
            VStack(spacing: 0) {
                Text(headline)
                    .font(.system(size: diameter * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(Halo.textPrimary)
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.system(size: diameter * 0.1, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection quality \(headline), \(caption)")
    }
}
