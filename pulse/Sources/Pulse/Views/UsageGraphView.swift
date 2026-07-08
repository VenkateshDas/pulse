import PulseKit
import SwiftUI

/// "Find what uses this" result sheet — a small node graph centered on the
/// queried path, with one node per distinct referrer found by
/// `UsageGraphScanner`. Static analysis only: an empty result is a strong
/// signal the folder is orphaned, not a guarantee.
struct UsageGraphView: View {
    @Environment(StorageModel.self) private var storage
    @Environment(\.dismiss) private var dismiss

    let targetPath: String
    let edges: [UsageEdge]
    let isScanning: Bool

    @State private var expandedReferrer: String?

    private var referrers: [(path: String, signal: ReferenceSignal, details: [String])] {
        var byPath: [String: (signal: ReferenceSignal, details: [String])] = [:]
        var order: [String] = []
        for edge in edges {
            let path = edge.source.path
            if byPath[path] == nil {
                order.append(path)
                byPath[path] = (edge.signal, [edge.detail])
            } else {
                byPath[path]?.details.append(edge.detail)
            }
        }
        return order.map { (path: $0, signal: byPath[$0]!.signal, details: byPath[$0]!.details) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Halo.surface2).frame(height: 1)
            ScrollView {
                VStack(spacing: 20) {
                    graph
                    if !isScanning && referrers.isEmpty {
                        orphanState
                    } else if !referrers.isEmpty {
                        legend
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 480)
        .background(Halo.void)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("What uses this")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text((targetPath as NSString).lastPathComponent)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                storage.findUsage(for: targetPath, forceRescan: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Halo.textDim)
            .disabled(isScanning)
            .help("Rescan")
            Button {
                dismiss()
                storage.dismissUsageGraph()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Halo.textDim)
        }
        .padding(16)
        .background(Halo.surface1)
    }

    // MARK: Graph

    private var graph: some View {
        ZStack {
            if isScanning {
                ProgressView().controlSize(.small)
            } else {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for (index, referrer) in referrers.enumerated() {
                        let point = nodePosition(index: index, total: referrers.count, center: center, radius: min(size.width, size.height) / 2 - 40)
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: point)
                        context.stroke(path, with: .color(color(for: referrer.signal).opacity(0.5)), lineWidth: 1.5)
                    }
                }
                centerNode
                ForEach(Array(referrers.enumerated()), id: \.element.path) { index, referrer in
                    referrerNode(referrer)
                        .position(nodePosition(
                            index: index, total: referrers.count,
                            center: CGPoint(x: 190, y: 130), radius: 100))
                }
            }
        }
        .frame(height: 260)
    }

    private func nodePosition(index: Int, total: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        guard total > 0 else { return center }
        let angle = (2 * .pi / Double(total)) * Double(index) - .pi / 2
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private var centerNode: some View {
        VStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundStyle(Halo.textPrimary)
            Text((targetPath as NSString).lastPathComponent)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 90)
        }
        .padding(10)
        .background(Halo.surface1, in: Circle())
        .overlay(Circle().stroke(Halo.textPrimary.opacity(0.3), lineWidth: 1.5))
        .position(x: 190, y: 130)
    }

    private func referrerNode(_ referrer: (path: String, signal: ReferenceSignal, details: [String])) -> some View {
        let isExpanded = expandedReferrer == referrer.path
        return VStack(spacing: 4) {
            Button {
                expandedReferrer = isExpanded ? nil : referrer.path
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: icon(for: referrer.signal))
                        .font(.system(size: 13))
                        .foregroundStyle(color(for: referrer.signal))
                    Text((referrer.path as NSString).lastPathComponent)
                        .font(.system(size: 9))
                        .foregroundStyle(Halo.textDim)
                        .lineLimit(1)
                        .frame(maxWidth: 74)
                }
                .padding(8)
                .background(Halo.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .help(referrer.details.joined(separator: "\n"))
        }
    }

    // MARK: States

    private var orphanState: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 22))
                .foregroundStyle(Halo.textDim)
            Text("No references found — appears orphaned")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            Text("Based on static analysis, not a guarantee — dynamic references (e.g. paths set at runtime) may not be caught.")
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(role: .destructive) {
                storage.trashUsageTarget()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(storage.isCleaning)
            .padding(.top, 4)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(referrers, id: \.path) { referrer in
                if expandedReferrer == referrer.path {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(referrer.path)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Halo.textPrimary)
                        ForEach(referrer.details, id: \.self) { detail in
                            Text(detail)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Halo.textDim)
                        }
                    }
                    .padding(8)
                    .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(spacing: 14) {
                ForEach(ReferenceSignal.allCases, id: \.self) { signal in
                    HStack(spacing: 4) {
                        Circle().fill(color(for: signal)).frame(width: 6, height: 6)
                        Text(label(for: signal)).font(.system(size: 9)).foregroundStyle(Halo.textDim)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Signal styling

    private func color(for signal: ReferenceSignal) -> Color {
        switch signal {
        case .homebrew: Halo.amber
        case .textRef: Halo.ion
        case .dylib: Halo.volt
        case .symlink: Halo.textDim
        }
    }

    private func icon(for signal: ReferenceSignal) -> String {
        switch signal {
        case .homebrew: "mug.fill"
        case .textRef: "doc.text"
        case .dylib: "app.connected.to.app.below.fill"
        case .symlink: "arrow.triangle.branch"
        }
    }

    private func label(for signal: ReferenceSignal) -> String {
        switch signal {
        case .homebrew: "Homebrew"
        case .textRef: "Text ref"
        case .dylib: "Binary link"
        case .symlink: "Symlink"
        }
    }
}
