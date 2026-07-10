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
    let nominal, warning, critical, interactive: UInt32
}

/// User-selectable theme presets, applied app-wide (Command Center + popover).
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case precision, midnight, contrast, slate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .precision: "Precision"
        case .midnight: "Midnight"
        case .contrast: "Contrast"
        case .slate: "Slate"
        }
    }

    /// `nil` = follow system appearance. Only Midnight forces dark.
    var forcedAppearance: NSAppearance.Name? {
        self == .midnight ? .darkAqua : nil
    }

    /// Precision's values MUST equal today's literal `Theme.swift` constants
    /// exactly — this is the regression anchor for users who never touch the
    /// setting. `RGB.gray(_:)` reproduces the old `NSColor(calibratedWhite:)`
    /// call bit-for-bit (r == g == b == the same float).
    var palette: Palette {
        switch self {
        case .precision:
            return Palette(
                void: ColorPair(light: .gray(0.965), dark: .gray(0.065)),
                surface1: ColorPair(light: .gray(1.0), dark: .gray(0.10)),
                surface2: ColorPair(light: .gray(0.94), dark: .gray(0.16)),
                border: ColorPair(light: .gray(0.88), dark: .gray(0.20)),
                borderSubtle: ColorPair(light: .gray(0.92), dark: .gray(0.14)),
                textPrimary: ColorPair(light: .gray(0.07), dark: .gray(0.96)),
                textSecondary: ColorPair(light: .gray(0.30), dark: .gray(0.75)),
                textDim: ColorPair(light: .gray(0.50), dark: .gray(0.55)),
                nominal: 0x30D158,
                warning: 0xFF9F0A,
                critical: 0xFF453A,
                interactive: 0x0A84FF
            )
        case .midnight:
            // Forced dark — deep indigo-black, not just a darker gray.
            // Light values mirror dark since this preset never shows light.
            let void = RGB.hex(0x080A16)
            let surface1 = RGB.hex(0x10142A)
            let surface2 = RGB.hex(0x171B36)
            let border = RGB.hex(0x262C52)
            let borderSubtle = RGB.hex(0x1B2040)
            let textPrimary = RGB.hex(0xF2F4FF)
            let textSecondary = RGB.hex(0xB9C0E0)
            let textDim = RGB.hex(0x7F87AD)
            return Palette(
                void: ColorPair(light: void, dark: void),
                surface1: ColorPair(light: surface1, dark: surface1),
                surface2: ColorPair(light: surface2, dark: surface2),
                border: ColorPair(light: border, dark: border),
                borderSubtle: ColorPair(light: borderSubtle, dark: borderSubtle),
                textPrimary: ColorPair(light: textPrimary, dark: textPrimary),
                textSecondary: ColorPair(light: textSecondary, dark: textSecondary),
                textDim: ColorPair(light: textDim, dark: textDim),
                nominal: 0x32D74B,
                warning: 0xFF9F0A,
                critical: 0xFF453A,
                interactive: 0x5E7CFF
            )
        case .contrast:
            // Extreme black/white with punchy, highly saturated accents.
            return Palette(
                void: ColorPair(light: .gray(1.0), dark: .gray(0.0)),
                surface1: ColorPair(light: .gray(1.0), dark: .gray(0.039)),
                surface2: ColorPair(light: .gray(0.929), dark: .gray(0.086)),
                border: ColorPair(light: .gray(0.557), dark: .gray(0.361)),
                borderSubtle: ColorPair(light: .gray(0.85), dark: .gray(0.25)),
                textPrimary: ColorPair(light: .gray(0.0), dark: .gray(1.0)),
                textSecondary: ColorPair(light: .gray(0.20), dark: .gray(0.85)),
                textDim: ColorPair(light: .gray(0.40), dark: .gray(0.65)),
                nominal: 0x00C853,
                warning: 0xFFAB00,
                critical: 0xFF1744,
                interactive: 0x2979FF
            )
        case .slate:
            // Cool blue-gray tint throughout, not neutral gray.
            return Palette(
                void: ColorPair(light: .hex(0xE4E7EC), dark: .hex(0x12161C)),
                surface1: ColorPair(light: .hex(0xEEF1F5), dark: .hex(0x1A2028)),
                surface2: ColorPair(light: .hex(0xDADFE6), dark: .hex(0x232B36)),
                border: ColorPair(light: .hex(0xB7C0CC), dark: .hex(0x384454)),
                borderSubtle: ColorPair(light: .hex(0xC7CFD9), dark: .hex(0x2B3542)),
                textPrimary: ColorPair(light: .hex(0x10151C), dark: .hex(0xEDF1F6)),
                textSecondary: ColorPair(light: .hex(0x38445A), dark: .hex(0xAEB9C8)),
                textDim: ColorPair(light: .hex(0x5C6B7D), dark: .hex(0x7C8B9C)),
                nominal: 0x30D158,
                warning: 0xFF9F0A,
                critical: 0xFF453A,
                interactive: 0x6C9BFF
            )
        }
    }
}
