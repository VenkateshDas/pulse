import PulseKit
import SwiftUI

/// Storage Timeline (spec §3.7): daily disk-usage history with a category
/// breakdown and a spike drill — "what ate my disk this week?" Records one
/// snapshot per day; gaps render honestly. A spike day links to Clean.
struct TimelineView: View {
    @Environment(TimelineModel.self) private var model
    @Environment(StorageModel.self) private var storage
    @Environment(DashboardModel.self) private var dashboard

    /// Posted to ask RootView to switch to the Clean section.
    static let navigateToClean = Notification.Name("PulseNavigateToClean")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    trendCard
                    deltaCard
                    breakdownCard
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear { model.recordToday(scan: storage.scan) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Timeline")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Halo.textPrimary)
            Text("How your disk usage changed over time. One snapshot per day — open a full Storage scan to capture the per-category breakdown.")
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
        }
    }

    // MARK: Trend

    private var trendCard: some View {
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
            if series.count < 2 {
                Text("Collecting — the trend builds one day at a time. Check back tomorrow.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 20)
            } else {
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
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Daily deltas + spike drill

    private var deltaCard: some View {
        let deltas = Array(model.deltas.suffix(14)).reversed()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DAILY CHANGE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if model.weeklyDeltaBytes != 0 {
                    let grew = model.weeklyDeltaBytes > 0
                    Text("\(grew ? "+" : "−")\(ByteFormat.string(UInt64(abs(model.weeklyDeltaBytes)))) this week")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(grew ? Halo.amber : Halo.pulseGreen)
                }
            }
            if deltas.isEmpty {
                Text("No day-over-day data yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(deltas), id: \.date) { entry in
                    deltaRow(entry.date, entry.deltaBytes)
                }
            }
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func deltaRow(_ date: Date, _ delta: Int64) -> some View {
        let grew = delta > 0
        let isSpike = delta >= TimelineModel.spikeThreshold
        return HStack(spacing: 12) {
            Text(Self.dateText(date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 60, alignment: .leading)
            if isSpike {
                Text("SPIKE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Halo.flare)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Halo.flare.opacity(0.12), in: Capsule())
            }
            Spacer()
            Text("\(grew ? "+" : "−")\(ByteFormat.string(UInt64(abs(delta))))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(delta == 0 ? Halo.textDim : (grew ? Halo.amber : Halo.pulseGreen))
            if isSpike {
                Button("Review in Clean") {
                    NotificationCenter.default.post(name: Self.navigateToClean, object: nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Halo.ion)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Halo.ion.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Category breakdown (latest day)

    @ViewBuilder
    private var breakdownCard: some View {
        if let latest = model.snapshots.last, !latest.categories.isEmpty {
            let sorted = latest.categories.sorted { $0.value > $1.value }.prefix(8)
            let maxBytes = sorted.first?.value ?? 1
            VStack(alignment: .leading, spacing: 10) {
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
            .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
