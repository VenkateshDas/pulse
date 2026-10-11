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
                .stroke(Halo.surface2, lineWidth: lineWidth - 1)
            Circle()
                .trim(from: 0, to: CGFloat(score.value) / 100)
                .stroke(score.band.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score \(score.value) of 100, \(score.band.rawValue)")
    }

    @ViewBuilder
    private var label: some View {
        switch labelMode {
        case .none:
            EmptyView()
        case .scoreOnly:
            Text("\(score.value)")
                .font(Halo.font(size: diameter * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(Halo.textPrimary)
                .monospacedDigit()
        case .full:
            VStack(spacing: 0) {
                Text("\(score.value)")
                    .font(Halo.font(size: diameter * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(Halo.textPrimary)
                    .monospacedDigit()
                Text(score.band.rawValue.capitalized)
                    .font(Halo.font(size: diameter * 0.1, weight: .bold))
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
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(diagnosis.severity.color.opacity(0.15))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(diagnosis.severity.color)
                    .frame(width: 8, height: 8)
            }
            Text(diagnosis.line)
                .font(Halo.font(size: 13, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            if let name = culpritName, diagnosis.culpritPID != nil {
                Button {
                    onCulpritTap?()
                } label: {
                    HStack(spacing: 4) {
                        Text(name).lineLimit(1)
                        Image(systemName: "arrow.up.right")
                            .font(Halo.font(size: 8, weight: .bold))
                    }
                    .font(Halo.font(size: 11, weight: .medium))
                    .foregroundStyle(diagnosis.severity.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(diagnosis.severity.color.opacity(0.15),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(diagnosis.severity.color.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Show \(name) in Monitor")
            }
        }
    }
}
