import AppKit
import PulseKit
import SwiftUI

/// Detail panel for the treemap cell the user tapped: size, contents, safety
/// grade, age, owning category, and the actions (Clean → Vault, reveal in
/// Finder, zoom in). Spec §3.3 "click any cell → detail panel".
struct StorageDetailPanel: View {
    @Environment(StorageModel.self) private var storage
    let cell: TreemapCell
    let onZoom: (StorageNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: cell.node.path))
                    .resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cell.node.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(2)
                    Text(cell.node.isDirectory ? "Folder" : "File")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
                Spacer()
                if cell.isProtected {
                    Text("PROTECTED")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Halo.textDim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Halo.surface2, in: Capsule())
                        .fixedSize()
                } else {
                    GradePill(grade: cell.grade)
                }
            }

            Divider().overlay(Halo.surface2)

            fact("SIZE", ByteFormat.string(cell.node.sizeBytes))
            if cell.node.isDirectory {
                if let count = cell.node.fileCount, count > 0 {
                    fact("CONTAINS", "\(count) item\(count == 1 ? "" : "s")")
                } else if let count = cell.node.children?.count, count > 0 {
                    fact("CONTAINS", "\(count) item\(count == 1 ? "" : "s")")
                }
            }
            if let idle = cell.idleDays {
                fact("LAST MODIFIED", "\(idle) day\(idle == 1 ? "" : "s") ago")
            }
            fact("CATEGORY", cell.category)
            fact("CONSEQUENCE", consequence)

            Spacer(minLength: 0)

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var consequence: String {
        if cell.isProtected { return "System or restricted file. Cannot be modified." }
        switch cell.grade {
        case .safe: return "Regenerates automatically — safe to clean."
        case .careful: return "Review before cleaning — may need a rebuild/redownload."
        case .review: return "Real data — open in Finder and decide yourself. Never bulk-cleaned."
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if cell.node.isDirectory {
                Button {
                    onZoom(cell.node)
                } label: {
                    Label("Zoom in", systemImage: "arrow.down.right.and.arrow.up.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Halo.ion)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: cell.node.path)
                ])
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Halo.textDim)
            if cell.isProtected {
                Button {} label: {
                    Label("Protected", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Halo.surface2)
                .disabled(true)
            } else if cell.grade != .review {
                Button {
                    storage.cleanNode(cell.node)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Halo.pulseGreen)
                .disabled(storage.isCleaning)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
