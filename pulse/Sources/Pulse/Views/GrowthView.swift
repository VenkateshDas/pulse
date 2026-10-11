import AppKit
import PulseKit
import SwiftUI

/// "Where did my free space go" — folders that accumulated new or rewritten
/// files inside a chosen window, biggest first, with the offending files one
/// click away. Needs no prior baseline: file dates are the history.
struct GrowthView: View {
    @Environment(StorageModel.self) private var storage

    @State private var expandedGroups: Set<String> = []

    private static let windows: [(value: Int, label: String)] = [
        (1, "24 hours"), (2, "2 days"), (7, "7 days"), (30, "30 days"),
    ]

    var body: some View {
        @Bindable var storage = storage
        VStack(spacing: 0) {
            HStack(spacing: Halo.Space.lg) {
                Text("New & changed files")
                    .font(Halo.font(size: 13, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                SegmentPicker(
                    options: Self.windows, selection: $storage.growthWindowDays, style: .chip)
                Spacer()
                if let report = storage.growthReport {
                    Text("\(ByteFormat.string(report.totalRecentBytes)) created or modified since \(shortDate(report.cutoff))")
                        .font(Halo.font(size: 11))
                        .foregroundStyle(Halo.textDim)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Halo.surface1)
            Rectangle().fill(Halo.surface2).frame(height: 1)
            content
        }
        .background(Halo.void)
        .onAppear { if storage.growthReport == nil && !storage.isGrowthScanning { storage.runGrowthScan() } }
    }

    @ViewBuilder
    private var content: some View {
        if storage.isGrowthScanning {
            VStack(spacing: 10) {
                ProgressView()
                Text("Checking file dates across the disk…")
                    .font(Halo.font(size: 12)).foregroundStyle(Halo.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let report = storage.growthReport {
            if report.groups.isEmpty {
                EmptyState(
                    icon: "checkmark.circle",
                    title: "No big growth here",
                    hint: "Checked \(report.scannedFiles.formatted()) files; \(ByteFormat.string(report.totalRecentBytes)) were created or modified in this window but no folder gathered over 25 MB. Growth may be in snapshots or purgeable space — see the Hidden & system data row in Files.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(report.groups) { group in
                            groupRow(group, maxBytes: report.groups.first?.recentBytes ?? 0)
                            if expandedGroups.contains(group.id) {
                                ForEach(group.topFiles) { file in fileRow(file) }
                            }
                        }
                        Text("Checked \(report.scannedFiles.formatted()) files across the disk. Files created or modified in this window, grouped by folder; folders under 25 MB and snapshot churn aren't listed — those live in Files's Hidden & system data row.")
                            .font(Halo.font(size: 10))
                            .foregroundStyle(Halo.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private func groupRow(_ group: GrowthGroup, maxBytes: UInt64) -> some View {
        let expanded = expandedGroups.contains(group.id)
        let fraction = maxBytes > 0 ? Double(group.recentBytes) / Double(maxBytes) : 0
        return Button {
            withAnimation(Halo.Motion.snappy) {
                if expanded { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(Halo.font(size: 9, weight: .bold))
                    .foregroundStyle(Halo.textDim)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                FileIconView(path: group.path).frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(displayPath(group.path))
                            .font(Halo.font(size: 12, weight: .medium))
                            .foregroundStyle(Halo.textPrimary)
                            .lineLimit(1)
                        Text("\(group.fileCount) files")
                            .font(Halo.font(size: 10))
                            .foregroundStyle(Halo.textDim)
                        Spacer(minLength: 4)
                        Text("▲ \(ByteFormat.string(group.recentBytes))")
                            .font(Halo.font(size: 11, design: .monospaced))
                            .foregroundStyle(Halo.amber)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Halo.surface2.opacity(0.5))
                            Capsule().fill(Halo.amber)
                                .frame(width: max(geo.size.width * fraction, 2))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(expanded ? Halo.surface1 : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: group.path)])
            }
        }
    }

    private func fileRow(_ file: RecentFile) -> some View {
        HStack(spacing: 8) {
            FileIconView(path: file.path).frame(width: 14, height: 14)
            Text(file.name)
                .font(Halo.font(size: 11))
                .foregroundStyle(Halo.textPrimary)
                .lineLimit(1)
            Text(file.modified, format: .relative(presentation: .named))
                .font(Halo.font(size: 10))
                .foregroundStyle(Halo.textDim)
            Spacer(minLength: 4)
            Text(ByteFormat.string(file.sizeBytes))
                .font(Halo.font(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            if !StorageScanner.isProtected(file.path) {
                Button {
                    storage.cleanNode(
                        StorageNode(
                            id: file.path, name: file.name, path: file.path,
                            sizeBytes: file.sizeBytes, isDirectory: false))
                } label: {
                    Image(systemName: "trash")
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.flare)
                }
                .buttonStyle(.plain)
                .disabled(storage.isCleaning)
                .help("Move to Trash")
            }
        }
        .padding(.leading, 46)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
