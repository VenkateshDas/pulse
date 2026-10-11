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
        Text(grade == .safe ? "Recommended" : (grade == .careful ? "Check first" : "Needs review"))
            .font(Halo.font(size: 8.5, weight: .bold))
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
                Text("Selected items")
                    .font(Halo.font(size: 9, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Text(ByteFormat.string(storage.selectedBytes))
                    .font(Halo.font(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
            }
            Text(footerNote)
                .font(Halo.font(size: 10))
                .foregroundStyle(storage.cleanReport == nil ? Halo.textDim : Halo.pulseGreen)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                storage.cleanSelected()
            } label: {
                Label(storage.isCleaning ? "Moving to Trash…" : "Move selected items to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Halo.onAccent)
            .disabled(storage.selectedBytes == 0 || storage.isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var footerNote: String {
        storage.cleanReport
            ?? "Review your selection. Storage remains used until Trash is emptied."
    }
}
