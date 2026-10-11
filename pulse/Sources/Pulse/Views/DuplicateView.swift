import AppKit
import SwiftUI
import PulseKit

struct DuplicateView: View {
    @Environment(StorageModel.self) private var storage
    @State private var directories: [URL] = [FileManager.SearchPathDirectory.downloadsDirectory, .documentDirectory, .desktopDirectory]
        .compactMap { FileManager.default.urls(for: $0, in: .userDomainMask).first }
    @State private var confirmRemoval = false

    private var selectedCount: Int {
        storage.duplicateGroups.reduce(0) { $0 + $1.files.filter(\.isSelectedForDeletion).count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader("Duplicate files", subtitle: "Find identical files. Keep the copies you need in their original locations.")
            HStack {
                Button("Choose folders…") { chooseFolders() }.buttonStyle(.bordered)
                    .disabled(storage.isDuplicateScanning || storage.isRemovingDuplicates)
                Text(directories.map(\.lastPathComponent).joined(separator: ", "))
                    .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary).lineLimit(2)
                Spacer()
                if storage.isDuplicateScanning {
                    Button("Stop scan") { storage.cancelDuplicateScan() }.buttonStyle(.bordered)
                } else {
                    Button("Find duplicates") { storage.startDuplicateScan(directories: directories) }
                        .buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent)
                        .disabled(directories.isEmpty || storage.isRemovingDuplicates)
                }
            }
            if let result = storage.duplicateStatusMessage { FeedbackBadge(message: result) }
            if storage.isDuplicateScanning {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(phaseTitle(storage.duplicateScanProgress?.phase)).font(Halo.font(size: 14, weight: .medium))
                        if let progress = storage.duplicateScanProgress {
                            Text("\(progress.processedFiles) files checked").font(Halo.font(size: 12)).monospacedDigit()
                        }
                    }
                }
                Spacer()
            } else if storage.duplicateGroups.isEmpty {
                EmptyState(icon: "doc.on.doc", title: storage.didScanDuplicates ? "No duplicate groups to review" : "Choose where to look",
                           hint: "Scanning does not remove files. Some protected or unreadable files may not be included.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(storage.duplicateGroups) { group in duplicateGroup(group) }
                    }
                }
                HStack {
                    Text("\(selectedCount) copies selected · removals go to Trash")
                        .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                    Spacer()
                    Button(storage.isRemovingDuplicates ? "Moving…" : "Review removal") { confirmRemoval = true }
                        .buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent)
                        .disabled(selectedCount == 0 || storage.isRemovingDuplicates)
                }
            }
        }
        .padding(24)
        .background(Halo.void)
        .confirmationDialog("Move \(selectedCount) duplicate copies to Trash?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Move to Trash") { storage.deleteSelectedDuplicates() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One copy stays in each group. Pulse checks the contents again before moving selected copies. Review in Trash or Recent removals to recover them; storage is not freed until Trash is emptied.")
        }
    }

    private func duplicateGroup(_ group: DuplicateScanner.DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.files.first?.url.lastPathComponent ?? "Identical files")
                .font(Halo.font(size: 16, weight: .semibold)).foregroundStyle(Halo.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if group.isAPFSClone {
                Text("These copies share storage. Removing a copy may not increase available space.")
                    .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
            }
            Text("Identical content can still be needed in different folders. Review each location.")
                .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
            ForEach(group.files) { file in
                HStack(alignment: .top, spacing: 12) {
                    Toggle("Select \(file.url.lastPathComponent) in \(file.url.deletingLastPathComponent().path) for removal", isOn: Binding(
                        get: { file.isSelectedForDeletion },
                        set: { storage.toggleDuplicateSelection(groupId: group.id, fileId: file.id, isSelected: $0) }
                    ))
                    .labelsHidden().toggleStyle(.checkbox)
                    .disabled(file.isKeepCandidate || storage.isRemovingDuplicates)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(file.url.path).font(Halo.font(size: 13)).foregroundStyle(Halo.textPrimary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text(ByteFormat.string(UInt64(max(0, file.fileSize)))).font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                        HStack {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.buttonStyle(.borderless)
                            if file.isKeepCandidate {
                                Label("Keeping this copy", systemImage: "checkmark.circle").foregroundStyle(Halo.nominal)
                            } else {
                                Button("Keep this copy") { storage.retainDuplicate(groupId: group.id, fileId: file.id) }.buttonStyle(.borderless)
                                    .disabled(storage.isRemovingDuplicates)
                            }
                        }.font(Halo.font(size: 12))
                    }
                }
                Divider()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose folders"
        if panel.runModal() == .OK { directories = panel.urls }
    }

    private func phaseTitle(_ phase: DuplicateScanner.ScanProgress.Phase?) -> String {
        switch phase {
        case .indexing: "Finding files…"
        case .sizeBucketing: "Comparing file sizes…"
        case .headTailHashing: "Checking possible matches…"
        case .fullHashing: "Comparing file contents…"
        case .completed: "Scan complete"
        case nil: "Starting scan…"
        }
    }
}
