import AppKit
import PulseKit
import SwiftUI

// MARK: - Vault

struct VaultPanel: View {
    @Environment(StorageModel.self) private var storage
    @State private var purgeAllConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrashCard().padding(.horizontal, 16).padding(.bottom, 16)
            
            // Header Action Bar
            HStack(alignment: .center) {
                let selectionCount = storage.vaultSelection.count
                let totalItems = storage.flatVaultItems.count
                
                Button(action: { storage.toggleAllVaultItems() }) {
                    Image(systemName: selectionCount == totalItems && totalItems > 0 ? "checkmark.square.fill" : (selectionCount > 0 ? "minus.square.fill" : "square"))
                        .font(.system(size: 14))
                        .foregroundStyle(selectionCount > 0 ? Halo.volt : Halo.textDim)
                }
                .buttonStyle(.plain)
                .frame(width: 24)
                
                if selectionCount > 0 {
                    let selectedBytes = storage.flatVaultItems.filter({ storage.vaultSelection.contains($0.id) }).reduce(0) { $0 + $1.item.sizeBytes }
                    Text("\(selectionCount) items selected (\(ByteFormat.string(selectedBytes)))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Halo.volt)
                    
                    Spacer()
                    
                    Button("Restore Selected") {
                        storage.restoreSelectedVaultItems()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Halo.pulseGreen)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Halo.pulseGreen.opacity(0.12), in: Capsule())
                    
                    Button("Purge Selected") {
                        storage.purgeSelectedVaultItems()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Halo.flare)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Halo.flare.opacity(0.12), in: Capsule())
                } else {
                    Text("SAFETY VAULT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Halo.textDim)
                    Text("· \(totalItems) items staged (\(ByteFormat.string(storage.vaultTotalBytes)))")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                        
                    Spacer()
                    
                    if totalItems > 0 {
                        Button("Restore All") {
                            storage.restoreAllVaultItems()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Halo.pulseGreen)
                        
                        Button("Purge All") {
                            purgeAllConfirm = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Halo.flare)
                        .padding(.leading, 16)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Halo.surface2.opacity(0.5))
            
            Divider().overlay(Halo.surface2)
            
            // List Header
            HStack(spacing: 12) {
                Spacer().frame(width: 24) // checkbox spacer
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Auto-Purges In").frame(width: 100, alignment: .leading)
                Text("Size").frame(width: 60, alignment: .trailing)
                Spacer().frame(width: 60) // Actions spacer
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Halo.textDim)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider().overlay(Halo.surface2)
            
            // File List
            let items = storage.flatVaultItems
            if items.isEmpty {
                Text("Vault is empty — nothing staged for deletion.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(items) { flatItem in
                        VaultItemRow(flatItem: flatItem)
                        Divider().overlay(Halo.surface2.opacity(0.3))
                    }
                }
            }
            
            Divider().overlay(Halo.surface2)
            retentionFooter.padding(.top, 16).padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog(
            "Permanently empty the Vault?",
            isPresented: $purgeAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Purge All Forever", role: .destructive) { storage.purgeAllVaultItems() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This will permanently delete all \(storage.flatVaultItems.count) items.") }
    }

    private var retentionFooter: some View {
        HStack(spacing: 12) {
            Text("RETENTION")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            Slider(
                value: Binding(
                    get: { Double(storage.retentionDays) },
                    set: { storage.retentionDays = Int($0.rounded()) }
                ),
                in: 1...30, step: 1
            )
            .tint(Halo.volt)
            .frame(maxWidth: 220)
            Text("\(storage.retentionDays) day\(storage.retentionDays == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 60, alignment: .leading)
            Text("oldest sessions purge first when disk is tight")
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
            Spacer()
        }
    }
}

struct VaultItemRow: View {
    @Environment(StorageModel.self) private var storage
    let flatItem: StorageModel.FlatVaultItem
    @State private var isHovered = false

    var body: some View {
        let isSelected = storage.vaultSelection.contains(flatItem.id)
        
        HStack(spacing: 12) {
            Button(action: { storage.toggleVaultItem(flatItem) }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Halo.volt : Halo.textDim.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 24)
            
            Image(systemName: "doc")
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(flatItem.item.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text(flatItem.item.originalPath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(countdownText(flatItem.session))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Halo.amber)
                .frame(width: 100, alignment: .leading)
            
            Text(ByteFormat.string(flatItem.item.sizeBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 60, alignment: .trailing)
            
            HStack(spacing: 12) {
                if isHovered {
                    Button(action: { storage.restoreItem(flatItem.item, from: flatItem.session) }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Halo.pulseGreen)
                    .help("Restore")
                    
                    Button(action: { storage.purgeItem(flatItem.item, from: flatItem.session) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Halo.flare)
                    .help("Purge")
                }
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Halo.volt.opacity(0.1) : (isHovered ? Halo.surface2.opacity(0.3) : Color.clear))
        .onHover { isHovered = $0 }
    }
    
    private func countdownText(_ session: VaultSession) -> String {
        let ttl = TimeInterval(storage.retentionDays) * 86400
        let remaining = session.expiry(ttl: ttl).timeIntervalSince(.now)
        guard remaining > 0 else { return "purging…" }
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        return days > 0 ? "\(days)d \(String(format: "%02d", hours))h" : "\(hours)h"
    }
}

// MARK: - Trash card

/// System Trash size/count with an Empty Trash action and the honesty line
/// that trashed files still occupy disk until emptied.
struct TrashCard: View {
    @Environment(StorageModel.self) private var storage
    @State private var confirmEmpty = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash")
                .font(.system(size: 18))
                .foregroundStyle(storage.trashItemCount > 0 ? Halo.amber : Halo.textDim)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("SYSTEM TRASH")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                if storage.trashItemCount > 0 {
                    Text("\(ByteFormat.string(storage.trashBytes)) · \(storage.trashItemCount) items — still occupy disk until emptied")
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textPrimary)
                } else {
                    Text("Empty — nothing occupying disk here")
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textDim)
                }
            }
            Spacer()
            if storage.trashItemCount > 0 {
                Button("Empty Trash") { confirmEmpty = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Halo.void)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Halo.amber, in: Capsule())
                    .disabled(storage.isCleaning)
            }
        }
        .padding(16)
        .background(Halo.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .confirmationDialog(
            "Empty the Trash?",
            isPresented: $confirmEmpty,
            titleVisibility: .visible
        ) {
            Button("Move \(ByteFormat.string(storage.trashBytes)) to Vault") {
                storage.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Trash contents move into the Safety Vault — space frees when that session purges, and you can restore until then.")
        }
    }
}

/// Dedicated Vault page for the sidebar — same panel, page chrome.
struct VaultView: View {
    @Environment(StorageModel.self) private var storage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Safety Vault")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text(
                    "Everything Pulse removes lands here first. Same-volume staging is instant — no copy. Restore is always one click."
                )
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
            }
            ScrollView {
                VaultPanel()
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear { storage.appeared() }
    }
}
