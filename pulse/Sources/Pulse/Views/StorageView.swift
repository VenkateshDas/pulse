import AppKit
import PulseKit
import SwiftUI

/// Storage browser: Finder-style Miller columns over any volume/folder.
/// Every row shows its size and a bar relative to the largest sibling, so
/// the heavy folders jump out at every level. Click a folder to open the
/// next column; select a file (or right-click anything) for details and
/// a safe move-to-Trash. Deletions sync in place — no rescan.
struct StorageView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(StorageModel.self) private var storage

    @State private var selectedID: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background { GlassLayer(tint: Halo.surface1.opacity(0.6)) }
            Rectangle().fill(Halo.surface2).frame(width: 1)

            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Halo.surface2).frame(height: 1)
                HStack(spacing: 0) {
                    columnsArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if selectedItem != nil {
                        Rectangle().fill(Halo.surface2).frame(width: 1)
                        detailArea
                            .frame(width: 280)
                    }
                }
                Rectangle().fill(Halo.surface2).frame(height: 1)
                bottomBar
            }
            .background(Halo.void)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { storage.appeared() }
    }

    // MARK: Sidebar — real volumes + favorite folders (AR-3)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VOLUMES")
                .font(.system(size: 10, weight: .bold)).tracking(1.5)
                .foregroundStyle(Halo.textDim)
            ForEach(Self.mountedVolumes(), id: \.path) { vol in
                sidebarRow(icon: "internaldrive", title: vol.name, subtitle: vol.capacity) {
                    storage.navigateToPath(vol.path, name: vol.name)
                    selectedID = nil
                }
            }

            Text("FAVORITE FOLDERS")
                .font(.system(size: 10, weight: .bold)).tracking(1.5)
                .foregroundStyle(Halo.textDim).padding(.top, 8)
            ForEach(Self.favoriteFolders(), id: \.path) { fav in
                sidebarRow(icon: fav.icon, title: fav.name, subtitle: nil) {
                    storage.navigateToPath(fav.path, name: fav.name)
                    selectedID = nil
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private func sidebarRow(icon: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20).foregroundStyle(Halo.ion)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Halo.textPrimary).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Top bar — breadcrumb + lens switcher

    private var topBar: some View {
        HStack(spacing: 12) {
            if storage.navigationPath.count > 1 {
                Button {
                    storage.popDirectory()
                    selectedID = nil
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Halo.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(storage.navigationPath.enumerated()), id: \.offset) { index, node in
                        Button {
                            storage.navigateTo(index: index)
                            selectedID = nil
                        } label: {
                            Text(node.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(index == storage.navigationPath.count - 1 ? Halo.textPrimary : Halo.textDim)
                        }
                        .buttonStyle(.plain)
                        if index < storage.navigationPath.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Halo.surface2)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Halo.surface1)
    }

    // MARK: Columns

    private var columnsArea: some View {
        ZStack {
            if storage.scanState == .scanning && storage.navigationPath.first?.children?.isEmpty != false {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning \(storage.navigationPath.last?.name ?? "disk")…")
                        .font(.system(size: 12)).foregroundStyle(Halo.textDim)
                }
            } else if storage.navigationPath.isEmpty {
                EmptyState(
                    icon: "folder.badge.questionmark",
                    title: "Nothing to browse",
                    hint: "Folder is empty or restricted.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 0) {
                            ForEach(Array(storage.navigationPath.enumerated()), id: \.element.id) { index, column in
                                columnView(index: index, column: column)
                                    .frame(width: 260)
                                    .id(column.id)
                                Rectangle().fill(Halo.surface2).frame(width: 1)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .onChange(of: storage.navigationPath.count) {
                        if let last = storage.navigationPath.last {
                            withAnimation(Halo.Motion.snappy) { proxy.scrollTo(last.id, anchor: .trailing) }
                        }
                    }
                }
            }
        }
    }

    private func columnView(index: Int, column: StorageNode) -> some View {
        let children = column.children ?? []
        let maxBytes = children.first?.sizeBytes ?? 0
        let openChildPath = index + 1 < storage.navigationPath.count
            ? storage.navigationPath[index + 1].path : nil
        let scanItems = storage.scanItemsByPath
        return ScrollView(.vertical) {
            LazyVStack(spacing: 1) {
                if children.isEmpty {
                    Text("Empty or restricted")
                        .font(.system(size: 11)).foregroundStyle(Halo.textDim)
                        .padding(.top, 24)
                } else {
                    ForEach(children) { child in
                        rowView(
                            child, columnIndex: index, maxBytes: maxBytes,
                            isOpen: child.path == openChildPath,
                            info: itemInfo(child, scanItems: scanItems))
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func rowView(_ node: StorageNode, columnIndex: Int, maxBytes: UInt64, isOpen: Bool, info: StorageItemInfo) -> some View {
        let isSelected = selectedID == node.id
        let fraction = maxBytes > 0 ? Double(node.sizeBytes) / Double(maxBytes) : 0
        return Button {
            if node.isDirectory && !info.isPseudo {
                selectedID = nil
                storage.openColumn(node, fromColumn: columnIndex)
            } else {
                selectedID = isSelected ? nil : node.id
            }
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                    .resizable().frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(node.name)
                            .font(.system(size: 12, weight: isOpen ? .semibold : .regular))
                            .foregroundStyle(Halo.textPrimary)
                            .lineLimit(1)
                        if info.isProtected {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Halo.textDim)
                        }
                        Spacer(minLength: 4)
                        Text(node.sizeBytes > 0 ? ByteFormat.string(node.sizeBytes) : "—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Halo.surface2.opacity(0.5))
                            Capsule()
                                .fill(info.isProtected ? AnyShapeStyle(Halo.textDim.opacity(0.5)) : AnyShapeStyle(gradeColor(info.grade)))
                                .frame(width: max(geo.size.width * fraction, node.sizeBytes > 0 ? 2 : 0))
                        }
                    }
                    .frame(height: 3)
                }
                if node.isDirectory && !info.isPseudo {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isOpen ? Halo.ion : Halo.textDim.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (isOpen || isSelected) ? Halo.ion.opacity(isOpen ? 0.18 : 0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu {
            if !info.isPseudo {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                }
                Button("Get Info") { selectedID = node.id }
                if !info.isProtected && info.grade != .review {
                    Divider()
                    Button("Move to Trash", role: .destructive) {
                        storage.cleanNode(node)
                    }
                    .disabled(storage.isCleaning)
                }
            }
        }
        .help("\(node.name) · \(ByteFormat.string(node.sizeBytes))")
    }

    // MARK: Detail

    private var selectedItem: StorageItemInfo? {
        guard let id = selectedID else { return nil }
        let scanItems = storage.scanItemsByPath
        for column in storage.navigationPath {
            if let node = column.children?.first(where: { $0.id == id }) {
                return itemInfo(node, scanItems: scanItems, includeAge: true)
            }
        }
        return nil
    }

    @ViewBuilder
    private var detailArea: some View {
        if let item = selectedItem {
            StorageDetailPanel(cell: item) { node in
                if let index = storage.navigationPath.lastIndex(where: { $0.children?.contains(where: { $0.id == node.id }) == true }) {
                    selectedID = nil
                    storage.openColumn(node, fromColumn: index)
                }
            }
            .padding(12)
        }
    }

    /// `includeAge` triggers a stat() for mtime — detail panel only, too
    /// costly to run per visible row.
    private func itemInfo(_ node: StorageNode, scanItems: [String: CleanItem], includeAge: Bool = false) -> StorageItemInfo {
        let item = scanItems[node.path]
        return StorageItemInfo(
            node: node,
            grade: item?.grade ?? Self.heuristicGrade(node),
            idleDays: item?.idleDays ?? (includeAge ? Self.mtimeDays(node.path) : nil),
            category: item?.category ?? Self.heuristicCategory(node))
    }

    // MARK: Bottom bar — purgeable explanation (SM-2) + total

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "internaldrive.fill").foregroundStyle(Halo.ion)
                Text(storage.navigationPath.last?.name ?? "Disk")
                    .font(.system(size: 13, weight: .semibold))
                
                Button(action: {
                    storage.refreshAll()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Halo.textDim)
                .padding(.leading, 4)
                .help("Rescan storage map and free space")
                .accessibilityLabel("Rescan")
                
                if storage.isStreamingSizes || storage.scanState == .scanning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .padding(.leading, 8)
                    Text("Scanning sizes…").font(.system(size: 11)).foregroundStyle(Halo.textDim)
                } else if let report = storage.cleanReport {
                    Text(report).font(.system(size: 12)).foregroundStyle(Halo.pulseGreen)
                        .padding(.leading, 12)
                }
                
                Spacer()
                
                // "Free" matches Finder and the dashboard/popover: it counts
                // purgeable space as available (volumeAvailableCapacityForImportantUsage).
                // Purgeable is still surfaced separately as a breakdown, not subtracted.
                let finderFree = model.snapshot?.diskFreeBytes ?? 0
                let total = model.snapshot?.diskTotalBytes ?? 0
                let purgeable = storage.purgeableBytes
                let used = total > finderFree ? total - finderFree : 0
                
                HStack(spacing: 12) {
                    Group {
                        Text("Used: ").foregroundStyle(Halo.textDim) +
                        Text(ByteFormat.string(used)).foregroundStyle(Halo.textPrimary)
                    }
                    if purgeable > 0 {
                        Group {
                            Text("Purgeable: ").foregroundStyle(Halo.textDim) +
                            Text(ByteFormat.string(purgeable)).foregroundStyle(Halo.amber)
                        }
                    }
                    Group {
                        Text("Free: ").foregroundStyle(Halo.textDim) +
                        Text(ByteFormat.string(finderFree)).foregroundStyle(Halo.pulseGreen)
                    }
                    Text("•").foregroundStyle(Halo.surface2)
                    Group {
                        Text("Total: ").foregroundStyle(Halo.textDim) +
                        Text(ByteFormat.string(total)).foregroundStyle(Halo.textPrimary)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .padding(16)
            .background(Halo.surface1)
        }
    }

    // MARK: Heuristics + helpers

    private static func heuristicGrade(_ node: StorageNode) -> SafetyGrade {
        let lower = node.path.lowercased()
        if lower.contains("/caches") || node.name.lowercased().contains("cache") { return .safe }
        if ["documents", "pictures", "movies", "music", "desktop"].contains(node.name.lowercased()) {
            return .review
        }
        return .careful
    }

    private static func heuristicCategory(_ node: StorageNode) -> String {
        if node.path.lowercased().contains("/caches") { return "Caches" }
        if !node.isDirectory { return "File" }
        return node.name
    }

    private nonisolated static func mtimeDays(_ path: String) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let modified = attrs[.modificationDate] as? Date
        else { return nil }
        return max(0, Int(Date.now.timeIntervalSince(modified) / 86400))
    }

    private struct Volume { let name: String; let path: String; let capacity: String }
    private struct Favorite { let name: String; let path: String; let icon: String }

    private static func mountedVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                values.volumeIsBrowsable == true
            else { return nil }
            let name = values.volumeName ?? url.lastPathComponent
            let cap = values.volumeTotalCapacity.map { ByteFormat.string(UInt64($0)) } ?? ""
            return Volume(name: name, path: url.path, capacity: cap)
        }
    }

    private static func favoriteFolders() -> [Favorite] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let specs: [(String, String)] = [
            ("Downloads", "arrow.down.circle"), ("Desktop", "menubar.dock.rectangle"),
            ("Documents", "doc"), ("Pictures", "photo"),
        ]
        return specs.compactMap { name, icon in
            let path = home.appendingPathComponent(name).path
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return Favorite(name: name, path: path, icon: icon)
        }
    }
}
