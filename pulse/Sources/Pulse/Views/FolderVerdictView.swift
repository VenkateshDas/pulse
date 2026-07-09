import AppKit
import PulseKit
import SwiftUI

/// "Can I delete this?" verdict card: one headline verdict backed by every
/// evidence row it rests on. Evidence is always visible — an opaque "safe
/// to delete" with hidden reasoning is how other cleaners lose user trust.
struct FolderVerdictView: View {
    @Environment(StorageModel.self) private var storage
    @Environment(\.dismiss) private var dismiss

    let targetPath: String
    let verdict: FolderVerdict?
    let isScanning: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Halo.surface2).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isScanning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Gathering evidence…")
                                .font(.system(size: 12)).foregroundStyle(Halo.textDim)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                    } else if let verdict {
                        verdictBanner(verdict)
                        evidenceList(verdict)
                        if let command = verdict.regenCommand {
                            regenRow(command)
                        }
                        actions(verdict)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 520)
        .background(Halo.void)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Can I delete this?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(targetPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Button {
                storage.inspect(path: targetPath, forceRescan: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Halo.textDim)
            .disabled(isScanning)
            .help("Re-gather all evidence")
            Button {
                dismiss()
                storage.dismissVerdict()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Halo.textDim)
        }
        .padding(16)
        .background(Halo.surface1)
    }

    // MARK: Verdict banner

    private func verdictBanner(_ verdict: FolderVerdict) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: verdict.verdict))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color(for: verdict.verdict))
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                HStack(spacing: 6) {
                    if let species = verdict.species {
                        Text(species.name).font(.system(size: 10)).foregroundStyle(Halo.textDim)
                    }
                    if verdict.sizeBytes > 0 {
                        Text(ByteFormat.string(verdict.sizeBytes))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(color(for: verdict.verdict).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color(for: verdict.verdict).opacity(0.35), lineWidth: 1))
    }

    // MARK: Evidence

    private func evidenceList(_ verdict: FolderVerdict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EVIDENCE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Halo.textDim)
                .kerning(0.8)
            ForEach(verdict.evidence) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: row.kind))
                        .font(.system(size: 11))
                        .foregroundStyle(leanColor(row.favorsDeletion))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.headline)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Halo.textPrimary)
                        Text(row.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(Halo.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            Text("Static analysis plus Pulse's own observation window — not a guarantee. When in doubt, Trash (recoverable) rather than delete.")
                .font(.system(size: 9))
                .foregroundStyle(Halo.textDim.opacity(0.8))
                .padding(.top, 2)
        }
    }

    // MARK: Regen command

    private func regenRow(_ command: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise.circle")
                .font(.system(size: 11))
                .foregroundStyle(Halo.pulseGreen)
            Text(command)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .lineLimit(2)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Halo.textDim)
            .help("Copy regeneration command")
        }
        .padding(10)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ verdict: FolderVerdict) -> some View {
        if verdict.verdict == .safeToDelete || verdict.verdict == .likelyUnused {
            HStack {
                Spacer()
                Button(role: .destructive) {
                    storage.trashInspectedTarget()
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .disabled(storage.isCleaning)
            }
        } else if verdict.verdict == .staleReview {
            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: targetPath)])
                } label: {
                    Label("Review in Finder", systemImage: "folder")
                }
            }
        }
    }

    // MARK: Styling

    private func color(for verdict: VerdictClass) -> Color {
        switch verdict {
        case .safeToDelete: Halo.pulseGreen
        case .likelyUnused: Halo.teal
        case .inUse: Halo.ion
        case .staleReview: Halo.amber
        case .unknown: Halo.textDim
        }
    }

    private func icon(for verdict: VerdictClass) -> String {
        switch verdict {
        case .safeToDelete: "checkmark.circle.fill"
        case .likelyUnused: "questionmark.circle.fill"
        case .inUse: "bolt.circle.fill"
        case .staleReview: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func icon(for kind: VerdictEvidence.Kind) -> String {
        switch kind {
        case .identity: "tag"
        case .owner: "person.crop.circle.badge.questionmark"
        case .staleness: "clock"
        case .spotlight: "magnifyingglass"
        case .shellHistory: "terminal"
        case .observer: "eye"
        case .references: "link"
        }
    }

    private func leanColor(_ favorsDeletion: Bool?) -> Color {
        switch favorsDeletion {
        case true: Halo.pulseGreen
        case false: Halo.ion
        case nil: Halo.textDim
        }
    }
}
