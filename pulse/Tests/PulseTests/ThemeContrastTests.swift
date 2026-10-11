import Foundation
import Testing
@testable import Pulse

@Suite("Readable theme colours")
struct ThemeContrastTests {
    private func luminance(_ rgb: RGB) -> Double {
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    @Test func textAndStatusTokensMeetNormalTextContrast() {
        for theme in AppTheme.allCases {
            let palette = theme.palette
            let text = [palette.textPrimary, palette.textSecondary, palette.textDim,
                        palette.nominal, palette.warning, palette.critical, palette.interactive]
            for foreground in text {
                for background in [palette.void, palette.surface1, palette.surface2] {
                    for dark in [false, true] {
                        let a = luminance(dark ? foreground.dark : foreground.light)
                        let b = luminance(dark ? background.dark : background.light)
                        let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
                        #expect(ratio >= 4.5, "\(theme.rawValue) \(dark ? "dark" : "light") contrast: \(ratio)")
                    }
                }
            }
        }
    }
}
