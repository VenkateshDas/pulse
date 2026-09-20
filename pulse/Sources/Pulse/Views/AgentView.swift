import SwiftUI
import PulseKit

enum AgentTimelineScrollEvent {
    case transcriptMutation
}

enum AgentTimelineScrollPolicy {
    /// Growing rich text can change its measured height more than once. Driving a
    /// ScrollViewReader from that mutation creates an offset/layout feedback loop.
    static func shouldScroll(for event: AgentTimelineScrollEvent) -> Bool {
        switch event {
        case .transcriptMutation: false
        }
    }
}

/// Local-first chat workspace: conversations remain navigable while Pulse
/// exposes only typed evidence and native approval controls.
struct AgentView: View {
    @State private var model = AgentModel()
    @State private var prompt = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(Halo.borderSubtle)
            VStack(spacing: 0) { header; Divider().overlay(Halo.borderSubtle); timeline; composer }
            if model.selectedTool != nil { Divider().overlay(Halo.borderSubtle); inspector }
        }
        .task { await model.start() }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: Halo.Space.sm) {
            Button { model.newConversation(); composerFocused = true } label: {
                Label("New conversation", systemImage: "square.and.pencil").font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(Halo.interactive)
            Text("RECENT").sectionLabel().padding(.top, Halo.Space.lg)
            ScrollView { LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.sessions) { session in sessionRow(session) }
            }}
            Spacer(minLength: 0)
            HStack(spacing: 6) { Circle().fill(statusColor).frame(width: 7, height: 7); Text("LOCAL AGENT").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1) }
                .foregroundStyle(Halo.textDim)
            Text("Evidence stays on this Mac.").font(.system(size: 10)).foregroundStyle(Halo.textDim)
        }.padding(Halo.Space.lg).frame(width: 216).background(Halo.surface1.opacity(0.45))
    }

    private func sessionRow(_ session: AgentSessionItem) -> some View {
        let selected = session.sessionId == model.sessionId
        return Button { Task { await model.loadSession(session.sessionId) } } label: {
            HStack(spacing: 7) {
                Circle().fill(selected && model.state == .running ? Halo.pulseGreen : .clear).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).lineLimit(1).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    Text(relativeTime(session.updatedAt)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Halo.textDim)
                }; Spacer(minLength: 0)
            }.foregroundStyle(selected ? Halo.textPrimary : Halo.textSecondary).padding(.horizontal, Halo.Space.sm).padding(.vertical, 7)
                .background(selected ? Halo.interactive.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: Halo.Radius.small)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: Halo.Space.sm) {
            Image(systemName: "sparkles").foregroundStyle(Halo.interactive)
            VStack(alignment: .leading, spacing: 2) {
                Text(activeSessionName).font(.system(size: 15, weight: .semibold))
            }; Spacer()
            Label("Local only", systemImage: "lock.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(Halo.textSecondary).padding(.horizontal, 8).padding(.vertical, 5).background(Halo.surface2, in: Capsule())
        }.padding(.horizontal, Halo.Space.xxl).padding(.vertical, Halo.Space.md)
    }

    private var timeline: some View {
        ScrollView(.vertical, showsIndicators: false) { LazyVStack(alignment: .leading, spacing: Halo.Space.md) {
            if model.items.isEmpty { welcome }
            if model.hasMoreHistory {
                Button(model.isLoadingHistory ? "Loading earlier messages…" : "Load earlier messages") {
                    Task { await model.loadEarlierHistory() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isLoadingHistory)
            }
            ForEach(model.items) { item in card(item) }
        }.padding(.horizontal, Halo.Space.xxl).padding(.vertical, Halo.Space.xl)
            .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity, alignment: .top) }
        .frame(maxHeight: .infinity)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Halo.Space.lg) {
            Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(Halo.interactive)
            Text("What can I check?").font(.system(size: 22, weight: .bold))
            Text("Ask about performance, storage, processes, displays, or safe cleanup. Pulse shows evidence before recommendations.").font(.system(size: 13)).foregroundStyle(Halo.textDim)
            HStack { suggest("Explain my health score"); suggest("What grew today?"); suggest("Find high CPU apps") }
        }.padding(.top, 72)
    }
    private func suggest(_ text: String) -> some View { Button(text) { prompt = text; composerFocused = true }.buttonStyle(.bordered).controlSize(.small) }

    @ViewBuilder private func card(_ item: AgentTimelineItem) -> some View {
        switch item.kind {
        case .user:
            Text(item.title).font(.system(size: 14)).foregroundStyle(Halo.void).padding(10).background(Halo.interactive, in: RoundedRectangle(cornerRadius: Halo.Radius.medium)).frame(maxWidth: .infinity, alignment: .trailing)
        case .approval:
            VStack(alignment: .leading, spacing: Halo.Space.sm) {
                Label(item.title, systemImage: "exclamationmark.shield.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Halo.amber)
                Text("Nothing has changed.").font(.system(size: 12, weight: .medium)); Text(item.detail).font(.system(size: 12)).foregroundStyle(Halo.textSecondary)
                HStack { Button("Decline") { model.resolveApproval(false) }; Spacer(); Button("Approve action") { model.resolveApproval(true) }.buttonStyle(.borderedProminent).tint(Halo.amber) }
            }.premiumCard().frame(maxWidth: 640)
        case .tool:
            Button { model.selectTool(id: item.id) } label: {
                HStack(spacing: Halo.Space.sm) {
                    Circle().fill(item.isRunning ? Halo.pulseGreen : Halo.interactive).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 3) { Text(item.title).font(.system(size: 12, weight: .semibold)); Text(item.isRunning ? "Working…" : compact(item.detail)).font(.system(size: 10, design: .monospaced)).lineLimit(1) }
                    Spacer(); Image(systemName: model.selectedToolID == item.id ? "sidebar.right" : "chevron.right").font(.system(size: 10))
                }.foregroundStyle(Halo.textPrimary).premiumCard(padding: Halo.Space.md)
            }.buttonStyle(.plain).frame(maxWidth: 880)
        case .progress:
            DisclosureGroup(isExpanded: Binding(
                get: { item.isExpanded },
                set: { _ in model.toggleExpansion(id: item.id) }
            )) {
                markdown(item).font(.system(size: 12)).foregroundStyle(Halo.textSecondary)
                    .padding(.top, Halo.Space.sm)
            } label: {
                Label(item.title, systemImage: item.isExpanded ? "brain.head.profile.fill" : "brain.head.profile")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Halo.textSecondary)
            }
            .tint(Halo.textDim).premiumCard(padding: Halo.Space.md).frame(maxWidth: 880)
        case .answer:
            VStack(alignment: .leading, spacing: Halo.Space.sm) {
                Label(item.title.isEmpty ? "Pulse Agent" : item.title, systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Halo.textSecondary)
                markdown(item)
                if AgentAnswerPresentation.needsExpansion(item.detail) {
                    Button(item.isExpanded ? "Show less" : "Show full response") { model.toggleExpansion(id: item.id) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }.frame(maxWidth: 960, alignment: .leading)
        case .error:
            VStack(alignment: .leading, spacing: 5) {
                Label(item.title, systemImage: "exclamationmark.triangle").font(.system(size: 11, weight: .semibold)).foregroundStyle(Halo.flare)
                Text(item.detail).font(.system(size: 12)).foregroundStyle(Halo.textPrimary).textSelection(.enabled)
            }.frame(maxWidth: 880, alignment: .leading)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: Halo.Space.md) {
            HStack { Text("EVIDENCE").sectionLabel(); Spacer(); Button { model.selectedToolID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            if let tool = model.selectedTool { Text(tool.title).font(.system(size: 13, weight: .semibold)); Text(tool.isRunning ? "Working…" : tool.detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(Halo.textSecondary).textSelection(.enabled).padding(Halo.Space.sm).frame(maxWidth: .infinity, alignment: .leading).background(Halo.surface2, in: RoundedRectangle(cornerRadius: Halo.Radius.small)) }
            Text("Typed Pulse tool output. Provider reasoning stays private.").font(.system(size: 10)).foregroundStyle(Halo.textDim); Spacer()
        }.padding(Halo.Space.lg).frame(width: 230).background(Halo.surface1.opacity(0.5))
    }

    @ViewBuilder private func markdown(_ item: AgentTimelineItem) -> some View {
        if item.rendersMarkdown {
            AgentMarkdownView(blocks: item.markdownBlocks)
        } else {
            Text(AgentAnswerPresentation.visibleSource(item.detail, isExpanded: item.isExpanded))
                .font(.system(size: 14)).lineSpacing(3).textSelection(.enabled)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.state == .idle ? "Ready" : model.status, systemImage: composerStatusIcon)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(composerStatusColor)
                .opacity(model.state == .idle ? 0 : 1)
                .frame(height: 13, alignment: .leading)
            HStack(alignment: .bottom, spacing: Halo.Space.sm) {
                TextField(model.state == .awaitingApproval ? "Approval pending" : "Ask Pulse about your Mac…", text: $prompt)
                    .textFieldStyle(.plain).frame(height: 22).focused($composerFocused).onSubmit { submit() }
                    .disabled(model.state == .running || model.state == .awaitingApproval)
                Button(action: composerAction) {
                    Image(systemName: model.state == .running ? "stop.circle.fill" : "arrow.up.circle.fill").font(.system(size: 22))
                }
                .buttonStyle(.plain).foregroundStyle(model.state == .running ? Halo.flare : Halo.interactive)
                .accessibilityLabel(model.state == .running ? "Stop response" : "Send message")
                .disabled(model.state == .running ? false : prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.state == .awaitingApproval)
            }
        }.padding(Halo.Space.md).background(Halo.surface1).overlay(alignment: .top) { Divider().overlay(Halo.borderSubtle) }.padding(.horizontal, Halo.Space.xl).padding(.vertical, Halo.Space.md)
    }

    private var activeSessionName: String { model.sessions.first(where: { $0.sessionId == model.sessionId })?.name ?? "Pulse Agent" }
    private var statusColor: Color { model.state == .awaitingApproval ? Halo.amber : model.state == .failed ? Halo.flare : Halo.pulseGreen }
    private var composerStatusColor: Color { model.state == .running ? Halo.pulseGreen : statusColor }
    private var composerStatusIcon: String { model.state == .running ? "ellipsis" : model.state == .completed ? "checkmark.circle.fill" : model.state == .cancelled ? "stop.circle.fill" : model.state == .failed ? "exclamationmark.triangle.fill" : "pause.circle.fill" }
    private func relativeTime(_ time: Int?) -> String { guard let time else { return "recent" }; let minutes = max(0, Int(Date().timeIntervalSince1970) - time) / 60; return minutes < 1 ? "now" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h" }
    private func compact(_ detail: String) -> String { detail.isEmpty ? "Complete" : detail.replacingOccurrences(of: "\n", with: " ") }
    private func composerAction() { model.state == .running ? model.cancel() : submit() }
    private func submit() { let text = prompt; prompt = ""; model.send(text) }
}
