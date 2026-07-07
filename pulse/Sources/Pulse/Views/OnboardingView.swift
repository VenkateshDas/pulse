import AppKit
import SwiftUI

/// First-run / post-update TCC pre-flight. Lists every permission Pulse needs
/// (shared with the Permissions center so they never drift), explains what each
/// unlocks, and deep-links to the right Settings pane — so no feature ever hits
/// an unexplained wall the first time it's used.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var store = PermissionStore()

    private var requiredGranted: Bool {
        PulsePermission.allCases.allSatisfy {
            !$0.required || store.status($0) == .granted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Pulse")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text("Grant what you'll use and you're set. Pulse never destroys a file — removals go to the Trash and stay restorable.")
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
        .padding(32)
        .frame(width: 580, height: 640)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .task { await store.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refresh() }
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
