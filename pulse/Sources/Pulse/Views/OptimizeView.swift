import PulseKit
import SwiftUI

/// Disk → Optimize tab: a risk-grouped maintenance checklist with dry-run
/// previews, skip reasons, and a trust panel of operations we refuse to do.
struct OptimizeView: View {
    @Environment(OptimizeModel.self) private var model
    @State private var showRefusals = false
    @State private var reviewTasks: [OptimizeTask] = []
    @State private var showingReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.tasks.contains(where: { $0.needsSudo && model.state(for: $0.id).skipReason == nil && model.state(for: $0.id).loaded }) { adminBanner }
                ForEach(OptimizeTask.Risk.allCases, id: \.self) { risk in
                    let group = model.tasks.filter { $0.risk == risk }
                    if !group.isEmpty { section(risk, group) }
                }
                refusalPanel
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Halo.void)
        .onAppear { model.loadIfNeeded() }
        .confirmationDialog("Run selected maintenance?", isPresented: $showingReview, titleVisibility: .visible) {
            Button("Run selected tasks") { Task { await model.runSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(reviewTasks.map { "\($0.label): \($0.detail)" }.joined(separator: "\n\n") + "\n\nTasks may change app behaviour. Files moved to Trash still use storage until Trash is emptied.")
        }
    }

    private var header: some View {
        PageHeader(
            "Maintenance",
            subtitle: "Choose a task for a specific problem. Routine maintenance does not guarantee a faster Mac."
        ) {
            if model.totalBytesMovedToTrash > 0 {
                Text("Moved \(ByteFormat.string(UInt64(model.totalBytesMovedToTrash))) to Trash")
                    .font(Halo.font(size: 12, weight: .semibold)).help("Space remains allocated until Trash is emptied")
            }
            if model.totalBytesFreed > 0 {
                Text("Freed \(ByteFormat.string(UInt64(max(0, model.totalBytesFreed))))")
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.pulseGreen)
            }
            RefreshButton(help: "Re-check task previews", disabled: model.isAnyRunning) {
                model.refreshAllStatuses()
            }
            Button {
                reviewTasks = model.selectedTasks
                showingReview = true
            } label: {
                if model.isAnyRunning {
                    Label("Running selected tasks…", systemImage: "hourglass")
                } else {
                    Label("Review \(model.selectedTasks.count) selected tasks", systemImage: "checklist")
                }
            }
            .buttonStyle(.borderedProminent)
                    .foregroundStyle(Halo.onAccent)
            .tint(Halo.pulseGreen)
            .disabled(model.isAnyRunning || model.selectedTasks.isEmpty)
        }
    }

    /// Explains how ADMIN tasks elevate (a native macOS password prompt).
    private var adminBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Halo.volt)
            Text("Tasks marked Requires administrator may request your Mac password. Review their effects before selecting them.")
                .font(Halo.font(size: 11))
                .foregroundStyle(Halo.textDim)
            Spacer()
        }
        .padding(12)
        .background(Halo.volt.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Halo.volt.opacity(0.3), lineWidth: 1))
    }

    private func section(_ risk: OptimizeTask.Risk, _ tasks: [OptimizeTask]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(risk == .safe ? "Standard tasks" : risk == .careful ? "Changes to review carefully" : "Advanced changes")
                .font(Halo.font(size: 10, weight: .semibold))
                .foregroundStyle(color(for: risk))
            ForEach(tasks) { task in taskRow(task, risk: risk) }
        }
    }

    private func taskRow(_ task: OptimizeTask, risk: OptimizeTask.Risk) -> some View {
        let s = model.state(for: task.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("Select \(task.label)", isOn: Binding(
                    get: { model.selectedIDs.contains(task.id) },
                    set: { model.setSelected($0, id: task.id) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(model.isAnyRunning || !s.loaded || s.skipReason != nil)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(task.label)
                            .font(Halo.font(size: 13, weight: .semibold))
                            .foregroundStyle(Halo.textPrimary)
                        if task.needsSudo {
                            tag("Requires administrator", Halo.volt)
                        }
                    }
                    Text(task.detail)
                        .font(Halo.font(size: 11))
                        .foregroundStyle(Halo.textDim)
                    statusLine(task, s)
                }
                Spacer()
                actionControl(task, s)
            }
        }
        .padding(14)
        .premiumCard(padding: 0)

    }

    @ViewBuilder
    private func statusLine(_ task: OptimizeTask, _ s: OptimizeModel.TaskState) -> some View {
        if let result = s.result {
            Text(result.summary)
                .font(Halo.font(size: 11, design: .monospaced))
                .foregroundStyle(result.success ? Halo.textPrimary : Halo.flare)
        } else if let skip = s.skipReason {
            Text(skip)
                .font(Halo.font(size: 11))
                .foregroundStyle(Halo.amber)
        } else {
            Text(s.preview)
                .font(Halo.font(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
    }

    /// Status only — tasks run in bulk from the header's Optimize now button.
    @ViewBuilder
    private func actionControl(_ task: OptimizeTask, _ s: OptimizeModel.TaskState) -> some View {
        if s.isRunning {
            ProgressView().controlSize(.small)
        } else if s.skipReason != nil {
            Text("Unavailable").foregroundStyle(Halo.textDim)
        } else if s.result?.success == true {
            Image(systemName: "checkmark.circle")
                .font(Halo.font(size: 14))
                .foregroundStyle(Halo.pulseGreen)
        } else if s.result?.success == false {
            Image(systemName: "exclamationmark.circle")
                .font(Halo.font(size: 14))
                .foregroundStyle(Halo.flare)
        }
    }

    private var refusalPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Halo.Motion.snappy) { showRefusals.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(Halo.flare)
                    Text("Changes Pulse avoids")
                        .font(Halo.font(size: 12, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                    Spacer()
                    Image(systemName: showRefusals ? "chevron.up" : "chevron.down")
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(14)

            if showRefusals {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.refusals, id: \.op) { refusal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(refusal.op)
                                .font(Halo.font(size: 12, weight: .medium))
                                .foregroundStyle(Halo.textPrimary)
                            Text(refusal.reason)
                                .font(Halo.font(size: 11))
                                .foregroundStyle(Halo.textDim)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .premiumCard(padding: 0)

    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(Halo.font(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func color(for risk: OptimizeTask.Risk) -> Color {
        switch risk {
        case .safe: Halo.pulseGreen
        case .careful: Halo.amber
        case .review: Halo.flare
        }
    }
}
