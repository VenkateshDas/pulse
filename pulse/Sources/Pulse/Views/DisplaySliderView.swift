import AppKit
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
            NativeBrightnessSlider(
                value: Binding(
                    get: { brightness },
                    set: { value in
                        // Manual changes must stop matching from fighting the user.
                        if !monitor.isBuiltIn && brightnessEngine.isAdaptiveModeEnabled {
                            brightnessEngine.isAdaptiveModeEnabled = false
                        }
                        brightnessEngine.setBrightness(for: monitor, to: value)
                    }),
                label: "Brightness for \(monitor.name)", valueDescription: valueLabel,
                onCommit: { brightnessEngine.saveBrightnessMap() })
                .frame(height: 28)
            Text("Below minimum brightness uses a dimming overlay.")
                .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
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
    }
}

/// NSSlider provides the native adjustable accessibility role and keyboard
/// behavior. SwiftUI's slider was rendered but missing from the macOS 26 AX
/// tree during runtime verification. Save only after editing completes.
private struct NativeBrightnessSlider: NSViewRepresentable {
    @Binding var value: Double
    let label: String
    let valueDescription: String
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> BrightnessControl {
        let slider = BrightnessControl(value: value, minValue: -1, maxValue: 1,
                                       target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isContinuous = true
        slider.altIncrementValue = 0.01
        slider.onCommit = onCommit
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateNSView(slider, context: context)
        return slider
    }
    func updateNSView(_ slider: BrightnessControl, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = value
        slider.onCommit = onCommit
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityValueDescription(valueDescription)
    }
    final class Coordinator: NSObject {
        var parent: NativeBrightnessSlider
        init(_ parent: NativeBrightnessSlider) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) { parent.value = sender.doubleValue }
    }
}

private final class BrightnessControl: NSSlider {
    var onCommit: () -> Void = {}
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onCommit()
    }
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        onCommit()
    }
}
