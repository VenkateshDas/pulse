import SwiftUI

/// HALO design tokens (see docs/design_mockups.html).
/// Safety colors are reserved for safety meaning only.
enum Halo {
    static let void = Color(hex: 0x06090F)
    static let surface1 = Color(hex: 0x0E1520)
    static let surface2 = Color(hex: 0x141D2C)
    static let ion = Color(hex: 0x00E5FF)      // live data + primary action
    static let volt = Color(hex: 0x7C5CFF)     // history / secondary
    static let pulseGreen = Color(hex: 0x2EE6A8)
    static let amber = Color(hex: 0xFFB02E)
    static let flare = Color(hex: 0xFF4D6A)
    static let textPrimary = Color(hex: 0xE8F0FA)
    static let textDim = Color(hex: 0x6C7A90)

    /// Status color for a 0–1 load fraction: calm → warn → critical.
    static func statusColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: ion
        case ..<0.85: amber
        default: flare
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
