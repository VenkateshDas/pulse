import AppKit
import PulseKit
import SwiftUI

/// App Uninstaller (§3.14): drag an app or pick one from the installed list,
/// review confidence-graded leftovers, then remove app + debris in one action.
/// The `.app` goes to the system Trash; ticked leftovers stage to the Vault.
struct UninstallView: View {
    @Environment(UninstallModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.tab {
                    case .uninstall: uninstallTab
                    case .orphans: OrphanScanCard()
                    }
                    if let report = model.report {
                        Text(report)
                            .font(.system(size: 11))
                            .foregroundStyle(Halo.pulseGreen)
                    }
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
            Text("Uninstall")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Halo.textPrimary)
            Text(
                "Remove an app and the debris it leaves behind. Matches are graded by confidence; the app goes to the Trash and every leftover is staged in the Vault — nothing is ever destroyed."
            )
            .font(.system(size: 12))
            .foregroundStyle(Halo.textDim)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(UninstallModel.Tab.allCases) { tab in
                let selected = model.tab == tab
                Button {
                    model.tab = tab
                } label: {
                    Text(tab.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(selected ? Halo.void : Halo.textDim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            selected ? AnyShapeStyle(Halo.ion) : AnyShapeStyle(Halo.surface2),
                            in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var uninstallTab: some View {
        if model.result != nil {
            UninstallResultCard()
        } else if model.plan != nil {
            UninstallPlanCard()
        } else {
            DropZoneCard()
            InstalledAppsCard()
        }
    }
}

// MARK: - Drop zone

struct DropZoneCard: View {
    @Environment(UninstallModel.self) private var model
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 30))
                .foregroundStyle(targeted ? Halo.ion : Halo.textDim)
            Text(model.isScanning ? "Scanning for leftovers…" : "Drag an app here to uninstall")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            Text("Drop any .app from Finder or the Dock — Pulse finds its leftover files.")
                .font(.system(size: 11))
                .foregroundStyle(Halo.textDim)
            if model.isScanning {
                ProgressView().controlSize(.small).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    targeted ? Halo.ion : Halo.surface2,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        // SwiftUI's Transferable-based drop runs its action on the main actor
        // and hands back URLs directly — no NSItemProvider concurrency dance.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.handleDrop(url)
            return true
        } isTargeted: { targeted = $0 }
    }
}

// MARK: - Installed apps list

struct InstalledAppsCard: View {
    @Environment(UninstallModel.self) private var model
    @State private var query = ""

    private var filtered: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.installedApps }
        return model.installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("INSTALLED APPS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                    TextField("Filter…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.textPrimary)
                        .frame(width: 140)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Halo.surface2, in: Capsule())
            }
            if model.isLoadingApps && model.installedApps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading /Applications…")
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else if filtered.isEmpty {
                Text("No apps match.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(filtered) { app in
                    appRow(app)
                }
            }
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func appRow(_ app: InstalledApp) -> some View {
        Button {
            model.selectApp(app)
        } label: {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                    Text(subtitle(app))
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                        .lineLimit(1)
                }
                Spacer()
                Text(ByteFormat.string(app.sizeBytes))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
                    .frame(width: 76, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ app: InstalledApp) -> String {
        var parts = ["v\(app.version)", app.bundleID]
        if let days = app.lastUsedDays {
            parts.append(days == 0 ? "used today" : "used \(days)d ago")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Plan detail

struct UninstallPlanCard: View {
    @Environment(UninstallModel.self) private var model

    var body: some View {
        if let plan = model.plan {
            VStack(alignment: .leading, spacing: 12) {
                planHeader(plan)
                appRow(plan.app)
                if plan.leftovers.isEmpty {
                    Text("No leftovers found — removing the app alone fully uninstalls it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                        .padding(.vertical, 8)
                } else {
                    ForEach(SafetyGrade.allCases, id: \.self) { grade in
                        section(grade, items: plan.leftovers.filter { $0.grade == grade })
                    }
                }
                if model.isPlanAppRunning {
                    Label("Quit \(plan.app.name) before uninstalling — it's running.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Halo.amber)
                }
                uninstallButton(plan)
            }
            .padding(16)
            .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func planHeader(_ plan: UninstallModel.Plan) -> some View {
        HStack(spacing: 10) {
            Button {
                model.clearPlan()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.ion)
            }
            .buttonStyle(.plain)
            .help("Back to the app list")
            Text("UNINSTALL PLAN")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Halo.textDim)
            Spacer()
            Text("\(plan.leftovers.count) leftover\(plan.leftovers.count == 1 ? "" : "s") found")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
    }

    /// The app bundle row — always removed (→ Trash), shown SAFE and locked on.
    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 13))
                .foregroundStyle(Halo.pulseGreen)
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text("the app itself → moved to Trash (Finder “Put Back” restores it)")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
            }
            Spacer()
            GradePill(grade: .safe)
            Text(ByteFormat.string(app.sizeBytes))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Halo.pulseGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                ForEach(items) { item in
                    leftoverRow(item)
                }
            }
        }
    }

    private func leftoverRow(_ item: CleanItem) -> some View {
        let selected = model.selection.contains(item.id)
        let selectable = item.grade != .review
        return HStack(spacing: 10) {
            Button {
                model.toggle(item)
            } label: {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        !selectable ? Halo.textDim.opacity(0.4)
                            : (selected ? Halo.pulseGreen : Halo.textDim))
            }
            .buttonStyle(.plain)
            .disabled(!selectable)
            .help(
                selectable
                    ? "" : "REVIEW matches are never bulk-selected — open in Finder and decide yourself")

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text("\(item.category) · \(item.detail)")
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

    private func uninstallButton(_ plan: UninstallModel.Plan) -> some View {
        Button {
            model.uninstall()
        } label: {
            HStack(spacing: 6) {
                if model.isUninstalling { ProgressView().controlSize(.small) }
                Text(buttonLabel(plan))
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Halo.void)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                model.isUninstalling || model.isPlanAppRunning
                    ? AnyShapeStyle(Halo.textDim) : AnyShapeStyle(Halo.flare),
                in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isUninstalling || model.isPlanAppRunning)
        .help("Move the app to Trash and stage every ticked leftover into the Vault")
    }

    private func buttonLabel(_ plan: UninstallModel.Plan) -> String {
        if model.isUninstalling { return "Uninstalling…" }
        let count = model.selectedLeftovers.count
        let total = ByteFormat.string(model.totalRemovalBytes)
        return "Uninstall \(plan.app.name) + \(count) leftover\(count == 1 ? "" : "s") (\(total))"
    }

    private func sectionNote(_ grade: SafetyGrade) -> String {
        switch grade {
        case .safe: "exact bundle-ID match — pre-selected"
        case .careful: "vendor or name match — tick to include"
        case .review: "weak name match — open in Finder, never bulk-removed"
        }
    }
}

// MARK: - Result receipt

/// The "Verify" beat: a post-uninstall receipt confirming exactly what was
/// removed. Every row reflects reality — the app's real `recycle` result and
/// the Vault session's actual contents.
struct UninstallResultCard: View {
    @Environment(UninstallModel.self) private var model

    var body: some View {
        if let result = model.result {
            VStack(alignment: .leading, spacing: 14) {
                successHeader(result)
                Divider().overlay(Halo.surface2)
                appRow(result)
                if !result.stagedItems.isEmpty {
                    stagedSection(result)
                }
                failedSection(result)
                notes(result)
                actions(result)
            }
            .padding(16)
            .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Halo.pulseGreen.opacity(0.35), lineWidth: 1))
        }
    }

    private func successHeader(_ result: UninstallModel.UninstallResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.appTrashed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(result.appTrashed ? Halo.pulseGreen : Halo.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.appTrashed ? "\(result.appName) uninstalled" : "\(result.appName) — partly removed")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text(headline(result))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer()
        }
    }

    private func headline(_ result: UninstallModel.UninstallResult) -> String {
        let count = result.stagedCount + (result.appTrashed ? 1 : 0)
        return "\(count) item\(count == 1 ? "" : "s") removed · \(ByteFormat.string(result.stagedBytes)) staged in Vault"
    }

    private func appRow(_ result: UninstallModel.UninstallResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.appTrashed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(result.appTrashed ? Halo.pulseGreen : Halo.flare)
            Image(nsImage: NSWorkspace.shared.icon(forFile: result.appBundlePath))
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(
                    result.appTrashed
                        ? "moved to Trash · Finder “Put Back” restores it"
                        : "couldn't be moved to Trash — it may need Full Disk Access"
                )
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func stagedSection(_ result: UninstallModel.UninstallResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("STAGED IN VAULT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Halo.pulseGreen)
                Text("exactly what was removed — restorable for 7 days")
                    .font(.system(size: 9))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text(ByteFormat.string(result.stagedBytes))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
            .padding(.top, 2)
            ForEach(result.stagedItems, id: \.originalPath) { item in
                stagedRow(item)
            }
        }
    }

    @ViewBuilder
    private func failedSection(_ result: UninstallModel.UninstallResult) -> some View {
        if !result.failedItems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("PENDING — NEEDS FULL DISK ACCESS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Halo.amber)
                    Spacer()
                }
                .padding(.top, 2)
                ForEach(result.failedItems, id: \.path) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Halo.amber)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Halo.textPrimary)
                                .lineLimit(1)
                            Text(item.path)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Halo.textDim)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(ByteFormat.string(item.sizeBytes))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Halo.textDim)
                            .frame(width: 76, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Halo.amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func fdaMessage(_ result: UninstallModel.UninstallResult) -> String {
        switch (result.appTrashed, result.failedItems.isEmpty) {
        case (false, false):
            return "\(result.appName) and \(result.failedCount) leftover\(result.failedCount == 1 ? "" : "s") couldn't be moved — Pulse needs Full Disk Access."
        case (false, true):
            return "\(result.appName) couldn't be moved to Trash — Pulse needs Full Disk Access."
        default:
            return "\(result.failedCount) leftover\(result.failedCount == 1 ? "" : "s") couldn't be moved — Pulse needs Full Disk Access."
        }
    }

    private func stagedRow(_ item: VaultItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: 10))
                .foregroundStyle(Halo.pulseGreen)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text(item.originalPath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(item.sizeBytes))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func notes(_ result: UninstallModel.UninstallResult) -> some View {
        if result.needsAttention {
            VStack(alignment: .leading, spacing: 4) {
                Label(fdaMessage(result), systemImage: "lock.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Halo.amber)
                Text(
                    "Grant Pulse Full Disk Access, then Retry. In Settings, toggle Pulse on under Full Disk Access (add it with “+” if it isn’t listed)."
                )
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
            }
        }
        if result.reviewLeftCount > 0 {
            Label(
                "\(result.reviewLeftCount) REVIEW match\(result.reviewLeftCount == 1 ? "" : "es") left untouched — open the app again to inspect them in Finder.",
                systemImage: "eye"
            )
            .font(.system(size: 11))
            .foregroundStyle(Halo.textDim)
        }
        if result.stagedItems.isEmpty && result.failedCount == 0 {
            Text("No leftovers were staged — removing the app fully uninstalled it.")
                .font(.system(size: 11))
                .foregroundStyle(Halo.textDim)
        }
    }

    private func actions(_ result: UninstallModel.UninstallResult) -> some View {
        HStack(spacing: 10) {
            if result.needsAttention {
                Button {
                    model.openFullDiskAccessSettings()
                } label: {
                    Text("Grant Full Disk Access")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Halo.void)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Halo.amber, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Open System Settings → Privacy & Security → Full Disk Access")
                Button {
                    model.retryUninstall()
                } label: {
                    HStack(spacing: 6) {
                        if model.isUninstalling { ProgressView().controlSize(.small) }
                        Text(model.isUninstalling ? "Retrying…" : "↻ Retry")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Halo.ion)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Halo.ion.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isUninstalling)
                .help("Re-attempt the parts that failed")
            } else if !result.sessionIDs.isEmpty, !result.stagedItems.isEmpty {
                Button {
                    model.restoreLastUninstall()
                } label: {
                    HStack(spacing: 6) {
                        if model.isRestoringResult { ProgressView().controlSize(.small) }
                        Text(model.isRestoringResult ? "Restoring…" : "↺ Restore everything")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Halo.pulseGreen)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Halo.pulseGreen.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isRestoringResult)
                .help("Pull every staged leftover back to its original location")
            }
            Spacer()
            Button {
                model.dismissResult()
            } label: {
                Text("Done")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Halo.void)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Halo.ion, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Dismiss — back to the app list to uninstall another")
        }
    }
}

// MARK: - Orphan scan

struct OrphanScanCard: View {
    @Environment(UninstallModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("ORPHANED FILES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("residue whose owning app is no longer installed")
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Button(model.hasScannedOrphans ? "Rescan" : "Scan") { model.scanOrphans() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.ion)
                    .disabled(model.isScanningOrphans)
            }

            if model.isScanningOrphans {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning residue locations…")
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else if !model.hasScannedOrphans {
                Text("Scan to find leftover files from apps you've already deleted.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else if model.orphans.isEmpty {
                Text("No orphaned files — every residue folder maps to an installed app.")
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.pulseGreen)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(model.orphans) { item in
                    orphanRow(item)
                }
                removeButton
            }
        }
        .padding(16)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func orphanRow(_ item: CleanItem) -> some View {
        let selected = model.orphanSelection.contains(item.id)
        return HStack(spacing: 10) {
            Button {
                model.toggleOrphan(item)
            } label: {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Halo.pulseGreen : Halo.textDim)
            }
            .buttonStyle(.plain)

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text("\(item.category) · \(item.detail)")
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

    private var removeButton: some View {
        Button {
            model.removeOrphans()
        } label: {
            HStack(spacing: 6) {
                if model.isRemovingOrphans { ProgressView().controlSize(.small) }
                Text(removeLabel)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Halo.void)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                model.orphanSelection.isEmpty || model.isRemovingOrphans
                    ? AnyShapeStyle(Halo.textDim) : AnyShapeStyle(Halo.pulseGreen),
                in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.orphanSelection.isEmpty || model.isRemovingOrphans)
        .help("Stage every selected orphan into the Vault — restore anytime for 7 days")
    }

    private var removeLabel: String {
        if model.isRemovingOrphans { return "Removing…" }
        let count = model.orphanSelection.count
        return "Remove \(count) orphan\(count == 1 ? "" : "s") (\(ByteFormat.string(model.selectedOrphanBytes)))"
    }
}
