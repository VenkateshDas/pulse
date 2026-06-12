import PulseKit
import SwiftUI

/// Monitor module (M5): process list/tree with sort + filter, a detail
/// card for the selected process, and per-interface network throughput.
struct MonitorView: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 16) {
                ProcessListCard()
                ProcessDetailCard()
                    .frame(width: 340)
            }
            .frame(maxHeight: .infinity)
            NetworkCard()
                .frame(height: 190)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear { model.appeared() }
        .onDisappear { model.disappeared() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Monitor")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Halo.textPrimary)
            Text(
                "Every process with CPU, memory, threads and page-fault rates, plus live per-interface network throughput. Per-process network needs private Apple entitlements — Pulse won't pretend otherwise."
            )
            .font(.system(size: 12))
            .foregroundStyle(Halo.textDim)
        }
    }
}

// MARK: - Process list card

private struct ProcessListCard: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("PROCESSES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("\(model.rows.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.ion)
                Spacer()
                modePicker
                sortMenu
            }

            filterField

            columnHeader

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(displayRows) { row in
                        ProcessRow(
                            process: row.process,
                            depth: row.depth,
                            selected: model.selectedPID == row.process.pid
                        ) {
                            model.select(row.process.pid)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Tree rows flattened with depth; a non-empty filter always shows the
    /// flat filtered list — filtering a tree hides matches under collapsed
    /// ancestors, which reads as "missing".
    private var displayRows: [DisplayRow] {
        if model.treeMode, model.filter.trimmingCharacters(in: .whitespaces).isEmpty {
            var rows: [DisplayRow] = []
            func walk(_ node: ProcessNode, depth: Int) {
                rows.append(DisplayRow(process: node.process, depth: depth))
                for child in node.children { walk(child, depth: depth + 1) }
            }
            for root in model.roots { walk(root, depth: 0) }
            return rows
        }
        return model.filteredRows.map { DisplayRow(process: $0, depth: 0) }
    }

    private struct DisplayRow: Identifiable {
        let process: ProcessExtendedSample
        let depth: Int
        var id: Int32 { process.pid }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton("LIST", isTree: false)
            modeButton("TREE", isTree: true)
        }
    }

    private func modeButton(_ title: String, isTree: Bool) -> some View {
        let selected = model.treeMode == isTree
        return Button {
            model.treeMode = isTree
        } label: {
            Text(title)
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
        .help(isTree ? "Group processes under their parent" : "Flat sortable list")
    }

    private var sortMenu: some View {
        @Bindable var model = model
        return HStack(spacing: 4) {
            Menu {
                Picker("Sort by", selection: $model.sortKey) {
                    ForEach(MonitorEngine.SortKey.allCases, id: \.self) { key in
                        Text(Self.sortLabel(key)).tag(key)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(Self.sortLabel(model.sortKey))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundStyle(Halo.textDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Halo.surface2, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort the process list")

            Button {
                model.sortAscending.toggle()
            } label: {
                Image(systemName: model.sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Halo.textDim)
                    .padding(6)
                    .background(Halo.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .help(model.sortAscending ? "Smallest first" : "Largest first")
        }
    }

    static func sortLabel(_ key: MonitorEngine.SortKey) -> String {
        switch key {
        case .cpu: "CPU"
        case .memory: "MEMORY"
        case .threads: "THREADS"
        case .pageFaults: "FAULTS"
        case .name: "NAME"
        case .pid: "PID"
        }
    }

    private var filterField: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Halo.textDim)
            TextField("Filter by name", text: $model.filter)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Halo.textPrimary)
            if !model.filter.isEmpty {
                Button {
                    model.filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 8))
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("NAME")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU").frame(width: 52, alignment: .trailing)
            Text("MEM").frame(width: 60, alignment: .trailing)
            Text("THR").frame(width: 36, alignment: .trailing)
            Text("FLT/S").frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1)
        .foregroundStyle(Halo.textDim)
        .padding(.horizontal, 8)
    }
}

private struct ProcessRow: View {
    let process: ProcessExtendedSample
    let depth: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    if depth > 0 {
                        Text(String(repeating: "  ", count: depth - 1) + "└")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Halo.textDim.opacity(0.6))
                    }
                    Circle()
                        .fill(activityColor)
                        .frame(width: 5, height: 5)
                    Text(process.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Halo.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%5.1f%%", process.cpuPercent))
                    .frame(width: 52, alignment: .trailing)
                Text(ByteFormat.string(process.residentBytes))
                    .frame(width: 60, alignment: .trailing)
                Text("\(process.threadCount)")
                    .frame(width: 36, alignment: .trailing)
                Text(faultText)
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Halo.textDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                selected ? Halo.surface2 : .clear,
                in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Halo.ion)
                        .frame(width: 2, height: 14)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var activityColor: Color {
        switch process.cpuPercent {
        case ..<1: Halo.textDim.opacity(0.4)
        case ..<50: Halo.ion
        case ..<100: Halo.amber
        default: Halo.flare
        }
    }

    private var faultText: String {
        process.pageFaultRate < 0.05 ? "—" : String(format: "%.0f", process.pageFaultRate)
    }
}

// MARK: - Detail card

private struct ProcessDetailCard: View {
    @Environment(MonitorModel.self) private var model
    @State private var confirmQuit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let process = model.selectedProcess {
                detail(process)
            } else {
                placeholder
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(Halo.textDim.opacity(0.5))
            Text("Select a process to inspect it")
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func detail(_ process: ProcessExtendedSample) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(process.name.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Halo.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("PID \(process.pid)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textDim)
            Spacer()
        }

        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading, spacing: 12
        ) {
            fact("CPU", String(format: "%.1f%%", process.cpuPercent), Halo.ion)
            fact("MEMORY", ByteFormat.string(process.residentBytes), Halo.textPrimary)
            fact("VIRTUAL", ByteFormat.string(process.virtualBytes), Halo.textPrimary)
            fact("THREADS", "\(process.threadCount)", Halo.textPrimary)
            fact(
                "PAGE FAULTS",
                String(format: "%.0f/s", process.pageFaultRate), Halo.textPrimary)
            fact("PARENT", model.selectedParentName ?? "—", Halo.textPrimary)
        }

        Divider().overlay(Halo.surface2)

        VStack(alignment: .leading, spacing: 6) {
            Text("CPU · LAST 2 MIN")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            Sparkline(values: model.selectedCPUHistory)
                .frame(height: 56)
                .background(Halo.void.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }

        Spacer()

        if let feedback = model.actionFeedback {
            Text(feedback)
                .font(.system(size: 11))
                .foregroundStyle(Halo.pulseGreen)
        }

        Button {
            confirmQuit = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon")
                    .font(.system(size: 10, weight: .bold))
                Text("Send Quit")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Halo.flare)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Halo.flare.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Send SIGTERM — asks the process to exit politely")
        .confirmationDialog(
            "Send Quit to \(process.name)?",
            isPresented: $confirmQuit, titleVisibility: .visible
        ) {
            Button("Send Quit", role: .destructive) {
                model.quitProcess(pid: process.pid, name: process.name)
            }
        } message: {
            Text("SIGTERM asks the process to exit. Unsaved work in it may be lost.")
        }
    }

    private func fact(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Halo.textDim)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Network card

private struct NetworkCard: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("NETWORK")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Spacer()
                legend("DOWNLOAD", Halo.ion)
                legend("UPLOAD", Halo.volt)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if model.networks.isEmpty {
                        Text("No active interface")
                            .font(.system(size: 11))
                            .foregroundStyle(Halo.textDim)
                    }
                    ForEach(model.networks) { sample in
                        interfaceRow(sample)
                    }
                }
                .frame(width: 280, alignment: .leading)

                DualSparkline(
                    primary: model.networkInHistory,
                    secondary: model.networkOutHistory
                )
                .background(Halo.void.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Halo.textDim)
        }
    }

    private func interfaceRow(_ sample: NetworkSample) -> some View {
        HStack(spacing: 10) {
            Text(sample.interfaceName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Halo.textPrimary)
                .frame(width: 44, alignment: .leading)
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Halo.ion)
                Text(rateText(sample.bytesIn))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
                    .frame(width: 76, alignment: .trailing)
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Halo.volt)
                Text(rateText(sample.bytesOut))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Halo.textPrimary)
                    .frame(width: 76, alignment: .trailing)
            }
        }
    }

    private func rateText(_ rate: UInt64) -> String {
        rate == 0 ? "0 B/s" : "\(ByteFormat.string(rate))/s"
    }
}

/// Two overlaid autoscaling line charts sharing one y-scale — download
/// (ion, filled) and upload (volt, line only). Scale follows the larger
/// of both series so the two are directly comparable.
private struct DualSparkline: View {
    let primary: [Double]
    let secondary: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max((primary + secondary).max() ?? 1, 1)
            ZStack {
                if primary.count >= 2 {
                    fillPath(points(primary, max: maxValue, size: geo.size), size: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [Halo.ion.opacity(0.22), .clear],
                                startPoint: .top, endPoint: .bottom))
                    linePath(points(primary, max: maxValue, size: geo.size))
                        .stroke(Halo.ion, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                if secondary.count >= 2 {
                    linePath(points(secondary, max: maxValue, size: geo.size))
                        .stroke(Halo.volt, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        }
    }

    private func points(_ values: [Double], max maxValue: Double, size: CGSize) -> [CGPoint] {
        let stepX = size.width / CGFloat(MonitorModel.historyLength - 1)
        let offset = MonitorModel.historyLength - values.count
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(offset + index) * stepX,
                y: size.height * (1 - CGFloat(min(Swift.max(value, 0), maxValue) / maxValue) * 0.92)
            )
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func fillPath(_ points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}
