import SwiftUI
import PulseKit

struct DisplaySliderView: View {
    let monitor: Monitor
    @ObservedObject private var brightnessEngine = BrightnessEngine.shared

    private var brightness: Double { brightnessEngine.brightnessMap[monitor.id] ?? 0 }
    private var valueLabel: String {
        brightness < 0 ? "Dimmed below minimum" : "\(Int((brightness * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(monitor.name, systemImage: monitor.isBuiltIn ? "laptopcomputer" : "display")
                    .font(Halo.font(size: 14, weight: .medium)).foregroundStyle(Halo.textPrimary)
                Spacer()
                Text(valueLabel).font(Halo.font(size: 12)).monospacedDigit().foregroundStyle(Halo.textSecondary)
            }
            Slider(value: Binding(
                get: { brightness },
                set: { value in
                    // Manual adjustment must stop the sync loop fighting the user.
                    if !monitor.isBuiltIn && brightnessEngine.isAdaptiveModeEnabled {
                        brightnessEngine.isAdaptiveModeEnabled = false
                    }
                    brightnessEngine.setBrightness(for: monitor, to: value)
                }
            ), in: -1...1, step: 0.01) {
                Text("Brightness for \(monitor.name)")
            } minimumValueLabel: {
                Image(systemName: "sun.min").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "sun.max").accessibilityHidden(true)
            } onEditingChanged: { editing in
                if !editing { brightnessEngine.saveBrightnessMap() }
            }
            .accessibilityValue(valueLabel)
            .help("Below minimum brightness uses a dimming overlay. A manual change turns off matching for external screens.")
            if brightness < 0 {
                Text("An overlay dims the screen below its hardware minimum.")
                    .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
            }
            if let error = brightnessEngine.lastWriteErrors[monitor.id] {
                Label("Hardware brightness could not be changed. \(error)", systemImage: "exclamationmark.circle")
                    .font(Halo.font(size: 12)).foregroundStyle(Halo.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(monitor.name)
    }
}
