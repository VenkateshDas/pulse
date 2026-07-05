import AppKit
import PulseKit
import SwiftUI

extension Notification.Name {
    static let navigateToOptimize = Notification.Name("PulseNavigateToOptimize")
}

/// Compact popover shown from the menu bar item: live vitals with 30s
/// sparklines, top processes, the 7-day disk delta, and quick actions
/// (Open Command Center, Quick Clean, Empty Trash).
struct MenuBarContent: View {
    @Environment(DashboardModel.self) private var model
    @Environment(CleanModel.self) private var clean
    @Environment(StorageModel.self) private var storage
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    @Environment(\.dismiss) private var dismiss
    @State private var isOptimizing = false
    @State private var optimizeReport: String?
    @State private var menuBarCollapsed = false
    @State private var confirmAttentionQuit: (pid: Int32, name: String)?

    /// 30s ≈ 15 two-second samples — the popover's sparkline window.
    private static let sparkSamples = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // HUD Card
                hud
                    .padding(12)
                    .background(Halo.surface1.opacity(0.6), in: RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous))

                // Vitals Card
                VStack(spacing: 8) {
                    if let snapshot = model.snapshot {
                        let cpuLabel = snapshot.gpuUsage.map { String(format: "%.0f%% · GPU %.0f%%", snapshot.cpuTotalPercent, $0.deviceUtilization) }
                            ?? String(format: "%.0f%%", snapshot.cpuTotalPercent)
                        metricRow(
                            "CPU", cpuLabel,
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
                    } else {
                        Text("Sampling…")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Halo.surface1.opacity(0.6), in: RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous))

                // Hardware Card
                if let snapshot = model.snapshot {
                    VStack(alignment: .leading, spacing: 10) {
                        DisplaysPopoverSection()
                        Divider().overlay(Halo.borderSubtle)
                        topProcesses(snapshot)
                    }
                    .padding(12)
                    .background(Halo.surface1.opacity(0.6), in: RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous))
                }

                // Controls Card
                VStack(spacing: 10) {
                    keepAwakeRow
                    Divider().overlay(Halo.borderSubtle)
                    menuBarManagerRow
                    Divider().overlay(Halo.borderSubtle)
                    actions
                }
                .padding(12)
                .background(Halo.surface1.opacity(0.6), in: RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous))
        }
        .padding(14)
        .onAppear {
            model.viewAppeared()
            storage.refreshTrashInfo()
            updater.checkForUpdates()  // throttled background check
        }
        .onDisappear { model.viewDisappeared() }
        .frame(width: 300)
        .background { GlassLayer(tint: Halo.void.opacity(0.4)) }
        .confirmationDialog(
            "Quit \(confirmAttentionQuit?.name ?? "")?",
            isPresented: Binding(
                get: { confirmAttentionQuit != nil },
                set: { if !$0 { confirmAttentionQuit = nil } }
            )
        ) {
            Button("Quit \(confirmAttentionQuit?.name ?? "")", role: .destructive) {
                if let target = confirmAttentionQuit {
                    model.quitProcess(pid: target.pid, name: target.name)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends a normal Quit signal. Unsaved work in that app may be lost.")
        }
    }

    // MARK: HUD (top attention item + score)

    private var topAttentionItem: AttentionItem? { model.attentionItems.first }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HealthScoreRing(score: model.healthScore, diameter: 44, lineWidth: 5, labelMode: .scoreOnly)
                VStack(alignment: .leading, spacing: 3) {
                    Text(topAttentionItem?.title ?? model.diagnosis.line)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("Health \(model.healthScore.value) · \(model.healthScore.band.rawValue)")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
                Spacer()
                Button {
                    dismiss()
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Halo.surface2, in: RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Command Center")
            }
            if let item = topAttentionItem {
                attentionRow(item)
            }
        }
    }

    @ViewBuilder
    private func attentionRow(_ item: AttentionItem) -> some View {
        HStack(spacing: 8) {
            Text(item.detail)
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            switch item.action {
            case .quitProcess(let pid, let name):
                Button("Quit") { confirmAttentionQuit = (pid, name) }
                    .buttonStyle(.borderedProminent)
                    .tint(Halo.ion.opacity(0.85))
                    .controlSize(.mini)
            case .cleanJunk:
                Button("Clean") { clean.runNow() }
                    .buttonStyle(.borderedProminent)
                    .tint(Halo.amber.opacity(0.85))
                    .controlSize(.mini)
            case .openPane(let target):
                Button("Review") { navigateAttention(to: target) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            case nil:
                EmptyView()
            }
        }
    }

    private func navigateAttention(to target: AttentionTarget) {
        dismiss()
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
        switch target {
        case .monitor:
            NotificationCenter.default.post(name: DashboardView.navigateToMonitor, object: nil)
        case .storage:
            NotificationCenter.default.post(name: .navigateToOptimize, object: nil)
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

    // MARK: Keep Awake

    private var keepAwakeRow: some View {
        let awake = KeepAwakeController.shared
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 11))
                    .foregroundStyle(awake.isActive ? Halo.ion : Halo.textSecondary)
                Text("Keep Awake")
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textSecondary)
                Spacer()
                if awake.isActive {
                    Menu {
                        ForEach(KeepAwakeController.durations, id: \.label) { choice in
                            Button(choice.label) { awake.activate(for: choice.seconds) }
                        }
                    } label: {
                        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text(awake.remainingText ?? "On")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Halo.ion)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Change duration")
                }
                Toggle("", isOn: Binding(
                    get: { awake.isActive },
                    set: { $0 ? awake.activate() : awake.deactivate() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            if awake.isActive {
                Text("Mac won't sleep\(awake.expiresAt == nil ? " until turned off" : "").")
                    .font(.system(size: 9))
                    .foregroundStyle(Halo.textDim)
            }
        }
    }

    // MARK: Menu Bar Manager

    private var menuBarManagerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textSecondary)
                Text("Menu Bar Manager")
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textSecondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { MenuBarManager.shared.isEnabled },
                    set: {
                        MenuBarManager.shared.isEnabled = $0
                        menuBarCollapsed = MenuBarManager.shared.isCollapsed
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            if MenuBarManager.shared.isEnabled {
                Button {
                    MenuBarManager.shared.toggle()
                    menuBarCollapsed = MenuBarManager.shared.isCollapsed
                } label: {
                    Label(menuBarCollapsed ? "Show hidden icons" : "Hide icons",
                          systemImage: menuBarCollapsed ? "eye" : "eye.slash")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(Halo.ion)

                Text("Or click the ‹ chevron in the menu bar. ⌘-drag an icon right of the | separator to keep it always visible.")
                    .font(.system(size: 9))
                    .foregroundStyle(Halo.textDim)
            }
        }
        .onAppear { menuBarCollapsed = MenuBarManager.shared.isCollapsed }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    isOptimizing = true
                    optimizeReport = nil
                    Task {
                        let report = await OptimizeEngine.runSafeTasks()
                        isOptimizing = false
                        optimizeReport = report
                    }
                } label: {
                    Label(isOptimizing ? "Optimizing…" : "Optimize", systemImage: "bolt.heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .tint(Halo.pulseGreen)
                .clipShape(Capsule())
                .disabled(isOptimizing)

                Button {
                    storage.emptyTrash()
                } label: {
                    Label(trashLabel, systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .tint(Halo.amber)
                .clipShape(Capsule())
                .disabled(storage.trashItemCount == 0 || storage.isCleaning)
            }

            if isOptimizing {
                Text("Running safe optimizations…")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            } else if let report = optimizeReport {
                Text(report)
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.pulseGreen)
                    .lineLimit(2)
            } else if storage.isCleaning {
                Text("Emptying Trash…")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            } else if let report = storage.cleanReport {
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
            .clipShape(Capsule())
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
