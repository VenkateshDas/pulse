import SwiftUI
import PulseKit

struct DisplaysView: View {
    @ObservedObject private var brightnessEngine = BrightnessEngine.shared

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            header

            VStack(spacing: 0) {
                Toggle(isOn: $brightnessEngine.isAdaptiveModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Match built-in brightness")
                            .font(Halo.font(size: 13, weight: .semibold))
                            .foregroundStyle(Halo.textPrimary)
                        Text("External screens follow your built-in screen. Adjusting an external screen manually turns matching off.")
                            .font(Halo.font(size: 11))
                            .foregroundStyle(Halo.textDim)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Match built-in brightness")
                .accessibilityHint("External screens follow the built-in screen. A manual adjustment stops matching.")
                .disabled(!brightnessEngine.monitors.contains { !$0.isBuiltIn })
                .padding()

                Divider().overlay(Halo.borderSubtle)

                if brightnessEngine.monitors.isEmpty {
                    Text("No screens are available. Connect a display, then reopen this page.")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear {
            brightnessEngine.refreshMonitors()
        }
    }

    private var header: some View {
        PageHeader(
            "Displays",
            subtitle: "Make each screen comfortable. Use the slider or your keyboard to adjust brightness."
        )
    }
}
