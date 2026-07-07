import AppKit
import PulseKit
import SwiftUI

/// Reclaim tab: cleanable items grouped by kind (safe pre-selected, careful
/// opt-in), plus big hidden locations worth reviewing by hand — the old
/// Hidden Space tab folded in as a section.
struct CleanView: View {
    @Environment(StorageModel.self) private var storage
    @Environment(InsightsModel.self) private var insights
    @State private var hoveredID: String?
    @State private var collapsedCategories: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if storage.scanState == .scanning && storage.scan == nil {
                        scanning
                    } else if let scan = storage.scan {
                        let items = scan.items.filter { $0.grade != .review }
                        if items.isEmpty {
                            Text("No safe or careful items found.")
                                .font(.system(size: 12))
                                .foregroundStyle(Halo.textDim)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                        } else {
                            categorySections(items)
                        }
                    } else {
                        Text("No scan yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(Halo.textDim)
                    }
                    hiddenSpaceSection
                    AutoCleanCard()
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)

            CleanFooter()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear {
            storage.appeared()
            if !insights.hasScanned { insights.scan() }
        }
    }

    private var header: some View {
        PageHeader(
            "Reclaim",
            subtitle: "Everything safe to remove, grouped by kind — safe items pre-selected, careful items opt-in."
        ) {
            RefreshButton(
                help: "Rescan cleanable items",
                disabled: storage.scanState == .scanning
            ) {
                storage.refreshAll()
                insights.scan()
            }
            Button("Select All Safe") {
                storage.selectAllSafe()
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Halo.textDim)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Text(category)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Halo.textPrimary)
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")\(selectedCount > 0 ? " · \(selectedCount) selected" : "")")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                    Spacer()
                    Text(ByteFormat.string(subtotal))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
    private var hiddenSpaceSection: some View {
        if insights.isScanning && insights.insights.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Measuring hidden space…").font(.system(size: 11)).foregroundStyle(Halo.textDim)
            }
        } else if !insights.insights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("WORTH A LOOK")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Halo.amber)
                    Text("Big, easy-to-forget locations — real data Pulse never bulk-cleans. Review in Finder.")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                    Spacer()
                    Text(ByteFormat.string(UInt64(max(0, insights.totalBytes))))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.horizontal, 4)
                ForEach(insights.insights) { insight in
                    insightRow(insight)
                }
            }
            .padding(.top, 8)
        }
    }

    private func insightRow(_ insight: Insight) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: insight.path))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(insight.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text(insight.reversibleHint)
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
            }
            Spacer()
            Text(ByteFormat.string(UInt64(max(0, insight.bytes))))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
            Button {
                insights.reveal(insight.path)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder — \(insight.path)")
            .accessibilityLabel("Reveal in Finder")
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
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func row(_ item: CleanItem) -> some View {
        let selected = storage.selection.contains(item.id)
        let selectable = item.grade != .review
        return HStack(spacing: 10) {
            Button {
                storage.toggle(item)
            } label: {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        !selectable ? Halo.textDim.opacity(0.4)
                            : (selected ? Halo.pulseGreen : Halo.textDim))
            }
            .buttonStyle(.plain)
            .disabled(!selectable)

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text(detailLine(item))
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
            }
            Spacer()
            GradePill(grade: item.grade)
            Text(ByteFormat.string(item.sizeBytes))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder — \(item.path)")
            .accessibilityLabel("Reveal in Finder")
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
    @Environment(CleanModel.self) private var model
    @AppStorage(SmartScanner.developerModeKey) private var developerMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("AUTO CLEAN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
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
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.textDim)
                timePreferencePicker
                Spacer()
            }

            Divider().overlay(Halo.surface2)

            HStack(spacing: 24) {
                toggleRow(
                    title: "Auto-clean safe items",
                    subtitle: "due runs stage the safe tier without asking",
                    isOn: Binding(
                        get: { model.schedule.autoCleanSafeTier },
                        set: { model.setAutoClean($0) }
                    ))
                toggleRow(
                    title: "Notify on completion",
                    subtitle: "one notification per run, never a nag",
                    isOn: Binding(
                        get: { model.schedule.notifyOnCompletion },
                        set: { model.setNotify($0) }
                    ))
                toggleRow(
                    title: "Developer Junk Mode",
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
        case .night: return "NIGHT · 3AM"
        case .morning: return "MORNING · 9AM"
        case .anytime: return "ANYTIME"
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
        Button {
            model.runNow()
        } label: {
            HStack(spacing: 6) {
                if model.isRunning {
                    ProgressView().controlSize(.small)
                }
                if !model.isRunning {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(model.isRunning ? "Cleaning…" : "Run Now")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Halo.void)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(
                model.isRunning ? AnyShapeStyle(Halo.textDim) : AnyShapeStyle(Halo.ion),
                in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isRunning)
        .help("Scan and stage every safe-tier item into the Vault now")
    }

    private func scheduleFact(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
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


