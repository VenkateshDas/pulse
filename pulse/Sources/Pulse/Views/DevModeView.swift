import PulseKit
import SwiftUI

struct DevModeView: View {
    @State private var model = DevModeModel()
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    smcCard
                    sysctlCard
                }
                .frame(maxWidth: .infinity)
                
                processFDCard
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Halo.void)
        .onAppear {
            Task { await model.sample() }
            timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                Task { await model.sample() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dev Mode")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Halo.textPrimary)
            Text("Raw diagnostic console: full SMC sensor reads, sysctl properties, and per-process file descriptors.")
                .font(.system(size: 12))
                .foregroundStyle(Halo.textDim)
        }
    }

    private var smcCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("SMC SENSOR DUMP")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("\(model.smcDump.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.volt)
            }
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(model.smcDump.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Halo.textPrimary)
                            Spacer()
                            Text(value)
                                .font(.system(size: 11, design: .monospaced))
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
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private var sysctlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("SYSCTL BROWSER")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("\(model.sysctls.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.ion)
            }
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.sysctls) { prop in
                        HStack {
                            Text(prop.id)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Halo.textPrimary)
                            Spacer()
                            Text(prop.value)
                                .font(.system(size: 11, design: .monospaced))
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
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }

    private var processFDCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("PROCESS FDs & THREADS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Halo.textDim)
                Text("\(model.processFDs.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Halo.amber)
            }
            
            HStack(spacing: 10) {
                Text("NAME")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 44, alignment: .trailing)
                Text("THREADS").frame(width: 56, alignment: .trailing)
                Text("FDs").frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Halo.textDim)
            .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.processFDs) { sample in
                        HStack(spacing: 10) {
                            Text(sample.name)
                                .font(.system(size: 11))
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
                        .font(.system(size: 11, design: .monospaced))
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
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: 14))
    }
}
