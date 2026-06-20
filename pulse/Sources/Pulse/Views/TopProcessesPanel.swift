import PulseKit
import SwiftUI

/// Top processes by CPU with proportional usage bars.
struct TopProcessesPanel: View {
    let processes: [ProcessSample]
    @State private var hoveredPID: Int32?

    var body: some View {
        VStack(alignment: .leading, spacing: Halo.Space.lg) {
            HStack {
                HStack(spacing: 4) {
                    Text("PROCESSES")
                        .sectionLabel()
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .help("Top active processes ranked by CPU usage")
                }
                .foregroundStyle(Halo.textDim)
                Spacer()
                Text("CPU · RAM")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }

            let maxCPU = max(processes.map(\.cpuPercent).max() ?? 1, 1)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(processes) { process in
                        row(process, maxCPU: maxCPU)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .premiumCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ process: ProcessSample, maxCPU: Double) -> some View {
        let isHovered = hoveredPID == process.pid
        return HStack(spacing: 10) {
            Text(process.name)
                .font(.system(size: 12, weight: isHovered ? .medium : .regular))
                .foregroundStyle(Halo.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule().fill(Halo.surface2)
                Capsule()
                    .fill(barGradient(process.cpuPercent))
                    .scaleEffect(
                        x: max(process.cpuPercent / maxCPU, 0.03), y: 1, anchor: .leading)
            }
            .frame(width: 80, height: 4)
            .clipShape(Capsule())

            Text(String(format: "%5.1f%%", process.cpuPercent))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(
                    process.cpuPercent >= 80 ? Halo.amber : Halo.textDim
                )
                .frame(width: 48, alignment: .trailing)

            Text(ByteFormat.string(process.residentBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, Halo.Space.sm)
        .padding(.vertical, 5)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                    .fill(Halo.surface2.opacity(0.5))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredPID = hovering ? process.pid : nil
            }
        }
    }

    private func barGradient(_ cpuPercent: Double) -> LinearGradient {
        let colors: [Color] =
            cpuPercent >= 80
            ? [Halo.amber, Halo.flare]
            : [Halo.ion, Halo.volt]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
