import AppKit
import PulseKit
import SwiftUI

/// Storage Map (spec §3.3): a squarified treemap of any volume/folder with
/// Safety / Age / Owner lenses, APFS-correct purgeable explanation, and a
/// click-to-detail panel. Replaces the old file-browser; the SmartScanner
/// grades enrich each cell so the Safety lens is actionable, not just pretty.
struct StorageView: View {
    @Environment(DashboardModel.self) private var model
    @Environment(StorageModel.self) private var storage

    @State private var lens: StorageLens = .safety
    @State private var selectedID: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(Halo.surface1)
            Rectangle().fill(Halo.surface2).frame(width: 1)

            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Halo.surface2).frame(height: 1)
                HStack(spacing: 0) {
                    mapArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if selectedID != nil {
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
            lensSwitcher
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Halo.surface1)
    }

    private var lensSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(StorageLens.allCases) { option in
                let on = lens == option
                Button { lens = option } label: {
                    Text(option.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(on ? Halo.void : Halo.textDim)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(on ? AnyShapeStyle(Halo.ion) : AnyShapeStyle(Halo.surface2), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("\(option.rawValue) lens")
            }
        }
    }

    // MARK: Map

    private var mapArea: some View {
        ZStack {
            if storage.scanState == .scanning && currentChildren.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning \(storage.navigationPath.last?.name ?? "disk")…")
                        .font(.system(size: 12)).foregroundStyle(Halo.textDim)
                }
            } else if currentCells.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32)).foregroundStyle(Halo.surface2)
                    Text("Folder is empty or restricted.")
                        .font(.system(size: 13)).foregroundStyle(Halo.textDim)
                }
            } else {
                TreemapView(cells: currentCells, lens: lens, selectedID: $selectedID) { node in
                    storage.pushDirectory(node)
                    selectedID = nil
                }
                .padding(10)
            }
            legend
        }
    }

    private var legend: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                ForEach(legendItems, id: \.0) { item in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(item.1).frame(width: 10, height: 10)
                        Text(item.0).font(.system(size: 9, weight: .medium)).foregroundStyle(Halo.textPrimary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Halo.surface1, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            .padding(10)
        }
    }

    private var legendItems: [(String, Color)] {
        switch lens {
        case .safety:
            return [("Safe", Halo.pulseGreen), ("Careful", Halo.amber), ("Review", Halo.flare)]
        case .age:
            return [("<30d", Halo.pulseGreen), ("30–180d", Halo.amber), (">180d", Halo.flare), ("unknown", Halo.textDim)]
        case .owner:
            var categories = [String]()
            for cell in currentCells {
                if !categories.contains(cell.category) {
                    categories.append(cell.category)
                }
            }
            let palette = [Halo.ion, Halo.volt, Halo.amber, Halo.pulseGreen, Halo.flare]
            return categories.prefix(5).map { cat in
                (cat, palette[abs(cat.hashValue) % palette.count])
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailArea: some View {
        if let id = selectedID, let cell = currentCells.first(where: { $0.id == id }) {
            StorageDetailPanel(cell: cell) { node in
                storage.pushDirectory(node)
                selectedID = nil
            }
            .padding(12)
        }
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
                
                let finderFree = model.snapshot?.diskFreeBytes ?? 0
                let total = model.snapshot?.diskTotalBytes ?? 0
                let purgeable = storage.purgeableBytes
                let rawFree = finderFree > purgeable ? finderFree - purgeable : 0
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
                        Text(ByteFormat.string(rawFree)).foregroundStyle(Halo.pulseGreen)
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

    // MARK: Cell building

    private var currentChildren: [StorageNode] {
        storage.navigationPath.last?.children ?? []
    }

    private var currentCells: [TreemapCell] {
        let items = storage.scanItemsByPath
        // Children arrive size-sorted; cap to the largest so the map stays
        // readable and per-cell mtime lookups stay cheap.
        return currentChildren.prefix(60).map { node in
            let item = items[node.path]
            return TreemapCell(
                node: node,
                grade: item?.grade ?? Self.heuristicGrade(node),
                idleDays: item?.idleDays ?? Self.mtimeDays(node.path),
                category: item?.category ?? Self.heuristicCategory(node))
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
