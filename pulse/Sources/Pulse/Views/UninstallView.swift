import AppKit
import PulseKit
import SwiftUI

/// App Uninstaller (§3.14): drag an app or pick one from the installed list,
/// review confidence-graded leftovers, then remove app + debris in one action.
/// The `.app` and every ticked leftover go to the system Trash.
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
                        FeedbackBadge(message: report)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .scrollIndicators(.automatic)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear { model.appeared() }
    }

    private var header: some View {
        PageHeader(
            "Apps",
            subtitle:
                "Choose an app, review its related files, then move selected items to Trash. They still use storage until Trash is emptied."
        ) {
            RefreshButton(help: "Reload installed apps", disabled: model.isLoadingApps) {
                model.loadInstalledApps()
            }
        }
    }

    private var tabBar: some View {
        @Bindable var model = model
        return SegmentPicker(
            options: UninstallModel.Tab.allCases.map { ($0, $0 == .uninstall ? "Installed apps" : "Leftover files") },
            selection: $model.tab)
    }

    @ViewBuilder
    private var uninstallTab: some View {
        if model.result != nil {
            UninstallResultCard()
        } else if model.plan != nil {
            UninstallPlanCard()
        } else {
            if model.isScanning {
                ProgressView("Finding related files…").padding()
            }
            InstalledAppsCard()
            DisclosureGroup("Choose an app from Finder") { DropZoneCard() }
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
                .font(Halo.font(size: 30))
                .foregroundStyle(targeted ? Halo.ion : Halo.textDim)
            Text(model.isScanning ? "Scanning for leftovers…" : "Drag an app here to review")
                .font(Halo.font(size: 13, weight: .semibold))
                .foregroundStyle(Halo.textPrimary)
            Text("Drop any .app from Finder or the Dock — Pulse checks common locations for related files.")
                .font(Halo.font(size: 11))
                .foregroundStyle(Halo.textDim)
            if model.isScanning {
                ProgressView().controlSize(.small).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
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
    @State private var hoveredPath: String?

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
                Text("Installed apps")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.textDim)
                    TextField("Search apps", text: $query)
                        .accessibilityLabel("Search installed apps")
                        .textFieldStyle(.roundedBorder)
                        .font(Halo.font(size: 11))
                        .foregroundStyle(Halo.textPrimary)
                        .frame(minWidth: 140, idealWidth: 210, maxWidth: 260)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            }
            if model.isLoadingApps && model.installedApps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading /Applications…")
                        .font(Halo.font(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else if filtered.isEmpty {
                Text(query.isEmpty ? "No removable apps found in the checked locations." : "No apps match. Try another name or clear the search.")
                    .font(Halo.font(size: 12))
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
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        Button {
            model.selectApp(app)
        } label: {
            HStack(spacing: 12) {
                Image(nsImage: model.icon(for: app.path))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(Halo.font(size: 13, weight: .semibold))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                    Text(subtitle(app))
                        .font(Halo.font(size: 10))
                        .foregroundStyle(Halo.textDim)
                        .lineLimit(1)
                }
                Spacer()
                // Size is computed lazily on selection, so the list omits it
                // (0 = not yet computed) to keep the list load fast.
                if app.sizeBytes > 0 {
                    Text(ByteFormat.string(app.sizeBytes))
                        .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Halo.textPrimary)
                        .frame(width: 76, alignment: .trailing)
                }
                Image(systemName: "chevron.right")
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Halo.surface2.opacity(hoveredPath == app.path ? 0.75 : 0.4),
                in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredPath = $0 ? app.path : nil }
        .disabled(model.isScanning || model.isUninstalling)
        .accessibilityHint("Review related files before removal")
    }

    private func subtitle(_ app: InstalledApp) -> String {
        var parts = ["Version \(app.version)"]
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
                    Text("No related files found in the checked locations. Files in other locations may remain.")
                        .font(Halo.font(size: 12))
                        .foregroundStyle(Halo.textDim)
                        .padding(.vertical, 8)
                } else {
                    ForEach(SafetyGrade.allCases, id: \.self) { grade in
                        section(grade, items: plan.leftovers.filter { $0.grade == grade })
                    }
                }
                if model.isPlanAppRunning {
                    Label("Quit \(plan.app.name) before uninstalling — it's running.", systemImage: "exclamationmark.triangle.fill")
                        .font(Halo.font(size: 11, weight: .semibold))
                        .foregroundStyle(Halo.amber)
                }
                uninstallButton(plan)
            }
            .padding(16)
            .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
        }
    }

    private func planHeader(_ plan: UninstallModel.Plan) -> some View {
        HStack(spacing: 10) {
            Button {
                model.clearPlan()
            } label: {
                Image(systemName: "chevron.left")
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.ion)
            }
            .buttonStyle(.plain)
            .help("Back to the app list")
            .accessibilityLabel("Back to installed apps")
            .disabled(model.isUninstalling)
            Text("Review removal")
                .font(Halo.font(size: 10, weight: .semibold))
                .foregroundStyle(Halo.textDim)
            Spacer()
            Text("\(plan.leftovers.count) leftover\(plan.leftovers.count == 1 ? "" : "s") found")
                .font(Halo.font(size: 10, design: .monospaced))
                .foregroundStyle(Halo.textDim)
        }
    }

    /// The app bundle row — always removed (→ Trash), shown SAFE and locked on.
    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.square.fill")
                .font(Halo.font(size: 13))
                .foregroundStyle(Halo.pulseGreen)
            Image(nsImage: model.icon(for: app.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text("Included in removal. Restore from Trash before emptying it.")
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(ByteFormat.string(app.sizeBytes))
                .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
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
                    Text(grade == .safe ? "Matched to this app" : grade == .careful ? "Check before selecting" : "Inspect in Finder")
                        .font(Halo.font(size: 9, weight: .bold))
                        .foregroundStyle(gradeColor(grade))
                    Text(sectionNote(grade))
                        .font(Halo.font(size: 9))
                        .foregroundStyle(Halo.textDim)
                    Spacer()
                    Text(ByteFormat.string(items.reduce(0) { $0 + $1.sizeBytes }))
                        .font(Halo.font(size: 9, design: .monospaced))
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
            Toggle("Select \(item.label), \(item.path)", isOn: Binding(
                get: { selected }, set: { _ in model.toggle(item) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!selectable || model.isUninstalling)
            .help(selectable ? item.path : "Uncertain matches must be reviewed individually in Finder")

            Image(nsImage: model.icon(for: item.path))
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text("\(item.category) · \(item.detail)")
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            GradePill(grade: item.grade)
            Text(ByteFormat.string(item.sizeBytes))
                .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
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
        .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func uninstallButton(_ plan: UninstallModel.Plan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PermissionHelp(permission: .appManagement)
            Text("Related files can contain preferences or documents. Leave anything you want to keep unselected. Restore from Trash before emptying it.")
                .font(Halo.font(size: 13)).foregroundStyle(Halo.textSecondary)
            Button(role: .destructive) { model.uninstall() } label: {
                Label(model.isUninstalling ? "Moving selected items…" : "Move \(plan.app.name) and \(model.selectedLeftovers.count) related files to Trash",
                      systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Halo.critical)
            .foregroundStyle(Halo.onAccent)
            .disabled(model.isUninstalling || model.isPlanAppRunning)
        }
    }

    private func sectionNote(_ grade: SafetyGrade) -> String {
        switch grade {
        case .safe: "matched app identifier — selected initially"
        case .careful: "shared publisher or name — select only if no longer needed"
        case .review: "uncertain match — not included in this removal"
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
                if !result.trashedLeftovers.isEmpty {
                    stagedSection(result)
                }
                failedSection(result)
                notes(result)
                actions(result)
            }
            .padding(16)
            .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Halo.pulseGreen.opacity(0.35), lineWidth: 1))
        }
    }

    private func successHeader(_ result: UninstallModel.UninstallResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.appTrashed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(Halo.font(size: 22))
                .foregroundStyle(result.appTrashed ? Halo.pulseGreen : Halo.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.appTrashed && !result.needsAttention ? "\(result.appName) moved to Trash" : "\(result.appName) — partly removed")
                    .font(Halo.font(size: 16, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text(headline(result))
                    .font(Halo.font(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer()
        }
    }

    private func headline(_ result: UninstallModel.UninstallResult) -> String {
        let count = result.trashedCount + (result.appTrashed ? 1 : 0)
        return "\(count) item\(count == 1 ? "" : "s") removed · \(ByteFormat.string(result.trashedBytes)) moved to Trash"
    }

    private func appRow(_ result: UninstallModel.UninstallResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.appTrashed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(Halo.font(size: 13))
                .foregroundStyle(result.appTrashed ? Halo.pulseGreen : Halo.flare)
            Image(nsImage: model.icon(for: result.appBundlePath))
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.appName)
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(
                    result.appTrashed
                        ? "moved to Trash · Finder “Put Back” restores it"
                        : "couldn't be moved to Trash — Retry and approve the Finder prompt"
                )
                .font(Halo.font(size: 10))
                .foregroundStyle(Halo.textDim)
                .fixedSize(horizontal: false, vertical: true)
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
                Text("MOVED TO TRASH")
                    .font(Halo.font(size: 9, weight: .bold))
                    .foregroundStyle(Halo.pulseGreen)
                Text("moved to Trash — empty Trash to free space")
                    .font(Halo.font(size: 9))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Text(ByteFormat.string(result.trashedBytes))
                    .font(Halo.font(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
            }
            .padding(.top, 2)
            ForEach(result.trashedLeftovers, id: \.path) { item in
                trashedRow(item)
            }
        }
    }

    @ViewBuilder
    private func failedSection(_ result: UninstallModel.UninstallResult) -> some View {
        if !result.failedItems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Items that could not be moved")
                        .font(Halo.font(size: 9, weight: .bold))
                        .foregroundStyle(Halo.amber)
                    Spacer()
                }
                .padding(.top, 2)
                ForEach(result.failedItems, id: \.path) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(Halo.font(size: 10))
                            .foregroundStyle(Halo.amber)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(Halo.font(size: 12, weight: .semibold))
                                .foregroundStyle(Halo.textPrimary)
                                .lineLimit(1)
                            Text(item.path)
                                .font(Halo.font(size: 9, design: .monospaced))
                                .foregroundStyle(Halo.textDim)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(ByteFormat.string(item.sizeBytes))
                            .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
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


    private func trashedRow(_ item: UninstallModel.PendingItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(Halo.font(size: 10))
                .foregroundStyle(Halo.pulseGreen)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text(item.path)
                    .font(Halo.font(size: 9, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(item.sizeBytes))
                .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func notes(_ result: UninstallModel.UninstallResult) -> some View {
        // App-bundle failure is an App Management / Finder-consent issue —
        // NOT Full Disk Access. Route it to its real remedy.
        if result.appNeedsAttention {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "\(result.appName) couldn't be moved to the Trash.",
                    systemImage: "lock.shield"
                )
                .font(Halo.font(size: 11, weight: .semibold))
                .foregroundStyle(Halo.amber)
                Text(
                    "Removing another app needs permission. Click Retry and approve the “control Finder” prompt (and the admin password, if asked) — same as dragging the app to the Trash by hand."
                )
                .font(Halo.font(size: 10))
                .foregroundStyle(Halo.textDim)
            }
        }
        // Leftover-staging failure is the genuine Full Disk Access case.
        if result.leftoversNeedAttention {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "\(result.failedCount) related file\(result.failedCount == 1 ? "" : "s") couldn't be moved. Check file permissions and Full Disk Access.",
                    systemImage: "externaldrive.badge.xmark"
                )
                .font(Halo.font(size: 11, weight: .semibold))
                .foregroundStyle(Halo.amber)
                Text(
                    "Grant Pulse Full Disk Access, then Retry. In Settings, toggle Pulse on under Full Disk Access (add it with “+” if it isn’t listed)."
                )
                .font(Halo.font(size: 10))
                .foregroundStyle(Halo.textDim)
            }
        }
        if result.reviewLeftCount > 0 {
            Label(
                "\(result.reviewLeftCount) REVIEW match\(result.reviewLeftCount == 1 ? "" : "es") left untouched — open the app again to inspect them in Finder.",
                systemImage: "eye"
            )
            .font(Halo.font(size: 11))
            .foregroundStyle(Halo.textDim)
        }
        if result.trashedLeftovers.isEmpty && result.failedCount == 0 {
            Text("No related files were removed. Other files may remain outside the checked locations.")
                .font(Halo.font(size: 11))
                .foregroundStyle(Halo.textDim)
        }
    }

    private func actions(_ result: UninstallModel.UninstallResult) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { resultActions(result) }
            VStack(alignment: .leading) { resultActions(result) }
        }
    }

    @ViewBuilder private func resultActions(_ result: UninstallModel.UninstallResult) -> some View {
        if result.leftoversNeedAttention {
            Button("Open Full Disk Access settings") { model.openFullDiskAccessSettings() }
                .buttonStyle(.bordered)
        }
        if result.needsAttention {
            Button(model.isUninstalling ? "Retrying…" : "Retry failed items") { model.retryUninstall() }
                .buttonStyle(.bordered).disabled(model.isUninstalling)
        }
        Button("View Trash") { PulseNavigation.open(.storage, diskTab: 2) }.buttonStyle(.bordered)
        Button("Done") { model.dismissResult() }
            .buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent)
            .disabled(model.isUninstalling)
    }

}

// MARK: - Orphan scan

struct OrphanScanCard: View {
    @State private var reviewingRemoval = false
    @Environment(UninstallModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Leftover files")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Text("possible files from apps you removed")
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
                Spacer()
                Button(model.hasScannedOrphans ? "Rescan" : "Scan") { model.scanOrphans() }
                    .buttonStyle(.plain)
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.ion)
                    .disabled(model.isScanningOrphans)
            }

            if model.isScanningOrphans {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning residue locations…")
                        .font(Halo.font(size: 12))
                        .foregroundStyle(Halo.textDim)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else if !model.hasScannedOrphans {
                Text("Scan to find leftover files from apps you've already deleted.")
                    .font(Halo.font(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else if model.orphans.isEmpty {
                Text("No unmatched files found in the checked locations.")
                    .font(Halo.font(size: 12))
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
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private func orphanRow(_ item: CleanItem) -> some View {
        let selected = model.orphanSelection.contains(item.id)
        return HStack(spacing: 10) {
            Toggle("Select \(item.label), \(item.path)", isOn: Binding(
                get: { selected }, set: { _ in model.toggleOrphan(item) }
            )).labelsHidden().toggleStyle(.checkbox)
                .disabled(model.isRemovingOrphans)

            Image(nsImage: model.icon(for: item.path))
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(Halo.font(size: 12, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                    .lineLimit(1)
                Text("\(item.category) · \(item.detail)")
                    .font(Halo.font(size: 10))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            GradePill(grade: item.grade)
            Text(ByteFormat.string(item.sizeBytes))
                .font(Halo.font(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 76, alignment: .trailing)
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
        .background(Halo.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var removeButton: some View {
        Button { reviewingRemoval = true } label: {
            Label(removeLabel, systemImage: "trash")
        }
        .buttonStyle(.borderedProminent).foregroundStyle(Halo.onAccent)
        .disabled(model.orphanSelection.isEmpty || model.isRemovingOrphans)
        .confirmationDialog("Move selected leftover files to Trash?", isPresented: $reviewingRemoval, titleVisibility: .visible) {
            Button("Move selected files to Trash", role: .destructive) { model.removeOrphans() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These files could not be matched to an installed app. They may still be useful. Restore from Trash before emptying it; moving files does not free storage yet.")
        }
    }

    private var removeLabel: String {
        if model.isRemovingOrphans { return "Removing…" }
        let count = model.orphanSelection.count
        return "Review \(count) leftover\(count == 1 ? "" : "s") (\(ByteFormat.string(model.selectedOrphanBytes)))"
    }
}
