import AppKit
import PulseKit
import SwiftUI

/// Reclaim tab: one flat list of safe + careful items across the disk, bulk action.
struct CleanView: View {
    @Environment(StorageModel.self) private var storage

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
                            LazyVStack(spacing: 4) {
                                ForEach(items) { item in
                                    row(item)
                                }
                            }
                        }
                    } else {
                        Text("No scan yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(Halo.textDim)
                    }
                    AutoCleanCard()
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            
            CleanFooter()
        }
        .padding(Halo.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .onAppear { storage.appeared() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("RECLAIM")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Halo.textDim)
            Text("flat list of everything safe to remove")
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
            Spacer()
            Button("Select All Safe") {
                storage.selectAllSafe()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Halo.ion)
            .disabled(storage.scanState == .scanning)
        }
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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
                Text(report)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.pulseGreen)
            }
        }
        .padding(Halo.Space.lg)
        .background { RoundedRectangle(cornerRadius: Halo.Radius.large, style: .continuous).fill(Halo.surface1).shadow(color: Halo.Shadow.cardColor, radius: Halo.Shadow.cardRadius, y: Halo.Shadow.cardY) } .overlay { RoundedRectangle(cornerRadius: Halo.Radius.large, style: .continuous).strokeBorder(Halo.borderSubtle, lineWidth: 0.5) }
    }

    private var frequencyPicker: some View {
        HStack(spacing: 4) {
            ForEach(CleanSchedule.Frequency.allCases, id: \.self) { frequency in
                let selected = model.schedule.frequency == frequency
                Button {
                    model.setFrequency(frequency)
                } label: {
                    Text("⚡ \(frequency.rawValue.uppercased())")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(selected ? Halo.void : Halo.textDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selected ? AnyShapeStyle(Halo.ion) : AnyShapeStyle(Halo.surface2),
                            in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Run the scheduled clean \(frequency.rawValue)")
            }
        }
    }

    private var timePreferencePicker: some View {
        HStack(spacing: 4) {
            ForEach(CleanSchedule.TimePreference.allCases, id: \.self) { preference in
                let selected = model.schedule.timePreference == preference
                Button {
                    model.setTimePreference(preference)
                } label: {
                    Text(Self.timeLabel(preference))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(selected ? Halo.void : Halo.textDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selected ? AnyShapeStyle(Halo.volt) : AnyShapeStyle(Halo.surface2),
                            in: Capsule())
                }
                .buttonStyle(.plain)
                .help(Self.timeHelp(preference))
            }
        }
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
                Text(model.isRunning ? "Cleaning…" : "⚡ Run Now")
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


