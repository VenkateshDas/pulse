// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PulseKit", targets: ["PulseKit"]),
        .executable(name: "Pulse", targets: ["Pulse"]),
        .executable(name: "PulseHelper", targets: ["PulseHelper"]),
    ],
    // Sparkle auto-updates (P0-8): Updater.swift wires it up behind
    // `#if canImport(Sparkle)`, so enabling is a two-line change here —
    // uncomment the dependency and add the product to the Pulse target.
    // Left off by default so the patched-CLT build resolves with no network.
    // dependencies: [
    //     .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    // ],
    targets: [
        // C shim exposing libproc (per-process CPU/memory) to Swift.
        .target(name: "CPulse"),
        // UI-independent system data collection core.
        .target(name: "PulseKit", dependencies: ["CPulse"]),
        // SwiftUI app: menu bar extra + dashboard window.
        .executableTarget(name: "Pulse", dependencies: ["PulseKit"], resources: [
            .process("Resources")
        ]),
        // Privileged root daemon (SMAppService). Runs the fixed maintenance
        // ops in PrivilegedOperation on behalf of the sandboxed GUI app.
        .executableTarget(name: "PulseHelper", dependencies: ["PulseKit"]),
        .testTarget(name: "PulseKitTests", dependencies: ["PulseKit"]),
    ]
)
