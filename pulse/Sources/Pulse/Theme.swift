import SwiftUI

/// HALO design tokens — Precision Instrument Aesthetic
/// Dynamic Light/Dark mode support.
enum Halo {
    /// A light/dark RGB token. Matching on `bestMatch` (not
    /// `name == .darkAqua`) is what makes the menu-bar popover follow the
    /// system: its window renders with a *vibrant* appearance
    /// (`.vibrantDark`/`.vibrantLight`), which `== .darkAqua` never matched —
    /// so every token fell through to its light value.
    private static func dynamicColor(_ pair: ColorPair, name: NSColor.Name) -> Color {
        Color(nsColor: NSColor(name: name, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? pair.dark : pair.light
            return NSColor(calibratedRed: c.r, green: c.g, blue: c.b, alpha: 1.0)
        }))
    }

    // MARK: - Surfaces
    // `static var` (not `let`) so every read reflects the currently selected
    // `ThemeManager.shared` preset. The `name:` argument keys the underlying
    // `NSColor` dynamic provider — kept stable across theme switches.
    private static var palette: Palette { ThemeManager.currentPalette }

    static var void: Color { dynamicColor(palette.void, name: "Canvas") }
    static var surface1: Color { dynamicColor(palette.surface1, name: "Surface1") }
    static var surface2: Color { dynamicColor(palette.surface2, name: "Surface2") }
    static var border: Color { dynamicColor(palette.border, name: "Border") }
    static var borderSubtle: Color { dynamicColor(palette.borderSubtle, name: "BorderSubtle") }

    // MARK: - Text
    static var textPrimary: Color { dynamicColor(palette.textPrimary, name: "TextPrimary") }
    static var textSecondary: Color { dynamicColor(palette.textSecondary, name: "TextSecondary") }
    static var textDim: Color { dynamicColor(palette.textDim, name: "TextDim") }

    // MARK: - Semantic Data Colors
    static var nominal: Color { Color(hex: palette.nominal) }
    static var warning: Color { Color(hex: palette.warning) }
    static var critical: Color { Color(hex: palette.critical) }
    static var interactive: Color { Color(hex: palette.interactive) }

    // MARK: - Brand Teal (landing page accent)
    static let teal = Color(hex: 0x10B981)
    static let tealLight = Color(hex: 0x34D399)
    static let tealDeep = Color(hex: 0x6EE7B7)
    static let tealSoft = Color(hex: 0x10B981).opacity(0.15)
    static let tealGlow = Color(hex: 0x10B981).opacity(0.4)

    // Legacy names
    static var ion: Color { interactive }
    static let volt = Color(hex: 0x5E5CE6) // Indigo
    static var pulseGreen: Color { nominal }
    static var amber: Color { warning }
    static var flare: Color { critical }

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
        static let elevatedColor = Color.black.opacity(0.15)
        static let elevatedRadius: CGFloat = 24
        static let elevatedY: CGFloat = 8
        static let glowColor = Color(hex: 0x10B981).opacity(0.4)
        static let glowRadius: CGFloat = 12
    }

    // MARK: - Corner Radii
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let xl: CGFloat = 18
    }

    // MARK: - Spacing
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
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

    static let meshBackground = RadialGradient(
        colors: [Color(hex: 0x10B981).opacity(0.04), .clear],
        center: .topTrailing,
        startRadius: 0,
        endRadius: 500
    )
}

// MARK: - Glass Backgrounds

/// Two-layer material + tint backdrop, shared by every full-bleed glass panel
/// (popover body, sidebars). Card-shaped surfaces with padding/shadow/border
/// use `premiumCard()` instead.
struct GlassLayer<S: ShapeStyle>: View {
    var material: Material = .regularMaterial
    var tint: S

    var body: some View {
        ZStack {
            Rectangle().fill(material)
            Rectangle().fill(tint)
        }
    }
}

// MARK: - View Modifiers

extension View {
    func premiumCard(padding: CGFloat = Halo.Space.lg, cornerRadius: CGFloat = Halo.Radius.medium) -> some View {
        self
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Halo.surface1.opacity(0.6))
                }
                .shadow(
                    color: Halo.Shadow.cardColor,
                    radius: Halo.Shadow.cardRadius,
                    y: Halo.Shadow.cardY
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Halo.borderSubtle, lineWidth: 0.5)
            }
    }

    func sectionLabel() -> some View {
        self
            .font(.system(size: 11, weight: .bold))
            .tracking(2)
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
