import SwiftUI
import PulseKit

struct DisplaysView: View {
    @ObservedObject private var brightnessEngine = BrightnessEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            VStack(spacing: 0) {
                Toggle(isOn: $brightnessEngine.isAdaptiveModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adaptive Sync")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Halo.textPrimary)
                        Text("Syncs external monitors to the built-in display's ambient brightness.")
                            .font(.system(size: 11))
                            .foregroundStyle(Halo.textDim)
                    }
                }
                .toggleStyle(.switch)
                .padding()
                
                Divider().overlay(Halo.borderSubtle)
                
                if brightnessEngine.monitors.isEmpty {
                    Text("No monitors detected.")
                        .font(.subheadline)
                        .foregroundStyle(Halo.textDim)
                        .padding()
                } else {
                    ForEach(brightnessEngine.monitors) { monitor in
                        DisplaySliderView(monitor: monitor)
                            .padding(.horizontal)
                        if monitor != brightnessEngine.monitors.last {
                            Divider().overlay(Halo.borderSubtle)
                        }
                    }
                }
            }
            .padding(16)
            .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear {
            brightnessEngine.refreshMonitors()
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Displays")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Halo.textPrimary)
            Text(
                "Intelligent adaptive brightness for built-in and external displays."
            )
            .font(.system(size: 12))
            .foregroundStyle(Halo.textDim)
        }
    }
}
