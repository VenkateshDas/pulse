import AppKit
import PulseKit
import SwiftUI

/// Compact popover shown from the menu bar item: live vitals with 30s
/// sparklines, top processes, the 7-day disk delta, and quick actions
/// (Open Command Center, Quick Clean, Empty Trash).
struct MenuBarContent: View {
    @Environment(DashboardModel.self) private var model
    @Environment(CleanModel.self) private var clean
    @Environment(StorageModel.self) private var storage
    @Environment(\.openWindow) private var openWindow

    /// 30s ≈ 15 two-second samples — the popover's sparkline window.
    private static let sparkSamples = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hud
            if let snapshot = model.snapshot {
                metricRow(
                    "CPU", String(format: "%.0f%%", snapshot.cpuTotalPercent),
                    fraction: snapshot.cpuTotalPercent / 100,
                    spark: model.cpuHistory)
                metricRow(
                    "Memory", ByteFormat.string(snapshot.memoryUsedBytes),
                    fraction: snapshot.memoryUsedFraction,
                    spark: model.memoryHistory)
                diskRow(snapshot)
                Divider().overlay(Halo.surface2)
                topProcesses(snapshot)
            } else {
                Text("Sampling…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }

            Divider().overlay(Halo.surface2)
            actions
        }
        .onAppear {
            model.viewAppeared()
            storage.refreshTrashInfo()
        }
        .onDisappear { model.viewDisappeared() }
        .padding(14)
        .frame(width: 280)
        .background(Halo.void)
    }

    // MARK: HUD (live verdict + score)

    private var hud: some View {
        HStack(spacing: 10) {
            HealthScoreRing(score: model.healthScore, diameter: 44, lineWidth: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.diagnosis.line)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Health \(model.healthScore.value) · \(model.healthScore.band.rawValue)")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer()
        }
    }

    // MARK: Metric rows

    private func metricRow(_ label: String, _ value: String, fraction: Double, spark: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
            }
            HStack(spacing: 6) {
                bar(fraction)
                if spark.count >= 2 {
                    Sparkline(values: Array(spark.suffix(Self.sparkSamples)))
                        .frame(width: 60, height: 14)
                }
            }
        }
    }

    private func diskRow(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Disk free")
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text(ByteFormat.string(snapshot.diskFreeBytes))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
            }
            bar(snapshot.diskUsedFraction)
            if let weekly = snapshot.diskWeeklyGrowthBytes {
                let sign = weekly >= 0 ? "−" : "+"  // growth shrinks free space
                Text("\(sign)\(ByteFormat.string(UInt64(abs(weekly)))) this week")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(weekly >= 0 ? Halo.amber : Halo.pulseGreen)
            }
        }
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Halo.surface2)
                Capsule()
                    .fill(Halo.statusColor(fraction))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }

    // MARK: Top processes

    @ViewBuilder
    private func topProcesses(_ snapshot: SystemSnapshot) -> some View {
        let top = Array(snapshot.topProcesses.prefix(3))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOP PROCESSES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.textDim)
                ForEach(top) { proc in
                    HStack(spacing: 8) {
                        Text(proc.name)
                            .font(.system(size: 11))
                            .foregroundStyle(Halo.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.0f%%", proc.cpuPercent))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Halo.ion)
                            .frame(width: 38, alignment: .trailing)
                        Text(ByteFormat.string(proc.residentBytes))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Command Center", systemImage: "rectangle.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Halo.ion.opacity(0.8))

            HStack(spacing: 8) {
                Button {
                    clean.runNow()
                } label: {
                    Label(clean.isRunning ? "Cleaning…" : "Quick Clean", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .tint(Halo.pulseGreen)
                .disabled(clean.isRunning)

                Button {
                    storage.emptyTrash()
                } label: {
                    Label(trashLabel, systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .tint(Halo.amber)
                .disabled(storage.trashItemCount == 0 || storage.isCleaning)
            }

            if let report = clean.report {
                Text(report)
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.pulseGreen)
                    .lineLimit(2)
            }

            menuBarMetricChooser

            if Updater.shared.isAvailable {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.ion)
                    .frame(maxWidth: .infinity)
            }

            Button("Quit Pulse") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Halo.textDim)
            .frame(maxWidth: .infinity)
        }
    }

    /// Lets the user pick which metrics the menu-bar label shows.
    private var menuBarMetricChooser: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MENU BAR SHOWS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            HStack(spacing: 6) {
                ForEach(MenuBarMetric.allCases) { metric in
                    let on = model.menuBarMetrics.contains(metric)
                    Button {
                        if on { model.menuBarMetrics.remove(metric) }
                        else { model.menuBarMetrics.insert(metric) }
                    } label: {
                        Image(systemName: metric.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(on ? Halo.void : Halo.textDim)
                            .frame(width: 26, height: 22)
                            .background(
                                on ? AnyShapeStyle(Halo.ion) : AnyShapeStyle(Halo.surface2),
                                in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(metric.label)
                }
            }
        }
    }

    private var trashLabel: String {
        storage.trashItemCount > 0
            ? "Trash · \(ByteFormat.string(storage.trashBytes))"
            : "Trash empty"
    }
}
