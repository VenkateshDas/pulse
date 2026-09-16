import SwiftUI

struct AgentView: View {
    @State private var model = AgentModel()
    @State private var prompt = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sessionRail
            Divider().overlay(Halo.borderSubtle)
            VStack(spacing: 0) {
                header
                Divider().overlay(Halo.borderSubtle)
                timeline
                composer
            }
        }
        .task { await model.start() }
    }

    private var sessionRail: some View {
        VStack(alignment: .leading, spacing: Halo.Space.md) {
            Button { model.sessionId = nil; model.items = [] } label: {
                Label("New conversation", systemImage: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(Halo.interactive)
            Text("RECENT").sectionLabel()
            ForEach(model.sessions.prefix(8)) { session in
                Button { model.sessionId = session.sessionId; model.items = [] } label: {
                    Text(session.name).lineLimit(1).font(.system(size: 12)).foregroundStyle(Halo.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }.buttonStyle(.plain)
            }
            Spacer()
            Text("Local agent").font(.system(size: 10, design: .monospaced)).foregroundStyle(Halo.textDim)
        }
        .padding(Halo.Space.lg).frame(width: 200).background(Halo.surface1.opacity(0.45))
    }

    private var header: some View {
        PageHeader("Pulse Agent", subtitle: model.status) {
            if model.state == .running { Button("Cancel") { model.cancel() }.buttonStyle(.bordered) }
        }.padding(.horizontal, Halo.Space.xxl).padding(.vertical, Halo.Space.lg)
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
            .onChange(of: model.items.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Halo.Space.lg) {
            Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(Halo.interactive)
            Text("What can I check?").font(.system(size: 22, weight: .bold))
            Text("Ask about performance, storage, processes, displays, or safe cleanup. I show evidence before recommendations.")
                .font(.system(size: 13)).foregroundStyle(Halo.textDim)
            HStack { suggestion("Explain my health score"); suggestion("What grew today?"); suggestion("Find high CPU apps") }
        }.frame(maxWidth: 640).padding(.top, 80)
    }

    private func suggestion(_ text: String) -> some View {
        Button(text) { prompt = text; composerFocused = true }.buttonStyle(.bordered).controlSize(.small)
    }

    @ViewBuilder private func card(_ item: AgentTimelineItem) -> some View {
        switch item.kind {
        case .user:
            Text(item.title).font(.system(size: 14)).foregroundStyle(Halo.void).padding(10)
                .background(Halo.interactive, in: RoundedRectangle(cornerRadius: Halo.Radius.medium)).frame(maxWidth: .infinity, alignment: .trailing)
        case .approval:
            VStack(alignment: .leading, spacing: Halo.Space.sm) {
                Label(item.title, systemImage: "exclamationmark.shield.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Halo.amber)
                Text(item.detail).font(.system(size: 12)).foregroundStyle(Halo.textSecondary)
                HStack { Button("Cancel") { model.resolveApproval(false) }; Button("Approve action") { model.resolveApproval(true) }.buttonStyle(.borderedProminent).tint(Halo.amber) }
            }.premiumCard().frame(maxWidth: 620)
        default:
            VStack(alignment: .leading, spacing: 5) {
                if !item.title.isEmpty { Label(item.title, systemImage: icon(for: item.kind)).font(.system(size: 12, weight: .semibold)).foregroundStyle(color(for: item.kind)) }
                Text(item.detail.isEmpty && item.isRunning ? "Working…" : item.detail).font(.system(size: item.kind == .answer ? 14 : 12, design: item.kind == .tool ? .monospaced : .default)).foregroundStyle(Halo.textPrimary).textSelection(.enabled)
            }.premiumCard(padding: Halo.Space.md).frame(maxWidth: item.kind == .answer ? 720 : 620)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Halo.Space.sm) {
            TextField("Ask Pulse about your Mac…", text: $prompt, axis: .vertical).textFieldStyle(.plain).lineLimit(1...4).focused($composerFocused)
                .onSubmit { submit() }
            Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
                .buttonStyle(.plain).foregroundStyle(Halo.interactive).disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.state == .running || model.state == .awaitingApproval)
        }.padding(Halo.Space.md).background(Halo.surface1).overlay(alignment: .top) { Divider().overlay(Halo.borderSubtle) }.padding(.horizontal, Halo.Space.xl).padding(.vertical, Halo.Space.md)
    }

    private func submit() { let text = prompt; prompt = ""; model.send(text) }
    private func icon(for kind: AgentTimelineItem.Kind) -> String { switch kind { case .answer: "sparkles"; case .progress: "ellipsis"; case .tool: "wrench.and.screwdriver"; case .error: "exclamationmark.triangle"; default: "circle" } }
    private func color(for kind: AgentTimelineItem.Kind) -> Color { kind == .error ? Halo.flare : kind == .tool ? Halo.interactive : Halo.textSecondary }
}
