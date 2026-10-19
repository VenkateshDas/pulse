import SwiftUI

struct AgentView: View {
    @Bindable var model: AgentModel
    var compact = false
    var minimize: () -> Void = {}
    var openSettings: () -> Void = { PulseNavigation.open(.settings) }
    @State private var webFailure: String?

    var body: some View {
        Group {
            if let webFailure {
                ContentUnavailableView {
                    Label("Ask Pulse could not render", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: { Text(webFailure) } actions: {
                    Button("Reload interface") { self.webFailure = nil }
                }
            } else {
                // Evaluate in body while visible: updateNSView alone does not
                // establish SwiftUI's Observation dependencies.
                AgentWebView(model: model, snapshot: AgentWebView.snapshot(for: model, largerText: ThemeManager.shared.largerText, compact: compact), failure: $webFailure, minimize: minimize, openSettings: openSettings)
            }
        }
        .background(Halo.void)
    }
}
