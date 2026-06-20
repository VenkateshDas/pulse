import PulseKit
import SwiftUI

/// Compact grid of CPU cores showing real-time utilization as a heatmap.
struct CoreHeatmap: View {
    let cpuPerCore: [Double]

    private let columns = [GridItem(.adaptive(minimum: 16, maximum: 20), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: Halo.Space.md) {
            HStack(spacing: 4) {
                Text("PER-CORE")
                    .sectionLabel()
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .help("Instantaneous load distribution across all CPU cores")
            }
            .foregroundStyle(Halo.textDim)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(Array(cpuPerCore.enumerated()), id: \.offset) { index, usage in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color(for: usage))
                        .aspectRatio(1, contentMode: .fit)
                        .shadow(color: glowColor(for: usage), radius: usage > 75 ? 4 : 0)
                        .help("Core \(index): \(Int(usage))%")
                }
            }
        }
        .premiumCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for usage: Double) -> Color {
        switch usage {
        case 0..<15: return Halo.surface2
        case 15..<40: return Halo.ion.opacity(0.35)
        case 40..<75: return Halo.ion
        case 75..<90: return Halo.amber
        default: return Halo.flare
        }
    }

    private func glowColor(for usage: Double) -> Color {
        switch usage {
        case 75..<90: return Halo.amber.opacity(0.3)
        case 90...: return Halo.flare.opacity(0.4)
        default: return .clear
        }
    }
}
