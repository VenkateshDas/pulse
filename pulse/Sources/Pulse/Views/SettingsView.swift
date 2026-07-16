import AppKit
import PulseKit
import SwiftUI

/// Centralized Settings page: a single readable column of icon-badged
/// sections — General, Menu Bar, Notifications, Dashboard, Managed Elsewhere
/// (quick links), Permissions, and About. Cleanup and Displays own their
/// full controls on their sidebar pages (`CleanView`/`AutoCleanCard`,
/// `DisplaysView`); this page only summarizes them with a link so exactly
/// one place owns each setting's UI.
struct SettingsView: View {
    @Environment(CleanModel.self) private var clean
    @Environment(Updater.self) private var updater
    @Environment(DashboardModel.self) private var dashboard
    @Binding var selection: SidebarItem

    @State private var recordingAction: PulseAction?
    @State private var conflictMessages: [PulseAction: String] = [:]
    /// Bumped after every keybinding write to force the shortcuts section to
    /// re-read `KeybindingStore`, which isn't `@Observable`.
    @State private var keybindingsVersion = 0

    private static let autoHideOptions: [TimeInterval] = [0, 5, 10, 15, 30]
    private static let maxItemsOptions = [1, 2, 3, 4, 5]
    private static let snoozeOptions: [TimeInterval] = [3600, 4 * 3600, 24 * 3600]

    var body: some View {
        // Registers an Observation dependency so the theme cards' selection
        // state (checkmark) updates immediately on tap.
        let _ = ThemeManager.shared.selected
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    "Settings",
                    subtitle: "Customize how Pulse runs, what it shows, and what it's allowed to do."
                )
                VStack(alignment: .leading, spacing: 16) {
                    appearanceSection
                    displayModeSection
                    generalSection
                    menuBarSection
                    keyboardShortcutsSection
                    notificationsSection
                    attentionSection
                    quickLinksSection
                    permissionsSection
                    aboutSection
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section("Appearance", icon: "paintpalette.fill", tint: Halo.interactive) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    themeCard(theme)
                }
            }
        }
    }

    // MARK: - Display Mode

    private var displayModeSection: some View {
        let mode = DisplayModeManager.shared.current
        return section(
            "Display Mode", icon: "eye.fill", tint: Halo.interactive,
            footnote: "Switch anytime — nothing is removed, only shown or hidden."
        ) {
            settingsRow(title: "Interface", detail: mode.subtitle) {
                Picker("", selection: displayModeBinding) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }

    private var displayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { DisplayModeManager.shared.current },
            set: { DisplayModeManager.shared.set($0) }
        )
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        let isSelected = ThemeManager.shared.selected == theme
        let palette = theme.palette
        return Button {
            ThemeManager.shared.select(theme)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    swatch(palette.void.dark)
                    swatch(palette.surface2.dark)
                    swatch(Color(hex: palette.interactive))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Halo.interactive)
                    }
                }
                Text(theme.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Halo.textPrimary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                    .fill(Halo.surface2.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                    .strokeBorder(isSelected ? Halo.interactive : Halo.borderSubtle, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ rgb: RGB) -> some View {
        Circle()
            .fill(Color(red: Double(rgb.r), green: Double(rgb.g), blue: Double(rgb.b)))
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(Halo.borderSubtle, lineWidth: 0.5))
    }

    private func swatch(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(Halo.borderSubtle, lineWidth: 0.5))
    }

    // MARK: - General

    private var generalSection: some View {
        section("General", icon: "gearshape.fill", tint: Halo.textDim) {
            settingsRow(
                title: "Show Dock Icon",
                detail: "Keep a permanent Dock icon. Otherwise Pulse only appears in the Dock while the Command Center is open."
            ) {
                Toggle("", isOn: dockIconBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            rowDivider
            settingsRow(
                title: "Launch at Login",
                detail: "Start Pulse automatically when you sign in."
            ) {
                Toggle("", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { AppActivation.shared.showDockIcon },
            set: { AppActivation.shared.showDockIcon = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { AppActivation.shared.launchAtLogin },
            set: { AppActivation.shared.setLaunchAtLogin($0) }
        )
    }

    // MARK: - Menu Bar

    private var menuBarSection: some View {
        let enabled = MenuBarManager.shared.isEnabled
        return section("Menu Bar", icon: "menubar.rectangle", tint: Halo.ion) {
            settingsRow(
                title: "Show in Menu Bar",
                detail: "Adds a collapsible chevron so you can hide other menu-bar icons to its left."
            ) {
                Toggle("", isOn: menuBarEnabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            rowDivider
            settingsRow(
                title: "Menu Bar Stats",
                detail: "Values shown in the menu bar. Pick any combination; at least one stays on."
            ) {
                HStack(spacing: 6) {
                    ForEach(MenuBarStat.allCases) { stat in
                        menuBarStatChip(stat)
                    }
                }
            }
            rowDivider
            settingsRow(
                title: "Auto-Hide Delay",
                detail: "How long after launch before hidden icons collapse automatically."
            ) {
                Picker("", selection: autoHideDelayBinding) {
                    ForEach(Self.autoHideOptions, id: \.self) { delay in
                        Text(delay == 0 ? "Off" : "\(Int(delay))s").tag(delay)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .disabled(!enabled)
            }
            .opacity(enabled ? 1 : 0.45)
        }
    }

    private var menuBarEnabledBinding: Binding<Bool> {
        Binding(
            get: { MenuBarManager.shared.isEnabled },
            set: { MenuBarManager.shared.isEnabled = $0 }
        )
    }

    /// Toggleable chip for one menu-bar stat. Deselecting the last remaining
    /// stat is a no-op — the label must always show something.
    private func menuBarStatChip(_ stat: MenuBarStat) -> some View {
        let selected = dashboard.menuBarStats.contains(stat)
        return Button {
            var stats = dashboard.menuBarStats
            if selected {
                stats.removeAll { $0 == stat }
            } else {
                stats.append(stat)
            }
            guard !stats.isEmpty else { return }
            // Canonical order regardless of click order.
            dashboard.menuBarStats = MenuBarStat.allCases.filter(stats.contains)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: stat.symbol)
                    .font(.system(size: 9))
                Text(stat.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? Halo.textPrimary : Halo.textDim)
            .background(
                Capsule().fill(selected ? Halo.ion.opacity(0.22) : .clear))
            .overlay(
                Capsule().strokeBorder(
                    selected ? Halo.ion.opacity(0.7) : Halo.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var autoHideDelayBinding: Binding<TimeInterval> {
        Binding(
            get: { MenuBarManager.shared.autoHideDelay },
            set: { MenuBarManager.shared.autoHideDelay = $0 }
        )
    }

    // MARK: - Keyboard Shortcuts

    private var keyboardShortcutsSection: some View {
        section(
            "Keyboard Shortcuts", icon: "keyboard.fill", tint: Halo.ion,
            footnote: "Shortcuts work anywhere on the Mac, even when Pulse isn't focused."
        ) {
            let _ = keybindingsVersion  // re-read the store when this changes
            ForEach(Array(PulseAction.allCases.enumerated()), id: \.element) { index, action in
                if index > 0 { rowDivider }
                shortcutRow(action)
            }
        }
    }

    private func shortcutRow(_ action: PulseAction) -> some View {
        let store = KeybindingStore.shared
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Halo.textPrimary)
                    Text(action.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { store.isEnabled(action) },
                    set: {
                        store.setEnabled($0, for: action)
                        keybindingsVersion += 1
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                ShortcutRecorderField(
                    combo: store.combo(for: action),
                    isRecording: recordingAction == action,
                    onStartRecording: {
                        conflictMessages[action] = nil
                        recordingAction = action
                    },
                    onCapture: { event in handleCapture(event, for: action) }
                )
                .disabled(!store.isEnabled(action))
                .opacity(store.isEnabled(action) ? 1 : 0.45)
                Button {
                    store.resetToDefault(action)
                    conflictMessages[action] = nil
                    keybindingsVersion += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Halo.textDim)
                .help("Reset to default")
            }
            if let message = conflictMessages[action] {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.flare)
            }
        }
    }

    private func handleCapture(_ event: NSEvent, for action: PulseAction) {
        recordingAction = nil
        guard event.keyCode != 53 else { return }  // Escape cancels recording
        guard let combo = KeyCombo(event: event) else {
            conflictMessages[action] = "Shortcuts need at least one modifier key (\u{2318}\u{2325}\u{2303}\u{21e7})."
            return
        }
        if let conflict = KeybindingStore.shared.setCombo(combo, for: action) {
            conflictMessages[action] = "Already used by \(conflict.displayName)."
        } else {
            conflictMessages[action] = nil
        }
        keybindingsVersion += 1
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        section(
            "Notifications", icon: "bell.badge.fill", tint: Halo.flare,
            footnote: "Auto-clean completion notices are set on the Storage page."
        ) {
            settingsRow(
                title: "Critical Alerts",
                detail: "Notify when something needs attention now — runaway process, low disk, thermal throttling."
            ) {
                Toggle("", isOn: notifyCriticalBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            rowDivider
            settingsRow(
                title: "Weekly Report",
                detail: "A Monday-morning summary of reclaimed space and Mac health."
            ) {
                Toggle("", isOn: notifyWeeklyBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var notifyCriticalBinding: Binding<Bool> {
        Binding(
            get: { NotificationPreferences.notifyCriticalAlerts },
            set: { NotificationPreferences.notifyCriticalAlerts = $0 }
        )
    }

    private var notifyWeeklyBinding: Binding<Bool> {
        Binding(
            get: { NotificationPreferences.notifyWeeklyReport },
            set: { NotificationPreferences.notifyWeeklyReport = $0 }
        )
    }

    // MARK: - Dashboard (attention & snooze)

    private var attentionSection: some View {
        section("Dashboard", icon: "rectangle.3.group.fill", tint: Halo.amber) {
            settingsRow(
                title: "Attention Items Shown",
                detail: "Max number of guided-focus cards on the Dashboard at once."
            ) {
                Picker("", selection: maxItemsBinding) {
                    ForEach(Self.maxItemsOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }
            rowDivider
            settingsRow(
                title: "Default Snooze",
                detail: "How long the quick \u{2018}Snooze\u{2019} action hides an item."
            ) {
                Picker("", selection: snoozeDurationBinding) {
                    ForEach(Self.snoozeOptions, id: \.self) { duration in
                        Text(snoozeLabel(duration)).tag(duration)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }

    private func snoozeLabel(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        return hours >= 24 ? "\(hours / 24) day" : "\(hours)h"
    }

    private var maxItemsBinding: Binding<Int> {
        Binding(
            get: { AttentionPreferences.maxItems },
            set: { AttentionPreferences.maxItems = $0 }
        )
    }

    private var snoozeDurationBinding: Binding<TimeInterval> {
        Binding(
            get: { AttentionPreferences.defaultSnoozeDuration },
            set: { AttentionPreferences.defaultSnoozeDuration = $0 }
        )
    }

    // MARK: - Quick links to settings owned by other pages

    private var quickLinksSection: some View {
        section("Managed Elsewhere", icon: "arrow.uturn.forward", tint: Halo.ion) {
            linkRow(
                title: "Cleanup Schedule",
                detail: "Schedule, safe-tier auto-clean, and completion notices.",
                summary: cleanupSummary
            ) { selection = .storage }
            rowDivider
            linkRow(
                title: "Displays",
                detail: "Per-monitor brightness and adaptive sync.",
                summary: displaysSummary
            ) { selection = .displays }
        }
    }

    private var cleanupSummary: String {
        let schedule = clean.schedule
        let freq = schedule.frequency.rawValue.capitalized
        let time = schedule.timePreference.rawValue.capitalized
        return "\(freq) \u{00b7} \(time) \u{00b7} auto-clean \(schedule.autoCleanSafeTier ? "on" : "off")"
    }

    private var displaysSummary: String {
        let count = BrightnessEngine.shared.monitors.count
        return count == 0 ? "No displays detected" : "\(count) display\(count == 1 ? "" : "s") connected"
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        section(
            "Permissions", icon: "lock.shield.fill", tint: Halo.pulseGreen,
            footnote: "Pulse asks for the minimum it needs; optional grants unlock specific features."
        ) {
            PermissionsSection()
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        section("About", icon: "info.circle.fill", tint: Halo.textDim) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pulse \u{00b7} v\(updater.currentVersion)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Halo.textPrimary)
                    aboutStatusText
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                Spacer(minLength: 12)
                aboutAction
            }
        }
    }

    @ViewBuilder
    private var aboutStatusText: some View {
        switch updater.status {
        case .upToDate: Text("You're up to date.")
        case .checking: Text("Checking for updates\u{2026}")
        case .failed: Text("Update check failed.")
        case .available(let release): Text("Update available \u{00b7} v\(release.version)")
        case .idle: Text("Automatic checks run periodically in the background.")
        }
    }

    @ViewBuilder
    private var aboutAction: some View {
        if case .available = updater.status {
            Button("Download") { updater.openLatestDownload() }
                .buttonStyle(.borderedProminent)
                .tint(Halo.ion)
        } else {
            Button("Check for Updates\u{2026}") { updater.checkForUpdates(userInitiated: true) }
                .buttonStyle(.bordered)
                .disabled(updater.status == .checking)
        }
    }

    // MARK: - Shared layout

    private var rowDivider: some View {
        Divider().overlay(Halo.borderSubtle).padding(.vertical, 2)
    }

    private func section(
        _ title: String, icon: String, tint: Color, footnote: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.85), tint.opacity(0.55)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
            }
            .padding(.bottom, 2)
            content()
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim.opacity(0.8))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: Halo.Radius.medium)
    }

    private func settingsRow(
        title: String, detail: String, @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Halo.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
    }

    /// Whole-row button linking to the page that owns the setting.
    private func linkRow(
        title: String, detail: String, summary: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Halo.textPrimary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                Spacer(minLength: 12)
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
