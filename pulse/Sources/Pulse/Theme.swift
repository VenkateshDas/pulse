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

    private static func dynamicColor(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat),
        name: NSColor.Name
    ) -> Color {
        Color(nsColor: NSColor(name: name, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1.0)
        }))
    }

    // MARK: - Surfaces
    static let void = dynamicWhite(light: 0.965, dark: 0.065, name: "Canvas")
    static let surface1 = dynamicWhite(light: 1.0, dark: 0.10, name: "Surface1")
    static let surface2 = dynamicWhite(light: 0.94, dark: 0.16, name: "Surface2")
    static let surface3 = dynamicWhite(light: 0.90, dark: 0.20, name: "Surface3")
    static let border = dynamicWhite(light: 0.88, dark: 0.20, name: "Border")
    static let borderSubtle = dynamicWhite(light: 0.92, dark: 0.14, name: "BorderSubtle")

    // MARK: - Text
    static let textPrimary = dynamicWhite(light: 0.07, dark: 0.96, name: "TextPrimary")
    static let textSecondary = dynamicWhite(light: 0.30, dark: 0.75, name: "TextSecondary")
    static let textDim = dynamicWhite(light: 0.50, dark: 0.55, name: "TextDim")

    // MARK: - Semantic Data Colors
    static let nominal = Color(hex: 0x30D158)   // Vibrant Green
    static let warning = Color(hex: 0xFF9F0A)   // Apple Orange
    static let critical = Color(hex: 0xFF453A)  // Apple Red
    static let interactive = Color(hex: 0x0A84FF) // System Blue

    // Legacy names
    static let ion = interactive
    static let volt = Color(hex: 0x5E5CE6) // Indigo
    static let pulseGreen = nominal
    static let amber = warning
    static let flare = critical

    // MARK: - Extended Palette
    static let teal = Color(hex: 0x64D2FF)
    static let purple = Color(hex: 0xBF5AF2)
    static let pink = Color(hex: 0xFF375F)

    /// Status color for a 0–1 load fraction: nominal → warning → critical.
    static func statusColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: nominal
        case ..<0.85: warning
        default: critical
        }
    }

    // MARK: - Shadows
    enum Shadow {
        static let cardColor = Color.black.opacity(0.08)
        static let cardRadius: CGFloat = 12
        static let cardY: CGFloat = 4

        static let elevatedColor = Color.black.opacity(0.12)
        static let elevatedRadius: CGFloat = 20
        static let elevatedY: CGFloat = 8

        static let glowRadius: CGFloat = 16
    }

    // MARK: - Corner Radii
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let xl: CGFloat = 18
        static let card: CGFloat = 12
    }

    // MARK: - Spacing
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let section: CGFloat = 28
    }

    // MARK: - Animation Curves
    enum Motion {
        static let snappy = Animation.spring(duration: 0.3, bounce: 0.15)
        static let smooth = Animation.easeInOut(duration: 0.25)
        static let ring = Animation.easeOut(duration: 0.5)
    }

    // MARK: - Gradients
    static func accentGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.85), color],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func subtleGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.15), color.opacity(0.05)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static let meshBackground = LinearGradient(
        colors: [
            Color(hex: 0x0A84FF).opacity(0.03),
            Color(hex: 0x5E5CE6).opacity(0.02),
            Color.clear
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - View Modifiers

extension View {
    func premiumCard(padding: CGFloat = Halo.Space.lg) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: Halo.Radius.card, style: .continuous)
                    .fill(Halo.surface1)
                    .shadow(
                        color: Halo.Shadow.cardColor,
                        radius: Halo.Shadow.cardRadius,
                        y: Halo.Shadow.cardY
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: Halo.Radius.card, style: .continuous)
                    .strokeBorder(Halo.borderSubtle, lineWidth: 0.5)
            }
    }

    func sectionLabel() -> some View {
        self
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Halo.textDim)
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
