import AppKit
import PulseKit
import SwiftUI

/// Centralized Settings page: General, Menu Bar, Notifications, Attention &
/// Snooze, Cleanup, Displays, Permissions, and About. Cleanup and Displays
/// already own full-featured controls on their own sidebar pages
/// (`CleanView`/`AutoCleanCard`, `DisplaysView`) — this page only summarizes
/// them with a quick link, so there's exactly one place that owns each
/// setting's UI.
struct SettingsView: View {
    @Environment(CleanModel.self) private var clean
    @Environment(Updater.self) private var updater
    @Binding var selection: SidebarItem

    private static let autoHideOptions: [TimeInterval] = [0, 5, 10, 15, 30]
    private static let maxItemsOptions = [1, 2, 3, 4, 5]
    private static let snoozeOptions: [TimeInterval] = [3600, 4 * 3600, 24 * 3600]
    private static let gridColumns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 16) {
                    generalSection
                    menuBarSection
                    notificationsSection
                    attentionSection
                    cleanupSection
                    displaysSection
                    aboutSection
                }
                permissionsSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
    }

    private var header: some View {
        PageHeader(
            "Settings",
            subtitle: "Customize how Pulse runs, what it shows, and what it's allowed to do."
        )
    }

    // MARK: - General

    private var generalSection: some View {
        section("General") {
            settingsRow(
                title: "Show Dock Icon",
                detail: "Keep a permanent Dock icon. Otherwise Pulse only appears in the Dock while the Command Center is open."
            ) {
                Toggle("", isOn: dockIconBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Divider().overlay(Halo.borderSubtle)
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
            set: { AppActivation.shared.launchAtLogin = $0 }
        )
    }

    // MARK: - Menu Bar

    private var menuBarSection: some View {
        section("Menu Bar") {
            settingsRow(
                title: "Show in Menu Bar",
                detail: "Adds a collapsible chevron so you can hide other menu-bar icons to its left."
            ) {
                Toggle("", isOn: menuBarEnabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if MenuBarManager.shared.isEnabled {
                Divider().overlay(Halo.borderSubtle)

                settingsRow(
                    title: "Auto-Hide Delay",
                    detail: "How long after launch before hidden icons collapse automatically."
                ) {
                    Picker("", selection: autoHideDelayBinding) {
                        ForEach(Self.autoHideOptions, id: \.self) { delay in
                            Text(delay == 0 ? "Off" : "\(Int(delay))s").tag(delay)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            }
        }
    }

    private var menuBarEnabledBinding: Binding<Bool> {
        Binding(
            get: { MenuBarManager.shared.isEnabled },
            set: { MenuBarManager.shared.isEnabled = $0 }
        )
    }

    private var autoHideDelayBinding: Binding<TimeInterval> {
        Binding(
            get: { MenuBarManager.shared.autoHideDelay },
            set: { MenuBarManager.shared.autoHideDelay = $0 }
        )
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        section("Notifications") {
            settingsRow(
                title: "Critical Alerts",
                detail: "Notify when something needs attention now — runaway process, low disk, thermal throttling."
            ) {
                Toggle("", isOn: notifyCriticalBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Divider().overlay(Halo.borderSubtle)
            settingsRow(
                title: "Weekly Report",
                detail: "A Monday-morning summary of reclaimed space and Mac health."
            ) {
                Toggle("", isOn: notifyWeeklyBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Divider().overlay(Halo.borderSubtle)
            Text("Auto-clean completion notices are set on the Storage page.")
                .font(.system(size: 11))
                .foregroundStyle(Halo.textDim.opacity(0.8))
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

    // MARK: - Attention & Snooze

    private var attentionSection: some View {
        section("Attention & Snooze") {
            settingsRow(
                title: "Items Shown",
                detail: "Max number of guided-focus cards on the Dashboard at once."
            ) {
                Picker("", selection: maxItemsBinding) {
                    ForEach(Self.maxItemsOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
            }
            Divider().overlay(Halo.borderSubtle)
            settingsRow(
                title: "Default Snooze",
                detail: "How long the quick \u{2018}Snooze\u{2019} action hides an item."
            ) {
                Picker("", selection: snoozeDurationBinding) {
                    ForEach(Self.snoozeOptions, id: \.self) { duration in
                        Text(snoozeLabel(duration)).tag(duration)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }
        }
    }

    private func snoozeLabel(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        return hours >= 24 ? "\(hours / 24)d" : "\(hours)h"
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

    // MARK: - Cleanup

    private var cleanupSection: some View {
        section("Cleanup") {
            VStack(alignment: .leading, spacing: 10) {
                Text(cleanupSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(Halo.textPrimary)
                Text("Schedule, safe-tier auto-clean, and completion notices live on the Storage page.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Manage in Storage \u{2192}") { selection = .storage }
                    .buttonStyle(.bordered)
                    .tint(Halo.ion)
            }
        }
    }

    private var cleanupSummary: String {
        let schedule = clean.schedule
        let freq = schedule.frequency.rawValue.capitalized
        let time = schedule.timePreference.rawValue.capitalized
        return "\(freq) \u{00b7} \(time)" + (schedule.autoCleanSafeTier ? " \u{00b7} auto-clean on" : " \u{00b7} auto-clean off")
    }

    // MARK: - Displays

    private var displaysSection: some View {
        section("Displays") {
            VStack(alignment: .leading, spacing: 10) {
                Text(displaysSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(Halo.textPrimary)
                Text("Per-monitor brightness and adaptive sync live on the Displays page.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Manage in Displays \u{2192}") { selection = .displays }
                    .buttonStyle(.bordered)
                    .tint(Halo.ion)
            }
        }
    }

    private var displaysSummary: String {
        let count = BrightnessEngine.shared.monitors.count
        return count == 0 ? "No displays detected" : "\(count) display\(count == 1 ? "" : "s") connected"
    }

    // MARK: - About

    private var aboutSection: some View {
        section("About") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pulse \u{00b7} v\(updater.currentVersion)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Halo.textPrimary)
                aboutStatusText
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
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
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PERMISSIONS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Halo.textDim.opacity(0.7))
            PermissionsSection()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: Halo.Radius.medium)
    }

    // MARK: - Shared layout

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Halo.textDim.opacity(0.7))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: Halo.Radius.medium)
    }

    private func settingsRow(
        title: String, detail: String, @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(alignment: .top) {
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
}
