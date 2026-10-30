import SwiftUI

/// Pulse design tokens — calm native surfaces, readable text and semantic color
/// Dynamic Light/Dark mode support.
enum Halo {
    /// A light/dark RGB token. Matching on `bestMatch` (not
    /// `name == .darkAqua`) is what makes the menu-bar popover follow the
    /// system: its window renders with a *vibrant* appearance
    /// (`.vibrantDark`/`.vibrantLight`), which `== .darkAqua` never matched —
    /// so every token fell through to its light value.
    private static func dynamicColor(_ pair: ColorPair, name: NSColor.Name) -> Color {
        // ponytail: namespace named colors so SwiftUI cannot reuse a previous palette.
        Color(nsColor: NSColor(name: "\(ThemeManager.currentPaletteID).\(name)", dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? pair.dark : pair.light
            return NSColor(calibratedRed: c.r, green: c.g, blue: c.b, alpha: 1.0)
        }))
    }

    // MARK: - Surfaces
    // `static var` (not `let`) so every read reflects the currently selected
    // `ThemeManager.shared` preset. The `name:` argument keys the underlying
    // `NSColor` dynamic provider — namespaced per theme to invalidate cached styles.
    private static var palette: Palette { ThemeManager.currentPalette }

    static var void: Color { dynamicColor(palette.void, name: "Canvas") }
    static var sidebar: Color { dynamicColor(.hex(0xF0F4F3, 0x1B2524), name: "Sidebar") }
    static var surface1: Color { dynamicColor(palette.surface1, name: "Surface1") }
    static var surface2: Color { dynamicColor(palette.surface2, name: "Surface2") }
    static var border: Color { dynamicColor(palette.border, name: "Border") }
    static var borderSubtle: Color { dynamicColor(palette.borderSubtle, name: "BorderSubtle") }

    // MARK: - Text
    static var textPrimary: Color { dynamicColor(palette.textPrimary, name: "TextPrimary") }
    static var textSecondary: Color { dynamicColor(palette.textSecondary, name: "TextSecondary") }
    static var textDim: Color { dynamicColor(palette.textDim, name: "TextDim") }

    // MARK: - Semantic Data Colors
    static var nominal: Color { dynamicColor(palette.nominal, name: "nominal") }
    static var warning: Color { dynamicColor(palette.warning, name: "warning") }
    static var critical: Color { dynamicColor(palette.critical, name: "critical") }
    static var interactive: Color { dynamicColor(palette.interactive, name: "interactive") }

    static var onAccent: Color { dynamicColor(.hex(0xFFFFFF, 0x172126), name: "OnAccent") }

    // Compatibility names used by existing charts and action controls.
    static var teal: Color { nominal }
    static var tealLight: Color { nominal }
    static var tealDeep: Color { nominal }
    static var tealSoft: Color { nominal.opacity(0.10) }
    static var tealGlow: Color { .clear }
    static var ion: Color { interactive }
    static var volt: Color { dynamicColor(.hex(0x5D4894, 0xC4B5F2), name: "SecondaryChart") }
    static var pulseGreen: Color { nominal }
    static var amber: Color { warning }
    static var flare: Color { critical }

    static func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: max(12, size) * ThemeManager.currentTextScale, weight: weight, design: design)
    }

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
        static let cardRadius: CGFloat = 0
        static let cardY: CGFloat = 4
        static let elevatedColor = Color.black.opacity(0.15)
        static let elevatedRadius: CGFloat = 8
        static let elevatedY: CGFloat = 8
        static let glowColor = Color(hex: 0x10B981).opacity(0.4)
        static let glowRadius: CGFloat = 12
    }

    // MARK: - Corner Radii
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let xl: CGFloat = 12
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
        static var snappy: Animation? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.18) }
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

    static let meshBackground = Color.clear
}

// MARK: - Glass Backgrounds

/// Two-layer material + tint backdrop, shared by every full-bleed glass panel
/// (popover body, sidebars). Card-shaped surfaces with padding/shadow/border
/// use `premiumCard()` instead.
struct GlassLayer<S: ShapeStyle>: View {
    var material: Material = .regularMaterial
    var tint: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency { Rectangle().fill(Halo.surface1) }
            else { Rectangle().fill(material) }
            Rectangle().fill(tint)
        }
    }
}

// MARK: - View Modifiers

extension View {
    func premiumCard(padding: CGFloat = Halo.Space.lg, cornerRadius: CGFloat = Halo.Radius.medium) -> some View {
        self
            .padding(padding)
            .background(Halo.surface1, in: RoundedRectangle(cornerRadius: min(cornerRadius, 12)))
            .overlay {
                RoundedRectangle(cornerRadius: min(cornerRadius, 12))
                    .strokeBorder(Halo.borderSubtle, lineWidth: 1)
            }
    }

    func sectionLabel() -> some View {
        self
            .font(Halo.font(size: 14, weight: .semibold))
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
