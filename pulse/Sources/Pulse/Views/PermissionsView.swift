import AppKit
import ApplicationServices
import PulseKit
import SwiftUI
import UserNotifications

// MARK: - Model

enum PermissionStatus: Sendable { case granted, denied, unknown }

/// Single source of truth for every macOS permission Pulse needs, the feature
/// each unlocks, and how to grant it. Drives both the first-run / post-update
/// onboarding and the always-available Permissions center, so the two never
/// drift apart.
enum PulsePermission: String, CaseIterable, Identifiable, Sendable {
    case fullDiskAccess
    case accessibility
    case appManagement
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullDiskAccess: "Full Disk Access"
        case .accessibility: "Accessibility"
        case .appManagement: "App Management"
        case .notifications: "Notifications"
        }
    }

    var symbol: String {
        switch self {
        case .fullDiskAccess: "externaldrive.fill.badge.person.crop"
        case .accessibility: "slider.horizontal.3"
        case .appManagement: "app.badge.checkmark"
        case .notifications: "bell.badge.fill"
        }
    }

    /// What the permission unlocks / what breaks without it.
    var detail: String {
        switch self {
        case .fullDiskAccess:
            "Maps large files and safe-to-clean space across the disk. Without it the first storage scan stalls silently."
        case .accessibility:
            "Routes the keyboard brightness keys to the display under your cursor — and stops macOS from only dimming the built-in screen."
        case .appManagement:
            "Lets the App Uninstaller move other apps' bundles to the Trash. macOS provides no way to read this state, so grant it here once."
        case .notifications:
            "Heads-up when an auto-clean finishes or a critical alert fires (low disk, runaway process, battery health). Optional."
        }
    }

    /// Required permissions gate the post-update re-prompt; optional ones don't.
    var required: Bool {
        switch self {
        case .fullDiskAccess, .accessibility: true
        case .appManagement, .notifications: false
        }
    }

    /// Whether macOS lets us trigger an in-app grant prompt (vs Settings only).
    var hasInAppPrompt: Bool {
        switch self {
        case .accessibility, .notifications: true
        case .fullDiskAccess, .appManagement: false
        }
    }

    /// Deep link to the exact System Settings pane.
    var settingsURL: URL {
        let s: String
        switch self {
        case .fullDiskAccess:
            s = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .accessibility:
            s = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .appManagement:
            s = "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
        case .notifications:
            s = "x-apple.systempreferences:com.apple.preference.notifications"
        }
        return URL(string: s)!
    }

    /// Status without crossing actors. App Management has no public read API
    /// (`.unknown`); Notifications is async-only here (`.unknown`).
    nonisolated var syncStatus: PermissionStatus {
        switch self {
        case .fullDiskAccess:
            return FullDiskAccess.isGranted ? .granted : .denied
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .appManagement, .notifications:
            return .unknown
        }
    }

    @MainActor func status() async -> PermissionStatus {
        switch self {
        case .notifications:
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: return .granted
            case .denied: return .denied
            default: return .unknown
            }
        default:
            return syncStatus
        }
    }

    /// In-app grant where macOS allows one; otherwise open the Settings pane.
    @MainActor func request() {
        switch self {
        case .accessibility:
            _ = MediaKeyManager.shared.isTrusted(prompt: true)   // system prompt
        case .notifications:
            guard Bundle.main.bundleIdentifier != nil else { return }
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        case .fullDiskAccess, .appManagement:
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

@MainActor
@Observable
final class PermissionStore {
    private(set) var statuses: [PulsePermission: PermissionStatus] = [:]

    init() {
        // Seed synchronously so rows render correct state on first paint.
        for p in PulsePermission.allCases { statuses[p] = p.syncStatus }
    }

    func refresh() async {
        for p in PulsePermission.allCases {
            statuses[p] = await p.status()
        }
    }

    func status(_ p: PulsePermission) -> PermissionStatus { statuses[p] ?? .unknown }
}

/// Decides when to surface the permission onboarding. Re-asks on a fresh install
/// and once after an update when a required permission is still missing — but
/// records the version each launch so we never nag twice for the same build.
enum PermissionsGate {
    private static let versionKey = "PulseLastPromptedVersion"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    nonisolated static func shouldPromptOnLaunch() -> Bool {
        if !OnboardingView.isComplete { return true }
        let last = UserDefaults.standard.string(forKey: versionKey)
        guard last != currentVersion else { return false }
        return PulsePermission.allCases.contains { $0.required && $0.syncStatus != .granted }
    }

    static func markPrompted() {
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }
}

// MARK: - Shared row

struct PermissionRow: View {
    let permission: PulsePermission
    let status: PermissionStatus
    let onChanged: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            statusBadge
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(permission.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                    if !permission.required {
                        Text("optional")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Halo.textDim.opacity(0.7))
                    }
                }
                Text(permission.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                actions.padding(.top, 2)
            }
            Spacer()
        }
        .premiumCard(cornerRadius: Halo.Radius.medium)
    }

    private var statusBadge: some View {
        ZStack {
            Circle()
                .fill(status == .granted ? Halo.pulseGreen : Halo.surface2)
                .frame(width: 30, height: 30)
                .shadow(color: status == .granted ? Halo.pulseGreen.opacity(0.4) : .clear, radius: 6)
            Image(systemName: status == .granted ? "checkmark" : permission.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(status == .granted ? Halo.void : Halo.textPrimary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if status == .granted {
            Text("Granted")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Halo.pulseGreen)
        } else {
            HStack(spacing: 10) {
                if permission.hasInAppPrompt {
                    Button("Enable") { act { permission.request() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Halo.ion.opacity(0.85))
                }
                Button(permission.hasInAppPrompt ? "Open Settings" : "Grant in Settings") {
                    act { NSWorkspace.shared.open(permission.settingsURL) }
                }
                .buttonStyle(.bordered)
                if status == .unknown {
                    Text("can't be detected — grant once")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim.opacity(0.8))
                }
            }
        }
    }

    /// Run an action, then re-check shortly after (the user grants out-of-process).
    private func act(_ body: @escaping () -> Void) {
        body()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onChanged() }
    }
}

// MARK: - Center (sidebar destination)

struct PermissionsView: View {
    @State private var store = PermissionStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Permissions")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Halo.textPrimary)
                    Text("Everything Pulse can ask macOS for, in one place. Grant only what you use — nothing here is required to launch.")
                        .font(.system(size: 13))
                        .foregroundStyle(Halo.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(PulsePermission.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        status: store.status(permission),
                        onChanged: { Task { await store.refresh() } }
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .task { await store.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refresh() }
        }
    }
}
