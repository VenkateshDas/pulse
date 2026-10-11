import AppKit
import PulseKit
import SwiftUI

struct TrashView: View {
    @Environment(StorageModel.self) private var storage
    @State private var selectedTab: Tab = .raw
    @State private var confirmEmpty = false

    enum Tab {
        case raw
        case history
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Halo.Space.lg) {
                PageHeader(
                    "Trash",
                    subtitle: "Review what was removed. Emptying Trash permanently removes its contents."
                ) {
                    RefreshButton(help: "Refresh Trash contents") {
                        storage.refreshTrashInfo()
                        storage.refreshUndoHistory()
                    }
                    if storage.isCleaning {
                        ProgressView().controlSize(.small)
                    } else if let report = storage.cleanReport {
                        Text(report)
                            .font(Halo.font(size: 11))
                            .foregroundStyle(Halo.pulseGreen)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if selectedTab == .raw {
                        Button(role: .destructive) {
                            confirmEmpty = true
                        } label: {
                            Text("Empty Trash")
                                .font(Halo.font(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    .foregroundStyle(Halo.onAccent)
                        .tint(Halo.critical)
                        .controlSize(.small)
                        .disabled(storage.trashItemCount == 0 || storage.isCleaning)
                    }
                }
                SegmentPicker(
                    options: [(Tab.raw, "Trash contents"), (Tab.history, "Recent removals")],
                    selection: $selectedTab)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, Halo.Space.lg)

            Divider().background(Halo.borderSubtle)

            if selectedTab == .raw {
                if storage.trashAccessError {
                    EmptyState(
                        icon: "lock.shield",
                        title: "Full Disk Access Required",
                        hint: "Pulse needs Full Disk Access to view your Trash.\nGo to System Settings > Privacy & Security to grant access.",
                        tint: Halo.amber)
                } else if storage.trashItemCount == 0 {
                    EmptyState(icon: "trash", title: "Trash is empty", hint: "Items moved here will be available to review before permanent removal.")
                } else {
                    contentList
                }
            } else {
                if storage.undoEntries.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: "No recent removals", hint: "Recoverable removals made by Pulse appear here while the items remain in Trash.")
                } else {
                    historyList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Halo.void)
        .confirmationDialog(
            "Empty the Trash?",
            isPresented: $confirmEmpty, titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) { storage.emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently erases \(storage.trashItemCount) items (\(ByteFormat.string(storage.trashBytes))). This can't be undone.")
        }
        .onAppear {
            storage.refreshTrashInfo()
            storage.refreshUndoHistory()
        }
    }

    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(storage.trashItems) { item in
                    TrashItemRow(item: item)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(storage.undoEntries) { entry in
                    UndoEntryRow(entry: entry)
                }
            }
            .padding(16)
        }
    }

}

private struct TrashItemRow: View {
    let item: StorageModel.TrashItem

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.id))
                .resizable()
                .frame(width: 24, height: 24)

            Text(item.name)
                .font(Halo.font(size: 12, weight: .medium))
                .foregroundStyle(Halo.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 16)

            Text(ByteFormat.string(item.sizeBytes))
                .font(Halo.font(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct UndoEntryRow: View {
    @Environment(StorageModel.self) private var storage
    let entry: UndoEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.op)
                        .font(Halo.font(size: 13, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)

                    Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.items.count) items · \(ByteFormat.string(UInt64(entry.bytesFreed)))")
                        .font(Halo.font(size: 11))
                        .foregroundStyle(Halo.textDim)
                }

                Spacer()

                Button("Restore") {
                    storage.restore(entry: entry)
                }
                .buttonStyle(.borderedProminent)
                    .foregroundStyle(Halo.onAccent)
                .tint(Halo.interactive)
                .controlSize(.small)
                .disabled(storage.isCleaning)

                Button {
                    withAnimation(Halo.Motion.snappy) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(Halo.font(size: 10, weight: .bold))
                        .foregroundStyle(Halo.textDim)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide removed files" : "Show removed files")
            }
            .padding(16)
            .background(Halo.surface1)

            if isExpanded {
                Divider().background(Halo.borderSubtle)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.items.prefix(10), id: \.originalPath) { item in
                        Text(URL(fileURLWithPath: item.originalPath).lastPathComponent)
                            .font(Halo.font(size: 11, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if entry.items.count > 10 {
                        Text("... and \(entry.items.count - 10) more")
                            .font(Halo.font(size: 11, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                    }
                }
                .padding(16)
                .background(Halo.surface2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Halo.border, lineWidth: 1)
        )
    }
}
