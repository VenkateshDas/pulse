import SwiftUI
import PulseKit
import PulseCommands

struct AgentView: View {
    @Bindable var model: AgentModel
    var visible: Bool = true
    @Environment(DashboardModel.self) private var dashboard
    @State private var webFailure: String?

    var body: some View {
        Group {
            if let webFailure {
                ContentUnavailableView {
                    Label("Ask Pulse could not render", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: { Text(webFailure) } actions: {
                    Button("Reload interface") { self.webFailure = nil }
                }
            } else if visible {
                AgentWebView(model: model, failure: $webFailure)
            } else { Color.clear }
        }
        .background(Halo.void)
        .task {
            model.visibilityChanged(visible)
            await AgentNativeBridge.shared.configureContext {
                guard let snapshot = dashboard.snapshot else { return "{\"unavailable\":\"No current visible snapshot\"}" }
                return (try? CLIOutput.json(VitalsDTO(snapshot: snapshot))) ?? "{}"
            }
            if visible { await model.start() }
        }
        .onChange(of: visible) { _, value in
            model.visibilityChanged(value)
            if value { Task { await model.start() } }
        }
        .onDisappear { model.visibilityChanged(false) }
    }
}
