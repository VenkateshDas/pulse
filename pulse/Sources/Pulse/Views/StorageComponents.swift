import SwiftUI
import PulseKit

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
        .premiumCard(padding: 0)
    }

    private var footerNote: String {
        storage.cleanReport
            ?? "→ moved to macOS Trash · frees space when emptied"
    }
}
