import AppKit
import PulseKit
import SwiftUI

/// Clean module (M4): scheduled deep clean. Auto-clean card, run history
/// with one-click restore, and an honest dry-run preview of the next run.
struct CleanView: View {
    @Environment(CleanModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AutoCleanCard()
                    CleanHistoryCard()
                    CleanPreviewCard()
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear { model.appeared() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clean")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Halo.textPrimary)
            Text(
                "Scheduled deep clean of the safe tier — items that regenerate automatically. Every run is staged in the Vault, restorable for 7 days."
            )
            .font(.system(size: 12))
            .foregroundStyle(Halo.textDim)
        }
    }
}

// MARK: - Auto Clean card

struct AutoCleanCard: View {
    @Environment(CleanModel.self) private var model

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
                Spacer()
            }

            if let report = model.report {
                Text(report)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.pulseGreen)
            }
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
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
        let freed = model.history.first(where: {
            abs($0.date.timeIntervalSince(last)) < 1
        })?.bytesFreed
        let ago = Self.relativeText(last)
        guard let freed, freed > 0 else { return ago }
        return "\(ago) · freed \(ByteFormat.string(freed))"
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

// MARK: - History card

struct CleanHistoryCard: View {
    @Environment(CleanModel.self) private var model
    @State private var purgeCandidate: CleanRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("CLEAN HISTORY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("every run links to its Vault session — restore is one click")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                Spacer()
            }
            if model.history.isEmpty {
                Text("No cleans yet — run one above or wait for the schedule.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(model.history.prefix(10)) { record in
                    historyRow(record)
                }
            }
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog(
            "Permanently delete this clean's Vault session?",
            isPresented: Binding(
                get: { purgeCandidate != nil },
                set: { if !$0 { purgeCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(
                "Delete \(ByteFormat.string(purgeCandidate?.bytesFreed ?? 0)) forever",
                role: .destructive
            ) {
                if let record = purgeCandidate { model.purge(record) }
                purgeCandidate = nil
            }
            Button("Cancel", role: .cancel) { purgeCandidate = nil }
        } message: {
            Text(
                "This is irreversible. \(purgeCandidate?.itemsCleaned ?? 0) items will be gone for good."
            )
        }
    }

    private func historyRow(_ record: CleanRecord) -> some View {
        let restorable = model.restorableSessions[record.sessionID] != nil
        return HStack(spacing: 12) {
            Text(Self.dateText(record.date))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 64, alignment: .leading)
            Text(
                record.itemsCleaned > 0
                    ? "\(ByteFormat.string(record.bytesFreed)) · \(record.itemsCleaned) items"
                    : "nothing to clean"
            )
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(record.itemsCleaned > 0 ? Halo.textPrimary : Halo.textDim)
            Spacer()
            if restorable {
                Button("↺ Restore") { model.restore(record) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Halo.pulseGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Halo.pulseGreen.opacity(0.12), in: Capsule())
                Button("Purge") { purgeCandidate = record }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Halo.flare)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Halo.flare.opacity(0.10), in: Capsule())
            } else if record.itemsCleaned > 0 {
                // Post-restart we can't tell restored from expired — say so.
                Text(
                    model.restoredSessionIDs.contains(record.sessionID)
                        ? "↺ restored" : "no longer in Vault"
                )
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(
                    model.restoredSessionIDs.contains(record.sessionID)
                        ? Halo.pulseGreen : Halo.textDim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Halo.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }
}

// MARK: - Preview card

struct CleanPreviewCard: View {
    @Environment(CleanModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("PREVIEW · NEXT SCHEDULED RUN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("dry run — nothing here is touched until the clean runs")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                if !model.preview.isEmpty {
                    Text("● \(ByteFormat.string(model.previewTotalBytes)) RECLAIMABLE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Halo.pulseGreen)
                }
                Button("Refresh") { model.loadPreview(force: true) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.ion)
                    .disabled(model.isPreviewLoading)
            }
            if model.isPreviewLoading && model.preview.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning the safe tier…")
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else if model.preview.isEmpty {
                Text("Safe tier is empty — the next run has nothing to do.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(model.preview.prefix(8)) { item in
                    previewRow(item)
                }
                if model.preview.count > 8 {
                    Text("+ \(model.preview.count - 8) more safe items")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                        .padding(.leading, 12)
                }
            }
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func previewRow(_ item: CleanItem) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Halo.pulseGreen)
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
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
            Text(ByteFormat.string(item.sizeBytes))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: item.path)
                ])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder — \(item.path)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
