import PulseKit
import SwiftUI

/// Disk → Optimize tab: a risk-grouped maintenance checklist with dry-run
/// previews, skip reasons, and a trust panel of operations we refuse to do.
struct OptimizeView: View {
    @Environment(OptimizeModel.self) private var model
    @State private var showRefusals = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.tasks.contains(where: { $0.needsSudo }) { adminBanner }
                ForEach(OptimizeTask.Risk.allCases, id: \.self) { risk in
                    let group = model.tasks.filter { $0.risk == risk }
                    if !group.isEmpty { section(risk, group) }
                }
                refusalPanel
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear { model.loadIfNeeded() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Optimize")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text("Safe maintenance tasks. Removals go to the Trash — reversible.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer()
            if model.totalBytesFreed > 0 {
                Text("Freed \(ByteFormat.string(UInt64(max(0, model.totalBytesFreed))))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.pulseGreen)
            }
            Button {
                Task { await model.runAllSafe() }
            } label: {
                Label("Run safe tasks", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(Halo.pulseGreen)
        }
    }

    /// Explains how ADMIN tasks elevate (a native macOS password prompt).
    private var adminBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Halo.volt)
            Text("Tasks marked ADMIN run as root — macOS asks for your password when you run one.")
                .font(.system(size: 11))
                .foregroundStyle(Halo.textDim)
            Spacer()
        }
        .padding(Halo.Space.md)
        .background(Halo.volt.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Halo.volt.opacity(0.3), lineWidth: 1))
    }

    private func section(_ risk: OptimizeTask.Risk, _ tasks: [OptimizeTask]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(risk.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(color(for: risk))
            ForEach(tasks) { task in taskRow(task, risk: risk) }
        }
    }

    private func taskRow(_ task: OptimizeTask, risk: OptimizeTask.Risk) -> some View {
        let s = model.state(for: task.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(color(for: risk)).frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(task.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Halo.textPrimary)
                        if task.needsSudo {
                            tag("ADMIN", Halo.volt)
                        }
                    }
                    Text(task.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textDim)
                    statusLine(task, s)
                }
                Spacer()
                actionControl(task, s)
            }
        }
        .padding(14)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Halo.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private func statusLine(_ task: OptimizeTask, _ s: OptimizeModel.TaskState) -> some View {
        if let result = s.result {
            Text(result.summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(result.success ? Halo.pulseGreen : Halo.flare)
        } else if let skip = s.skipReason {
            Text(skip)
                .font(.system(size: 11))
                .foregroundStyle(Halo.amber)
        } else {
            Text(s.preview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
    }

    @ViewBuilder
    private func actionControl(_ task: OptimizeTask, _ s: OptimizeModel.TaskState) -> some View {
        if s.isRunning {
            ProgressView().controlSize(.small)
        } else if s.skipReason != nil {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(Halo.pulseGreen)
        } else {
            Button {
                Task { await model.run(task) }
            } label: {
                if task.needsSudo {
                    Label("Run", systemImage: "lock.fill")
                } else {
                    Text("Run")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(task.needsSudo ? Halo.volt : nil)
        }
    }

    private var refusalPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showRefusals.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(Halo.flare)
                    Text("We refuse \(model.refusals.count) risky operations")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                    Spacer()
                    Image(systemName: showRefusals ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
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
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Halo.textPrimary)
                            Text(refusal.reason)
                                .font(.system(size: 11))
                                .foregroundStyle(Halo.textDim)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Halo.borderSubtle, lineWidth: 1))
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
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
