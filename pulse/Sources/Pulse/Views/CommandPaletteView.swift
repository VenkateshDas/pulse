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
            ) { selection = .storage; clean.runNow() })
        list.append(
            Command(
                title: "Empty Trash", subtitle: "Empty the macOS Trash",
                symbol: "trash"
            ) { selection = .storage; storage.emptyTrash() })
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
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Halo.textDim)
                TextField("Search commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Halo.textPrimary)
                    .focused($searchFocused)
                    .onSubmit { runHighlighted() }
                Text("esc")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Halo.textDim)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .padding(.horizontal, Halo.Space.lg)
            .padding(.vertical, Halo.Space.md)

            Divider().overlay(Halo.borderSubtle)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                        row(command, active: index == highlighted)
                            .onTapGesture { run(command) }
                    }
                }
                .padding(Halo.Space.sm)
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 500)
        .background {
            RoundedRectangle(cornerRadius: Halo.Radius.xl, style: .continuous)
                .fill(Halo.surface1)
                .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Halo.Radius.xl, style: .continuous)
                .strokeBorder(Halo.borderSubtle, lineWidth: 0.5)
        }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onAppear { searchFocused = true }
    }

    private func row(_ command: Command, active: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                    .fill(active ? Halo.interactive.opacity(0.12) : Halo.surface2.opacity(0.5))
                    .frame(width: 28, height: 28)
                Image(systemName: command.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? Halo.ion : Halo.textDim)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Halo.textPrimary)
                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Halo.textDim)
            }
            Spacer()
        }
        .padding(.horizontal, Halo.Space.md)
        .padding(.vertical, Halo.Space.sm)
        .background {
            if active {
                RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous)
                    .fill(Halo.surface2.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
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
