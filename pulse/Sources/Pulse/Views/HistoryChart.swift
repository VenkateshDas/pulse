import SwiftUI

/// Filled line chart over a fixed-width minute series (0–100). nil values
/// are gaps (app closed, Mac asleep) and break the line into segments —
/// honesty rule: never draw data that wasn't sampled.
struct HistoryChart: View {
    /// One slot per minute, oldest first; count defines the x-axis width.
    let values: [Double?]
    var color: Color = Halo.ion
    var maxValue: Double = 100

    var body: some View {
        GeometryReader { geo in
            let segments = segments(in: geo.size)
            ZStack {
                gridLines(in: geo.size)
                ForEach(segments.indices, id: \.self) { index in
                    let points = segments[index]
                    if points.count >= 2 {
                        fillPath(points, size: geo.size)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.20), .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        linePath(points)
                            .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    } else if let only = points.first {
                        // Isolated minute (gap on both sides): a dot, not nothing.
                        Circle()
                            .fill(color)
                            .frame(width: 2.5, height: 2.5)
                            .position(only)
                    }
                }
            }
        }
    }

    /// Consecutive non-nil runs mapped to chart coordinates.
    private func segments(in size: CGSize) -> [[CGPoint]] {
        guard values.count >= 2 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        for (index, value) in values.enumerated() {
            guard let value else {
                if !current.isEmpty {
                    result.append(current)
                    current = []
                }
                continue
            }
            current.append(
                CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height * (1 - min(max(value, 0), maxValue) / maxValue)
                ))
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func gridLines(in size: CGSize) -> some View {
        Path { path in
            for fraction in [0.25, 0.5, 0.75] {
                let y = size.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Halo.textDim.opacity(0.08), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func fillPath(_ points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: points[0].x, y: size.height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            path.closeSubpath()
        }
    }
}
