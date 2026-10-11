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
    @Environment(NetworkModel.self) private var network
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    @Environment(\.dismiss) private var dismiss
    @State private var menuBarCollapsed = false
    @State private var confirmAttentionQuit: (pid: Int32, name: String)?
    @State private var confirmEmptyTrash = false

    /// 30s ≈ 15 two-second samples — the popover's sparkline window.
    private static let sparkSamples = 15

    var body: some View {
        // Registers an Observation dependency on the current theme so the
        // popover re-renders (picking up fresh `Halo.*` values) when the
        // user switches presets in Settings.
        let _ = ThemeManager.shared.selected
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hud
                Divider()
                if let snapshot = model.snapshot {
                    VStack(spacing: 10) {
                        infoRow("Processor use", String(format: "%.0f%%", snapshot.cpuTotalPercent), color: Halo.textPrimary)
                        infoRow("Storage available", ByteFormat.string(snapshot.diskFreeBytes), color: Halo.textPrimary)
                        if let battery = snapshot.battery { batteryRow(battery) }
                    }
                    DisclosureGroup("More readings") {
                        VStack(spacing: 12) {
                            metricRow("Memory used", ByteFormat.string(snapshot.memoryUsedBytes), fraction: snapshot.memoryUsedFraction, spark: model.memoryHistory)
                            thermalRow(snapshot)
                            networkRow(snapshot)
                            topProcesses(snapshot)
                        }.padding(.top, 8)
                    }
                    DisplaysPopoverSection()
                } else {
                    ProgressView("Checking current activity…")
                }
                Divider()
                keepAwakeRow
                DisclosureGroup("Organise menu bar icons") { menuBarManagerRow.padding(.top, 8) }
                Divider()
                actions
            }.padding(18)
        }
        // MenuBarExtra sizes its panel from the content; a ScrollView has no
        // intrinsic height, so a maximum alone can collapse it to a thin strip.
        .frame(height: 620)
        .onAppear {
            model.viewAppeared()
            storage.refreshTrashInfo()
            // Hotkey handlers are static; make sure the speed-test binding
            // reaches this NetworkModel even if the main window never opened.
            KeybindingActions.networkModel = network
            updater.checkForUpdates()  // throttled background check
        }
        .onDisappear { model.viewDisappeared() }
        .frame(width: 360)
        .background(Halo.surface1)
        .disabled(confirmEmptyTrash || confirmAttentionQuit != nil)
        .overlay { confirmOverlay }
    }

    // MARK: Inline confirmation

    // `confirmationDialog` presents an AppKit sheet on the MenuBarExtra
    // `.window` panel, which is non-activating and can never become key —
    // the sheet's buttons don't receive clicks, the modal never dismisses,
    // and the stuck modal session freezes the menu bar. Confirmations in
    // this popover must stay pure SwiftUI (no sheets/alerts).
    @ViewBuilder private var confirmOverlay: some View {
        if confirmEmptyTrash {
            confirmCard(
                title: "Empty the Trash?",
                message:
                    "Permanently erases \(storage.trashItemCount) items (\(ByteFormat.string(storage.trashBytes))). This can't be undone.",
                actionLabel: "Empty Trash",
                onConfirm: {
                    confirmEmptyTrash = false
                    storage.emptyTrash()
                },
                onCancel: { confirmEmptyTrash = false })
        } else if let target = confirmAttentionQuit {
            confirmCard(
                title: "Quit \(target.name)?",
                message: "Sends a normal Quit signal. Unsaved work in that app may be lost.",
                actionLabel: "Quit \(target.name)",
                onConfirm: {
                    confirmAttentionQuit = nil
                    model.quitProcess(pid: target.pid, name: target.name)
                },
                onCancel: { confirmAttentionQuit = nil })
        }
    }

    private func confirmCard(
        title: String, message: String, actionLabel: String,
        onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(Halo.font(size: 13, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            Text(message)
                .font(Halo.font(size: 11))
                .foregroundStyle(Halo.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)

                Button(actionLabel, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Halo.onAccent)
                    .tint(Halo.critical)

            }
        }
        .padding(16)
        .frame(maxWidth: 320)
        .background(
            Halo.surface1,
            in: RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous)
                .strokeBorder(Halo.borderSubtle)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Dim + swallow clicks on everything behind the card.
        .background(Color.black.opacity(0.45).contentShape(Rectangle()).onTapGesture(perform: onCancel))
    }

    // MARK: HUD (top attention item + score)

    private var topAttentionItem: AttentionItem? { model.attentionItems.first }

    private var hud: some View {
        let condition = HomeCondition(diagnosis: model.diagnosis, hasSnapshot: model.snapshot != nil, hasAttention: !model.attentionItems.isEmpty)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Pulse", systemImage: "waveform.path.ecg")
                    .font(Halo.font(size: 17, weight: .semibold))
                Spacer()
                Button("Open Pulse") { navigate(to: .dashboard) }.buttonStyle(.bordered)
            }
            Label(condition.title, systemImage: condition.symbol)
                .font(Halo.font(size: 14, weight: .semibold))
            Text(condition.explanation).font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let item = topAttentionItem { attentionRow(item) }
        }
    }

    private func navigate(to item: SidebarItem, diskTab: Int? = nil) {
        PulseNavigation.open(item, diskTab: diskTab)
        dismiss()
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    @ViewBuilder
    private func attentionRow(_ item: AttentionItem) -> some View {
        HStack(spacing: 8) {
            Text(item.detail)
                .font(Halo.font(size: 10))
                .foregroundStyle(Halo.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            switch item.action {
            case .quitProcess(let pid, let name):
                Button("Quit") { confirmAttentionQuit = (pid, name) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Halo.onAccent)
                    .tint(Halo.ion.opacity(0.85))
                    .controlSize(.mini)
            case .cleanJunk:
                Button("Review cleanup") { navigate(to: .storage, diskTab: 1) }
                    .buttonStyle(.bordered)
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
        switch target {
        case .monitor: navigate(to: .monitor)
        case .storage: navigate(to: .storage, diskTab: 1)
        }
    }

    // MARK: Metric rows

    private func metricRow(_ label: String, _ value: String, fraction: Double, spark: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(Halo.font(size: 11))
                    .foregroundStyle(Halo.textSecondary)
                Spacer()
                Text(value)
                    .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
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
                    .font(Halo.font(size: 11))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text("\(ByteFormat.string(snapshot.diskFreeBytes)) / \(ByteFormat.string(snapshot.diskTotalBytes))")
                    .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
            }
            bar(snapshot.diskUsedFraction)
            if let weekly = snapshot.diskWeeklyGrowthBytes {
                // Same sign semantics as the Dashboard disk card: + = usage grew.
                let sign = weekly >= 0 ? "+" : "−"
                Text("\(sign)\(ByteFormat.string(UInt64(abs(weekly)))) used this week")
                    .font(Halo.font(size: 10, design: .monospaced))
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

    /// Connection medium + Wi-Fi signal verdict, same polarity as the
    /// dashboard card (high quality = green, offline = neutral gray).
    private func networkRow(_ snapshot: SystemSnapshot) -> some View {
        let wifi = snapshot.wifiInfo
        let (value, color): (String, Color) =
            switch snapshot.connectionType {
            case .wifi:
                (wifi.map { "\($0.ssid ?? "Wi-Fi") · \($0.signalQualityPercent)% signal" } ?? "Wi-Fi connected; signal unavailable",
                 (wifi?.signalQualityFraction ?? 0) < 0.35
                     ? Halo.flare
                     : ((wifi?.signalQualityFraction ?? 0) < 0.65 ? Halo.amber : Halo.pulseGreen))
            case .ethernet: ("Wired", Halo.pulseGreen)
            case .cellular: ("Cellular", Halo.textPrimary)
            case .other: ("Connected", Halo.textPrimary)
            case .none: ("Offline", Halo.textDim)
            }
        return infoRow("Network", value, color: color)
    }

    /// Compact label/value row (no bar/sparkline) for the secondary metrics.
    private func infoRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(Halo.font(size: 11))
                .foregroundStyle(Halo.textDim)
            Spacer()
            Text(value)
                .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
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
        .accessibilityHidden(true)
    }

    // MARK: Top processes

    @ViewBuilder
    private func topProcesses(_ snapshot: SystemSnapshot) -> some View {
        let top = Array(snapshot.topProcesses.prefix(3))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOP PROCESSES")
                    .font(Halo.font(size: 9, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                ForEach(top) { proc in
                    HStack(spacing: 8) {
                        Text(proc.name)
                            .font(Halo.font(size: 11))
                            .foregroundStyle(Halo.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.0f%%", proc.cpuPercent))
                            .font(Halo.font(size: 10, design: .monospaced))
                            .foregroundStyle(Halo.ion)
                            .frame(width: 38, alignment: .trailing)
                        Text(ByteFormat.string(proc.residentBytes))
                            .font(Halo.font(size: 10, design: .monospaced))
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
                    .font(Halo.font(size: 11))
                    .foregroundStyle(awake.isActive ? Halo.ion : Halo.textSecondary)
                Text("Keep Awake")
                    .font(Halo.font(size: 11))
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
                                .font(Halo.font(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Halo.ion)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Change duration")
                }
                Toggle("Keep Mac awake", isOn: Binding(
                    get: { awake.isActive },
                    set: { $0 ? awake.activate() : awake.deactivate() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            if awake.isActive {
                Text("Mac won't sleep\(awake.expiresAt == nil ? " until turned off" : "").")
                    .font(Halo.font(size: 9))
                    .foregroundStyle(Halo.textDim)
            } else if awake.lastActivationFailed {
                Text("Couldn't create the power assertion — try again.")
                    .font(Halo.font(size: 9))
                    .foregroundStyle(Halo.amber)
            }
        }
    }

    // MARK: Menu Bar Manager

    private var menuBarManagerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "menubar.rectangle")
                    .font(Halo.font(size: 11))
                    .foregroundStyle(Halo.textSecondary)
                Text("Menu Bar Manager")
                    .font(Halo.font(size: 11))
                    .foregroundStyle(Halo.textSecondary)
                Spacer()
                Toggle("Organise menu bar icons", isOn: Binding(
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
                    .font(Halo.font(size: 9))
                    .foregroundStyle(Halo.textDim)
            }
        }
        .onAppear { menuBarCollapsed = MenuBarManager.shared.isCollapsed }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { navigate(to: .storage, diskTab: 1) } label: {
                Label("Review cleanup", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent)
            Button { navigate(to: .optimize) } label: {
                Label("Review maintenance tasks", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            Button { confirmEmptyTrash = true } label: {
                Label(trashLabel, systemImage: "trash").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
                .disabled(storage.trashItemCount == 0 || storage.isCleaning)
            if storage.isCleaning {
                ProgressView("Emptying Trash…")
            } else if let report = storage.cleanReport {
                Text(report).font(Halo.font(size: 13)).foregroundStyle(Halo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            updateRow
            Button("Quit Pulse") { AppActivation.shared.quit() }.buttonStyle(.bordered)
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
                    .foregroundStyle(Halo.onAccent)
            .tint(Halo.ion)

        case .checking:
            Text("Checking for updates…")
                .font(Halo.font(size: 11))
                .foregroundStyle(Halo.textDim)
                .frame(maxWidth: .infinity)
        default:
            Button(updateLinkLabel) { updater.checkForUpdates(userInitiated: true) }
                .buttonStyle(.plain)
                .font(Halo.font(size: 11))
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
