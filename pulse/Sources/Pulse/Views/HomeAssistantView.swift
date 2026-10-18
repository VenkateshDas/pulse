import SwiftUI
import AppKit

/// After keyboard navigation, reveal a Home control covered by floating chat.
/// Reads only this app's accessibility tree; no TCC grant or polling required.
struct HomeAssistantFocusGuard: NSViewRepresentable {
    let minimize: () -> Void
    func makeNSView(context: Context) -> FocusView { FocusView(minimize: minimize) }
    func updateNSView(_ view: FocusView, context: Context) { view.minimize = minimize }
    static func dismantleNSView(_ view: FocusView, coordinator: ()) { view.stop() }

    final class FocusView: NSView {
        var minimize: () -> Void
        private var monitor: Any?
        init(minimize: @escaping () -> Void) {
            self.minimize = minimize
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 48 {
                    Task { @MainActor [weak self] in self?.revealFocusedControl() }
                }
                return event
            }
        }
        required init?(coder: NSCoder) { nil }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        private func revealFocusedControl() {
            guard monitor != nil, let window, window.isKeyWindow,
                  let focused = NSApplication.accessibilityFocusedUIElement() as? NSAccessibilityProtocol else { return }
            var ancestor: Any? = focused
            for _ in 0..<32 {
                guard let element = ancestor as? NSAccessibilityProtocol else { break }
                if element.accessibilityIdentifier() == "pulse-home-assistant" { return }
                ancestor = element.accessibilityParent()
            }
            let panelFrame = window.convertToScreen(convert(bounds, to: nil))
            if panelFrame.intersects(focused.accessibilityFrame()) { minimize() }
        }
    }
}

/// Small native controls; observing run state here never subscribes Home cards to streamed text.
struct HomeAssistantLauncher: View {
    let model: AgentModel
    let presentation: HomeAssistantState
    let open: () -> Void
    @FocusState.Binding var focused: Bool

    var body: some View {
        Button(action: open) {
            Label(presentation.label(for: model.state), systemImage: "waveform.path")
                .font(Halo.font(size: 14, weight: .semibold))
                .padding(.horizontal, 18).frame(minHeight: 44)
                .foregroundStyle(Halo.textPrimary)
                .background(Halo.surface1, in: Capsule())
                .overlay(Capsule().strokeBorder(Halo.interactive, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .accessibilityLabel("Ask Pulse")
        .accessibilityValue(presentation.label(for: model.state))
        .help("Start or continue a conversation on Home")
    }
}

struct HomeAssistantHeader: View {
    let model: AgentModel
    let fullDetail: Bool
    let expand: () -> Void
    let minimize: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path").font(.system(size: 23)).foregroundStyle(Halo.interactive)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ask Pulse").font(Halo.font(size: 15, weight: .semibold))
                Text("AI assistant").font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("New conversation") { model.newConversation() }.disabled(model.isBusy || model.workspaceBusy)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().help("Conversation options")
                .accessibilityLabel("Conversation options")
            Button(action: expand) { Image(systemName: "arrow.up.right.square") }
                .help("Open in Ask Pulse").accessibilityLabel("Open in Ask Pulse")
            Button(action: minimize) { Image(systemName: fullDetail ? "chevron.backward" : "minus") }
                .help(fullDetail ? "Back to Home" : "Minimize conversation")
                .accessibilityLabel(fullDetail ? "Back to Home" : "Minimize conversation")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Halo.textPrimary)
        .padding(16)
        .background(Halo.surface1)
        .overlay(alignment: .bottom) { Divider() }
        .onExitCommand(perform: minimize)
    }
}
