import PulseKit
import SwiftUI

/// Top processes by CPU with proportional usage bars.
struct TopProcessesPanel: View {
    let processes: [ProcessSample]
    @State private var hoveredPID: Int32?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 4) {
                    Text("PROCESSES")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
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

            let groups = ProcessGrouper.group(processes)
            let maxCPU = max(groups.map(\.cpuPercent).max() ?? 1, 1)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(groups) { group in
                        row(group, maxCPU: maxCPU)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(cornerRadius: Halo.Radius.large)
    }

    private func row(_ process: ProcessGroup, maxCPU: Double) -> some View {
        let isHover = hoveredPID == process.topPID
        return HStack(spacing: 10) {
            Image(nsImage: ProcessIconCache.icon(for: process.topPID))
                .resizable()
                .frame(width: 14, height: 14)
            Text(process.count > 1 ? "\(process.name) (\(process.count))" : process.name)
                .font(.system(size: 12))
                .foregroundStyle(Halo.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // scaleEffect is a render-only transform — bar growth never
            // triggers a layout pass (GeometryReader + frame(width:) does).
            ZStack(alignment: .leading) {
                Capsule().fill(Halo.surface2)
                Capsule()
                    .fill(barGradient(process.cpuPercent))
                    .scaleEffect(
                        x: max(process.cpuPercent / maxCPU, 0.03), y: 1, anchor: .leading)
            }
            .frame(width: 80, height: 5)
            .clipShape(Capsule())

            Text(String(format: "%5.1f%%", process.cpuPercent))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(process.cpuPercent >= 80 ? Halo.amber : Halo.textDim)
                .frame(width: 48, alignment: .trailing)

            Text(ByteFormat.string(process.residentBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textDim)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHover ? Halo.surface2.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: Halo.Radius.small))
        .onHover { hoveredPID = $0 ? process.topPID : nil }
    }

    private func barGradient(_ cpuPercent: Double) -> LinearGradient {
        let colors: [Color] =
            cpuPercent >= 80
            ? [Halo.amber, Halo.flare]
            : [Halo.ion, Halo.volt]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
