import PulseKit
import SwiftUI

/// Disk → Insights tab: surfaces large, easy-to-forget locations the treemap
/// buries. Awareness-only — "👀" hidden-space items are real data; cleanable
/// items are rebuildable. Reveal in Finder to act.
struct InsightsView: View {
    @Environment(InsightsModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if model.isScanning && model.insights.isEmpty {
                    scanning
                } else if model.hasScanned && model.insights.isEmpty {
                    empty
                } else {
                    section(.hiddenSpace, "Hidden space — review before removing")
                    section(.cleanable, "Cleanable — rebuilt or re-downloaded")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear { if !model.hasScanned { model.scan() } }
    }

    private var header: some View {
        PageHeader(
            "Hidden Space",
            subtitle: "Big, easy-to-forget locations. Not all safe to delete — read each hint."
        ) {
            if model.totalBytes > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormat.string(UInt64(max(0, model.totalBytes))))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Halo.textPrimary)
                    Text("surfaced").font(.system(size: 10)).foregroundStyle(Halo.textDim)
                }
            }
            Button(model.hasScanned ? "Rescan" : "Scan") { model.scan() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(model.isScanning)
        }
    }

    @ViewBuilder
    private func section(_ kind: Insight.Kind, _ title: String) -> some View {
        let items = model.insights.filter { $0.kind == kind }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(kind == .hiddenSpace ? Halo.amber : Halo.ion)
                ForEach(items) { row($0) }
            }
        }
    }

    private func row(_ insight: Insight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(insight.reversibleHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
                Text(insight.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Halo.textDim.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(UInt64(max(0, insight.bytes))))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
            Button {
                model.reveal(insight.path)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(14)
        .premiumCard(padding: 0)
        
    }

    private var scanning: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Measuring hidden space…").font(.system(size: 12)).foregroundStyle(Halo.textDim)
        }
        .padding(.top, 40)
    }

    private var empty: some View {
        EmptyState(
            icon: "checkmark.seal",
            title: "Nothing notable",
            hint: "No large hidden caches or backups found.",
            tint: Halo.pulseGreen)
        .padding(.top, 24)
    }
}
