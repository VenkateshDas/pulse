import PulseKit
import SwiftUI

struct HealthView: View {
    enum Scope { case battery, startup, benchmark }
    var scope: Scope = .battery
    @Environment(HealthModel.self) private var model
    @Environment(DashboardModel.self) private var dashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Halo.Space.lg) {
                header

                if scope == .battery {
                    if model.batteryUnavailable {
                        EmptyState(icon: "desktopcomputer", title: "This Mac has no battery reading",
                                   hint: "Desktop Macs do not have an internal battery. Available connected-device batteries appear below.")
                    } else {
                        BatteryCard()
                        BatteryLevelCard().frame(minHeight: 170)
                        BatteryDrainCard()
                        DisclosureGroup("Battery history and details") {
                            VStack(spacing: Halo.Space.lg) {
                                batteryTrendCard
                                BatteryConsumptionCard()
                                BatterySessionsCard()
                            }.padding(.top, 12)
                        }
                    }
                    if !model.bluetoothDevices.isEmpty { BluetoothCard() }
                    DisclosureGroup("Overall condition details") { HealthScoreCard().padding(.top, 12) }

                }
                if scope == .startup {
                // Startup agents: full width so the ITEM/KIND/STATUS columns breathe.
                // Grows with its content; the page scrolls, the card doesn't.
                StartupItemsCard()

                }
                if scope == .benchmark {
                BenchmarkCard()
                    .frame(minHeight: 180)
                }
            }
            .padding(Halo.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Halo.void)
        .onAppear {
            if scope == .battery { model.appeared() }
            if scope == .startup { model.refreshStartupItems() }
        }
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
            scope == .battery ? "Battery & energy" : (scope == .startup ? "Startup helpers" : "Performance test"),
            subtitle: scope == .battery ? "Understand your battery and how your Mac uses energy." : (scope == .startup ? "Review background helpers that start when you sign in." : "Measure processor, memory and storage performance. Close other busy apps for a fair comparison.")
        ) {
            // Battery/bluetooth re-sample every 5s on their own — startup
            // items are the cached bit worth a manual refresh.
            if scope == .startup {
                RefreshButton(help: "Refresh startup helpers") { model.refreshStartupItems() }
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
                    .font(Halo.font(size: 11, weight: .medium))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
            }
            .frame(width: 150)

            VStack(alignment: .leading, spacing: 10) {
                Text("Factors in the estimated score")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                if factors.isEmpty {
                    Text("No factors are currently reducing this estimated score.")
                        .font(Halo.font(size: 12))
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
                .font(Halo.font(size: 11))
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
                .font(Halo.font(size: 10, design: .monospaced))
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
            Text("Current charge")
                .font(Halo.font(size: 10, weight: .semibold))
                .foregroundStyle(Halo.textDim)

            if let battery = model.battery {
                detail(battery)
            } else {
                Text(model.batteryUnavailable ? "No battery — desktop Mac" : "Reading battery…")
                    .font(Halo.font(size: 12))
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
                        .font(Halo.font(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(Halo.textPrimary)
                    Text(stateText(battery))
                        .font(Halo.font(size: 11, weight: .semibold))
                        .foregroundStyle(stateColor(battery))
                }
                if let event = eventText(battery) {
                    Text(event)
                        .font(Halo.font(size: 11))
                        .foregroundStyle(Halo.textDim)
                }
            }
            Spacer()
        }

        Text("Battery condition: \(battery.condition)")
            .font(Halo.font(size: 14, weight: .medium))
        DisclosureGroup("Battery hardware details") {
            let cols = [GridItem(.adaptive(minimum: 160), alignment: .leading)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 14) {
                fact("Maximum capacity", "\(battery.capacityPercent)% of original capacity", Halo.textPrimary)
                fact("Charge cycles", "\(battery.cycleCount)", Halo.textPrimary)
                if let watts = battery.powerWatts {
                    fact(battery.isCharging ? "Charging power" : "Battery power use",
                         String(format: "%.1f W", watts), Halo.textPrimary)
                }
                thermalFact()
            }.padding(.top, 10)
            Text("Battery life estimates change with your work. A charge cycle is cumulative use of a full battery, not a count of plugs or a fixed expiry date.")
                .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
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
                    .font(Halo.font(size: 11, weight: .bold))
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
        if battery.isCharging { return "Charging" }
        if battery.isOnAC { return "Connected to power" }
        return "Using battery"
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
                .font(Halo.font(size: 9, weight: .semibold))
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(Halo.font(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                // Half-width card → narrow columns; keep long values like
                // "Service Recommended" on one line by scaling down a touch.
                .lineLimit(1)
        }
    }
}

// MARK: - Bluetooth Card

private struct BluetoothCard: View {
    @Environment(HealthModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BLUETOOTH PERIPHERALS")
                .font(Halo.font(size: 10, weight: .semibold))
                .foregroundStyle(Halo.textDim)

            HStack(spacing: 20) {
                ForEach(model.bluetoothDevices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: "b.square.fill")
                            .font(Halo.font(size: 16))
                            .foregroundStyle(Halo.ion)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(Halo.font(size: 11, weight: .semibold))
                                .foregroundStyle(Halo.textPrimary)
                                .lineLimit(1)

                            if let battery = device.batteryPercent {
                                Text("\(battery)%")
                                    .font(Halo.font(size: 10, design: .monospaced))
                                    .foregroundStyle(battery > 20 ? Halo.pulseGreen : Halo.flare)
                            } else {
                                Text("3rd party · connection only")
                                    .font(Halo.font(size: 9))
                                    .foregroundStyle(Halo.textDim)
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
                    .font(Halo.font(size: 10))
                    .foregroundStyle(color)
                Text(title)
                    .font(Halo.font(size: 9, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
            }
            Text(value)
                .font(Halo.font(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(subtitle)
                .font(Halo.font(size: 10))
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
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if let latest = readings.last {
                    Text("\(latest)% of design")
                        .font(Halo.font(size: 11, weight: .semibold, design: .monospaced))
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
                .font(Halo.font(size: 9, design: .monospaced))
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
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if let today = recent.last, Calendar.current.isDateInToday(today.date) {
                    Text(String(format: "%.1f h today", today.timeOnBattery / 3600))
                        .font(Halo.font(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hoursColor(today.timeOnBattery / 3600))
                }
            }

            if recent.isEmpty {
                Text("No data yet. Using on battery will populate this.")
                    .font(Halo.font(size: 12))
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
                            .font(Halo.font(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(hoursColor(hours))
                            .lineLimit(1)
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
        .font(Halo.font(size: 9, design: .monospaced))
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
                Text("Estimated app energy use · 7 days")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text("Estimate based on processor activity")
                    .font(Halo.font(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }

            Text("Pulse estimates each app’s share using processor activity during recorded battery sessions. It does not directly measure an app’s power use; display, graphics and other hardware also consume energy.")
                .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
            if items.isEmpty {
                Text("No on-battery app data in the last 7 days. Unplug and use the Mac to populate this.")
                    .font(Halo.font(size: 12))
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
                .font(Halo.font(size: 12, weight: .medium))
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
            .accessibilityHidden(true)
            Text(String(format: "~%.0f%% share", item.fraction * 100))
                .font(Halo.font(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 110, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Battery Level Card (24h intraday % curve with charging bands)

private struct BatteryLevelCard: View {
    @Environment(DashboardModel.self) private var dashboardModel

    var body: some View {
        let series = dashboardModel.batteryDayHistory
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery level · 24 hours")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill").font(Halo.font(size: 7))
                    Text("charging")
                }
                .font(Halo.font(size: 9, design: .monospaced))
                .foregroundStyle(Halo.pulseGreen.opacity(0.8))
            }

            if series.contains(where: { $0 != nil }) {
                ZStack {
                    chargingBands
                    HistoryChart(values: series, color: Halo.pulseGreen, maxValue: 100)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery level history over 24 hours")
                .accessibilityValue(batteryChartSummary(series))
                HStack {
                    Text("24h ago")
                    Spacer()
                    Text("12h")
                    Spacer()
                    Text("now")
                }
                .font(Halo.font(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
            } else {
                Text("Collecting battery levels — the curve fills in as Pulse runs.")
                    .font(Halo.font(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func batteryChartSummary(_ series: [Double?]) -> String {
        let values = series.compactMap { $0 }
        guard let low = values.min(), let high = values.max(), let last = values.last else { return "No recorded readings" }
        return String(format: "Recorded charge from %.0f to %.0f percent. Latest recorded charge %.0f percent. Gaps are periods without readings.", low, high, last)
    }

    /// Green shading behind the curve wherever a charge session overlaps the
    /// trailing 24h window. Gaps in sampling stay unshaded like the curve.
    private var chargingBands: some View {
        GeometryReader { geo in
            let now = Date.now
            let windowStart = now.addingTimeInterval(-24 * 3600)
            let windows = chargeWindows(from: windowStart, to: now)
            ForEach(windows.indices, id: \.self) { index in
                let window = windows[index]
                let x0 = geo.size.width * window.start
                let x1 = geo.size.width * window.end
                Rectangle()
                    .fill(Halo.pulseGreen.opacity(0.12))
                    .frame(width: max(x1 - x0, 1))
                    .offset(x: x0)
            }
        }
    }

    /// Charge-session overlaps with the 24h window as 0–1 x-fractions.
    private func chargeWindows(from windowStart: Date, to now: Date)
        -> [(start: Double, end: Double)]
    {
        let span = now.timeIntervalSince(windowStart)
        return dashboardModel.batterySessions.compactMap { session in
            guard session.isCharge else { return nil }
            let start = max(session.startedAt, windowStart)
            let end = min(session.endedAt ?? now, now)
            guard end > start else { return nil }
            return (
                start.timeIntervalSince(windowStart) / span,
                end.timeIntervalSince(windowStart) / span
            )
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
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text("energy = share of active compute · approx")
                    .font(Halo.font(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }

            if dashboardModel.batterySessions.isEmpty {
                Text("No unplugged sessions in the last 60 days. Run on battery and each unplug will appear here.")
                    .font(Halo.font(size: 12))
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
                    .font(Halo.font(size: 10, weight: .medium))
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
        let gain = group.sessions.reduce(0) { $0 + $1.chargeGain }
        let count = group.sessions.count
        let parts = [drop > 0 ? "−\(drop)%" : nil, gain > 0 ? "+\(gain)%" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .firstTextBaseline) {
            Text(dayLabel(group.day))
                .font(Halo.font(size: 11, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            Spacer()
            Text("\(parts)\(parts.isEmpty ? "" : " · ")\(count) session\(count == 1 ? "" : "s")")
                .font(Halo.font(size: 10, design: .monospaced))
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
                    Text(session.isCharge ? "Charging…" : "Measuring app activity…")
                        .font(Halo.font(size: 10))
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
                    .font(Halo.font(size: 8, weight: .bold))
                    .foregroundStyle(Halo.textDim)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            if session.isCharge {
                Image(systemName: "bolt.fill")
                    .font(Halo.font(size: 9))
                    .foregroundStyle(Halo.pulseGreen)
            }
            Text(windowText(session))
                .font(Halo.font(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
            if session.isLive {
                Text("LIVE")
                    .font(Halo.font(size: 9, weight: .bold))
                    .foregroundStyle(Halo.pulseGreen)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Halo.pulseGreen.opacity(0.15), in: Capsule())
            }
            if session.isBackfilled {
                Text("pmset")
                    .font(Halo.font(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
            if (session.screenOnSeconds ?? 0) > 0 || (session.screenOffSeconds ?? 0) > 0 {
                screenGlyphs(on: session.screenOnSeconds ?? 0, off: session.screenOffSeconds ?? 0)
            }
            Spacer(minLength: 8)
            if let top = shares.first {
                Text(top.app.name)
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            if let rate = session.ratePerHour() {
                Text(String(format: "%+.1f%%/h", rate))
                    .font(Halo.font(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
            if session.isCharge {
                Text("+\(session.chargeGain)%")
                    .font(Halo.font(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Halo.pulseGreen)
            } else {
                Text("−\(session.chargeDrop)%")
                    .font(Halo.font(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(dropColor(session.chargeDrop))
            }
            Text("\(session.startCharge)→\(session.endCharge)")
                .font(Halo.font(size: 10, design: .monospaced))
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
                if session.isCharge {
                    // Charging: green segment is what the plug put back.
                    Capsule()
                        .fill(Halo.pulseGreen)
                        .frame(width: w * endFrac)
                    Capsule()
                        .fill(Halo.ion.opacity(0.5))
                        .frame(width: w * startFrac)
                } else {
                    Capsule()
                        .fill(dropColor(session.chargeDrop).opacity(0.25))
                        .frame(width: w * startFrac)
                    Capsule()
                        .fill(Halo.ion)
                        .frame(width: w * endFrac)
                }
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
                        .font(Halo.font(size: 11))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text("\(Int((entry.fraction * 100).rounded()))%")
                        .font(Halo.font(size: 11, weight: .semibold, design: .monospaced))
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
                Image(systemName: "display").font(Halo.font(size: 8))
                Text(Self.shortDuration(on))
            }
            .foregroundStyle(Halo.ion)
            if off > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "moon.fill").font(Halo.font(size: 8))
                    Text(Self.shortDuration(off))
                }
                .foregroundStyle(Halo.textDim)
            }
        }
        .font(Halo.font(size: 9, weight: .medium, design: .monospaced))
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

// MARK: - Startup helpers

private struct StartupItemsCard: View {
    @Environment(HealthModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Background helpers · \(model.startupItems.count)")
                .font(Halo.font(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("These are launch helpers, not a complete list of login apps. Changes take effect the next time you sign in; a helper already running may continue until then. You can turn a personal helper back on here.")
                .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
            if let feedback = model.actionFeedback {
                Text(feedback).font(Halo.font(size: 13))
                    .foregroundStyle(Halo.textPrimary)
                    .textSelection(.enabled)
            }
            if model.startupItems.isEmpty {
                Text("No helpers found in the checked LaunchAgents folders. Other login apps may appear in System Settings → General → Login Items & Extensions.")
                    .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(model.startupItems) { item in
                        StartupItemRow(item: item, changing: model.changingStartupItems.contains(item.id)) {
                            model.toggle(item)
                        }
                        if item.id != model.startupItems.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }
}

private struct StartupItemRow: View {
    let item: StartupItem
    let changing: Bool
    let toggle: () -> Void

    private var title: String {
        guard let program = item.program, let appEnd = program.range(of: ".app/") else { return item.label }
        return URL(fileURLWithPath: String(program[..<appEnd.lowerBound])).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.kind == .userAgent {
                Toggle(isOn: Binding(get: { item.isEnabled }, set: { _ in toggle() })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(Halo.font(size: 14, weight: .medium))
                        Text(changing ? "Applying change…" : "Start this helper when you sign in")
                            .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(changing)
                .accessibilityLabel("Start \(title) helper when you sign in")
                .accessibilityHint("Changes apply at next sign-in. This does not stop a running helper.")
            } else {
                Text(title).font(Halo.font(size: 14, weight: .medium))
                Label("Installed for everyone · \(item.isEnabled ? "enabled" : "disabled") · read only", systemImage: "lock")
                    .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                Text("Manage this helper through its app or macOS Login Items settings.")
                    .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
            }
            DisclosureGroup("Helper details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Identifier: \(item.label)")
                    if let program = item.program { Text("Program: \(program)") }
                    Text("Configuration: \(item.path)")
                }
                .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(Halo.font(size: 12))
        }
        .foregroundStyle(Halo.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Benchmark card

private struct BenchmarkCard: View {
    @Environment(HealthModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PERFORMANCE BENCHMARK")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text("CPU: SHA256 5s · Disk: 50 MB write · Memory: 256 MB copy")
                    .font(Halo.font(size: 10, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
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
                        .font(Halo.font(size: 11))
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
                        .font(Halo.font(size: 11, weight: .bold))
                }
                Text(model.benchmarkRunning ? "Running…" : "Run Benchmark")
                    .font(Halo.font(size: 11, weight: .bold))
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
                .font(Halo.font(size: 9, weight: .semibold))
                .foregroundStyle(Halo.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(result.score)")
                    .font(Halo.font(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Halo.ion)
                if let previous = model.previousBenchmark, previous.score > 0 {
                    let delta = result.score - previous.score
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .font(Halo.font(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(deltaColor(delta, baseline: previous.score))
                        .help("vs previous run (\(previous.score))")
                }
            }
            Text(result.date.formatted(date: .abbreviated, time: .shortened))
                .font(Halo.font(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
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
                .font(Halo.font(size: 9, weight: .semibold))
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(Halo.font(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
        }
    }

    private func baselineFact(_ label: String, _ score: String, _ desc: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(Halo.font(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 45, alignment: .leading)
            Text(score)
                .font(Halo.font(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 60, alignment: .leading)
            Text(desc)
                .font(Halo.font(size: 10))
                .foregroundStyle(Halo.textDim)
        }
    }
}
