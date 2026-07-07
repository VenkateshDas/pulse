import SwiftUI

/// ⌘K command palette: fuzzy-searchable registry of navigation targets and
/// quick actions. The power-user / discovery surface the spec calls for.
struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var selection: SidebarItem
    @Environment(CleanModel.self) private var clean
    @Environment(StorageModel.self) private var storage
    @Environment(HealthModel.self) private var health
    @Environment(UninstallModel.self) private var uninstall

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    /// One palette entry.
    struct Command: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let symbol: String
        let run: () -> Void
    }

    private var commands: [Command] {
        var list: [Command] = SidebarItem.allCases.map { item in
            Command(
                title: "Go to \(item.rawValue)",
                subtitle: "Open the \(item.rawValue) section",
                symbol: item.symbol
            ) { selection = item }
        }
        list.append(
            Command(
                title: "Run Quick Clean", subtitle: "Move the safe tier to Trash",
                symbol: "sparkles"
            ) {
                storage.pendingDiskTab = 1  // land on Reclaim, where the result shows
                selection = .storage
                clean.runNow()
            })
        list.append(
            Command(
                title: "Empty Trash", subtitle: "Review and empty the macOS Trash",
                symbol: "trash"
            ) {
                // Destructive — open the Trash tab so emptying goes through
                // its confirmation instead of firing straight from the palette.
                storage.pendingDiskTab = 2
                selection = .storage
            })
        list.append(
            Command(
                title: "Scan Orphaned Files",
                subtitle: "Find leftover files from apps you've already deleted",
                symbol: "trash.slash"
            ) {
                selection = .uninstall
                uninstall.tab = .orphans
                uninstall.scanOrphans()
            })
        list.append(
            Command(
                title: "Run Benchmark", subtitle: "CPU + disk + memory micro-benchmark",
                symbol: "gauge.with.needle"
            ) { selection = .health; health.runBenchmark() })
        list.append(
            Command(
                title: "Rescan Storage", subtitle: "Re-walk the disk for large + cleanable files",
                symbol: "arrow.clockwise"
            ) { selection = .storage; storage.runScan() })
        list.append(
            Command(
                title: "Storage Timeline", subtitle: "What ate my disk this week — daily usage trend",
                symbol: "chart.xyaxis.line"
            ) { selection = .timeline })
        return list
    }

    private var filtered: [Command] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.subtitle.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Halo.textDim)
                TextField("Search commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Halo.textPrimary)
                    .focused($searchFocused)
                    .onSubmit { runHighlighted() }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                Text("esc")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(14)
            Divider().overlay(Halo.surface2)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                            row(command, active: index == highlighted)
                                .onTapGesture { run(command) }
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 340)
                .onChange(of: highlighted) { _, index in
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .frame(width: 500)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: Halo.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Halo.Radius.xl, style: .continuous).strokeBorder(Halo.borderSubtle, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onAppear { searchFocused = true }
    }

    private func row(_ command: Command, active: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                    .fill((active ? Halo.ion : Halo.textDim).opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: command.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(active ? Halo.ion : Halo.textDim)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Halo.textPrimary)
                Text(command.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(active ? Halo.surface2 : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    /// Moves the keyboard highlight, wrapping at both ends.
    private func move(_ delta: Int) -> KeyPress.Result {
        guard !filtered.isEmpty else { return .ignored }
        highlighted = (highlighted + delta + filtered.count) % filtered.count
        return .handled
    }

    private func runHighlighted() {
        guard filtered.indices.contains(highlighted) else { return }
        run(filtered[highlighted])
    }

    private func run(_ command: Command) {
        command.run()
        isPresented = false
    }
}
