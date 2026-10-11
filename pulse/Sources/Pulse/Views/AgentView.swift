import SwiftUI
import PulseKit

struct AgentView: View {
    @State private var model = AgentModel()
    @State private var prompt = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.hasApiKey && model.state != .starting { providerSetup } else { timeline; composer }
        }
        .background(Halo.void)
        .task { await model.start() }
    }

    private var providerSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Set up Ask Pulse", systemImage: "bubble.left.and.text.bubble.right")
                .font(Halo.font(size: 22, weight: .semibold))
            Text("Ask questions about your Mac in everyday language. This optional feature needs an AI provider and an API key; the rest of Pulse works without it.")
            Text("Your questions and requested diagnostic results are sent to the provider you choose. Provider charges may apply. Review the provider settings before sending a question.")
                .foregroundStyle(Halo.textSecondary)
            Button("Open provider settings") { PulseNavigation.open(.settings) }
                .buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent)
            Button("Check setup again") { Task { await model.start() } }.buttonStyle(.bordered)
        }.font(Halo.font(size: 14)).frame(maxWidth: 640, alignment: .leading)
            .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        PageHeader("Ask Pulse", subtitle: model.status) {
            Menu("Conversations") {
                Button("New conversation") { model.newConversation() }
                ForEach(model.sessions.prefix(20)) { session in
                    Button(session.name) { Task { await model.loadSession(session.sessionId) } }
                }
            }.disabled(model.isBusy)
            if model.state == .running || model.state == .awaitingApproval {
                Button("Stop") { model.cancel() }.buttonStyle(.bordered)
            }
            if model.state == .failed { Button("Reconnect") { Task { await model.start() } }.buttonStyle(.bordered) }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Halo.Space.md) {
                    if model.items.isEmpty { welcome }
                    ForEach(model.items) { item in card(item) }
                    Color.clear.frame(height: 1).id("end")
                }.padding(Halo.Space.xxl)
            }
            .overlay(alignment: .bottomTrailing) {
                if !model.items.isEmpty {
                    Button("Jump to latest") { proxy.scrollTo("end", anchor: .bottom) }
                        .buttonStyle(.bordered).padding(12)
                }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Halo.Space.lg) {
            Image(systemName: "sparkles").font(Halo.font(size: 30)).foregroundStyle(Halo.interactive)
            Text("What can I check?").font(Halo.font(size: 22, weight: .bold))
            Text("Ask about performance, storage, processes, displays, or safe cleanup. I show evidence before recommendations.")
                .font(Halo.font(size: 13)).foregroundStyle(Halo.textDim)
            VStack(alignment: .leading) { suggestion("Why does my Mac feel slow?"); suggestion("What can I review to free up space?"); suggestion("Which apps are busy?") }
        }.frame(maxWidth: 640).padding(.top, 80)
    }

    private func suggestion(_ text: String) -> some View {
        Button(text) { prompt = text; composerFocused = true }.buttonStyle(.bordered).controlSize(.small)
    }

    @ViewBuilder private func card(_ item: AgentTimelineItem) -> some View {
        switch item.kind {
        case .user:
            Text(item.title).font(Halo.font(size: 14)).foregroundStyle(Halo.onAccent).padding(10)
                .background(Halo.interactive, in: RoundedRectangle(cornerRadius: Halo.Radius.medium)).frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("You: \(item.title)")
        case .approval:
            VStack(alignment: .leading, spacing: Halo.Space.sm) {
                Label(item.title, systemImage: "exclamationmark.shield.fill").font(Halo.font(size: 14, weight: .bold)).foregroundStyle(Halo.amber)
                Text(item.detail).font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                Text("Review the affected items and effects above. Declining prevents this proposed action; earlier completed actions stay in effect.")
                    .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
                HStack {
                    Button("Decline action") { model.resolveApproval(false) }.buttonStyle(.bordered)
                    Button("Approve this action") { model.resolveApproval(true) }
                        .buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent)
                }.disabled(model.state != .awaitingApproval || model.items.last(where: { $0.kind == .approval })?.id != item.id)
            }.premiumCard().frame(maxWidth: 620)
        case .tool:
            DisclosureGroup(isExpanded: Binding(get: { item.isExpanded }, set: { _ in model.toggleExpansion(id: item.id) })) {
                Text(item.detail.isEmpty && item.isRunning ? "Working…" : item.detail)
                    .font(Halo.font(size: 12, design: .monospaced)).foregroundStyle(Halo.textPrimary)
                    .textSelection(.enabled).padding(.top, Halo.Space.xs)
            } label: {
                Label(item.title, systemImage: icon(for: item.kind)).font(Halo.font(size: 12, weight: .semibold)).foregroundStyle(color(for: item.kind))
            }.premiumCard(padding: Halo.Space.md).frame(maxWidth: 620)
        default:
            VStack(alignment: .leading, spacing: 5) {
                if !item.title.isEmpty { Label(item.title, systemImage: icon(for: item.kind)).font(Halo.font(size: 12, weight: .semibold)).foregroundStyle(color(for: item.kind)) }
                Text(item.detail.isEmpty && item.isRunning ? "Working…" : item.detail).font(Halo.font(size: item.kind == .answer ? 14 : 12, design: item.kind == .tool ? .monospaced : .default)).foregroundStyle(Halo.textPrimary).textSelection(.enabled)
            }.premiumCard(padding: Halo.Space.md).frame(maxWidth: item.kind == .answer ? 720 : 620)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Halo.Space.sm) {
            TextField("Ask Pulse about your Mac…", text: $prompt, axis: .vertical)
                .accessibilityLabel("Question for Pulse").textFieldStyle(.plain).lineLimit(1...4).focused($composerFocused)
                .onSubmit { submit() }
            Button("Send", systemImage: "arrow.up", action: submit)
                .buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent).disabled(!model.hasApiKey || model.state == .starting || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.state == .running || model.state == .awaitingApproval)
        }.padding(Halo.Space.md).background(Halo.surface1).overlay(alignment: .top) { Divider().overlay(Halo.borderSubtle) }.padding(.horizontal, Halo.Space.xl).padding(.vertical, Halo.Space.md)
    }

    private func submit() {
        guard model.hasApiKey, !model.isBusy, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = prompt; prompt = ""; model.send(text)
    }
    private func icon(for kind: AgentTimelineItem.Kind) -> String { switch kind { case .answer: "sparkles"; case .progress: "ellipsis"; case .tool: "wrench.and.screwdriver"; case .error: "exclamationmark.triangle"; default: "circle" } }
    private func color(for kind: AgentTimelineItem.Kind) -> Color { kind == .error ? Halo.flare : kind == .tool ? Halo.interactive : Halo.textSecondary }
}
