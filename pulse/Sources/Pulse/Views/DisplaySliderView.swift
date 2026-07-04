import SwiftUI
import PulseKit

struct DisplaySliderView: View {
    let monitor: Monitor
    @ObservedObject private var brightnessEngine = BrightnessEngine.shared
    
    @State private var isDragging: Bool = false
    
    var body: some View {
        let currentBrightness = brightnessEngine.brightnessMap[monitor.id] ?? 0.0
        
        VStack(alignment: .leading, spacing: Halo.Space.xs) {
            HStack {
                Text(monitor.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Spacer()
                Text("\(Int(currentBrightness * 100))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Halo.textDim)
            }
            
            // Custom Premium Capsule Slider
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let fillWidth = max(0, min(trackWidth, trackWidth * CGFloat(currentBrightness)))

                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Halo.surface2)
                        .frame(height: 18)

                    // Track Fill
                    Capsule()
                        .fill(Halo.accentGradient(Halo.ion))
                        .frame(width: fillWidth, height: 18)
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                withAnimation(Halo.Motion.snappy) {
                                    isDragging = true
                                }
                            }
                            
                            let newValue = max(0, min(1, value.location.x / trackWidth))

                            if brightnessEngine.isAdaptiveModeEnabled && !monitor.isBuiltIn {
                                brightnessEngine.isAdaptiveModeEnabled = false
                            }
                            
                            // User-initiated transitions get smooth spring animation
                            withAnimation(Halo.Motion.snappy) {
                                brightnessEngine.setBrightness(for: monitor, to: newValue)
                            }
                        }
                        .onEnded { value in
                            withAnimation(Halo.Motion.snappy) {
                                isDragging = false
                            }
                            brightnessEngine.saveBrightnessMap()
                        }
                )
            }
            .frame(height: 18)
            .padding(.vertical, 4)
        }
        .padding(.vertical, Halo.Space.sm)
    }
}
