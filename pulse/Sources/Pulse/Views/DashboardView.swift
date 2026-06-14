import PulseKit
import SwiftUI

/// Main command-center content: greeting, vitals row, Cause→Fix alerts,
/// CPU chart and top processes.
struct DashboardView: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        // No ScrollView: the layout is designed to fit the window's minimum
        // size, and the bottom row stretches to absorb extra height.
        VStack(alignment: .leading, spacing: 16) {
            greeting
            vitals
            AlertsSection()
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    chartsPanel
                    CoreHeatmap(cpuPerCore: model.snapshot?.cpuPerCore ?? [])
                }
                .frame(maxHeight: .infinity)
                
                TopProcessesPanel(processes: model.snapshot?.topProcesses ?? [])
                    .frame(width: 400)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(timeGreeting), \(firstName)")
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundStyle(Halo.textPrimary)
            Text(statusLine)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(Halo.textDim)
        }
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
        return "\(health) · \(attention) · sampling live every 2s"
    }

    // MARK: Vitals

    private var vitals: some View {
        HStack(spacing: 12) {
            cpuCard
            memoryCard
            diskCard
            thermalCard
        }
    }

    private var cpuCard: some View {
        let snapshot = model.snapshot
        let total = snapshot?.cpuTotalPercent ?? 0
        // Fixed-width formats keep text intrinsic size constant between
        // samples, so value changes redraw without relaying out the window.
        let split: String
        if let e = snapshot?.cpuEfficiencyPercent, let p = snapshot?.cpuPerformancePercent {
            split = String(format: "E %2d%% · P %2d%%", Int(e), Int(p))
        } else {
            split = "\(snapshot?.cpuPerCore.count ?? 0) cores"
        }
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
            line1: split,
            line2: String(format: "load %5.2f", snapshot?.loadAverage1m ?? 0),
            history: model.cpuHistory,
            cardTooltip: cpuTooltip,
            stats: cpuStats
        )
    }

    private var memoryCard: some View {
        let snapshot = model.snapshot
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

        let segments = [
            VitalCard.Segment(start: 0, end: appF, color: Halo.ion),
            VitalCard.Segment(start: appF, end: appF + wiredF, color: Halo.volt),
            VitalCard.Segment(start: appF + wiredF, end: appF + wiredF + compF, color: Halo.pulseGreen)
        ]

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

        let legend = [
            VitalCard.LegendItem(color: Halo.ion, label: "App"),
            VitalCard.LegendItem(color: Halo.volt, label: "Wired"),
            VitalCard.LegendItem(color: Halo.pulseGreen, label: "Comp")
        ]

        return VitalCard(
            title: "MEMORY",
            fraction: snapshot?.memoryUsedFraction ?? 0,
            ringColor: pressureColor,
            value: String(format: "%2d%%", Int((snapshot?.memoryUsedFraction ?? 0) * 100)),
            line1: "U: \(ByteFormat.string(memUsed)) · F: \(ByteFormat.string(memFree))",
            line2: "Swap \(ByteFormat.string(snapshot?.swapUsedBytes ?? 0))\(pressureStr)",
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
                line2: "no SMC sensors found",
                history: model.loadHistory,
                historyScale: 10
            )
        }

        // Ring maps 20–110 °C; color thresholds follow Apple Silicon
        // norms (sustained >90 °C is throttling territory).
        let color: Color = hottest < 70 ? Halo.volt : (hottest < 90 ? Halo.amber : Halo.flare)
        let line1 = [
            sensors.cpuTempC.map { String(format: "CPU %2.0f°", $0) },
            sensors.gpuTempC.map { String(format: "GPU %2.0f°", $0) },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

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
        let headroom = max(0, 90 - hottest)
        var thermalStats: [VitalCard.Stat] = [
            .init(
                label: "HEADROOM", value: String(format: "%.0f°", headroom),
                color: headroom < 10 ? Halo.flare : (headroom < 25 ? Halo.amber : nil))
        ]
        if model.tempHistory.count >= 6 {
            let recent = model.tempHistory.suffix(6)
            let delta = (recent.last ?? 0) - (recent.first ?? 0)
            let trend = delta > 2 ? "rising" : (delta < -2 ? "falling" : "steady")
            thermalStats.append(
                .init(label: "TREND", value: trend, color: delta > 2 ? Halo.amber : nil))
        }

        return VitalCard(
            title: "THERMAL",
            fraction: min(max((hottest - 20) / 90, 0), 1),
            ringColor: color,
            value: String(format: "%2.0f°", hottest),
            line1: line1,
            line2: parts.joined(separator: " · "),
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

            cpuDayChartRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Halo.border, lineWidth: 1)
        )
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
                    .help("Network throughput over the last 30 minutes (Blue = In, Orange = Out)")
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
                    HistoryChart(values: paddedHistory(model.networkInHistory), color: Halo.ion, maxValue: maxValue)
                    HistoryChart(values: paddedHistory(model.networkOutHistory), color: Halo.flare, maxValue: maxValue)
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
