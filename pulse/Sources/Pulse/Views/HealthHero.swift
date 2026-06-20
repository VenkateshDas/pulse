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
    /// What to draw inside the ring. The compact menu-bar popover uses
    /// `.scoreOnly` (number, no band word).
    enum LabelMode { case full, scoreOnly, none }

    let score: HealthScore
    var diameter: CGFloat = 96
    var lineWidth: CGFloat = 9
    var labelMode: LabelMode = .full

    var body: some View {
        ZStack {
            Circle()
                .stroke(Halo.surface2, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(score.value) / 100)
                .stroke(
                    score.band.color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Halo.Motion.ring, value: score.value)
                .shadow(color: score.band.color.opacity(0.3), radius: 8)
            label
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private var label: some View {
        switch labelMode {
        case .none:
            EmptyView()
        case .scoreOnly:
            Text("\(score.value)")
                .font(.system(size: diameter * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(Halo.textPrimary)
                .contentTransition(.numericText())
        case .full:
            VStack(spacing: 1) {
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
        HStack(spacing: Halo.Space.sm) {
            ZStack {
                Circle()
                    .fill(diagnosis.severity.color.opacity(0.15))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(diagnosis.severity.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: diagnosis.severity.color.opacity(0.4), radius: 4)
            }
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        diagnosis.severity.color.opacity(0.12),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(diagnosis.severity.color.opacity(0.2), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .help("Show \(name) in Monitor")
            }
        }
    }
}
