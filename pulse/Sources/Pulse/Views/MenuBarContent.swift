import PulseKit
import SwiftUI

/// Compact popover shown from the menu bar item.
struct MenuBarContent: View {
    @Environment(DashboardModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = model.snapshot {
                stat("CPU", String(format: "%.0f%%", snapshot.cpuTotalPercent),
                     fraction: snapshot.cpuTotalPercent / 100)
                stat("Memory", ByteFormat.string(snapshot.memoryUsedBytes),
                     fraction: snapshot.memoryUsedFraction)
                stat("Disk free", ByteFormat.string(snapshot.diskFreeBytes),
                     fraction: snapshot.diskUsedFraction)
            } else {
                Text("Sampling…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }

            Divider().overlay(Halo.surface2)

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

            Button("Quit Pulse") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Halo.textDim)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.viewAppeared() }
        .onDisappear { model.viewDisappeared() }
        .padding(14)
        .frame(width: 260)
        .background(Halo.void)
        .preferredColorScheme(.dark)
    }

    private func stat(_ label: String, _ value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
            }
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
    }
}
