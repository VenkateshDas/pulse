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

    @State private var isHovered = false

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var color: Color { ringColor ?? Halo.statusColor(clamped) }

    var body: some View {
        VStack(alignment: .leading, spacing: Halo.Space.sm) {
            HStack(spacing: 12) {
                ring
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 4) {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
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
                .frame(height: 18)

            if let legend = legend {
                HStack(spacing: 10) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.color)
                                .frame(width: 8, height: 4)
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
        .padding(Halo.Space.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous)
                .fill(Halo.surface1)
                .shadow(
                    color: isHovered
                        ? color.opacity(0.15)
                        : Halo.Shadow.cardColor,
                    radius: isHovered ? Halo.Shadow.elevatedRadius : Halo.Shadow.cardRadius,
                    y: isHovered ? Halo.Shadow.elevatedY : Halo.Shadow.cardY
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: Halo.Radius.medium, style: .continuous)
                .strokeBorder(
                    isHovered ? color.opacity(0.25) : Halo.borderSubtle,
                    lineWidth: isHovered ? 1 : 0.5
                )
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(Halo.Motion.snappy, value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .contentShape(RoundedRectangle(cornerRadius: Halo.Radius.medium))
        .help(cardTooltip ?? "")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Halo.surface2, lineWidth: 3)
            if let segments = segments {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(Halo.Motion.ring, value: clamped)
                    .shadow(color: color.opacity(0.3), radius: 6)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Halo.textPrimary)
        }
        .frame(width: 48, height: 48)
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
            ZStack {
                fillPath(in: geo.size)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.12), color.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                linePath(in: geo.size)
                    .stroke(
                        color.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
            }
        }
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            let stepX = size.width / CGFloat(max(values.count - 1, 1))
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height * (1 - min(max(value / scale, 0), 1))
                )
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }

    private func fillPath(in size: CGSize) -> Path {
        Path { path in
            let stepX = size.width / CGFloat(max(values.count - 1, 1))
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height * (1 - min(max(value / scale, 0), 1))
                )
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: size.height))
            path.closeSubpath()
        }
    }
}
