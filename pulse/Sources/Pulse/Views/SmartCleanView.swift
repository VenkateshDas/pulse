import AppKit
import PulseKit
import SwiftUI

/// Dedicated Smart Clean review flow (spec §3.4): scan → review every item by
/// safety grade → select → clean → verify. SAFE rows are pre-ticked, CAREFUL
/// need an explicit tick, REVIEW can never be bulk-selected (Finder-first).
/// Backed by StorageModel's evidence-based scan; staging goes to the Vault.
struct SmartCleanCard: View {
    @Environment(StorageModel.self) private var storage
    @Environment(DashboardModel.self) private var dashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            forecast
            if storage.scanState == .scanning && storage.scan == nil {
                scanning
            } else if let scan = storage.scan {
                ForEach(SafetyGrade.allCases, id: \.self) { grade in
                    section(grade, items: scan.items.filter { $0.grade == grade })
                }
            } else {
                Text("No scan yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
            }
            if let report = storage.cleanReport {
                Text(report)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.pulseGreen)
            }
            cleanButton
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { storage.appeared() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("SMART CLEAN")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Halo.textDim)
            Text("review every item before it moves — SAFE is pre-selected, CAREFUL needs a tick, REVIEW is Finder-only")
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
            Spacer()
            Button("Rescan") { storage.runScan() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Halo.ion)
                .disabled(storage.scanState == .scanning)
        }
    }

    /// "At this rate, full in N days" from the weekly growth trend.
    @ViewBuilder
    private var forecast: some View {
        if let weekly = dashboard.snapshot?.diskWeeklyGrowthBytes, weekly > 0,
            let free = dashboard.snapshot?.diskFreeBytes
        {
            let perDay = Double(weekly) / 7
            let days = perDay > 0 ? Int(Double(free) / perDay) : 0
            if days > 0 {
                Text("At this rate, your startup disk fills in ~\(days) days.")
                    .font(.system(size: 11))
                    .foregroundStyle(days < 30 ? Halo.amber : Halo.textDim)
            }
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

    @ViewBuilder
    private func section(_ grade: SafetyGrade, items: [CleanItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(grade.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(gradeColor(grade))
                    Text(sectionNote(grade))
                        .font(.system(size: 9))
                        .foregroundStyle(Halo.textDim)
                    Spacer()
                    Text(ByteFormat.string(items.reduce(0) { $0 + $1.sizeBytes }))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.top, 6)
                ForEach(items.prefix(grade == .review ? 8 : 20)) { item in
                    row(item)
                }
            }
        }
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
            .help(selectable ? "" : "REVIEW items are never bulk-selected — open in Finder and decide yourself")

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

    private var cleanButton: some View {
        Button {
            storage.cleanSelected()
        } label: {
            HStack(spacing: 6) {
                if storage.isCleaning { ProgressView().controlSize(.small) }
                Text(cleanLabel)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Halo.void)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                storage.selection.isEmpty || storage.isCleaning
                    ? AnyShapeStyle(Halo.textDim) : AnyShapeStyle(Halo.pulseGreen),
                in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(storage.selection.isEmpty || storage.isCleaning)
        .help("Stage every selected item into the Vault — freed space is verified against the disk")
    }

    private var cleanLabel: String {
        storage.isCleaning
            ? "Cleaning…"
            : "Clean \(storage.selection.count) item\(storage.selection.count == 1 ? "" : "s") (\(ByteFormat.string(storage.selectedBytes)))"
    }

    private func detailLine(_ item: CleanItem) -> String {
        if let idle = item.idleDays {
            return "\(item.detail) · idle \(idle)d"
        }
        return item.detail
    }

    private func sectionNote(_ grade: SafetyGrade) -> String {
        switch grade {
        case .safe: "regenerates automatically — pre-selected"
        case .careful: "tick individually to include"
        case .review: "real data — open in Finder, never bulk-clean"
        }
    }

    private func gradeColor(_ grade: SafetyGrade) -> Color {
        switch grade {
        case .safe: Halo.pulseGreen
        case .careful: Halo.amber
        case .review: Halo.flare
        }
    }
}
