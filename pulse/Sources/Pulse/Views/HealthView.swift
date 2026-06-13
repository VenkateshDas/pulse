import PulseKit
import SwiftUI

/// Health module (M6): battery state + 60-day capacity trend, startup
/// items (launch agents) with next-login toggles, and on-demand
/// micro-benchmarks.
struct HealthView: View {
    @Environment(HealthModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            BatteryCard()
                .frame(height: 120)
            if !model.batteryUnavailable {
                CapacityTrendCard()
                    .frame(height: 130)
            }
            HStack(alignment: .top, spacing: 16) {
                StartupItemsCard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.batteryUnavailable {
                    BatteryConsumptionCard()
                        .frame(maxWidth: 320, maxHeight: .infinity)
                }
            }
            BenchmarkCard()
                .frame(height: 180) // A bit taller to fit baselines
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear { model.appeared() }
        .onDisappear { model.disappeared() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Health")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Halo.textPrimary)
            Text(
                "Battery condition with a 60-day capacity trend, what launches at login, and repeatable speed benchmarks. Login items beyond launch agents need private Apple APIs to list — Pulse shows only what it can truthfully read."
            )
            .font(.system(size: 12))
            .foregroundStyle(Halo.textDim)
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
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
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

        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading, spacing: 12
        ) {
            fact(
                "CAPACITY", "\(battery.capacityPercent)% of design",
                battery.capacityPercent >= 80 ? Halo.textPrimary : Halo.amber)
            fact("CYCLES", "\(battery.cycleCount)", Halo.textPrimary)
            fact(
                "CONDITION", battery.condition,
                battery.condition == "Normal" ? Halo.pulseGreen : Halo.amber)
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

// MARK: - Capacity Trend Card

/// 60-day battery capacity (% of design) degradation trend — one reading per
/// day from BatteryHistoryStore. The y-axis is a tight band around the data so
/// a few points of drift are visible; gaps render honestly (no interpolation).
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

            if readings.count < 2 {
                Text("Collecting — one reading per day builds the trend over time.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Tight band: floor a few points below the minimum so small
                // degradation is legible without distorting the zero baseline.
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Battery Consumption Card

private struct BatteryConsumptionCard: View {
    @Environment(DashboardModel.self) private var dashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BATTERY CONSUMPTION (DAILY)")
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
                        // Show most recent days first
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
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(for entry: BatteryHistoryStore.Entry) -> some View {
        HStack {
            Text(formatDate(entry.date))
                .font(.system(size: 12))
                .foregroundStyle(Halo.textPrimary)
            Spacer()
            let hours = entry.timeOnBattery / 3600.0
            Text(String(format: "%.1f hrs", hours))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Halo.ion)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
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
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
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
                
                // Baselines context
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
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
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

    /// Benchmarks jitter a few percent run to run; color only real moves.
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
