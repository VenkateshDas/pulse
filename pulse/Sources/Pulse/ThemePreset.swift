import AppKit
import SwiftUI

/// A calibrated-space RGB triple, 0–1 per channel. Grayscale convenience
/// (`gray(_:)`) reproduces `NSColor(calibratedWhite:)` exactly (r == g == b),
/// which is what `Theme.swift` used before theme presets existed.
struct RGB {
    let r, g, b: CGFloat

    static func gray(_ w: CGFloat) -> RGB { RGB(r: w, g: w, b: w) }

    /// 0xRRGGBB → 0–1 float triple.
    static func hex(_ value: UInt32) -> RGB {
        RGB(
            r: CGFloat((value >> 16) & 0xFF) / 255,
            g: CGFloat((value >> 8) & 0xFF) / 255,
            b: CGFloat(value & 0xFF) / 255
        )
    }
}

/// A light/dark RGB pair, matching the shape `Halo`'s dynamic-appearance
/// tokens already consume.
struct ColorPair {
    let light: RGB
    let dark: RGB
}

/// One theme preset's full token set.
struct Palette {
    let void, surface1, surface2, border, borderSubtle: ColorPair
    let textPrimary, textSecondary, textDim: ColorPair
    let nominal, warning, critical, interactive: ColorPair
}

/// User-selectable theme presets, applied app-wide (Command Center + popover).
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case precision, midnight, contrast, slate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .precision: "Pulse"
        case .midnight: "Midnight"
        case .contrast: "Contrast"
        case .slate: "Slate"
        }
    }

    /// `nil` = follow system appearance. Only Midnight forces dark.
    var forcedAppearance: NSAppearance.Name? {
        self == .midnight ? .darkAqua : nil
    }

    /// Preset identifiers remain stable so saved appearance choices survive.
    var palette: Palette {
        let base = Palette(
            void: .hex(0xF5F7F8, 0x171D21),
            surface1: .hex(0xFFFFFF, 0x222B30),
            surface2: .hex(0xE8EDF0, 0x303C43),
            border: .hex(0x84949C, 0x71828B),
            borderSubtle: .hex(0xCCD5DA, 0x52616A),
            textPrimary: .hex(0x172126, 0xF2F6F7),
            textSecondary: .hex(0x4F6068, 0xB5C2C9),
            textDim: .hex(0x4F6068, 0xB5C2C9),
            nominal: .hex(0x176B56, 0x70D6B3),
            warning: .hex(0x875100, 0xF4C16A),
            critical: .hex(0xB62F39, 0xFF9DA4),
            interactive: .hex(0x176B56, 0x70D6B3)
        )
        switch self {
        case .precision:
            return base
        case .midnight:
            return Palette(
                void: .hex(0x111526, 0x111526),
                surface1: .hex(0x1D2439, 0x1D2439),
                surface2: .hex(0x2D3650, 0x2D3650),
                border: .hex(0x8090B3, 0x8090B3),
                borderSubtle: .hex(0x4E5B78, 0x4E5B78),
                textPrimary: .hex(0xF2F4FF, 0xF2F4FF),
                textSecondary: .hex(0xC0C9E3, 0xC0C9E3),
                textDim: .hex(0xC0C9E3, 0xC0C9E3),
                nominal: .hex(0x70D6B3, 0x70D6B3),
                warning: .hex(0xF4C16A, 0xF4C16A),
                critical: .hex(0xFF9DA4, 0xFF9DA4),
                interactive: .hex(0xB2C1FF, 0xB2C1FF)
            )
        case .contrast:
            return Palette(
                void: .hex(0xFFFFFF, 0x000000),
                surface1: .hex(0xFFFFFF, 0x101010),
                surface2: .hex(0xEEEEEE, 0x242424),
                border: .hex(0x555555, 0xAAAAAA),
                borderSubtle: .hex(0x555555, 0xAAAAAA),
                textPrimary: .hex(0x000000, 0xFFFFFF),
                textSecondary: .hex(0x333333, 0xDDDDDD),
                textDim: .hex(0x333333, 0xDDDDDD),
                nominal: .hex(0x07523E, 0x8AEFCB),
                warning: .hex(0x744500, 0xFFD68A),
                critical: .hex(0xA61D2A, 0xFFB8BE),
                interactive: .hex(0x07523E, 0x8AEFCB)
            )
        case .slate:
            return Palette(
                void: .hex(0xEDF1F5, 0x121B25),
                surface1: .hex(0xF8FAFC, 0x1D2A38),
                surface2: .hex(0xDFE7EF, 0x2C3C4D),
                border: .hex(0x7A8EA2, 0x8196AD),
                borderSubtle: .hex(0xBDCAD7, 0x506880),
                textPrimary: .hex(0x16283A, 0xEFF5FC),
                textSecondary: .hex(0x425A70, 0xB6CAE0),
                textDim: .hex(0x425A70, 0xB6CAE0),
                nominal: base.nominal, warning: base.warning, critical: base.critical,
                interactive: .hex(0x235A8C, 0xA1D0FF)
            )
        }
    }
}

extension ColorPair {
    static func hex(_ light: UInt32, _ dark: UInt32) -> ColorPair {
        ColorPair(light: .hex(light), dark: .hex(dark))
    }
}
