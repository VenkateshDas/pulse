import AppKit
import PulseKit
import SwiftUI

/// Reclaim tab: cleanable items grouped by kind (safe pre-selected, careful
/// opt-in), plus big hidden locations worth reviewing by hand — the old
/// Hidden Space tab folded in as a section.
struct CleanView: View {
    @Environment(StorageModel.self) private var storage
    @Environment(InsightsModel.self) private var insights
    @Environment(CleanModel.self) private var cleanModel
    @State private var hoveredID: String?
    @State private var collapsedCategories: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            PermissionHelp(permission: .fullDiskAccess)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if storage.scanState == .scanning && storage.scan == nil {
                        scanning
                    } else if let scan = storage.scan {
                        let allItems = scan.items
                        let unprotectedItems = allItems.filter {
                            $0.grade != .review && !CleanSchedule.isPathExcluded($0.path, in: cleanModel.schedule.excludedPaths)
                        }
                        let protectedItems = allItems.filter {
                            CleanSchedule.isPathExcluded($0.path, in: cleanModel.schedule.excludedPaths)
                        }
                        if unprotectedItems.isEmpty {
                            Text("No recommended items found. You can review larger files in the Files view.")
                                .font(Halo.font(size: 12))
                                .foregroundStyle(Halo.textDim)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                        } else {
                            categorySections(unprotectedItems)
                        }
                        hiddenSpaceSection(protectedItems: protectedItems)
                    } else {
                        Text("Choose Rescan to look for cleanup candidates. Scanning does not remove files.")
                            .font(Halo.font(size: 12))
                            .foregroundStyle(Halo.textDim)
                        hiddenSpaceSection(protectedItems: [])
                    }
                    AutoCleanCard()
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)

            CleanFooter()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear {
            storage.appeared()
            if !insights.hasScanned { insights.scan() }
        }
    }

    private var header: some View {
        PageHeader(
            "Cleanup",
            subtitle: "Review files you no longer need. Recommended items are selected; other items need your choice."
        ) {
            RefreshButton(
                help: "Rescan cleanable items",
                disabled: storage.scanState == .scanning
            ) {
                storage.refreshAll()
                insights.scan()
            }
            if storage.scanState == .scanning || storage.isStreamingSizes {
                Button("Stop scan") { storage.cancelScan() }.buttonStyle(.bordered)
            }
            Button("Select recommended") {
                storage.selectAllSafe(excludedPaths: cleanModel.schedule.excludedPaths)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(Halo.ion)
            .disabled(storage.scanState == .scanning)
        }
    }

    // MARK: Category groups

    @ViewBuilder
    private func categorySections(_ items: [CleanItem]) -> some View {
        let groups = Dictionary(grouping: items, by: \.category)
            .sorted { lhs, rhs in
                lhs.value.reduce(0) { $0 + $1.sizeBytes } > rhs.value.reduce(0) { $0 + $1.sizeBytes }
            }
        LazyVStack(spacing: 12) {
            ForEach(groups, id: \.key) { category, group in
                categorySection(category, group)
            }
        }
    }

    private func categorySection(_ category: String, _ items: [CleanItem]) -> some View {
        let subtotal = items.reduce(0) { $0 + $1.sizeBytes }
        let collapsed = collapsedCategories.contains(category)
        let selectedCount = items.filter { storage.selection.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(Halo.Motion.snappy) {
                    if collapsed { collapsedCategories.remove(category) } else { collapsedCategories.insert(category) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(Halo.font(size: 9, weight: .bold))
                        .foregroundStyle(Halo.textDim)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Text(category)
                        .font(Halo.font(size: 11, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")\(selectedCount > 0 ? " · \(selectedCount) selected" : "")")
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.textDim)
                    Spacer()
                    Text(ByteFormat.string(subtotal))
                        .font(Halo.font(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            if !collapsed {
                ForEach(items) { item in
                    row(item)
                }
            }
        }
    }

    // MARK: Hidden space (merged from the old Hidden Space tab)

    @ViewBuilder
    private func hiddenSpaceSection(protectedItems: [CleanItem]) -> some View {
        let hasInsights = !insights.insights.isEmpty
        let hasProtected = !protectedItems.isEmpty
        if insights.isScanning && !hasInsights && !hasProtected {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Measuring hidden space…").font(Halo.font(size: 11)).foregroundStyle(Halo.textDim)
            }
        } else if hasInsights || hasProtected {
            let totalBytes = UInt64(max(0, insights.totalBytes)) + protectedItems.reduce(0) { $0 + $1.sizeBytes }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("WORTH A LOOK")
                        .font(Halo.font(size: 10, weight: .semibold))
                        .foregroundStyle(Halo.amber)
                    Text("Big locations & protected items — real data Pulse never bulk-cleans.")
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.textDim)
                    Spacer()
                    Text(ByteFormat.string(totalBytes))
                        .font(Halo.font(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.horizontal, 4)

                if hasProtected {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.fill")
                                .font(Halo.font(size: 10))
                                .foregroundStyle(Halo.ion)
                            Text("PROTECTED ITEMS (\(protectedItems.count))")
                                .font(Halo.font(size: 9, weight: .semibold))
                                .foregroundStyle(Halo.textPrimary)
                            Text("Exempted from auto-clean & bulk deletion")
                                .font(Halo.font(size: 10))
                                .foregroundStyle(Halo.textDim)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)

                        ForEach(protectedItems) { item in
                            row(item, isProtected: true)
                        }
                    }
                    .padding(.bottom, 4)
                }

                ForEach(insights.insights) { insight in
                    insightRow(insight)
                }
            }
            .padding(.top, 8)
        }
    }

    private func insightRow(_ insight: Insight) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: FileIconCache.icon(forPath: insight.path, isDirectory: true))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(insight.label)
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text(insight.reversibleHint)
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
            }
            Spacer()
            Text(ByteFormat.string(UInt64(max(0, insight.bytes))))
                .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
            Button {
                insights.reveal(insight.path)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder — \(insight.path)")
            .accessibilityLabel("Show \(insight.path) in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Halo.surface2.opacity(hoveredID == insight.id ? 0.75 : 0.4),
            in: RoundedRectangle(cornerRadius: 8))
        .onHover { hoveredID = $0 ? insight.id : nil }
    }

    private var scanning: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Scanning for cleanable space…")
                .font(Halo.font(size: 12))
                .foregroundStyle(Halo.textDim)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func row(_ item: CleanItem, isProtected: Bool = false) -> some View {
        let selected = storage.selection.contains(item.id)
        let selectable = item.grade != .review && !isProtected
        return HStack(spacing: 10) {
            if !isProtected {
                Toggle("Select \(item.label), \(item.path)", isOn: Binding(
                    get: { selected }, set: { _ in storage.toggle(item) }
                ))
                .labelsHidden().toggleStyle(.checkbox)
                .disabled(!selectable || storage.isCleaning)

            }

            Image(nsImage: FileIconCache.icon(forPath: item.path))
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(Halo.font(size: 12, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                    if isProtected {
                        Text("PROTECTED")
                            .font(Halo.font(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Halo.ion.opacity(0.15), in: Capsule())
                            .foregroundStyle(Halo.ion)
                    }
                }
                Text(detailLine(item))
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
            }
            Spacer()
            if !isProtected { GradePill(grade: item.grade) }
            Text(ByteFormat.string(item.sizeBytes))
                .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)

            if isProtected {
                Button {
                    cleanModel.toggleExclusion(item.path)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
                .buttonStyle(.plain)
                .help("Include in cleanup suggestions")
                .accessibilityLabel("Include \(item.label) in cleanup suggestions")

                Button {
                    storage.trashProtectedItem(item, cleanModel: cleanModel)
                } label: {
                    Image(systemName: "trash")
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.critical)
                }
                .buttonStyle(.plain)
                .help("Move to Trash")
                .accessibilityLabel("Move \(item.label) to Trash")
            } else {
                Button {
                    if storage.selection.contains(item.id) {
                        storage.toggle(item)
                    }
                    cleanModel.toggleExclusion(item.path)
                } label: {
                    Image(systemName: "shield.slash")
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
                .buttonStyle(.plain)
                .help("Exclude from automatic cleanup")
                .accessibilityLabel("Exclude \(item.label) from automatic cleanup")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder — \(item.path)")
            .accessibilityLabel("Show \(item.label) in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Halo.surface2.opacity(hoveredID == item.id ? 0.75 : 0.4),
            in: RoundedRectangle(cornerRadius: 8))
        .onHover { hoveredID = $0 ? item.id : nil }
    }

    private func detailLine(_ item: CleanItem) -> String {
        if let idle = item.idleDays {
            return "\(item.detail) · idle \(idle)d"
        }
        return item.detail
    }
}

// MARK: - Auto Clean card

struct AutoCleanCard: View {
    @State private var reviewAutomaticCleanup = false
    @Environment(CleanModel.self) private var model
    @AppStorage(SmartScanner.developerModeKey) private var developerMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Automatic cleanup")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                frequencyPicker
            }

            HStack(spacing: 28) {
                scheduleFact(
                    label: "NEXT RUN",
                    value: Self.runDateText(model.schedule.nextRun),
                    tint: Halo.ion)
                scheduleFact(
                    label: "LAST RUN",
                    value: lastRunText,
                    tint: Halo.textPrimary)
                Spacer()
                runButton
            }

            HStack(spacing: 10) {
                Text("WHEN")
                    .font(Halo.font(size: 9, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                timePreferencePicker
                Spacer()
            }

            Divider().overlay(Halo.surface2)

            HStack(spacing: 24) {
                toggleRow(
                    title: "Automatic cleanup",
                    subtitle: "moves recommended items to Trash at scheduled times",
                    isOn: Binding(
                        get: { model.schedule.autoCleanSafeTier },
                        set: { enabled in
                            if enabled { reviewAutomaticCleanup = true } else { model.setAutoClean(false) }
                        }
                    ))
                toggleRow(
                    title: "Notify on completion",
                    subtitle: "receive a result after scheduled cleanup",
                    isOn: Binding(
                        get: { model.schedule.notifyOnCompletion },
                        set: { model.setNotify($0) }
                    ))
                toggleRow(
                    title: "Include developer caches",
                    subtitle: "scan Homebrew, Docker & Xcode simulator caches too",
                    isOn: Binding(
                        get: { developerMode },
                        set: { developerMode = $0; model.loadPreview(force: true) }
                    ))
                Spacer()
            }

            if let report = model.report {
                FeedbackBadge(message: report)
            }
        }
        .padding(16)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
        .onAppear { model.appeared() }
        .confirmationDialog("Enable automatic cleanup?", isPresented: $reviewAutomaticCleanup, titleVisibility: .visible) {
            Button("Enable automatic cleanup") { model.setAutoClean(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("At scheduled times, Pulse will move recommended items from its cleanup scan to Trash without asking again. Excluded paths are skipped. Future scans can find different items; apps may need to rebuild removed caches. Restore files before emptying Trash. You can turn this off at any time.")
        }
    }

    private var frequencyPicker: some View {
        SegmentPicker(
            options: CleanSchedule.Frequency.allCases.map { ($0, $0.rawValue) },
            selection: Binding(
                get: { model.schedule.frequency },
                set: { model.setFrequency($0) }),
            help: { "Run the scheduled clean \($0.rawValue)" })
    }

    private var timePreferencePicker: some View {
        SegmentPicker(
            options: CleanSchedule.TimePreference.allCases.map { ($0, Self.timeLabel($0)) },
            selection: Binding(
                get: { model.schedule.timePreference },
                set: { model.setTimePreference($0) }),
            help: Self.timeHelp)
    }

    static func timeLabel(_ preference: CleanSchedule.TimePreference) -> String {
        switch preference {
        case .night: return "Night · 3 AM"
        case .morning: return "Morning · 9 AM"
        case .anytime: return "When idle"
        }
    }

    static func timeHelp(_ preference: CleanSchedule.TimePreference) -> String {
        switch preference {
        case .night: return "Run around 3:00 AM, when the Mac is usually idle"
        case .morning: return "Run around 9:00 AM"
        case .anytime: return "Run whenever the system is idle (background-scheduled)"
        }
    }

    private var runButton: some View {
        Button("Review cleanup candidates", systemImage: "checklist") {
            PulseNavigation.open(.storage, diskTab: 1)
        }.buttonStyle(.bordered)
            .help("Review the candidate list and selected items before moving anything to Trash")
    }

    private func scheduleFact(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Halo.font(size: 9, weight: .semibold))
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(Halo.font(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(subtitle)
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Halo.ion)
    }

    private var lastRunText: String {
        guard let last = model.schedule.lastRun else { return "never" }
        return Self.relativeText(last)
    }

    static func runDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' HH:mm"
        return formatter.string(from: date)
    }

    static func relativeText(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 90 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}


