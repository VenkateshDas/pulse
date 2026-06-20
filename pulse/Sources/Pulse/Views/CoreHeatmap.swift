import PulseKit
import SwiftUI

/// Compact grid of CPU cores showing real-time utilization as a heatmap.
struct CoreHeatmap: View {
    let cpuPerCore: [Double]

    private let columns = [GridItem(.adaptive(minimum: 14, maximum: 18), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("PER-CORE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .help("Instantaneous load distribution across all CPU cores")
            }
            .foregroundStyle(Halo.textDim)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Array(cpuPerCore.enumerated()), id: \.offset) { index, usage in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: usage))
                        .aspectRatio(1, contentMode: .fit)
                        .help("Core \(index): \(Int(usage))%")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: Halo.Radius.large)
    }

    private func color(for usage: Double) -> Color {
        switch usage {
        case 0..<15: return Halo.surface2
        case 15..<40: return Halo.ion.opacity(0.4)
        case 40..<75: return Halo.ion
        case 75..<90: return Halo.amber
        default: return Halo.flare
        }
    }
}
