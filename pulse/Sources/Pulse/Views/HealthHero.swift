import PulseKit
import SwiftUI

// MARK: - Color mapping

extension HealthScore.Band {
    var color: Color {
        switch self {
        case .excellent: Halo.pulseGreen
        case .good: Halo.ion
        case .fair: Halo.amber
        case .poor: Halo.flare
        }
    }
}

extension Diagnosis.Severity {
    var color: Color {
        switch self {
        case .clear: Halo.pulseGreen
        case .info: Halo.ion
        case .warn: Halo.amber
        case .critical: Halo.flare
        }
    }
}

// MARK: - Score ring

/// Circular 0–100 health gauge with the number centered. Band drives color.
struct HealthScoreRing: View {
    let score: HealthScore
    var diameter: CGFloat = 96
    var lineWidth: CGFloat = 9
    /// When false, the ring is drawn empty (no score/band text inside) — used
    /// by the compact menu-bar popover.
    var showsLabel: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Halo.surface2, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(score.value) / 100)
                .stroke(score.band.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: score.value)
            if showsLabel {
                VStack(spacing: 0) {
                    Text("\(score.value)")
                        .font(.system(size: diameter * 0.32, weight: .bold, design: .rounded))
                        .foregroundStyle(Halo.textPrimary)
                        .contentTransition(.numericText())
                    Text(score.band.rawValue.uppercased())
                        .font(.system(size: diameter * 0.1, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(score.band.color)
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Diagnosis line + culprit chip

/// The verdict line with a colored dot and an optional tappable culprit chip
/// that deep-links to the Monitor tab.
struct DiagnosisBadge: View {
    let diagnosis: Diagnosis
    var culpritName: String?
    /// Fired when the culprit chip is tapped (RootView navigates to Monitor).
    var onCulpritTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(diagnosis.severity.color)
                .frame(width: 8, height: 8)
            Text(diagnosis.line)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            if let name = culpritName, diagnosis.culpritPID != nil {
                Button {
                    onCulpritTap?()
                } label: {
                    HStack(spacing: 4) {
                        Text(name).lineLimit(1)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(diagnosis.severity.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(diagnosis.severity.color.opacity(0.15),
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Show \(name) in Monitor")
            }
        }
    }
}
