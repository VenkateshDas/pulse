import SwiftUI
import PulseKit

struct DuplicateView: View {
    @Environment(StorageModel.self) private var storage
    @State private var hasAutoScanned: Bool = false

    private var totalReclaimableBytes: Int64 {
        storage.duplicateGroups.reduce(0) { $0 + $1.totalReclaimableBytes }
    }

    private var totalSelectedCount: Int {
        storage.duplicateGroups.reduce(0) { count, group in
            count + group.files.filter(\.isSelectedForDeletion).count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            if storage.isDuplicateScanning {
                progressSection
            } else if storage.duplicateGroups.isEmpty {
                emptyStateSection
            } else {
                resultsListSection
            }
        }
        .padding(Halo.Space.lg)
        .onAppear {
            if !hasAutoScanned && storage.duplicateGroups.isEmpty && !storage.isDuplicateScanning {
                hasAutoScanned = true
                storage.startDuplicateScan()
            }
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duplicate Finder")
                    .font(.headline)
                    .foregroundColor(Halo.textPrimary)
                Text("BLAKE3 4-stage scan with APFS Copy-on-Write clone detection")
                    .font(.caption)
                    .foregroundColor(Halo.textDim)
            }
            Spacer()

            if !storage.duplicateGroups.isEmpty && !storage.isDuplicateScanning {
                Button(action: { storage.deleteSelectedDuplicates() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete Selected (\(ByteFormat.string(UInt64(max(0, totalReclaimableBytes)))))")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(totalSelectedCount > 0 ? Color.red : Color.gray)
                    .cornerRadius(Halo.Radius.medium)
                }
                .disabled(totalSelectedCount == 0)
            }

            Button(action: { storage.startDuplicateScan() }) {
                HStack(spacing: 6) {
                    Image(systemName: storage.isDuplicateScanning ? "arrow.clockwise" : "magnifyingglass")
                    Text(storage.isDuplicateScanning ? "Scanning..." : "Scan Duplicates")
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Halo.surface1)
                .cornerRadius(Halo.Radius.medium)
                .overlay(RoundedRectangle(cornerRadius: Halo.Radius.medium).stroke(Halo.borderSubtle, lineWidth: 1))
            }
            .disabled(storage.isDuplicateScanning)
        }
        .padding(.bottom, Halo.Space.md)
    }

    private var progressSection: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            
            if let progress = storage.duplicateScanProgress {
                VStack(spacing: 6) {
                    Text(phaseTitle(progress.phase))
                        .font(.headline)
                        .foregroundColor(Halo.textPrimary)
                    Text("\(progress.processedFiles) files processed · \(progress.foundDuplicates) duplicates found")
                        .font(.subheadline)
                        .foregroundColor(Halo.textDim)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateSection: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.on.doc")
                .font(.system(size: 44))
                .foregroundColor(Halo.textDim)
            Text("No Duplicates Found")
                .font(.headline)
                .foregroundColor(Halo.textPrimary)
            Text("Click 'Scan Duplicates' to scan Downloads, Documents, and Desktop folders.")
                .font(.subheadline)
                .foregroundColor(Halo.textDim)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsListSection: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(storage.duplicateGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.files.first?.url.lastPathComponent ?? "Duplicate Group")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(Halo.textPrimary)
                            Spacer()
                            if group.isAPFSClone {
                                Text("APFS Clone (0B Reclaim)")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            } else {
                                Text("Reclaim: \(ByteFormat.string(UInt64(max(0, group.totalReclaimableBytes))))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.green)
                            }
                        }

                        Divider()

                        ForEach(group.files) { file in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { file.isSelectedForDeletion },
                                    set: { newValue in
                                        storage.toggleDuplicateSelection(groupId: group.id, fileId: file.id, isSelected: newValue)
                                    }
                                ))
                                .labelsHidden()

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.url.path)
                                        .font(.caption.monospaced())
                                        .foregroundColor(Halo.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(ByteFormat.string(UInt64(max(0, file.fileSize))))
                                        .font(.caption2)
                                        .foregroundColor(Halo.textDim)
                                }
                                Spacer()

                                if file.isKeepCandidate {
                                    Text("KEEP")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .cornerRadius(4)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(Halo.Space.md)
                    .background(Halo.surface1)
                    .cornerRadius(Halo.Radius.medium)
                    .overlay(RoundedRectangle(cornerRadius: Halo.Radius.medium).stroke(Halo.borderSubtle, lineWidth: 1))
                }
            }
        }
    }

    private func phaseTitle(_ phase: DuplicateScanner.ScanProgress.Phase) -> String {
        switch phase {
        case .indexing: return "Indexing directory files..."
        case .sizeBucketing: return "Filtering by byte size..."
        case .headTailHashing: return "Checking head & tail fingerprints..."
        case .fullHashing: return "Streaming BLAKE3 hashes..."
        case .completed: return "Scan Completed"
        }
    }
}
