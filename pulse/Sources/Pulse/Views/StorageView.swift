import AppKit
import PulseKit
import QuickLook
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
    @State private var hoveredRowID: String?
    /// Quick Look target (spacebar on a selected row, like Finder).
    @State private var previewURL: URL?
    @State private var keyMonitor: Any?
    @State private var usagePathQuery: String = ""
    @State private var showHiddenBreakdown = false

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .quickLookPreview($previewURL)
        .sheet(isPresented: Binding(
            get: { storage.verdictTarget != nil },
            set: { if !$0 { storage.dismissVerdict() } })
        ) {
            if let target = storage.verdictTarget {
                FolderVerdictView(
                    targetPath: target, verdict: storage.verdict,
                    isScanning: storage.isScanningVerdict)
            }
        }
        .onAppear {
            storage.appeared()
            startKeyMonitor()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    /// Spacebar toggles Quick Look for the selected row, like Finder.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                let item = selectedItem, !item.isPseudo
            else { return event }
            previewURL = previewURL == nil ? URL(fileURLWithPath: item.node.path) : nil
            return nil
        }
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
            usagePathField
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Halo.surface1)
    }

    /// Paste any path directly to get its deletion verdict, without browsing there.
    private var usagePathField: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
            TextField("Can I delete… (paste a path)", text: $usagePathQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 180)
                .onSubmit {
                    let path = (usagePathQuery.trimmingCharacters(in: .whitespaces) as NSString)
                        .expandingTildeInPath
                    guard !path.isEmpty else { return }
                    storage.inspect(path: path)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Halo.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
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
                            info: itemInfo(child, scanItems: scanItems),
                            delta: index == 0 ? storage.rootDelta(for: child.path) : nil)
                    }
                    if index == 0, column.path == "/" {
                        hiddenRemainderRow(listed: children.reduce(0) { $0 + $1.sizeBytes })
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// Root folders never sum to "Used": APFS snapshots, purgeable space and
    /// hidden system data live outside every listed folder. Say so instead of
    /// letting the math silently not add up.
    @ViewBuilder
    private func hiddenRemainderRow(listed: UInt64) -> some View {
        let free = model.snapshot?.diskFreeBytes ?? 0
        let total = model.snapshot?.diskTotalBytes ?? 0
        let used = total > free ? total - free : 0
        if !storage.isStreamingSizes, used > listed, used - listed > 1_000_000_000 {
            Button {
                withAnimation(Halo.Motion.snappy) { showHiddenBreakdown.toggle() }
            } label: {
                pseudoRow(
                    icon: showHiddenBreakdown ? "chevron.down" : "eye.slash",
                    title: "Hidden & system data",
                    subtitle: "Snapshots, purgeable & system files outside these folders — click for breakdown",
                    value: "~\(ByteFormat.string(used - listed))",
                    valueColor: Halo.textDim,
                    delta: storage.hiddenDelta(current: used - listed))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Folders above sum to \(ByteFormat.string(listed)); used space is \(ByteFormat.string(used)). The difference is APFS snapshots, purgeable space and hidden system data macOS doesn't expose as folders.")
            if showHiddenBreakdown {
                hiddenBreakdownRows
            }
            // With free space listed too, the column visibly sums to Total.
            pseudoRow(
                icon: "circle.dashed",
                title: "Free space",
                subtitle: "Folders + hidden + free = \(ByteFormat.string(total)) total",
                value: ByteFormat.string(free),
                valueColor: Halo.pulseGreen)
        }
    }

    /// What the hidden remainder actually is: helper-volume sizes (df-style
    /// statfs), staged-update snapshot state and purgeable. Answers "where
    /// did 20 GB go" without leaving the app.
    @ViewBuilder
    private var hiddenBreakdownRows: some View {
        Group {
            if storage.stagedUpdatePinned {
                pseudoRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Staged macOS update",
                    subtitle: "Prepared & pinned by an os.update snapshot — frees itself after installing (or when macOS discards it)",
                    value: "pinned",
                    valueColor: Halo.amber)
                .help("macOS prepared an update and pinned the pre-update state in APFS snapshots. This can hold 10–25 GB. Installing the update (or letting macOS expire it) releases the space — nothing can delete it manually.")
            }
            ForEach(storage.hiddenComponents) { comp in
                pseudoRow(
                    icon: "internaldrive",
                    title: comp.label,
                    subtitle: comp.subtitle,
                    value: ByteFormat.string(comp.bytes),
                    valueColor: Halo.textDim)
            }
            if storage.purgeableBytes > 0 {
                pseudoRow(
                    icon: "sparkles",
                    title: "Purgeable space",
                    subtitle: "Caches & snapshots macOS reclaims automatically when needed",
                    value: ByteFormat.string(storage.purgeableBytes),
                    valueColor: Halo.amber)
            }
            if storage.tmSnapshotCount > 0 {
                HStack(spacing: 8) {
                    pseudoRow(
                        icon: "camera.on.rectangle",
                        title: "Time Machine snapshots (\(storage.tmSnapshotCount))",
                        subtitle: "Pin recently deleted data — safe to thin, hourly backups re-create them",
                        value: "—",
                        valueColor: Halo.textDim)
                    Button {
                        storage.thinLocalSnapshots()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(Halo.flare)
                    }
                    .buttonStyle(.plain)
                    .disabled(storage.isCleaning)
                    .padding(.trailing, 16)
                    .help("Runs Apple's tmutil thinlocalsnapshots (admin password required) — the sanctioned way to purge local Time Machine snapshots. Your actual backups on the backup disk are untouched.")
                    .accessibilityLabel("Thin Time Machine snapshots")
                }
            }
            if storage.updateDownloadsBytes >= 50_000_000 {
                updateDownloadsRow
            }
            // Volumes, snapshots and purgeable overlap each other and the
            // folder rows — attribution, not arithmetic that sums to the top.
            Text("Slices overlap — they explain the space, they don't sum to it.")
                .font(.system(size: 9))
                .foregroundStyle(Halo.textDim.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .padding(.leading, 14)
    }

    /// Downloaded-but-not-installed macOS/firmware updates (/Library/Updates).
    /// Apple removed the delete button from System Settings; this restores it.
    private var updateDownloadsRow: some View {
        HStack(spacing: 8) {
            pseudoRow(
                icon: "arrow.down.circle.dotted",
                title: "macOS update downloads",
                subtitle: "Downloaded, not installed — re-downloads on demand",
                value: ByteFormat.string(storage.updateDownloadsBytes),
                valueColor: Halo.amber)
            if storage.updateDownloadsRestricted {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .padding(.trailing, 16)
                    .help("SIP-protected — no app (even with an admin password) can delete these. macOS removes them itself after the update installs or expires.")
            } else {
                Button {
                    storage.clearUpdateDownloads()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.flare)
                }
                .buttonStyle(.plain)
                .disabled(storage.isCleaning)
                .padding(.trailing, 16)
                .help("Deletes /Library/Updates downloads permanently (admin password required). Software Update re-downloads if you install later.")
                .accessibilityLabel("Delete macOS update downloads")
            }
        }
    }

    private func pseudoRow(icon: String, title: String, subtitle: String, value: String, valueColor: Color, delta: Int64? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Halo.textDim)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                    Spacer(minLength: 4)
                    // Same ▲/▼ daily-baseline chip the folder rows show.
                    if let delta, abs(delta) >= 100_000_000 {
                        Text("\(delta >= 0 ? "▲" : "▼") \(ByteFormat.string(UInt64(abs(delta))))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(delta >= 0 ? Halo.amber : Halo.pulseGreen)
                            .help("Changed \(ByteFormat.string(UInt64(abs(delta)))) since the last daily size check")
                    }
                    Text(value)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(valueColor)
                }
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(Halo.textDim.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func rowView(_ node: StorageNode, columnIndex: Int, maxBytes: UInt64, isOpen: Bool, info: StorageItemInfo, delta: Int64? = nil) -> some View {
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
                        // ▲/▼ vs the saved daily baseline — where growth is.
                        if let delta, abs(delta) >= 100_000_000 {
                            Text("\(delta >= 0 ? "▲" : "▼") \(ByteFormat.string(UInt64(abs(delta))))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(delta >= 0 ? Halo.amber : Halo.pulseGreen)
                                .help("Changed \(ByteFormat.string(UInt64(abs(delta)))) since the last daily size check")
                        }
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
                // Hover-revealed trash, Finder-quiet: always laid out (no row
                // jump), visible only on hover, and only for deletable rows.
                if !info.isPseudo && !info.isProtected && info.grade != .review {
                    Button {
                        storage.cleanNode(node)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(hoveredRowID == node.id ? Halo.flare : Halo.textDim)
                    }
                    .buttonStyle(.plain)
                    .opacity(hoveredRowID == node.id ? 1 : 0)
                    .disabled(storage.isCleaning)
                    .help("Move to Trash")
                    .accessibilityLabel("Move \(node.name) to Trash")
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
        .onHover { hoveredRowID = $0 ? node.id : (hoveredRowID == node.id ? nil : hoveredRowID) }
        .contextMenu {
            if !info.isPseudo {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                }
                Button("Get Info") { selectedID = node.id }
                Button("Can I delete this?") {
                    storage.inspect(path: node.path)
                }
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

}
