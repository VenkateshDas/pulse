import AppKit
import SwiftUI
import UserNotifications

/// First-run TCC pre-flight. The first storage scan reads protected folders;
/// without Full Disk Access it stalls silently and reads as a freeze. This
/// flow explains why, deep-links to the right Settings pane, and requests
/// notification permission — so the first scan never hits an unexplained wall.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var fdaGranted = FullDiskAccess.isGranted
    @State private var notificationsAsked = false

    var body: some View {
        VStack(alignment: .leading, spacing: Halo.Space.xxl) {
            VStack(alignment: .leading, spacing: Halo.Space.sm) {
                Text("Welcome to Pulse")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundStyle(Halo.textPrimary)
                Text("Two quick permissions and you're set. Pulse never moves a file without staging it in the Vault first — everything is restorable.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Halo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            step(
                number: 1,
                title: "Full Disk Access",
                body: "Lets Pulse map large files and find safe-to-clean space across your disk. Without it, the first scan stalls silently.",
                granted: fdaGranted
            ) {
                if fdaGranted {
                    EmptyView().eraseToAny()
                } else {
                    HStack(spacing: 10) {
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(
                                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Halo.ion)
                        Button("Re-check") { fdaGranted = FullDiskAccess.isGranted }
                            .buttonStyle(.bordered)
                    }
                    .eraseToAny()
                }
            }

            step(
                number: 2,
                title: "Notifications",
                body: "Get a heads-up when an auto-clean finishes or a critical alert fires (low disk, runaway process, battery health). Optional.",
                granted: notificationsAsked
            ) {
                Button(notificationsAsked ? "Requested" : "Enable Notifications") {
                    requestNotifications()
                }
                .buttonStyle(.bordered)
                .disabled(notificationsAsked)
                .eraseToAny()
            }

            Spacer(minLength: 0)

            HStack {
                Button("Skip for now") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Button(fdaGranted ? "Start Pulse" : "Continue anyway") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(Halo.pulseGreen)
                    .controlSize(.large)
            }
        }
        .padding(36)
        .frame(width: 560, height: 520)
        .background {
            ZStack {
                Halo.void
                Halo.meshBackground
            }
        }
    }

    private func step<Content: View>(
        number: Int, title: String, body: String, granted: Bool,
        @ViewBuilder action: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: Halo.Space.lg) {
            ZStack {
                Circle()
                    .fill(granted ? Halo.pulseGreen : Halo.surface2)
                    .frame(width: 32, height: 32)
                    .shadow(color: granted ? Halo.pulseGreen.opacity(0.3) : .clear, radius: 6)
                if granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Halo.textPrimary)
                }
            }
            VStack(alignment: .leading, spacing: Halo.Space.sm) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1)
                action()
                    .padding(.top, 2)
            }
            Spacer()
        }
        .premiumCard()
    }

    private func requestNotifications() {
        notificationsAsked = true
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: OnboardingView.completeKey)
        isPresented = false
    }

    static let completeKey = "PulseOnboardingComplete"
    static var isComplete: Bool { UserDefaults.standard.bool(forKey: completeKey) }
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

private extension View {
    func eraseToAny() -> AnyView { AnyView(self) }
}
