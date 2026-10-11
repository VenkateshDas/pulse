import PulseKit
import SwiftUI

struct DevModeView: View {
    @State private var model = DevModeModel()
    @State private var selectedSection = 0
    @State private var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            SegmentPicker(options: [(0, "Sensors"), (1, "System properties"), (2, "Open files")], selection: $selectedSection)
            Group {
                switch selectedSection {
                case 1: sysctlCard
                case 2: processFDCard
                default: smcCard
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .task { await refresh() }
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await model.sample()
    }

    private var header: some View {
        PageHeader("Diagnostics", subtitle: "Advanced readings for troubleshooting. Readings update when you choose Refresh.") {
            RefreshButton(help: "Refresh diagnostic readings", disabled: refreshing) { Task { await refresh() } }
        }
    }

    private var smcCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Sensor readings")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Text("\(model.smcDump.count)")
                    .font(Halo.font(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.volt)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 8) {
                    ForEach(model.smcDump.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .font(Halo.font(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Halo.textPrimary)
                            Spacer()
                            Text(value)
                                .font(Halo.font(size: 11, design: .monospaced))
                                .foregroundStyle(Halo.textDim)
                        }
                        .padding(6)
                        .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var sysctlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("System properties")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Text("\(model.sysctls.count)")
                    .font(Halo.font(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.ion)
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.sysctls) { prop in
                        HStack {
                            Text(prop.id)
                                .font(Halo.font(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Halo.textPrimary)
                            Spacer()
                            Text(prop.value)
                                .font(Halo.font(size: 11, design: .monospaced))
                                .foregroundStyle(Halo.textDim)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }

    private var processFDCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("PROCESS FDs & THREADS")
                    .font(Halo.font(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.textDim)
                Text("\(model.processFDs.count)")
                    .font(Halo.font(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.amber)
            }

            HStack(spacing: 10) {
                Text("NAME")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 44, alignment: .trailing)
                Text("THREADS").frame(width: 56, alignment: .trailing)
                Text("FDs").frame(width: 44, alignment: .trailing)
            }
            .font(Halo.font(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Halo.textDim)
            .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.processFDs) { sample in
                        HStack(spacing: 10) {
                            Text(sample.name)
                                .font(Halo.font(size: 11))
                                .foregroundStyle(Halo.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(sample.id)")
                                .frame(width: 44, alignment: .trailing)
                            Text("\(sample.threadCount)")
                                .frame(width: 56, alignment: .trailing)
                            Text("\(sample.fdCount)")
                                .frame(width: 44, alignment: .trailing)
                        }
                        .font(Halo.font(size: 11, design: .monospaced))
                        .foregroundStyle(Halo.textDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(padding: 0, cornerRadius: Halo.Radius.large)
    }
}
