import SwiftUI
import PulseKit

struct DisplaysPopoverSection: View {
    @ObservedObject private var brightnessEngine = BrightnessEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DISPLAYS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.textDim)
                
                Spacer()
                
                Toggle("Sync", isOn: $brightnessEngine.isAdaptiveModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10))
            }
            
            if brightnessEngine.monitors.isEmpty {
                Text("No monitors detected")
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
            } else {
                ForEach(brightnessEngine.monitors) { monitor in
                    DisplaySliderView(monitor: monitor)
                }
            }
        }
        .onAppear {
            brightnessEngine.refreshMonitors()
        }
    }
}
