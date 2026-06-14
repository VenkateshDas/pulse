import AppKit
import PulseKit
import SwiftUI

struct TrashView: View {
    @Environment(StorageModel.self) private var storage

    var body: some View {
        VStack(spacing: 0) {
            header
            
            if storage.trashAccessError {
                fdaWarningState
            } else if storage.trashItemCount == 0 {
                emptyState
            } else {
                contentList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Halo.void)
        .onAppear {
            storage.refreshTrashInfo()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trash")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Halo.textDim)
                Text("\(storage.trashItemCount) items (\(ByteFormat.string(storage.trashBytes)))")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer()
            Button(role: .destructive) {
                storage.emptyTrash()
            } label: {
                Text("Empty Trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.red)
            .controlSize(.small)
            .disabled(storage.trashItemCount == 0 || storage.isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Halo.surface2)
        .overlay(alignment: .bottom) {
            Divider().background(Halo.border)
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 32))
                .foregroundStyle(Halo.surface2)
            Text("Trash is Empty")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Halo.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fdaWarningState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(Halo.amber)
            Text("Full Disk Access Required")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            Text("Pulse needs Full Disk Access to view your Trash.\nGo to System Settings > Privacy & Security to grant access.")
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Halo.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer(minLength: 16)
            
            Text(ByteFormat.string(item.sizeBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
