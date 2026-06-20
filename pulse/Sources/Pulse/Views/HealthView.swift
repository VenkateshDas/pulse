import PulseKit
import SwiftUI

struct HealthView: View {
    @Environment(HealthModel.self) private var model
    @Environment(DashboardModel.self) private var dashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            HealthScoreCard()
                .frame(height: 150)
            BatteryCard()
                .frame(height: 185)
            if !model.bluetoothDevices.isEmpty {
                BluetoothCard()
                    .frame(height: 90)
            }
            if !model.batteryUnavailable {
                let readings = dashboardModel.batteryTrend.compactMap { $0.capacityPercent }
                if readings.count >= 2 {
                    CapacityTrendCard()
                        .frame(height: 130)
                } else {
                    BatteryStatsCard()
                        .frame(height: 100)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                StartupItemsCard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.batteryUnavailable {
                    BatteryConsumptionCard()
                        .frame(maxWidth: 340, maxHeight: .infinity)
                }
            }
            BenchmarkCard()
                .frame(height: 180)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear { model.appeared() }
        .onDisappear { model.disappeared() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Health")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Halo.textPrimary)
            Text("Battery, startup agents, and repeatable performance benchmarks.")
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
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

            if let watts = battery.powerWatts {
                fact("POWER DRAW", String(format: "%.1f W", watts), Halo.ion)
            } else {
                fact("POWER DRAW", "—", Halo.textDim)
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

            let minReading = readings.min() ?? 0
            let floorValue = Double(max(0, minReading - 3))
            let scale = 100.0 - floorValue
            let series: [Double?] = dashboardModel.batteryTrend.map { entry in
                entry.capacityPercent.map { Double($0) - floorValue }
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing) {
                    Text("100%")
                    Spacer()
                    Text("\(Int(floorValue))%")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 44, alignment: .trailing)
                HistoryChart(values: series, color: Halo.volt, maxValue: scale)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }
}

// MARK: - Battery Consumption Card

private struct BatteryConsumptionCard: View {
    @Environment(DashboardModel.self) private var dashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BATTERY USE · DAILY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Halo.textDim)

            if dashboardModel.batteryTrend.isEmpty {
                Text("No data yet. Using on battery will populate this list.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(dashboardModel.batteryTrend.reversed()) { entry in
                            row(for: entry)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func row(for entry: BatteryHistoryStore.Entry) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(formatDate(entry.date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Halo.textPrimary)
                    .frame(width: 70, alignment: .leading)

                Spacer()

                // Time-of-day window (e.g. "9:00 AM – 11:30 PM")
                if let first = entry.firstActiveAt, let last = entry.lastActiveAt {
                    Text("\(formatTime(first)) – \(formatTime(last))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                }

                let hours = entry.timeOnBattery / 3600.0
                Text(String(format: "%.1f h", hours))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(hoursColor(hours))
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            // Thin usage bar proportional to 12h max
            GeometryReader { geo in
                let fraction = min(entry.timeOnBattery / (12 * 3600), 1.0)
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Halo.ion.opacity(0.4))
                        .frame(width: geo.size.width * fraction, height: 2)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 10)
        }
        .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 8))
    }

    private func hoursColor(_ hours: Double) -> Color {
        hours >= 8 ? Halo.pulseGreen : hours >= 4 ? Halo.ion : Halo.textDim
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter.string(from: date)
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
                    Text(feedback)
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.pulseGreen)
                }
            }

            columnHeader

            if model.startupItems.isEmpty {
                Text("No launch agents installed")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.startupItems) { item in
                            StartupItemRow(item: item) { model.toggle(item) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    baselineFact("BAD", "500-1000", "Older Intel", color: Halo.amber)
                    baselineFact("WORSE", "< 500", "Thermal Throttling", color: Halo.flare)
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
