// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PulseKit", targets: ["PulseKit"]),
        .executable(name: "Pulse", targets: ["Pulse"]),
    ],
    targets: [
        // C shim exposing libproc (per-process CPU/memory) to Swift.
        .target(name: "CPulse"),
        // UI-independent system data collection core.
        .target(name: "PulseKit", dependencies: ["CPulse"]),
        // SwiftUI app: menu bar extra + dashboard window.
        .executableTarget(name: "Pulse", dependencies: ["PulseKit"]),
        .testTarget(name: "PulseKitTests", dependencies: ["PulseKit"]),
    ]
)
