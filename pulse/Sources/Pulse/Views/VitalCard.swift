import SwiftUI

/// One vitals tile: compact ring, headline value, two detail lines,
/// session sparkline along the bottom.
struct VitalCard: View {
    let title: String
    /// 0–1 ring fill.
    let fraction: Double
    /// Override ring color (safety semantics); default = statusColor(fraction).
    var ringColor: Color?
    let value: String
    let line1: String
    let line2: String
    var history: [Double] = []
    var historyScale: Double = 100
    /// Tooltip shown when hovering the entire card
    var cardTooltip: String? = nil

    /// Optional legend rendered below the sparkline
    struct LegendItem: Equatable {
        let color: Color
        let label: String
    }
    var legend: [LegendItem]? = nil

    /// Optional secondary stat chips (small LABEL value pairs) rendered along
    /// the card footer — fills the space cards without a legend would waste.
    struct Stat: Equatable {
        let label: String
        let value: String
        var color: Color? = nil
    }
    var stats: [Stat]? = nil

    /// Optional segmented ring definition (start and end fractions, and color).
    struct Segment: Equatable {
        let start: Double
        let end: Double
        let color: Color
    }
    var segments: [Segment]? = nil

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var color: Color { ringColor ?? Halo.statusColor(clamped) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ring
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 3) {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                        if cardTooltip != nil {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                        }
                    }
                    .foregroundStyle(Halo.textDim)
                    Text(line1)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(line2)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }
            sparkline
                .frame(height: 14)
            
            if let legend = legend {
                HStack(spacing: 8) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 3) {
                            Circle().fill(item.color).frame(width: 5, height: 5)
                            Text(item.label)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Halo.textDim)
                        }
                    }
                }
            }

            if let stats = stats {
                HStack(spacing: 12) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                        HStack(spacing: 4) {
                            Text(stat.label)
                                .font(.system(size: 8, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(Halo.textDim.opacity(0.7))
                            Text(stat.value)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(stat.color ?? Halo.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Halo.border, lineWidth: 1)
        )
        .help(cardTooltip ?? "")
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Halo.surface2, lineWidth: 5)
            if let segments = segments {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
        }
        .frame(width: 46, height: 46)
    }

    @ViewBuilder
    private var sparkline: some View {
        if history.count >= 2 {
            MiniLine(values: history, scale: historyScale, color: color)
        } else {
            Color.clear
        }
    }
}

/// Minimal line trace for card footers — no fill, no axes.
struct MiniLine: View {
    let values: [Double]
    let scale: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: CGFloat(index) * stepX,
                        y: geo.size.height * (1 - min(max(value / scale, 0), 1))
                    )
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }
}
