import PulseKit
import SwiftUI

struct HealthView: View {
    @Environment(HealthModel.self) private var model
    @Environment(DashboardModel.self) private var dashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Halo.Space.lg) {
                header

                // Summary row: overall score beside live battery state.
                HStack(alignment: .top, spacing: Halo.Space.lg) {
                    HealthScoreCard()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !model.batteryUnavailable {
                        BatteryCard()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 200)

                if !model.batteryUnavailable {
                    // Battery over time: 60-day capacity trend beside daily use.
                    HStack(alignment: .top, spacing: Halo.Space.lg) {
                        batteryTrendCard
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        BatteryConsumptionCard()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 175)

                    // Which apps cost the most battery this week — rollup of
                    // the per-session shares below.
                    BatteryDrainCard()

                    // Per-session detail (unplug window, charge drop, app energy).
                    BatterySessionsCard()
                }

                // Bluetooth peripherals: a slim full-width strip.
                if !model.bluetoothDevices.isEmpty {
                    BluetoothCard()
                        .frame(height: 90)
                }

                // Startup agents: full width so the ITEM/KIND/STATUS columns breathe.
                // Grows with its content; the page scrolls, the card doesn't.
                StartupItemsCard()

                BenchmarkCard()
                    .frame(height: 180)
            }
            .padding(Halo.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear { model.appeared() }
        .onDisappear { model.disappeared() }
    }

    /// 60-day capacity trend once there are ≥2 daily readings; otherwise the
    /// collecting-state stat card.
    @ViewBuilder
    private var batteryTrendCard: some View {
        let readings = dashboardModel.batteryTrend.compactMap { $0.capacityPercent }
        if readings.count >= 2 {
            CapacityTrendCard()
        } else {
            BatteryStatsCard()
        }
    }

    private var header: some View {
        PageHeader(
            "Health",
            subtitle: "Battery, startup agents, and repeatable performance benchmarks."
        ) {
            // Battery/bluetooth re-sample every 5s on their own — startup
            // items are the cached bit worth a manual refresh.
            RefreshButton(help: "Refresh startup items") {
                model.refreshStartupItems()
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Health score card (F1 breakdown)

/// Unified weighted score with per-factor "points lost" bars. Reads the live
/// HealthScore the DashboardModel computes each sample.
private struct HealthScoreCard: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        let score = model.healthScore
        // Largest contributor first; only factors that actually cost points.
        let factors = score.breakdown
            .filter { $0.value > 0.05 }
            .sorted { $0.value > $1.value }

        return HStack(alignment: .center, spacing: 24) {
            VStack(spacing: 6) {
                HealthScoreRing(score: score, diameter: 96, labelMode: .scoreOnly)
                Text(model.diagnosis.line)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
            }
            .frame(width: 150)

            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT'S COSTING YOU")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.textDim)
                if factors.isEmpty {
                    Text("Nothing — every metric is in the green.")
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                } else {
                    ForEach(factors, id: \.key) { factor, lost in
                        factorRow(factor, lost: lost)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .premiumCard(padding: 0)
        
    }

    private func factorRow(_ factor: HealthFactor, lost: Double) -> some View {
        // Bar fills relative to the worst-case the factor can cost (its weight).
        let fraction = min(1, lost / factor.weight)
        return HStack(spacing: 10) {
            Text(factor.label)
                .font(.system(size: 11))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 60, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Halo.surface2)
                    Capsule()
                        .fill(fraction > 0.66 ? Halo.flare : (fraction > 0.33 ? Halo.amber : Halo.ion))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text(String(format: "−%.0f pts", lost))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - Battery card

private struct BatteryCard: View {
    @Environment(HealthModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BATTERY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Halo.textDim)

            if let battery = model.battery {
                detail(battery)
            } else {
                Text(model.batteryUnavailable ? "No battery — desktop Mac" : "Reading battery…")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    @ViewBuilder
    private func detail(_ battery: BatteryHealth) -> some View {
        HStack(spacing: 14) {
            chargeBar(battery)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(battery.currentChargePercent)%")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(Halo.textPrimary)
                    Text(stateText(battery))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(stateColor(battery))
                }
                if let event = eventText(battery) {
                    Text(event)
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textDim)
                }
            }
            Spacer()
        }

        // 6-fact grid: row 1 = capacity / cycles / condition; row 2 = power / cycles left / thermal
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
            fact("CAPACITY", "\(battery.capacityPercent)% of design",
                 battery.capacityPercent >= 80 ? Halo.textPrimary : Halo.amber)
            fact("CYCLES", "\(battery.cycleCount)", Halo.textPrimary)
            fact("CONDITION", battery.condition,
                 battery.condition == "Normal" ? Halo.pulseGreen : Halo.amber)

            // |InstantAmperage| × Voltage measures battery current in either
            // direction — while charging it's power INTO the battery, not the
            // machine's consumption, so label it as such.
            let powerLabel = battery.isCharging ? "CHARGING AT" : "POWER DRAW"
            if let watts = battery.powerWatts {
                fact(powerLabel, String(format: "%.1f W", watts),
                     battery.isCharging ? Halo.pulseGreen : Halo.ion)
            } else {
                fact(powerLabel, "—", Halo.textDim)
            }
            let left = battery.cyclesRemaining
            fact("CYCLES LEFT", "\(left)",
                 left > 500 ? Halo.pulseGreen : left > 150 ? Halo.amber : Halo.flare)
            thermalFact()
        }
    }

    private func chargeBar(_ battery: BatteryHealth) -> some View {
        let fraction = Double(battery.currentChargePercent) / 100
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Halo.surface2)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 6)
                    .fill(chargeColor(battery))
                    .frame(width: max(geo.size.width * fraction, 6))
            }
            if battery.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Halo.void)
                    .padding(.leading, 8)
            }
        }
        .frame(width: 120, height: 28)
    }

    private func chargeColor(_ battery: BatteryHealth) -> Color {
        if battery.currentChargePercent <= 10, !battery.isCharging { return Halo.flare }
        if battery.isCharging { return Halo.pulseGreen }
        return Halo.ion
    }

    private func stateText(_ battery: BatteryHealth) -> String {
        if battery.isCharging { return "CHARGING" }
        if battery.isOnAC { return "ON AC" }
        return "ON BATTERY"
    }

    private func stateColor(_ battery: BatteryHealth) -> Color {
        battery.isCharging ? Halo.pulseGreen : Halo.textDim
    }

    private func eventText(_ battery: BatteryHealth) -> String? {
        guard let seconds = battery.timeToEvent else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let span = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        return battery.isCharging ? "~\(span) to full" : "~\(span) remaining"
    }

    @ViewBuilder
    private func thermalFact() -> some View {
        let state = ProcessInfo.processInfo.thermalState
        let (label, color): (String, Color) = switch state {
        case .nominal: ("Nominal", Halo.pulseGreen)
        case .fair: ("Fair", Halo.amber)
        case .serious: ("Serious", Halo.flare)
        case .critical: ("Critical!", Halo.flare)
        @unknown default: ("Unknown", Halo.textDim)
        }
        fact("THERMAL", label, color)
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
                // Half-width card → narrow columns; keep long values like
                // "Service Recommended" on one line by scaling down a touch.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Bluetooth Card

private struct BluetoothCard: View {
    @Environment(HealthModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BLUETOOTH PERIPHERALS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Halo.textDim)

            HStack(spacing: 20) {
                ForEach(model.bluetoothDevices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: "b.square.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Halo.ion)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Halo.textPrimary)
                                .lineLimit(1)
                            
                            if let battery = device.batteryPercent {
                                Text("\(battery)%")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(battery > 20 ? Halo.pulseGreen : Halo.flare)
                            } else {
                                Text("3rd party · connection only")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Halo.textDim.opacity(0.8))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }
}

// MARK: - Battery Stats Card (shown while the 60-day trend is still collecting)

private struct BatteryStatsCard: View {
    @Environment(HealthModel.self) private var model
    @Environment(DashboardModel.self) private var dashboardModel

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            statBlock(
                icon: "bolt.heart.fill",
                title: "CAPACITY HEALTH",
                value: model.battery.map { "\($0.capacityPercent)%" } ?? "—",
                subtitle: model.battery.map {
                    $0.capacityPercent >= 80 ? "Within normal range" : "Below Apple threshold"
                } ?? "",
                color: capacityColor
            )
            divider
            statBlock(
                icon: "arrow.clockwise.circle.fill",
                title: "CYCLE HEALTH",
                value: model.battery.map { "\($0.cyclesRemaining)" } ?? "—",
                subtitle: model.battery.map {
                    "cycles remaining · \($0.cycleCount) of 1000 used"
                } ?? "",
                color: cyclesColor
            )
            divider
            statBlock(
                icon: "chart.line.uptrend.xyaxis",
                title: "CAPACITY TREND",
                value: "Collecting",
                subtitle: "1 reading/day · builds over 60 days",
                color: Halo.textDim
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var divider: some View {
        Rectangle()
            .fill(Halo.surface2)
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private var capacityColor: Color {
        guard let b = model.battery else { return Halo.textDim }
        return b.capacityPercent >= 80 ? Halo.pulseGreen : Halo.amber
    }

    private var cyclesColor: Color {
        guard let b = model.battery else { return Halo.textDim }
        return b.cyclesRemaining > 500 ? Halo.pulseGreen : b.cyclesRemaining > 150 ? Halo.amber : Halo.flare
    }

    private func statBlock(icon: String, title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Capacity Trend Card

private struct CapacityTrendCard: View {
    @Environment(DashboardModel.self) private var dashboardModel

    var body: some View {
        let readings = dashboardModel.batteryTrend.compactMap { $0.capacityPercent }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("BATTERY CAPACITY · 60-DAY TREND")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if let latest = readings.last {
                    Text("\(latest)% of design")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(latest >= 80 ? Halo.pulseGreen : Halo.amber)
                }
            }

            // Adaptive window: pad ±2% around the observed range (capped at
            // 100%) so a near-flat trend uses the plot area instead of hugging
            // the floor. Honest — both axis labels reflect the real bounds.
            let minReading = readings.min() ?? 0
            let maxReading = readings.max() ?? 100
            let floorValue = Double(max(0, minReading - 2))
            let ceilValue = Double(min(100, maxReading + 2))
            let scale = max(ceilValue - floorValue, 1)
            let series: [Double?] = dashboardModel.batteryTrend.map { entry in
                entry.capacityPercent.map { Double($0) - floorValue }
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing) {
                    Text("\(Int(ceilValue))%")
                    Spacer()
                    Text("\(Int(floorValue))%")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 40, alignment: .trailing)
                HistoryChart(values: series, color: Halo.volt, maxValue: scale)
            }
            .padding(.vertical, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }
}

// MARK: - Battery Consumption Card

private struct BatteryConsumptionCard: View {
    @Environment(DashboardModel.self) private var dashboardModel
    /// Days of daily-use bars shown at a glance. A compact bar chart instead
    /// of a scrolling list keeps this card to a single (page-level) scroll.
    private static let dayWindow = 14

    private var recent: [BatteryHistoryStore.Entry] {
        Array(dashboardModel.batteryTrend.suffix(Self.dayWindow))
    }

    var body: some View {
        // Scale to the busiest day in view, with an 8h floor so a light week
        // doesn't exaggerate tiny bars.
        let maxHours = recent.map { $0.timeOnBattery / 3600 }.max() ?? 0
        let scaleMax = Swift.max(maxHours.rounded(.up), 8)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("BATTERY USE · DAILY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if let today = recent.last, Calendar.current.isDateInToday(today.date) {
                    Text(String(format: "%.1f h today", today.timeOnBattery / 3600))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hoursColor(today.timeOnBattery / 3600))
                }
            }

            if recent.isEmpty {
                Text("No data yet. Using on battery will populate this.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart(scaleMax: scaleMax)
                axis
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func chart(scaleMax: Double) -> some View {
        GeometryReader { geo in
            // Reserve a row for the value label so bars never clip it.
            let labelHeight: CGFloat = 13
            let barMax = max(geo.size.height - labelHeight, 8)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(recent) { entry in
                    let hours = entry.timeOnBattery / 3600
                    let fraction = min(hours / scaleMax, 1)
                    VStack(spacing: 2) {
                        Text(hours >= 0.05 ? String(format: "%.1f", hours) : "")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(hoursColor(hours))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barGradient(hours))
                            .frame(height: max(barMax * fraction, 3))
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .help(tooltip(for: entry, hours: hours))
                    .accessibilityLabel(
                        "\(formatDate(entry.date)): \(String(format: "%.1f", hours)) hours on battery")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxHeight: .infinity)
    }

    /// Top-lit gradient so the bars read with depth rather than as flat blocks.
    private func barGradient(_ hours: Double) -> LinearGradient {
        let base = hoursColor(hours)
        return LinearGradient(
            colors: [base, base.opacity(0.55)],
            startPoint: .top, endPoint: .bottom)
    }

    private var axis: some View {
        HStack {
            if let first = recent.first { Text(formatDate(first.date)) }
            Spacer()
            if recent.count > 1, let last = recent.last { Text(formatDate(last.date)) }
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(Halo.textDim)
    }

    private func hoursColor(_ hours: Double) -> Color {
        hours >= 8 ? Halo.pulseGreen : hours >= 4 ? Halo.ion : Halo.textDim
    }

    /// Hover detail: "Jun 14 · 5.2 h on battery · 9:00am–6:00pm".
    private func tooltip(for entry: BatteryHistoryStore.Entry, hours: Double) -> String {
        var parts = ["\(formatDate(entry.date)) · \(String(format: "%.1f", hours)) h on battery"]
        if let first = entry.firstActiveAt, let last = entry.lastActiveAt {
            parts.append("\(formatTime(first))–\(formatTime(last))")
        }
        return parts.joined(separator: " · ")
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yest" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "am"; formatter.pmSymbol = "pm"
        return formatter.string(from: date)
    }
}

// MARK: - Battery Drain Card (7-day cross-session app attribution)

private struct BatteryDrainCard: View {
    @Environment(DashboardModel.self) private var dashboardModel

    private var consumers: [BatteryAttribution] {
        BatteryAttributionEngine.topConsumers(
            sessions: dashboardModel.batterySessions,
            since: Date.now.addingTimeInterval(-7 * 24 * 3600))
    }

    var body: some View {
        let items = consumers
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TOP ENERGY CONSUMERS · 7 DAYS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text("share of tracked on-battery drain · approx")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim.opacity(0.7))
            }

            if items.isEmpty {
                Text("No on-battery app data in the last 7 days. Unplug and use the Mac to populate this.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 8)
            } else {
                let maxFraction = items.map(\.fraction).max() ?? 1
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, index: index, maxFraction: maxFraction)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func row(_ item: BatteryAttribution, index: Int, maxFraction: Double) -> some View {
        let isOther = item.name == "Other"
        let color =
            isOther
            ? Halo.textDim.opacity(0.5)
            : BatterySessionsCard.palette[index % BatterySessionsCard.palette.count]
        return HStack(spacing: 10) {
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOther ? Halo.textDim : Halo.textPrimary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(color)
                    .frame(width: max(3, geo.size.width * item.fraction / maxFraction))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 6)
            Text(String(format: "%.0f%% of drain", item.fraction * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 90, alignment: .trailing)
        }
    }
}

// MARK: - Battery Sessions Card (per-session charge drop + per-app energy share)

private struct BatterySessionsCard: View {
    @Environment(DashboardModel.self) private var dashboardModel
    @State private var expanded: Set<UUID> = []
    @State private var showAllSessions = false

    /// Rows rendered by default. Every row costs a full layout pass (bars,
    /// legend grid), so keep the initial page light; "Show all" opts in.
    private static let sessionLimit = 10

    /// Segment colors for the stacked share bar; "Other" always renders dim.
    /// Shared with BatteryDrainCard so the same rank gets the same hue.
    static let palette: [Color] = [
        Halo.ion, Halo.volt, Halo.tealLight, Halo.amber,
        Halo.pulseGreen, Halo.flare, Halo.teal, Halo.tealDeep,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("BATTERY SESSIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text("energy = share of active compute · approx")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim.opacity(0.7))
            }

            if dashboardModel.batterySessions.isEmpty {
                Text("No unplugged sessions in the last 60 days. Run on battery and each unplug will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 8)
            } else {
                let all = Array(dashboardModel.batterySessions.reversed())
                let visible = showAllSessions ? all : Array(all.prefix(Self.sessionLimit))
                LazyVStack(spacing: 6) {
                    ForEach(dayGroups(visible), id: \.day) { group in
                        dayHeader(group)
                        ForEach(group.sessions) { session in
                            sessionRow(session)
                        }
                    }
                }
                if all.count > Self.sessionLimit {
                    Button(
                        showAllSessions
                            ? "Show recent \(Self.sessionLimit)"
                            : "Show all \(all.count) sessions"
                    ) {
                        showAllSessions.toggle()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Halo.ion)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
        .onAppear {
            // The live session is what you opened the page for — start it open.
            if let live = dashboardModel.batterySessions.last, live.isLive {
                expanded.insert(live.id)
            }
        }
    }

    /// Consecutive sessions bucketed by calendar day, preserving newest-first
    /// order. Input is already sorted, so a single pass suffices.
    private func dayGroups(_ sessions: [BatterySession])
        -> [(day: Date, sessions: [BatterySession])]
    {
        let cal = Calendar.current
        var groups: [(day: Date, sessions: [BatterySession])] = []
        for session in sessions {
            let day = cal.startOfDay(for: session.startedAt)
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].sessions.append(session)
            } else {
                groups.append((day, [session]))
            }
        }
        return groups
    }

    private func dayHeader(_ group: (day: Date, sessions: [BatterySession])) -> some View {
        let drop = group.sessions.reduce(0) { $0 + $1.chargeDrop }
        let count = group.sessions.count
        return HStack(alignment: .firstTextBaseline) {
            Text(dayLabel(group.day))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            Spacer()
            Text("−\(drop)% · \(count) session\(count == 1 ? "" : "s")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func sessionRow(_ session: BatterySession) -> some View {
        let shares = session.shares
        // Backfilled sessions carry no app data — nothing to expand into.
        let expandable = !shares.isEmpty || session.isLive
        let isExpanded = expandable && expanded.contains(session.id)
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if isExpanded { expanded.remove(session.id) } else { expanded.insert(session.id) }
            } label: {
                collapsedLine(session, shares: shares, expandable: expandable, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)
            .disabled(!expandable)

            if isExpanded {
                // Charge depletion: full bar = startCharge, filled portion =
                // what remained at the end; the dim tail is what drained.
                chargeBar(session)
                if !shares.isEmpty {
                    shareBar(shares)
                    legend(shares)
                } else {
                    Text("Measuring app activity…")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    /// The always-visible one-liner: time window, badges, screen on/off,
    /// top app, charge drop.
    private func collapsedLine(
        _ session: BatterySession,
        shares: [(app: AppEnergyShare, fraction: Double)],
        expandable: Bool, isExpanded: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if expandable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Halo.textDim)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            Text(windowText(session))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
            if session.isLive {
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Halo.pulseGreen)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Halo.pulseGreen.opacity(0.15), in: Capsule())
            }
            if session.isBackfilled {
                Text("pmset")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim.opacity(0.7))
            }
            if (session.screenOnSeconds ?? 0) > 0 || (session.screenOffSeconds ?? 0) > 0 {
                screenGlyphs(on: session.screenOnSeconds ?? 0, off: session.screenOffSeconds ?? 0)
            }
            Spacer(minLength: 8)
            if let top = shares.first {
                Text(top.app.name)
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            Text("−\(session.chargeDrop)%")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(dropColor(session.chargeDrop))
            Text("\(session.startCharge)→\(session.endCharge)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
        .contentShape(Rectangle())
    }

    /// Horizontal charge gauge: solid up to the end charge, a dimmed segment for
    /// the drop, over a faint track to 100%.
    private func chargeBar(_ session: BatterySession) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let endFrac = min(max(Double(session.endCharge) / 100, 0), 1)
            let startFrac = min(max(Double(session.startCharge) / 100, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Halo.surface2)
                Capsule()
                    .fill(dropColor(session.chargeDrop).opacity(0.25))
                    .frame(width: w * startFrac)
                Capsule()
                    .fill(Halo.ion)
                    .frame(width: w * endFrac)
            }
        }
        .frame(height: 4)
    }

    private func shareBar(_ shares: [(app: AppEnergyShare, fraction: Double)]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                // Index-keyed: app.id is the name, and a duplicate name must
                // never corrupt the layout.
                ForEach(Array(shares.enumerated()), id: \.offset) { index, entry in
                    Rectangle()
                        .fill(color(for: entry.app.name, index: index))
                        .frame(width: max(geo.size.width * entry.fraction - 1, 0))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 8)
    }

    @ViewBuilder
    private func legend(_ shares: [(app: AppEnergyShare, fraction: Double)]) -> some View {
        // Two-column grid keeps long app names readable at any window width.
        // Shares are already capped to top-N + "Other", so show them all.
        let cols = [GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
            ForEach(Array(shares.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: entry.app.name, index: index))
                        .frame(width: 7, height: 7)
                    Text(entry.app.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text("\(Int((entry.fraction * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                }
            }
        }
    }

    private func color(for name: String, index: Int) -> Color {
        name == "Other" ? Halo.textDim.opacity(0.5) : Self.palette[index % Self.palette.count]
    }

    /// Compact screen on/off durations for the collapsed line.
    private func screenGlyphs(on: TimeInterval, off: TimeInterval) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "display").font(.system(size: 8))
                Text(Self.shortDuration(on))
            }
            .foregroundStyle(Halo.ion)
            if off > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "moon.fill").font(.system(size: 8))
                    Text(Self.shortDuration(off))
                }
                .foregroundStyle(Halo.textDim)
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
    }

    private static func shortDuration(_ s: TimeInterval) -> String {
        let mins = Int(s) / 60
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins)m"
    }

    private func dropColor(_ drop: Int) -> Color {
        drop >= 40 ? Halo.flare : drop >= 20 ? Halo.amber : Halo.textPrimary
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private func windowText(_ session: BatterySession) -> String {
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        time.amSymbol = "am"; time.pmSymbol = "pm"
        let start = time.string(from: session.startedAt)
        let mins = Int(session.duration() / 60)
        let dur = mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"

        guard !session.isLive, let endedAt = session.endedAt else {
            return "\(start) – now · \(dur)"
        }
        // Prefix the end with its date when the session crossed midnight, so an
        // overnight unplug doesn't read like it ended earlier the same day.
        let sameDay = Calendar.current.isDate(session.startedAt, inSameDayAs: endedAt)
        var end = time.string(from: endedAt)
        if !sameDay {
            let day = DateFormatter()
            day.dateFormat = "MMM d"
            end = "\(day.string(from: endedAt)) \(end)"
        }
        return "\(start) – \(end) · \(dur)"
    }
}

// MARK: - Startup items card

private struct StartupItemsCard: View {
    @Environment(HealthModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("STARTUP ITEMS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("\(model.startupItems.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.ion)
                Spacer()
                if let feedback = model.actionFeedback {
                    FeedbackBadge(message: feedback)
                }
            }

            columnHeader

            if model.startupItems.isEmpty {
                Text("No launch agents installed")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                // No inner ScrollView — the card grows with its rows and the
                // page is the single scroll surface (avoids nested scrolling).
                LazyVStack(spacing: 2) {
                    ForEach(model.startupItems) { item in
                        StartupItemRow(item: item) { model.toggle(item) }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("ITEM").frame(maxWidth: .infinity, alignment: .leading)
            Text("KIND").frame(width: 110, alignment: .leading)
            Text("STATUS").frame(width: 76, alignment: .leading)
            Text("").frame(width: 60)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1)
        .foregroundStyle(Halo.textDim)
        .padding(.horizontal, 8)
    }
}

private struct StartupItemRow: View {
    let item: StartupItem
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let program = item.program {
                    Text(program)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Halo.textDim.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.kind == .userAgent ? "Launch Agent" : "Global Agent")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 110, alignment: .leading)

            HStack(spacing: 4) {
                Circle()
                    .fill(item.isEnabled ? Halo.pulseGreen : Halo.textDim.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(item.isEnabled ? "Enabled" : "Disabled")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(item.isEnabled ? Halo.textPrimary : Halo.textDim)
            }
            .frame(width: 76, alignment: .leading)

            if item.kind == .userAgent {
                Button(action: toggle) {
                    Text(item.isEnabled ? "Off" : "On")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(item.isEnabled ? Halo.flare : Halo.pulseGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            (item.isEnabled ? Halo.flare : Halo.pulseGreen).opacity(0.12),
                            in: Capsule())
                }
                .buttonStyle(.plain)
                .help(
                    item.isEnabled
                        ? "Disable — renames the plist; applies at next login"
                        : "Enable — restores the plist; applies at next login")
                .frame(width: 60)
            } else {
                Image(systemName: "lock")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim.opacity(0.6))
                    .help("System-wide agent — changing it needs admin rights")
                    .frame(width: 60)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

// MARK: - Benchmark card

private struct BenchmarkCard: View {
    @Environment(HealthModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PERFORMANCE BENCHMARK")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text("CPU: SHA256 5s · Disk: 50 MB write · Memory: 256 MB copy")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Halo.textDim.opacity(0.8))
            }

            HStack(alignment: .center, spacing: 24) {
                runButton

                if let result = model.latestBenchmark {
                    scoreBlock(result)
                    Divider().overlay(Halo.surface2).frame(height: 48)
                    fact("CPU HASH", String(format: "%.0f MB/s", result.cpuHashMBps))
                    fact("DISK WRITE", String(format: "%.0f MB/s", result.diskWriteMBps))
                    fact("MEM COPY", String(format: "%.1f GB/s", result.memCopyGBps))
                } else if !model.benchmarkRunning {
                    Text("No runs yet — results persist across launches")
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textDim)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    baselineFact("GOOD", "> 1000", "M1+ Class", color: Halo.pulseGreen)
                    baselineFact("FAIR", "500-1000", "Older Intel", color: Halo.amber)
                    baselineFact("LOW", "< 500", "Thermal Throttling", color: Halo.flare)
                }
                .padding(.leading, 16)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var runButton: some View {
        Button {
            model.runBenchmark()
        } label: {
            HStack(spacing: 6) {
                if model.benchmarkRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(model.benchmarkRunning ? "Running…" : "Run Benchmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(model.benchmarkRunning ? Halo.textDim : Halo.void)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                model.benchmarkRunning ? AnyShapeStyle(Halo.surface2) : AnyShapeStyle(Halo.ion),
                in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.benchmarkRunning)
        .help("~8 seconds; the CPU phase loads one core on purpose")
    }

    @ViewBuilder
    private func scoreBlock(_ result: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SCORE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(result.score)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Halo.ion)
                if let previous = model.previousBenchmark, previous.score > 0 {
                    let delta = result.score - previous.score
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(deltaColor(delta, baseline: previous.score))
                        .help("vs previous run (\(previous.score))")
                }
            }
            Text(result.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim.opacity(0.8))
        }
        .help("1000 ≈ base M1 — average of the three phases against fixed reference speeds")
    }

    private func deltaColor(_ delta: Int, baseline: Int) -> Color {
        let fraction = Double(delta) / Double(baseline)
        if fraction <= -0.10 { return Halo.amber }
        if fraction >= 0.10 { return Halo.pulseGreen }
        return Halo.textDim
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
        }
    }

    private func baselineFact(_ label: String, _ score: String, _ desc: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 45, alignment: .leading)
            Text(score)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 60, alignment: .leading)
            Text(desc)
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
        }
    }
}
