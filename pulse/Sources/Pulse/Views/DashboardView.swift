import PulseKit
import SwiftUI

/// Main command-center content: greeting, guided-focus attention cards,
/// vitals row, CPU chart and top processes.
struct DashboardView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(NetworkModel.self) private var networkModel
    /// Gates the charts/heatmap/process-table wall behind a tap in Simple
    /// mode, so a non-technical user's first view is verdict + vitals, not
    /// an instrument panel. Pro mode starts expanded — nothing changes for
    /// existing users. Set once at construction, not re-derived on every
    /// render, so a manual toggle during the session sticks.
    @State private var showDetails: Bool

    /// Posted when the user taps the diagnosis culprit chip; RootView
    /// switches the sidebar to the Monitor tab.
    static let navigateToMonitor = Notification.Name("PulseNavigateToMonitor")

    init() {
        _showDetails = State(initialValue: DisplayModeManager.shared.current == .pro)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Halo.Space.lg) {
                hero
                AttentionSection()
                if let feedback = model.actionFeedback {
                    FeedbackBadge(message: feedback)
                }
                vitals
                detailsDisclosure
                if showDetails {
                    HStack(alignment: .top, spacing: Halo.Space.lg) {
                        VStack(spacing: Halo.Space.lg) {
                            chartsPanel
                            CoreHeatmap(cpuPerCore: model.snapshot?.cpuPerCore ?? [])
                        }
                        .frame(maxHeight: .infinity)

                        TopProcessesPanel(processes: model.snapshot?.topProcesses ?? [])
                            .frame(width: 400)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(minHeight: 480)
                }
            }
            .padding(Halo.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background { ZStack { Halo.void; Halo.meshBackground } }
    }

    private var detailsDisclosure: some View {
        Button {
            withAnimation(Halo.Motion.snappy) { showDetails.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(showDetails ? "Hide details" : "Show details")
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(showDetails ? 90 : 0))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Halo.textDim)
        }
        .buttonStyle(.plain)
    }

    // MARK: Hero (greeting + diagnosis verdict + health score)

    private var hero: some View {
        HStack(alignment: .center, spacing: 20) {
            greeting
            Spacer()
            HealthScoreRing(score: model.healthScore, labelMode: .scoreOnly)
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(timeGreeting), \(firstName)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Halo.textPrimary)
            DiagnosisBadge(
                diagnosis: model.diagnosis,
                culpritName: culpritName,
                onCulpritTap: {
                    // Carry the PID so Monitor opens with the culprit selected.
                    NotificationCenter.default.post(
                        name: Self.navigateToMonitor,
                        object: model.diagnosis.culpritPID)
                })
            Text(statusLine)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(Halo.textDim)
        }
    }

    /// Name of the diagnosis culprit process, looked up by PID in the snapshot.
    private var culpritName: String? {
        guard let pid = model.diagnosis.culpritPID else { return nil }
        return model.snapshot?.topProcesses.first { $0.pid == pid }?.name
    }

    private var timeGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var firstName: String {
        NSFullUserName().components(separatedBy: " ").first ?? "there"
    }

    private var statusLine: String {
        let issues = model.alerts.count
        // Info-level alerts are FYIs, not problems — only warning+ changes
        // the health verdict (the sidebar footer uses the same rule).
        let hasProblems = model.alerts.contains { $0.severity != .info }
        let health = hasProblems ? "Your Mac needs a look" : "Your Mac is healthy"
        let attention =
            issues == 0
            ? "nothing needs attention"
            : "\(issues) thing\(issues == 1 ? "" : "s") worth a glance"
        return "\(health) · \(attention) · sampling live"
    }

    // MARK: Vitals

    private var vitals: some View {
        HStack(spacing: Halo.Space.md) {
            cpuCard
            memoryCard
            diskCard
            thermalCard
            networkCard
        }
    }

    private var networkCard: some View {
        let snapshot = model.snapshot
        let connectionType = snapshot?.connectionType ?? .none
        let wifi = snapshot?.wifiInfo

        // Quality, 0–1: real Wi-Fi signal quality, or a flat "fine"/"off"
        // state for other connection types. Deliberately NOT run through
        // Halo.statusColor — that treats a high fraction as *bad* (it's
        // built for CPU/memory load), which made full signal show red.
        let quality: Double =
            switch connectionType {
            case .wifi: wifi?.signalQualityFraction ?? 0
            case .ethernet, .cellular, .other: 1.0
            case .none: 0
            }
        let ringColor: Color =
            connectionType == .none
                ? Halo.textDim
                : (quality < 0.35 ? Halo.flare : (quality < 0.65 ? Halo.amber : Halo.pulseGreen))

        let value: String =
            switch connectionType {
            case .wifi: "\(wifi?.signalQualityPercent ?? 0)%"
            case .ethernet: "Wired"
            case .cellular: "Cell"
            case .other: "On"
            case .none: "Off"
            }

        let line1: String =
            switch connectionType {
            case .wifi: wifi?.ssid ?? "Wi-Fi Network"
            case .ethernet: "Ethernet"
            case .cellular: "Cellular"
            case .other: "Connected"
            case .none: "Not connected"
            }

        // Cached speed-test result answers "how fast is my internet" right on
        // the dashboard; falls back to the signal verdict before the first run.
        let line2: String =
            if connectionType == .none {
                "No network"
            } else if let result = networkModel.lastResult {
                String(format: "%.0f ↓ · %.0f ↑ Mbps", result.downloadMbps, result.uploadMbps)
            } else {
                switch connectionType {
                case .wifi: wifi.map { "\($0.signalQualityLabel) signal" } ?? "Signal unknown"
                case .ethernet: "Stable connection"
                default: "Connected"
                }
            }

        let down = ByteFormat.string(snapshot?.networkBytesInPerSecond ?? 0) + "/s"
        let up = ByteFormat.string(snapshot?.networkBytesOutPerSecond ?? 0) + "/s"

        var networkStats: [VitalCard.Stat] = [.init(label: "↓", value: down), .init(label: "↑", value: up)]
        if connectionType == .wifi, let channel = wifi?.channel, let band = wifi?.channelBand {
            networkStats.append(.init(label: "CH", value: "\(channel) · \(band)"))
        }

        let tooltip: String? =
            if let wifi, connectionType == .wifi {
                [
                    wifi.security.map { "Security: \($0)" },
                    wifi.rssi.map { "Signal: \($0) dBm" },
                    wifi.txRateMbps.map { String(format: "Link rate: %.0f Mbps", $0) },
                ].compactMap { $0 }.joined(separator: "\n")
            } else {
                nil
            }

        return VitalCard(
            title: "NETWORK",
            fraction: quality,
            ringColor: ringColor,
            value: value,
            line1: line1,
            line2: line2,
            history: model.networkInHistory,
            historyScale: max(model.networkInHistory.max() ?? 1024, 1024) * 1.2,
            cardTooltip: tooltip,
            stats: networkStats
        )
    }

    private var cpuCard: some View {
        let snapshot = model.snapshot
        let total = snapshot?.cpuTotalPercent ?? 0
        let mode = DisplayModeManager.shared.current
        let cpuTooltip = snapshot?.cpuPerCore.enumerated().map { "Core \($0.offset): \(Int($0.element))%" }.joined(separator: "\n")

        // Footer chips: the biggest CPU consumer right now, and how many cores
        // are actually loaded — the two things you reach for when CPU is high.
        var cpuStats: [VitalCard.Stat] = []
        if let top = snapshot?.topProcesses.first, top.cpuPercent >= 1 {
            let name = top.name.count > 12 ? String(top.name.prefix(11)) + "…" : top.name
            cpuStats.append(.init(label: "TOP", value: "\(name) \(Int(top.cpuPercent))%"))
        }
        if let cores = snapshot?.cpuPerCore, !cores.isEmpty {
            let busy = cores.filter { $0 >= 20 }.count
            cpuStats.append(
                .init(label: "BUSY", value: "\(busy)/\(cores.count)",
                    color: busy == cores.count ? Halo.amber : nil))
        }

        return VitalCard(
            title: "CPU",
            fraction: total / 100,
            value: String(format: "%2d%%", Int(total)),
            line1: DashboardFormatting.cpuLine1(
                mode: mode,
                efficiencyPercent: snapshot?.cpuEfficiencyPercent.map { Int($0) },
                performancePercent: snapshot?.cpuPerformancePercent.map { Int($0) },
                coreCount: snapshot?.cpuPerCore.count ?? 0,
                gpuPercent: snapshot?.gpuUsage?.deviceUtilization),
            line2: DashboardFormatting.cpuLine2(mode: mode, loadAverage1m: snapshot?.loadAverage1m ?? 0) ?? "",
            history: model.cpuHistory,
            cardTooltip: cpuTooltip,
            stats: cpuStats
        )
    }

    private var memoryCard: some View {
        let snapshot = model.snapshot
        let mode = DisplayModeManager.shared.current
        let pressureColor: Color =
            switch snapshot?.memoryPressure {
            case .critical: Halo.flare
            case .warning: Halo.amber
            default: Halo.pulseGreen
            }

        let total = Double(snapshot?.memoryTotalBytes ?? 1)
        let appF = Double(snapshot?.memoryAppBytes ?? 0) / total
        let wiredF = Double(snapshot?.memoryWiredBytes ?? 0) / total
        let compF = Double(snapshot?.memoryCompressedBytes ?? 0) / total

        let showBreakdown = DashboardFormatting.showsMemoryBreakdown(mode: mode)
        let segments: [VitalCard.Segment]? = showBreakdown ? [
            VitalCard.Segment(start: 0, end: appF, color: Halo.ion),
            VitalCard.Segment(start: appF, end: appF + wiredF, color: Halo.volt),
            VitalCard.Segment(start: appF + wiredF, end: appF + wiredF + compF, color: Halo.pulseGreen)
        ] : nil

        let breakdownTooltip = [
            "App Memory: \(ByteFormat.string(snapshot?.memoryAppBytes ?? 0))",
            "Wired Memory: \(ByteFormat.string(snapshot?.memoryWiredBytes ?? 0))",
            "Compressed: \(ByteFormat.string(snapshot?.memoryCompressedBytes ?? 0))"
        ].joined(separator: "\n")

        let memUsed = snapshot?.memoryUsedBytes ?? 0
        let memTotal = snapshot?.memoryTotalBytes ?? 0
        let memFree = memTotal > memUsed ? memTotal - memUsed : 0

        let pressureStr: String =
            switch snapshot?.memoryPressure {
            case .critical: " · CRIT"
            case .warning: " · WARN"
            default: ""
            }

        let legend: [VitalCard.LegendItem]? = showBreakdown ? [
            VitalCard.LegendItem(color: Halo.ion, label: "App"),
            VitalCard.LegendItem(color: Halo.volt, label: "Wired"),
            VitalCard.LegendItem(color: Halo.pulseGreen, label: "Comp")
        ] : nil

        return VitalCard(
            title: "MEMORY",
            fraction: snapshot?.memoryUsedFraction ?? 0,
            ringColor: pressureColor,
            value: String(format: "%2d%%", Int((snapshot?.memoryUsedFraction ?? 0) * 100)),
            line1: DashboardFormatting.memoryLine1(mode: mode, usedBytes: memUsed, freeBytes: memFree),
            line2: DashboardFormatting.memoryLine2(mode: mode, swapUsedBytes: snapshot?.swapUsedBytes ?? 0, pressureSuffix: pressureStr) ?? "",
            history: model.memoryHistory,
            cardTooltip: breakdownTooltip,
            legend: legend,
            segments: segments
        )
    }

    private var diskCard: some View {
        let snapshot = model.snapshot
        let total = snapshot?.diskTotalBytes ?? 0
        let free = snapshot?.diskFreeBytes ?? 0
        let used = total > free ? total - free : 0
        let growth: String
        if let weekly = snapshot?.diskWeeklyGrowthBytes {
            let sign = weekly >= 0 ? "+" : "−"
            growth = "\(sign)\(ByteFormat.string(UInt64(abs(weekly))))/wk"
        } else {
            growth = "growth: tracking…"
        }
        let diskTooltip = [
            "Total Space: \(ByteFormat.string(total))",
            "Used Space: \(ByteFormat.string(used))",
            "Free Space: \(ByteFormat.string(free))"
        ].joined(separator: "\n")

        // Footer chips: free space, and — projecting the weekly growth trend
        // forward — roughly when the disk runs out.
        var diskStats: [VitalCard.Stat] = [.init(label: "FREE", value: ByteFormat.string(free))]
        if let weekly = snapshot?.diskWeeklyGrowthBytes {
            if weekly > 0, free > 0 {
                let weeks = Double(free) / Double(weekly)
                diskStats.append(
                    .init(label: "FULL IN", value: Self.diskETA(weeks),
                        color: weeks < 8 ? Halo.amber : nil))
            } else {
                diskStats.append(.init(label: "TREND", value: "stable"))
            }
        }

        return VitalCard(
            title: "DISK",
            fraction: snapshot?.diskUsedFraction ?? 0,
            value: String(format: "%2d%%", Int((snapshot?.diskUsedFraction ?? 0) * 100)),
            line1: "\(ByteFormat.string(used)) / \(ByteFormat.string(total))",
            line2: growth,
            cardTooltip: diskTooltip,
            stats: diskStats
        )
    }

    /// Human-friendly "time until full" from a week count: years / months / weeks.
    private static func diskETA(_ weeks: Double) -> String {
        if weeks >= 104 { return "~\(Int((weeks / 52).rounded()))y" }
        if weeks >= 9 { return "~\(Int((weeks / 4.345).rounded()))mo" }
        return "~\(max(1, Int(weeks.rounded())))wk"
    }

    private var thermalCard: some View {
        let sensors = model.snapshot?.sensors ?? SensorReadings()
        let hottest = [sensors.cpuTempC, sensors.gpuTempC].compactMap { $0 }.max()
        let mode = DisplayModeManager.shared.current

        guard let hottest else {
            // No SMC on this machine (or access denied): fall back to the
            // macOS thermal state, which is always available.
            let thermal = model.snapshot?.thermal ?? .nominal
            let (label, fraction, color): (String, Double, Color) =
                switch thermal {
                case .nominal: ("OK", 0.18, Halo.volt)
                case .fair: ("WARM", 0.5, Halo.amber)
                case .serious: ("HOT", 0.8, Halo.flare)
                case .critical: ("CRIT", 1.0, Halo.flare)
                }
            return VitalCard(
                title: "THERMAL",
                fraction: fraction,
                ringColor: color,
                value: label,
                line1: "thermal state",
                line2: DashboardFormatting.thermalFallbackLine2(mode: mode),
                history: model.loadHistory,
                historyScale: 10
            )
        }

        // Ring maps 20–110 °C; color thresholds follow Apple Silicon
        // norms (sustained >90 °C is throttling territory).
        let color: Color = hottest < 70 ? Halo.volt : (hottest < 90 ? Halo.amber : Halo.flare)
        let line1 = DashboardFormatting.thermalLine1(mode: mode, cpuTempC: sensors.cpuTempC, gpuTempC: sensors.gpuTempC)

        var parts: [String] = []
        if let battery = sensors.batteryTempC {
            parts.append(String(format: "batt %2.0f°", battery))
        }
        if let fans = sensors.fanCount, fans > 0, let rpm = sensors.fanRPM {
            parts.append(String(format: "fan %.0f rpm", rpm))
        }
        if let watts = sensors.systemWatts {
            parts.append(String(format: "%.1f W", watts))
        } else if sensors.fanCount == 0 {
            parts.append("fanless")
        }

        var thermalLines: [String] = []
        if let cpu = sensors.cpuTempC { thermalLines.append(String(format: "CPU: %.0f°C", cpu)) }
        if let gpu = sensors.gpuTempC { thermalLines.append(String(format: "GPU: %.0f°C", gpu)) }
        if let batt = sensors.batteryTempC { thermalLines.append(String(format: "Battery: %.0f°C", batt)) }
        let thermalTooltip = thermalLines.isEmpty ? nil : thermalLines.joined(separator: "\n")

        // Footer chips: degrees of headroom before throttling (~90 °C on Apple
        // Silicon) and whether temps are climbing — context a bare number lacks.
        var thermalStats: [VitalCard.Stat]? = nil
        if DashboardFormatting.showsThermalStats(mode: mode) {
            let headroom = max(0, 90 - hottest)
            var stats: [VitalCard.Stat] = [
                .init(
                    label: "HEADROOM", value: String(format: "%.0f°", headroom),
                    color: headroom < 10 ? Halo.flare : (headroom < 25 ? Halo.amber : nil))
            ]
            if model.tempHistory.count >= 6 {
                let recent = model.tempHistory.suffix(6)
                let delta = (recent.last ?? 0) - (recent.first ?? 0)
                let trend = delta > 2 ? "rising" : (delta < -2 ? "falling" : "steady")
                stats.append(
                    .init(label: "TREND", value: trend, color: delta > 2 ? Halo.amber : nil))
            }
            thermalStats = stats
        }

        return VitalCard(
            title: "THERMAL",
            fraction: min(max((hottest - 20) / 90, 0), 1),
            ringColor: color,
            value: String(format: "%2.0f°", hottest),
            line1: line1,
            line2: DashboardFormatting.thermalLine2(mode: mode, parts: parts) ?? "",
            history: model.tempHistory,
            historyScale: 110,
            cardTooltip: thermalTooltip,
            stats: thermalStats
        )
    }

    // MARK: Performance Charts

    private var chartsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                chartRow(
                    title: "CPU · 30M", topLabel: "100%", bottomLabel: "0%",
                    history: paddedHistory(model.cpuHistory),
                    color: Halo.ion, maxValue: 100
                )
                chartRow(
                    title: "MEMORY · 30M", topLabel: "100%", bottomLabel: "0%",
                    history: paddedHistory(model.memoryHistory),
                    color: Halo.volt, maxValue: 100
                )
            }
            
            HStack(spacing: 16) {
                networkChartRow

                let maxPower = max(model.powerHistory.compactMap { $0 }.max() ?? 50, 10)
                let powerScale = maxPower * 1.2
                chartRow(
                    title: "POWER · 30M", topLabel: String(format: "%.0f W", powerScale), bottomLabel: "0 W",
                    history: paddedHistory(model.powerHistory),
                    color: Halo.amber, maxValue: powerScale
                )
            }

            thermalChartRow
            cpuDayChartRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard()
    }
    
    private var thermalChartRow: some View {
        let maxTemp = max(
            model.tempHistory.max() ?? 60,
            model.gpuTempHistory.max() ?? 60,
            60
        )
        let scale = maxTemp + 10

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("THERMAL · 30M")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .help("CPU and GPU temperature over the last 30 minutes (Orange = CPU, Purple = GPU)")
            }
            .foregroundStyle(Halo.textDim)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing) {
                    Text(String(format: "%.0f°", scale))
                    Spacer()
                    Text("0°")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 50, alignment: .trailing)

                ZStack {
                    HistoryChart(values: paddedHistory(model.tempHistory), color: Halo.amber, maxValue: scale)
                    HistoryChart(values: paddedHistory(model.gpuTempHistory), color: .purple, maxValue: scale)
                }
            }
            .frame(height: 70)

            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Halo.amber).frame(width: 5, height: 5)
                    Text("CPU")
                }
                HStack(spacing: 4) {
                    Circle().fill(.purple).frame(width: 5, height: 5)
                    Text("GPU")
                }
                Spacer()
                Text("-30m")
                Spacer()
                Text("-15m")
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Halo.pulseGreen).frame(width: 5, height: 5)
                    Text("LIVE").foregroundStyle(Halo.pulseGreen)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Halo.textDim)
        }
    }

    /// 24-hour CPU history — gap-honest (nil minutes render as gaps, never
    /// interpolated), persisted across launches via MinuteHistoryStore.
    private var cpuDayChartRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("CPU · 24H")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .help("Minute-averaged CPU over the last 24 hours. Gaps (sleep, app closed) are shown honestly — never interpolated.")
            }
            .foregroundStyle(Halo.textDim)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing) {
                    Text("100%")
                    Spacer()
                    Text("0%")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 50, alignment: .trailing)
                HistoryChart(values: model.cpuDayHistory, color: Halo.ion, maxValue: 100)
            }
            .frame(height: 70)

            HStack {
                Text("-24h")
                Spacer()
                Text("-12h")
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Halo.pulseGreen).frame(width: 5, height: 5)
                    Text("LIVE").foregroundStyle(Halo.pulseGreen)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Halo.textDim)
        }
    }

    private var xAxis: some View {
        HStack {
            Text("-30m")
            Spacer()
            Text("-15m")
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Halo.pulseGreen).frame(width: 5, height: 5)
                Text("LIVE")
                    .foregroundStyle(Halo.pulseGreen)
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(Halo.textDim)
    }
    
    private var networkChartRow: some View {
        let maxIn = model.networkInHistory.compactMap { $0 }.max() ?? 1024
        let maxOut = model.networkOutHistory.compactMap { $0 }.max() ?? 1024
        let maxValue = max(maxIn, maxOut, 1024) * 1.2 // Scale to fit
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("NETWORK · 30M")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .help("Network throughput over the last 30 minutes (Blue = Download, Purple = Upload)")
            }
            .foregroundStyle(Halo.textDim)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing) {
                    Text(ByteFormat.string(UInt64(maxValue)) + "/s")
                    Spacer()
                    Text("0 B/s")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 50, alignment: .trailing)
                
                ZStack {
                    // Download = ion, upload = volt — same semantics as Monitor.
                    HistoryChart(values: paddedHistory(model.networkInHistory), color: Halo.ion, maxValue: maxValue)
                    HistoryChart(values: paddedHistory(model.networkOutHistory), color: Halo.volt, maxValue: maxValue)
                }
            }
            .frame(maxHeight: .infinity)
            
            xAxis
        }
    }

    private func chartRow(title: String, topLabel: String, bottomLabel: String, history: [Double?], color: Color, maxValue: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .help(title.contains("CPU") ? "CPU utilization history over the last 30 minutes" : "System memory utilization history over the last 30 minutes")
            }
            .foregroundStyle(Halo.textDim)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing) {
                    Text(topLabel)
                    Spacer()
                    Text(bottomLabel)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 50, alignment: .trailing)
                HistoryChart(values: history, color: color, maxValue: maxValue)
            }
            .frame(maxHeight: .infinity)
            
            xAxis
        }
    }
    
    private func paddedHistory(_ buffer: [Double]) -> [Double?] {
        let missing = 900 - buffer.count
        if missing <= 0 { return buffer.map { $0 } }
        let padding: [Double?] = Array(repeating: nil, count: missing)
        return padding + buffer.map { $0 }
    }
}
