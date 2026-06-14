import SwiftUI

/// HALO design tokens — Precision Instrument Aesthetic
/// Dynamic Light/Dark mode support.
enum Halo {
    static let void = Color(nsColor: NSColor(name: "Canvas", dynamicProvider: { appearance in
        appearance.name == .darkAqua ? NSColor(calibratedWhite: 0.08, alpha: 1.0) : NSColor(calibratedWhite: 0.96, alpha: 1.0)
    }))

    static let surface1 = Color(nsColor: NSColor(name: "Surface1", dynamicProvider: { appearance in
        appearance.name == .darkAqua ? NSColor(calibratedWhite: 0.12, alpha: 1.0) : NSColor(calibratedWhite: 1.0, alpha: 1.0)
    }))

    static let surface2 = Color(nsColor: NSColor(name: "Surface2", dynamicProvider: { appearance in
        appearance.name == .darkAqua ? NSColor(calibratedWhite: 0.18, alpha: 1.0) : NSColor(calibratedWhite: 0.92, alpha: 1.0)
    }))

    static let border = Color(nsColor: NSColor(name: "Border", dynamicProvider: { appearance in
        appearance.name == .darkAqua ? NSColor(calibratedWhite: 0.25, alpha: 1.0) : NSColor(calibratedWhite: 0.85, alpha: 1.0)
    }))

    static let textPrimary = Color(nsColor: NSColor(name: "TextPrimary", dynamicProvider: { appearance in
        appearance.name == .darkAqua ? NSColor(calibratedWhite: 0.95, alpha: 1.0) : NSColor(calibratedWhite: 0.10, alpha: 1.0)
    }))

    static let textDim = Color(nsColor: NSColor(name: "TextDim", dynamicProvider: { appearance in
        appearance.name == .darkAqua ? NSColor(calibratedWhite: 0.60, alpha: 1.0) : NSColor(calibratedWhite: 0.50, alpha: 1.0)
    }))

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
