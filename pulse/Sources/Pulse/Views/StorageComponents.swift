import SwiftUI
import PulseKit

/// A folder/file node enriched with the smart-scan grade, idle age, and
/// owning category when known. Feeds the column rows and the detail panel.
struct StorageItemInfo: Identifiable, Equatable {
    let node: StorageNode
    let grade: SafetyGrade
    let idleDays: Int?
    let category: String
    var isProtected: Bool { StorageScanner.isProtected(node.path) }
    /// Synthetic rows ("Other Files") aggregate loose files; they carry the
    /// parent directory's path, so acting on that path would hit the parent.
    var isPseudo: Bool { node.id != node.path }
    var id: String { node.id }
}

struct GradePill: View {
    let grade: SafetyGrade

    var body: some View {
        Text(grade.rawValue.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(gradeColor(grade))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(gradeColor(grade).opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

func gradeColor(_ grade: SafetyGrade) -> Color {
    switch grade {
    case .safe: Halo.pulseGreen
    case .careful: Halo.amber
    case .review: Halo.flare
    }
}

// MARK: - Clean footer

struct CleanFooter: View {
    @Environment(StorageModel.self) private var storage

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SELECTED")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.textDim)
                Text(ByteFormat.string(storage.selectedBytes))
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
            }
            Text(footerNote)
                .font(.system(size: 10))
                .foregroundStyle(storage.cleanReport == nil ? Halo.textDim : Halo.pulseGreen)
                .lineLimit(2)
            Spacer()
            Button {
                storage.cleanSelected()
            } label: {
                HStack(spacing: 6) {
                    if storage.isCleaning {
                        ProgressView().controlSize(.small)
                    }
                    Text("Move \(ByteFormat.string(storage.selectedBytes)) to Trash")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Halo.void)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(
                    storage.selectedBytes == 0 ? AnyShapeStyle(Halo.textDim) : AnyShapeStyle(Halo.ion),
                    in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(storage.selectedBytes == 0 || storage.isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var footerNote: String {
        storage.cleanReport
            ?? "→ moved to macOS Trash · frees space when emptied"
    }
}
