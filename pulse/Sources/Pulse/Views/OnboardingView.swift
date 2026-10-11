import AppKit
import SwiftUI

/// First run explains the task model; permissions are requested where needed.
struct OnboardingView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("Pulse", systemImage: "circle.inset.filled")
                .font(Halo.font(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Halo.interactive)
            Text("A little clarity for your Mac")
                .font(Halo.font(size: 28, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Understand what's happening, choose what to do, and see the result.")
                .font(Halo.font(size: 14)).foregroundStyle(Halo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 20) {
                benefit("Find room for what matters", detail: "Review files and apps before moving anything to Trash.", symbol: "internaldrive")
                benefit("Make sense of a slowdown", detail: "See which apps are busy and check while the problem happens.", symbol: "waveform.path.ecg")
                benefit("Stay in control", detail: "Pulse explains permissions when a task needs them. Technical details are always available.", symbol: "hand.raised")
            }
            Divider()
            Text("Items in Trash can usually be restored. Emptying Trash permanently removes them. Some maintenance actions have different recovery limits, which Pulse explains before you act.")
                .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Get started") { finish() }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Halo.onAccent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 520)
        .background(Halo.surface1)
        .tint(Halo.interactive)
    }

    private func benefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(Halo.interactive).font(Halo.font(size: 18))
                .frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Halo.font(size: 14, weight: .semibold)).foregroundStyle(Halo.textPrimary)
                Text(detail).font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completeKey)
        PermissionsGate.markPrompted()
        isPresented = false
    }

    nonisolated static let completeKey = "PulseOnboardingComplete"
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
