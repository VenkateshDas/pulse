import AppKit
import SwiftUI

/// First-run / post-update pre-flight: a value-prop + Simple/Pro choice page,
/// then the TCC permission checklist (shared with the Permissions center so
/// they never drift, explains what each unlocks, and deep-links to the right
/// Settings pane — so no feature ever hits an unexplained wall the first time
/// it's used).
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var store = PermissionStore()
    @State private var page: Page = .welcome

    private enum Page { case welcome, permissions }

    private var requiredGranted: Bool {
        PulsePermission.allCases.allSatisfy {
            !$0.required || store.status($0) == .granted
        }
    }

    var body: some View {
        Group {
            switch page {
            case .welcome: welcomePage
            case .permissions: permissionsPage
            }
        }
        .padding(32)
        .frame(width: 580, height: 640)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .task { await store.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refresh() }
        }
    }

    // MARK: - Page 1: welcome + display mode

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Pulse")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text("Your Mac's command center.")
                    .font(.system(size: 13))
                    .foregroundStyle(Halo.textDim)
            }

            VStack(alignment: .leading, spacing: 12) {
                valueRow(icon: "sparkles", text: "Frees up space safely — nothing is ever deleted for good.")
                valueRow(icon: "waveform.path.ecg", text: "Tells you what's slowing your Mac down, in plain English.")
                valueRow(icon: "arrow.uturn.backward.circle", text: "Every removal goes to the Trash and stays restorable.")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How would you like Pulse to look?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                HStack(spacing: 12) {
                    modeCard(.simple)
                    modeCard(.pro)
                }
                Text("You can switch anytime in Settings — nothing is removed, only shown or hidden.")
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
            }

            Spacer()

            HStack {
                Button("Skip for now") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Button("Continue") { page = .permissions }
                    .buttonStyle(.borderedProminent)
                    .tint(Halo.pulseGreen)
            }
        }
    }

    private func valueRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Halo.pulseGreen)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Halo.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeCard(_ mode: DisplayMode) -> some View {
        let isSelected = DisplayModeManager.shared.current == mode
        return Button {
            DisplayModeManager.shared.set(mode)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(mode.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Halo.interactive.opacity(0.12) : Halo.surface2.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Halo.interactive : Halo.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 2: permissions

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                page = .welcome
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Halo.textDim)

            VStack(alignment: .leading, spacing: 6) {
                Text("Grant what you'll use")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text("You're set as soon as you grant what you plan to use. Pulse never destroys a file — removals go to the Trash and stay restorable.")
                    .font(.system(size: 13))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(PulsePermission.allCases) { permission in
                        PermissionRow(
                            permission: permission,
                            status: store.status(permission),
                            onChanged: { Task { await store.refresh() } }
                        )
                    }
                }
            }

            HStack {
                Button("Skip for now") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Button(requiredGranted ? "Start Pulse" : "Continue anyway") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(Halo.pulseGreen)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: OnboardingView.completeKey)
        PermissionsGate.markPrompted()
        isPresented = false
    }

    nonisolated static let completeKey = "PulseOnboardingComplete"
    // nonisolated: only reads thread-safe UserDefaults, so the launch-time
    // gate (PermissionsGate.shouldPromptOnLaunch) can call it off the main actor.
    nonisolated static var isComplete: Bool { UserDefaults.standard.bool(forKey: completeKey) }
}

/// Detects Full Disk Access by attempting to read a TCC-protected path that
/// is only listable when the app holds FDA.
enum FullDiskAccess {
    static var isGranted: Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        return FileManager.default.isReadableFile(atPath: probe.path)
    }
}
