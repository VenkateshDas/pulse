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
                
                // Map currentBrightness (-1...1) to (0...1) fraction for width
                let fraction = (currentBrightness + 1.0) / 2.0
                let fillWidth = max(0, min(trackWidth, trackWidth * CGFloat(fraction)))
                
                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Halo.surface2)
                        .frame(height: 18)
                        
                    // Track Fill
                    Capsule()
                        .fill(Halo.accentGradient(Halo.ion))
                        .frame(width: fillWidth, height: 18)
                        
                    // Zero Marker (Optional, shows where 0% / hardware boundary is)
                    if currentBrightness < 0.0 {
                        Capsule()
                            .fill(Halo.textPrimary.opacity(0.8))
                            .frame(width: 2, height: 18)
                            .offset(x: trackWidth / 2)
                    }
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
                            
                            let dragFraction = max(0, min(1, value.location.x / trackWidth))
                            let newValue = (dragFraction * 2.0) - 1.0 // Map (0...1) back to (-1...1)
                            
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
