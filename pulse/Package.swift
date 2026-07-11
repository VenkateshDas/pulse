// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PulseKit", targets: ["PulseKit"]),
        .executable(name: "Pulse", targets: ["Pulse"]),
    ],
    // Sparkle auto-updates (P0-8): Updater.swift wires it up behind
    // `#if canImport(Sparkle)`, so enabling is a two-line change here —
    // uncomment the dependency and add the product to the Pulse target.
    // Left off by default so the patched-CLT build resolves with no network.
    dependencies: [
        .package(url: "https://github.com/alin23/MediaKeyTap", branch: "dev"),
    ],
    targets: [
        // C shim exposing libproc (per-process CPU/memory) to Swift.
        .target(
            name: "CPulse",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "CoreDisplay", "-framework", "DisplayServices"])
            ]
        ),
        // UI-independent system data collection core.
        .target(name: "PulseKit", dependencies: [
            "CPulse",
            .product(name: "MediaKeyTap", package: "MediaKeyTap")
        ], linkerSettings: [
            .linkedFramework("CoreWLAN"),
            .linkedFramework("CoreLocation"),
        ]),
        // SwiftUI app: menu bar extra + dashboard window.
        .executableTarget(name: "Pulse", dependencies: ["PulseKit"], resources: [
            .process("Resources")
        ]),
        .testTarget(name: "PulseKitTests", dependencies: ["PulseKit"]),
        // Unit tests for pure app-layer logic (display-mode gating, sidebar
        // visibility, label formatting) — no UI, so testable directly
        // against the executable target.
        .testTarget(name: "PulseTests", dependencies: ["Pulse"]),
    ]
)
