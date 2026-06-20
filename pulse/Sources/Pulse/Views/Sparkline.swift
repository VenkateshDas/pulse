import SwiftUI

/// Filled line chart of recent values (0–100), ion-cyan on void.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            if points.count >= 2 {
                ZStack {
                    fillPath(points, size: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [Halo.ion.opacity(0.20), Halo.ion.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    linePath(points)
                        .stroke(Halo.ion, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let stepX = size.width / CGFloat(Sparkline.capacity - 1)
        let offset = Sparkline.capacity - values.count
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(offset + index) * stepX,
                y: size.height * (1 - min(max(value, 0), 100) / 100)
            )
        }
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

    /// Chart x-axis capacity; history scrolls right-to-left until full.
    static let capacity = 60
}
