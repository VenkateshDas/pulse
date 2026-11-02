#!/bin/bash
# Render real Pulse SwiftUI components with fictional fixtures; never start samplers.
set -eu
repo_root="$(git rev-parse --show-toplevel)"
capture_dir="$(mktemp -d /tmp/pulse-native-proof.XXXXXX)"
output_path="${1:-/tmp/pulse-native-indicators.png}"
source_commit=b698bfd
mkdir -p "$capture_dir/Sources"
for source_file in Theme.swift ThemePreset.swift ThemeManager.swift Views/VitalCard.swift; do
  git -C "$repo_root" show "$source_commit:pulse/Sources/Pulse/$source_file" > "$capture_dir/Sources/$(basename "$source_file")"
done
cat > "$capture_dir/Package.swift" <<'SWIFT'
// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "PulseMarketingProof", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "PulseMarketingProof", path: "Sources")])
SWIFT
cat > "$capture_dir/Sources/Capture.swift" <<'SWIFT'
import AppKit
import SwiftUI

struct NativeIndicatorProof: View {
    private let trace: [Double] = [8, 12, 11, 16, 13, 20, 17, 21, 18]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Technical details").font(Halo.font(size: 24, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                VitalCard(title: "CPU", fraction: 0.18, ringColor: Halo.nominal, value: "18%", line1: "Processor activity", line2: "GPU: 12%", history: trace)
                VitalCard(title: "MEMORY", fraction: 0.4, ringColor: Halo.nominal, value: "40%", line1: "6.4 / 16 GB", line2: "Pressure: normal", history: [37, 38, 38, 39, 38, 40, 40, 39, 40])
                VitalCard(title: "DISK", fraction: 0.875, ringColor: Halo.nominal, value: "88%", line1: "64 GB available", line2: "512 GB total", history: [86, 86, 87, 87, 87, 88, 88, 88, 88])
                VitalCard(title: "THERMAL", fraction: 0.18, ringColor: Halo.nominal, value: "OK", line1: "thermal state", line2: "macOS status: nominal", history: [17, 18, 18, 18, 19, 18, 17, 18, 18])
                VitalCard(title: "NETWORK", fraction: 1, ringColor: Halo.nominal, value: "Wired", line1: "↓ 1.8 MB/s · ↑ 0.2 MB/s", line2: "Transfer activity", history: [0.2, 0.6, 0.4, 1.2, 0.8, 1.8, 1.2, 1.6, 1.8], historyScale: 2)
            }
            Text("Example readings · Your Mac’s readings will vary")
                .font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
        }
        .padding(28)
        .frame(width: 1120, alignment: .leading)
        .foregroundStyle(Halo.textPrimary)
        .background(Halo.void)
        .environment(\.colorScheme, .light)
    }
}

@main struct Capture {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        let renderer = ImageRenderer(content: NativeIndicatorProof())
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PulseMarketingProof", code: 1)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
SWIFT
cat > "$capture_dir/Marketing.mk" <<'MAKE'
.PHONY: marketing-proof
marketing-proof: fix-toolchain
	$(SWIFT) build --package-path "$(CAPTURE_DIR)" --product PulseMarketingProof
MAKE
make -C "$repo_root/pulse" -f Makefile -f "$capture_dir/Marketing.mk" marketing-proof CAPTURE_DIR="$capture_dir"
"$capture_dir/.build/debug/PulseMarketingProof" "$output_path"
printf 'Native fixture render: %s\n' "$output_path"
