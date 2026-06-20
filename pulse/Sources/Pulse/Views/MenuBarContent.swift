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
    @Environment(Updater.self) private var updater
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
                thermalRow(snapshot)
                if let battery = snapshot.battery {
                    batteryRow(battery)
                }
                Divider().overlay(Halo.borderSubtle)
                topProcesses(snapshot)
            } else {
                Text("Sampling…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }

            Divider().overlay(Halo.borderSubtle)
            actions
        }
        .onAppear {
            model.viewAppeared()
            storage.refreshTrashInfo()
            updater.checkForUpdates()  // throttled background check
        }
        .onDisappear { model.viewDisappeared() }
        .padding(14)
        .frame(width: 280)
        .background(Halo.void)
    }

    // MARK: HUD (live verdict + score)

    private var hud: some View {
        HStack(spacing: 10) {
            HealthScoreRing(score: model.healthScore, diameter: 44, lineWidth: 5, labelMode: .scoreOnly)
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
                    .foregroundStyle(Halo.textSecondary)
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
                Text("\(ByteFormat.string(snapshot.diskFreeBytes)) / \(ByteFormat.string(snapshot.diskTotalBytes))")
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

    /// Temperature + thermal-pressure state. Shows the SMC reading when this
    /// Mac exposes one; otherwise falls back to the kernel thermal level word.
    private func thermalRow(_ snapshot: SystemSnapshot) -> some View {
        let temp = [snapshot.sensors.cpuTempC, snapshot.sensors.gpuTempC]
            .compactMap { $0 }.max()
        let value = temp.map { String(format: "%.0f°C · ", $0) } ?? ""
        return infoRow(
            "Thermal",
            value + thermalText(snapshot.thermal),
            color: thermalColor(snapshot.thermal))
    }

    private func batteryRow(_ battery: BatteryHealth) -> some View {
        let state = battery.isCharging ? "Charging"
            : (battery.isOnAC ? "On AC" : "On battery")
        return infoRow(
            "Battery",
            "\(battery.currentChargePercent)% · \(state)",
            color: Halo.textPrimary)
    }

    /// Compact label/value row (no bar/sparkline) for the secondary metrics.
    private func infoRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Halo.textDim)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func thermalText(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    private func thermalColor(_ level: ThermalLevel) -> Color {
        switch level {
        case .nominal: Halo.pulseGreen
        case .fair: Halo.ion
        case .serious: Halo.amber
        case .critical: Halo.flare
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

            updateRow

            Button("Quit Pulse") {
                // The one true exit. Cmd-Q only closes the window (stays in the
                // menu bar); this actually terminates Pulse.
                AppActivation.shared.quit()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Halo.textDim)
            .frame(maxWidth: .infinity)
        }
    }

    /// Update nudge / "Check for Updates…" control. Shows a prominent download
    /// button when a newer GitHub release exists, otherwise a quiet check link.
    @ViewBuilder private var updateRow: some View {
        switch updater.status {
        case .available(let release):
            Button {
                updater.openLatestDownload()
            } label: {
                Label("Update available · v\(release.version)", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(Halo.ion)
        case .checking:
            Text("Checking for updates…")
                .font(.system(size: 11))
                .foregroundStyle(Halo.textDim)
                .frame(maxWidth: .infinity)
        default:
            Button(updateLinkLabel) { updater.checkForUpdates(userInitiated: true) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(updater.status == .failed ? Halo.amber : Halo.ion)
                .frame(maxWidth: .infinity)
        }
    }

    private var updateLinkLabel: String {
        switch updater.status {
        case .upToDate: return "You're up to date · v\(updater.currentVersion)"
        case .failed:   return "Update check failed — retry"
        default:        return "Check for Updates…"
        }
    }

    private var trashLabel: String {
        storage.trashItemCount > 0
            ? "Trash · \(ByteFormat.string(storage.trashBytes))"
            : "Trash empty"
    }
}
