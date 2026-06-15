import SwiftUI

/// HALO design tokens — Precision Instrument Aesthetic
/// Dynamic Light/Dark mode support.
enum Halo {
    /// A light/dark grayscale token. Matching on `bestMatch` (not
    /// `name == .darkAqua`) is what makes the menu-bar popover follow the
    /// system: its window renders with a *vibrant* appearance
    /// (`.vibrantDark`/`.vibrantLight`), which `== .darkAqua` never matched —
    /// so every token fell through to its light value.
    private static func dynamicWhite(light: CGFloat, dark: CGFloat, name: NSColor.Name) -> Color {
        Color(nsColor: NSColor(name: name, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? dark : light, alpha: 1.0)
        }))
    }

    static let void = dynamicWhite(light: 0.96, dark: 0.08, name: "Canvas")
    static let surface1 = dynamicWhite(light: 1.0, dark: 0.12, name: "Surface1")
    static let surface2 = dynamicWhite(light: 0.92, dark: 0.18, name: "Surface2")
    static let border = dynamicWhite(light: 0.85, dark: 0.25, name: "Border")
    static let textPrimary = dynamicWhite(light: 0.10, dark: 0.95, name: "TextPrimary")
    static let textDim = dynamicWhite(light: 0.50, dark: 0.60, name: "TextDim")

    // Semantic Data Colors (Precision Instrument)
    static let nominal = Color(hex: 0x34C759)   // Apple Green
    static let warning = Color(hex: 0xFF9F0A)   // Apple Orange
    static let critical = Color(hex: 0xFF453A)  // Apple Red
    static let interactive = Color(hex: 0x007AFF) // Apple Blue

    // Legacy names mapped to new semantic colors to prevent breaking other files
    static let ion = interactive
    static let volt = Color(hex: 0x5E5CE6) // Indigo
    static let pulseGreen = nominal
    static let amber = warning
    static let flare = critical

    /// Status color for a 0–1 load fraction: nominal → warning → critical.
    static func statusColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: nominal
        case ..<0.85: warning
        default: critical
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
