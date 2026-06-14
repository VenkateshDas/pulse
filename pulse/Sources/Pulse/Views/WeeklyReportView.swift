import AppKit
import PulseKit
import SwiftUI

/// Weekly Pulse Report: a glanceable summary of the last 7 days — space
/// reclaimed, cleans run, current vitals — plus a copyable share card. The
/// retention surface for a one-time purchase; the share card is organic reach.
struct WeeklyReportView: View {
    @Binding var isPresented: Bool
    @Environment(DashboardModel.self) private var model
    @Environment(CleanModel.self) private var clean

    /// Notification name any surface can post to open this report.
    static let showNotification = Notification.Name("PulseShowWeeklyReport")

    private var weekRecords: [CleanRecord] {
        let cutoff = Date.now.addingTimeInterval(-7 * 86400)
        return clean.history.filter { $0.date >= cutoff }
    }
    private var bytesFreed: UInt64 { weekRecords.reduce(0) { $0 + $1.bytesFreed } }
    private var itemsCleaned: Int { weekRecords.reduce(0) { $0 + $1.itemsCleaned } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Pulse")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Halo.textPrimary)
                    Text(weekRangeText)
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Halo.textDim)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                stat(ByteFormat.string(bytesFreed), "reclaimed", Halo.pulseGreen)
                stat("\(weekRecords.count)", "cleans run", Halo.ion)
                stat("\(itemsCleaned)", "items staged", Halo.volt)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("CURRENT VITALS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                vitalLine("Disk free", ByteFormat.string(model.snapshot?.diskFreeBytes ?? 0))
                if let weekly = model.snapshot?.diskWeeklyGrowthBytes {
                    let sign = weekly >= 0 ? "−" : "+"
                    vitalLine("Disk trend", "\(sign)\(ByteFormat.string(UInt64(abs(weekly)))) this week")
                }
                if let cap = model.batteryTrend.compactMap(\.capacityPercent).last {
                    vitalLine("Battery health", "\(cap)% of design")
                }
                vitalLine("Reclaimable now", ByteFormat.string(clean.previewTotalBytes))
            }
            .padding(16)
            .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 0)

            HStack {
                Button {
                    let card = shareCardText
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card, forType: .string)
                } label: {
                    Label("Copy Share Card", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .tint(Halo.ion)
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Halo.pulseGreen)
            }
        }
        .padding(28)
        .frame(width: 540, height: 560)
        .background(Halo.void)
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Halo.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func vitalLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
        }
    }

    private var weekRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = Date.now.addingTimeInterval(-7 * 86400)
        return "\(formatter.string(from: start)) – \(formatter.string(from: .now))"
    }

    private var shareCardText: String {
        """
        🩺 My week with Pulse (\(weekRangeText))
        • \(ByteFormat.string(bytesFreed)) reclaimed across \(weekRecords.count) clean\(weekRecords.count == 1 ? "" : "s")
        • \(itemsCleaned) items staged safely (all restorable)
        • Disk free: \(ByteFormat.string(model.snapshot?.diskFreeBytes ?? 0))
        """
    }
}
