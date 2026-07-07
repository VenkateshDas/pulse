import PulseKit
import SwiftUI

/// Joined per-day record: disk snapshot + battery session.
private struct DayEntry: Identifiable {
    let date: Date
    let diskTotalBytes: UInt64?
    let diskDeltaBytes: Int64?
    let categories: [String: UInt64]
    let batteryHours: Double?
    let firstActiveAt: Date?
    let lastActiveAt: Date?
    let batteryCapacity: Int?
    var id: Date { date }
    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var isSpike: Bool { abs(diskDeltaBytes ?? 0) >= 2_000_000_000 }
}

struct TimelineView: View {
    @Environment(TimelineModel.self) private var model
    @Environment(StorageModel.self) private var storage
    @Environment(DashboardModel.self) private var dashboard
    @Environment(HealthModel.self) private var healthModel

    static let navigateToClean = Notification.Name("PulseNavigateToClean")

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    weekSummaryCard
                    sectionLabel("DAILY HISTORY · NEWEST FIRST")
                    todayCard
                    if !pastEntries.isEmpty {
                        pastDaysCard
                    }
                    if model.snapshots.count >= 7 {
                        diskTrendCard
                    }
                    if let latest = model.snapshots.last, !latest.categories.isEmpty {
                        categoryCard(latest)
                    }
                    if !dashboard.recentAnomalies.isEmpty {
                        sectionLabel("PROCESS ANOMALIES · SUSTAINED CPU")
                        anomalyCard
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear { model.recordToday(scan: storage.scan) }
    }

    // MARK: - Header

    private var header: some View {
        PageHeader(
            "Timeline",
            subtitle: "Your Mac's daily health record — disk growth, battery sessions, and notable events."
        )
        .padding(.bottom, 4)
    }

    // MARK: - Process anomalies (F5)

    private var anomalyCard: some View {
        let items = Array(dashboard.recentAnomalies.prefix(20))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { anomaly in
                HStack(spacing: 10) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.amber)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(anomaly.processName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Halo.textPrimary)
                        Text("\(Int(anomaly.cpuPercent))% CPU for \(Int(anomaly.sustainedSeconds / 60)) min · pid \(anomaly.pid)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                    }
                    Spacer()
                    Text(anomaly.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.vertical, 8)
                if anomaly.id != items.last?.id {
                    Rectangle().fill(Halo.borderSubtle).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .premiumCard(padding: 0)
        
    }

    // MARK: - Data join

    /// All daily entries (disk + battery) sorted newest first, today excluded.
    private var pastEntries: [DayEntry] { allEntries.filter { !$0.isToday } }

    private var allEntries: [DayEntry] {
        var batteryByDay: [Date: BatteryHistoryStore.Entry] = [:]
        for e in dashboard.batteryTrend { batteryByDay[e.date] = e }

        // Build delta map from consecutive disk snapshots
        var deltaByDay: [Date: Int64] = [:]
        let deltas = model.deltas
        for d in deltas { deltaByDay[d.date] = d.deltaBytes }

        // Union all dates
        var allDates = Set(model.snapshots.map { $0.date })
        allDates.formUnion(batteryByDay.keys)

        return allDates.sorted(by: >).map { date in
            let snap = model.snapshots.first { $0.date == date }
            let bat = batteryByDay[date]
            return DayEntry(
                date: date,
                diskTotalBytes: snap?.totalUsedBytes,
                diskDeltaBytes: deltaByDay[date],
                categories: snap?.categories ?? [:],
                batteryHours: bat.map { $0.timeOnBattery / 3600 },
                firstActiveAt: bat?.firstActiveAt,
                lastActiveAt: bat?.lastActiveAt,
                batteryCapacity: bat?.capacityPercent
            )
        }
    }

    // MARK: - Week summary card

    private var weekSummaryCard: some View {
        let cutoff = Calendar.current.startOfDay(
            for: Date.now.addingTimeInterval(-7 * 86400))
        let weekBattery = dashboard.batteryTrend
            .filter { $0.date >= cutoff }
            .reduce(0.0) { $0 + $1.timeOnBattery / 3600 }
        let avgBattery = dashboard.batteryTrend.filter { $0.date >= cutoff }.isEmpty
            ? nil : weekBattery / 7.0
        let weekDisk = model.weeklyDeltaBytes

        return VStack(alignment: .leading, spacing: 12) {
            Text("PAST 7 DAYS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Halo.textDim)

            HStack(spacing: 10) {
                summaryCell(
                    label: "Disk grew",
                    value: weekDisk == 0
                        ? "—"
                        : "\(weekDisk > 0 ? "+" : "−")\(ByteFormat.string(UInt64(abs(weekDisk))))",
                    color: weekDisk > 0 ? Halo.amber : Halo.pulseGreen
                )
                summaryCell(
                    label: "On battery",
                    value: weekBattery > 0 ? String(format: "%.1f h", weekBattery) : "—",
                    color: Halo.ion
                )
                summaryCell(
                    label: "Avg/day",
                    value: avgBattery.map { String(format: "%.1f h", $0) } ?? "—",
                    color: Halo.textPrimary
                )
                if let bench = healthModel.latestBenchmark {
                    summaryCell(
                        label: "Benchmark",
                        value: "\(bench.score)",
                        color: bench.score >= 1000 ? Halo.pulseGreen : bench.score >= 500 ? Halo.amber : Halo.flare
                    )
                } else {
                    summaryCell(label: "Benchmark", value: "—", color: Halo.textDim)
                }
            }
        }
        .padding(16)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func summaryCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Today card

    @ViewBuilder
    private var todayCard: some View {
        let snap = dashboard.snapshot
        let diskUsed = snap.map { $0.diskTotalBytes - $0.diskFreeBytes }
        let todayBat = dashboard.batteryTrend.first {
            Calendar.current.isDateInToday($0.date)
        }
        let todayBench = healthModel.benchmarkHistory.last {
            Calendar.current.isDateInToday($0.date)
        }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(todayDateString())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Spacer()
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.ion)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Halo.ion.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 0) {
                todayMetric(
                    label: "DISK",
                    value: diskUsed.map { ByteFormat.string($0) } ?? "—",
                    sub: model.deltas.last.map { deltaSub($0.deltaBytes) },
                    color: diskDeltaColor(model.deltas.last?.deltaBytes ?? 0)
                )
                metricDivider
                todayMetric(
                    label: "BATTERY",
                    value: todayBat.map { String(format: "%.1f h", $0.timeOnBattery / 3600) } ?? "—",
                    sub: batteryWindowSub(todayBat),
                    color: Halo.ion
                )
                metricDivider
                todayMetric(
                    label: "SYSTEM",
                    value: snap.map { uptimeString($0.uptime) } ?? "—",
                    sub: snap.map { _ in "uptime" },
                    color: Halo.textPrimary
                )
            }

            if let bench = todayBench {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                    Text("Benchmark run today — score \(bench.score)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                    Spacer()
                    Text(bench.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Halo.textDim.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Halo.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Halo.ion.opacity(0.2), lineWidth: 1)
        )
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Halo.surface2)
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private func todayMetric(label: String, value: String, sub: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            if let sub {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            } else {
                Text(" ")
                    .font(.system(size: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }

    // MARK: - Past days card

    private var pastDaysCard: some View {
        let maxDelta = pastEntries.compactMap { $0.diskDeltaBytes }.map { abs($0) }.max() ?? 1

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PAST DAYS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text("disk · battery")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Halo.textDim.opacity(0.6))
            }
            .padding(.bottom, 10)

            ForEach(Array(pastEntries.prefix(14))) { entry in
                pastDayRow(entry, maxDelta: maxDelta)
            }
        }
        .padding(16)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func pastDayRow(_ entry: DayEntry, maxDelta: Int64) -> some View {
        let delta = entry.diskDeltaBytes ?? 0
        let fraction = maxDelta > 0 ? min(Double(abs(delta)) / Double(maxDelta), 1.0) : 0
        let grew = delta >= 0
        let isSpike = abs(delta) >= 2_000_000_000

        return VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(pastDateString(entry.date))
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
                    .frame(width: 72, alignment: .leading)

                if let delta = entry.diskDeltaBytes {
                    Text(deltaSub(delta))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(diskDeltaColor(delta))
                        .frame(width: 88, alignment: .leading)
                } else {
                    Text("—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                        .frame(width: 88, alignment: .leading)
                }

                if isSpike {
                    Text("SPIKE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Halo.flare)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Halo.flare.opacity(0.12), in: Capsule())
                }

                Spacer()

                // Battery
                if let hours = entry.batteryHours {
                    HStack(spacing: 4) {
                        if let first = entry.firstActiveAt, let last = entry.lastActiveAt {
                            Text("\(formatTime(first)) – \(formatTime(last))")
                                .font(.system(size: 10))
                                .foregroundStyle(Halo.textDim.opacity(0.7))
                        }
                        Text(String(format: "%.1f h", hours))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Halo.ion)
                    }
                } else {
                    Text("no battery data")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim.opacity(0.5))
                }
            }

            // Delta bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(grew ? Halo.amber.opacity(0.5) : Halo.pulseGreen.opacity(0.5))
                        .frame(width: geo.size.width * fraction, height: 2)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 2)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Halo.surface2.opacity(0.5))
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSpike {
                NotificationCenter.default.post(name: Self.navigateToClean, object: nil)
            }
        }
    }

    // MARK: - Disk trend chart (7+ days only)

    private var diskTrendCard: some View {
        let total = dashboard.snapshot?.diskTotalBytes ?? 0
        let series: [Double?] = model.snapshots.map { Double($0.totalUsedBytes) }
        let scale = total > 0 ? Double(total) : (series.compactMap { $0 }.max() ?? 1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DISK USED · \(model.snapshots.count)-DAY TREND")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if let last = model.snapshots.last {
                    Text(ByteFormat.string(last.totalUsedBytes))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Halo.ion)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing) {
                    Text(ByteFormat.string(UInt64(scale)))
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 56, alignment: .trailing)
                HistoryChart(values: series, color: Halo.ion, maxValue: scale)
            }
            .frame(height: 90)
        }
        .padding(16)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    // MARK: - Category breakdown

    private func categoryCard(_ snapshot: TimelineSnapshot) -> some View {
        let sorted = snapshot.categories.sorted { $0.value > $1.value }.prefix(8)
        let maxBytes = sorted.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("WHAT'S USING SPACE · LATEST SCAN")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Halo.textDim)
            ForEach(Array(sorted), id: \.key) { name, bytes in
                HStack(spacing: 10) {
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textPrimary)
                        .frame(width: 130, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        Capsule()
                            .fill(Halo.volt)
                            .frame(width: geo.size.width * (Double(bytes) / Double(maxBytes)))
                    }
                    .frame(height: 8)
                    Text(ByteFormat.string(bytes))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                        .frame(width: 76, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Halo.textDim.opacity(0.7))
    }

    private func deltaSub(_ delta: Int64) -> String {
        // Arrow already carries the direction — no redundant +/− sign.
        "\(delta >= 0 ? "▲" : "▼") \(ByteFormat.string(UInt64(abs(delta))))"
    }

    private func diskDeltaColor(_ delta: Int64) -> Color {
        if delta == 0 { return Halo.textDim }
        return delta > 0 ? Halo.amber : Halo.pulseGreen
    }

    private func batteryWindowSub(_ entry: BatteryHistoryStore.Entry?) -> String? {
        guard let entry,
              let first = entry.firstActiveAt,
              let last = entry.lastActiveAt
        else { return nil }
        return "\(formatTime(first)) – \(formatTime(last))"
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date)
    }

    private func uptimeString(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h"
    }

    private func todayDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private func pastDateString(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date)
    }
}
