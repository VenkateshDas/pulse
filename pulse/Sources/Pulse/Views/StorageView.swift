import AppKit
import PulseKit
import SwiftUI

/// Storage module (mockup 02 + 03): volume header, safety-tinted storage
/// map, evidence-based Smart Clean rows, and the Vault — every delete is
/// staged, nothing is silently destroyed.
struct StorageView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(StorageModel.self) private var storage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    storageMap
                    SmartCleanPanel()
                    VaultPanel()
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            CleanFooter()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear { storage.appeared() }
    }

    // MARK: Header

    private var header: some View {
        let snapshot = model.snapshot
        let total = snapshot?.diskTotalBytes ?? 0
        let free = snapshot?.diskFreeBytes ?? 0
        let used = total > free ? total - free : 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Macintosh HD")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text("\(ByteFormat.string(used)) / \(ByteFormat.string(total))")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.statusColor(snapshot?.diskUsedFraction ?? 0))
                if storage.purgeableBytes > 0 {
                    Text("· \(ByteFormat.string(storage.purgeableBytes)) purgeable")
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textDim)
                }
                Spacer()
                scanStatus
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Halo.surface2)
                    Capsule()
                        .fill(Halo.statusColor(snapshot?.diskUsedFraction ?? 0))
                        .frame(width: geo.size.width * (snapshot?.diskUsedFraction ?? 0))
                }
            }
            .frame(height: 5)
        }
    }

    @ViewBuilder
    private var scanStatus: some View {
        switch storage.scanState {
        case .scanning:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("SCANNING…")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
        case .done(let date):
            HStack(spacing: 8) {
                Text(
                    "● SCAN FRESH · \(scannedFilesText) files · \(relativeText(date))"
                )
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.pulseGreen)
                Button("Rescan") { storage.runScan() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.ion)
            }
        case .idle:
            EmptyView()
        }
    }

    private var scannedFilesText: String {
        let count = storage.scan?.scannedFiles ?? 0
        return count >= 1_000_000
            ? String(format: "%.1fM", Double(count) / 1_000_000)
            : (count >= 1000 ? String(format: "%dK", count / 1000) : "\(count)")
    }

    private func relativeText(_ date: Date) -> String {
        let minutes = Int(Date.now.timeIntervalSince(date) / 60)
        return minutes < 1 ? "just now" : "indexed \(minutes)m ago"
    }

    // MARK: Storage map

    @ViewBuilder
    private var storageMap: some View {
        if let folders = storage.scan?.topFolders, !folders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STORAGE MAP · HOME FOLDER")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Halo.textDim)
                    Spacer()
                    Text("safety lens — green is pre-vetted reclaim, red is never bulk-touched")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
                TreemapView(folders: Array(folders.prefix(8)))
                    .frame(height: 190)
            }
            .padding(16)
            .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Treemap

/// Binary treemap: recursively split items into two size-balanced halves,
/// dividing the rect along its longer axis. Good enough aspect ratios for
/// ≤8 cells, ~40 lines, no GPU drama.
struct TreemapView: View {
    let folders: [FolderUsage]

    var body: some View {
        GeometryReader { geo in
            let rects = Self.layout(
                weights: folders.map { Double($0.sizeBytes) },
                in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                    if index < rects.count {
                        cell(folder)
                            .frame(width: rects[index].width - 4, height: rects[index].height - 4)
                            .offset(x: rects[index].minX + 2, y: rects[index].minY + 2)
                    }
                }
            }
        }
    }

    private func cell(_ folder: FolderUsage) -> some View {
        let tint = gradeColor(folder.grade)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.18), tint.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(ByteFormat.string(folder.sizeBytes))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
            .padding(8)
        }
        .clipped()
        .help("\(folder.path) — \(ByteFormat.string(folder.sizeBytes))")
        .onTapGesture {
            NSWorkspace.shared.activateFileViewerSelecting([
                URL(fileURLWithPath: folder.path)
            ])
        }
    }

    static func layout(weights: [Double], in rect: CGRect) -> [CGRect] {
        guard !weights.isEmpty else { return [] }
        guard weights.count > 1 else { return [rect] }
        let total = weights.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: rect, count: weights.count)
        }
        // Split into a prefix/suffix whose sums are as balanced as possible.
        // Items arrive sorted descending, so the prefix stays small.
        var prefixSum = 0.0
        var splitIndex = 1
        for (index, weight) in weights.enumerated() {
            prefixSum += weight
            if prefixSum >= total / 2 || index == weights.count - 2 {
                splitIndex = index + 1
                break
            }
        }
        let fraction = weights[..<splitIndex].reduce(0, +) / total
        let first: CGRect
        let second: CGRect
        if rect.width >= rect.height {
            let w = rect.width * fraction
            first = CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)
            second = CGRect(
                x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height)
        } else {
            let h = rect.height * fraction
            first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h)
            second = CGRect(
                x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h)
        }
        return layout(weights: Array(weights[..<splitIndex]), in: first)
            + layout(weights: Array(weights[splitIndex...]), in: second)
    }
}

// MARK: - Smart Clean

struct SmartCleanPanel: View {
    @Environment(StorageModel.self) private var storage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("SMART CLEAN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("every item explained · everything undoable for 7 days")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                legend
            }
            if let items = storage.scan?.items, !items.isEmpty {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        CleanRow(item: item)
                    }
                }
            } else if storage.scanState == .scanning {
                Text("Scanning your home folder and app caches…")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Nothing to clean — your Mac is already tidy.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private var legend: some View {
        HStack(spacing: 8) {
            GradePill(grade: .safe)
            Text("auto-selected ·")
            GradePill(grade: .careful)
            Text("needs your tick ·")
            GradePill(grade: .review)
            Text("never bulk-selected")
        }
        .font(.system(size: 9))
        .foregroundStyle(Halo.textDim)
    }
}

struct CleanRow: View {
    @Environment(StorageModel.self) private var storage
    let item: CleanItem

    private var isSelected: Bool { storage.selection.contains(item.id) }
    private var isExpanded: Bool { storage.expandedItem == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                checkbox
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(symbol(item.category))  \(item.label)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                        .lineLimit(1)
                }
                Spacer()
                GradePill(grade: item.grade)
                Text(idleText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .frame(width: 64, alignment: .trailing)
                Text(ByteFormat.string(item.sizeBytes))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
                    .frame(width: 76, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                isSelected ? Halo.surface2 : Halo.surface2.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .opacity(item.grade == .review ? 0.75 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                storage.expandedItem = isExpanded ? nil : item.id
            }

            if isExpanded {
                evidence
            }
        }
    }

    private var checkbox: some View {
        Button { storage.toggle(item) } label: {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(
                    isSelected ? Halo.ion : Halo.textDim.opacity(0.6),
                    style: StrokeStyle(lineWidth: 1.5, dash: item.grade == .review ? [3] : [])
                )
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Halo.ion.opacity(0.9) : .clear)
                )
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Halo.void)
                    }
                }
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .disabled(item.grade == .review)
        .help(
            item.grade == .review
                ? "Real data — Pulse never bulk-selects this tier" : "Include in clean")
    }

    private var evidence: some View {
        HStack(spacing: 8) {
            Text("Why \(item.grade.rawValue.uppercased()):")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(gradeColor(item.grade))
            Text(item.detail)
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
                .lineLimit(1)
            Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: item.path)
                ])
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Halo.ion)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Halo.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 24)
        .padding(.top, 2)
    }

    private var idleText: String {
        guard let days = item.idleDays else { return "—" }
        if days < 1 { return "live" }
        if days >= 30 { return "\(days / 30)mo idle" }
        return "\(days)d idle"
    }

    private func symbol(_ category: String) -> String {
        switch category {
        case "App caches": "🌐"
        case "App logs": "📋"
        case "Developer junk", "Stale dev junk": "🧑‍💻"
        case "Old installers": "📦"
        case "iOS backups": "📱"
        case "Trash": "🗑"
        case "Large & old": "🎥"
        default: "📁"
        }
    }
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
                    Text("⚡ Clean \(ByteFormat.string(storage.selectedBytes))")
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
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private var footerNote: String {
        storage.cleanReport
            ?? "→ staged in Vault for 7 days · restore anytime · space frees when the Vault purges, never silently"
    }
}

// MARK: - Vault

struct VaultPanel: View {
    @Environment(StorageModel.self) private var storage
    @State private var purgeCandidate: VaultSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("SAFETY VAULT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("everything Pulse removes lands here first · restore is always one click")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if storage.vaultTotalBytes > 0 {
                    Text("● \(ByteFormat.string(storage.vaultTotalBytes)) STAGED")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Halo.pulseGreen)
                }
            }
            if storage.vaultSessions.isEmpty {
                Text("Vault is empty — nothing staged for deletion.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(storage.vaultSessions) { session in
                    sessionRow(session)
                }
            }
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog(
            "Permanently delete this Vault session?",
            isPresented: Binding(
                get: { purgeCandidate != nil },
                set: { if !$0 { purgeCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(ByteFormat.string(purgeCandidate?.totalBytes ?? 0)) forever", role: .destructive) {
                if let session = purgeCandidate { storage.purge(session) }
                purgeCandidate = nil
            }
            Button("Cancel", role: .cancel) { purgeCandidate = nil }
        } message: {
            Text(
                "This is the only irreversible action in Pulse. "
                    + "\(purgeCandidate?.items.count ?? 0) items will be gone for good."
            )
        }
    }

    private func sessionRow(_ session: VaultSession) -> some View {
        HStack(spacing: 12) {
            Text("✦")
                .font(.system(size: 14))
                .foregroundStyle(Halo.volt)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text("\(session.items.count) items · staged \(dateText(session.date))")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer()
            Text(countdownText(session))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.amber)
            Text(ByteFormat.string(session.totalBytes))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
            Button("↺ Restore all") { storage.restore(session) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Halo.pulseGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Halo.pulseGreen.opacity(0.12), in: Capsule())
            Button("Purge now") { purgeCandidate = session }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Halo.flare)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Halo.flare.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Halo.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func countdownText(_ session: VaultSession) -> String {
        let remaining = session.expiry().timeIntervalSince(.now)
        guard remaining > 0 else { return "purging…" }
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        return days > 0 ? "purges in \(days)d \(String(format: "%02d", hours))h" : "purges in \(hours)h"
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
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
