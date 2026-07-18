import AppKit

/// Draws the menu-bar label (icon + value per selected stat) into a single
/// NSImage.
///
/// Why not SwiftUI: MenuBarExtra flattens its label to one image + one
/// string, and SF Symbols interpolated into a Text render with sloppy
/// baselines and spacing. Drawing the label ourselves gives exact baseline
/// alignment and per-group spacing.
///
/// Rendering has two modes:
/// - Every stat nominal (the common case): one template image; `isTemplate`
///   hands tinting to macOS — correct in dark/light menu bars and when
///   highlighted on click, exactly like native menu extras.
/// - Any stat charging/warning/critical: non-template image so the alerted
///   group can carry color (green/orange/red), like the native battery extra
///   when red. Neutral groups use `labelColor`, which resolves against the
///   current appearance. Trade-off: no white highlight tint while colored.
@MainActor
enum MenuBarLabelRenderer {
    /// Native menu-bar look: SF Pro at menu-bar size with tabular digits.
    /// Value strings pad with figure spaces (digit-width), so no jiggle.
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private static let iconConfig = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
    /// Gap between stat groups / between an icon and its value.
    private static let groupGap: CGFloat = 9
    private static let iconGap: CGFloat = 3.5
    private static let height: CGFloat = 17

    private static func tint(for severity: MenuBarSeverity) -> NSColor? {
        switch severity {
        case .nominal: nil
        case .charging: .systemGreen
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }

    static func image(
        stats: [MenuBarStat], readings: [MenuBarStat: MenuBarReading], flashSymbol: String?
    ) -> NSImage {
        var groups:
            [(symbol: String, label: String, text: NSString, textSize: CGSize, tint: NSColor?)] = []
        let measureAttrs: [NSAttributedString.Key: Any] = [.font: font]
        for (index, stat) in stats.enumerated() {
            let reading = readings[stat]
            // Action feedback: MenuBarFlash briefly swaps the leading icon to
            // the triggered action's symbol, then reverts.
            let symbol =
                index == 0
                ? (flashSymbol ?? reading?.symbol ?? stat.symbol)
                : (reading?.symbol ?? stat.symbol)
            let text = stat.text(for: reading?.value) as NSString
            groups.append(
                (symbol, stat.label, text, text.size(withAttributes: measureAttrs),
                 tint(for: reading?.severity ?? .nominal)))
        }
        let colored = groups.contains { $0.tint != nil }

        var icons: [NSImage?] = []
        var width: CGFloat = 0
        for (index, group) in groups.enumerated() {
            // Colored mode paints glyphs via palette configuration; template
            // mode leaves them black and lets macOS tint the whole image.
            var config = iconConfig
            if colored {
                config = config.applying(
                    .init(paletteColors: [group.tint ?? .labelColor]))
            }
            let icon = NSImage(
                systemSymbolName: group.symbol, accessibilityDescription: group.label)?
                .withSymbolConfiguration(config)
            icons.append(icon)
            if index > 0 { width += groupGap }
            if let icon { width += icon.size.width + iconGap }
            width += group.textSize.width
        }
        width = ceil(max(width, 1))

        let image = NSImage(
            size: NSSize(width: width, height: height), flipped: false
        ) { _ in
            var x: CGFloat = 0
            for (index, group) in groups.enumerated() {
                if index > 0 { x += groupGap }
                if let icon = icons[index] {
                    let iconY = ((height - icon.size.height) / 2).rounded()
                    // Template mode: slightly dimmer than the digits (template
                    // = alpha only). Colored mode: palette color as-is.
                    icon.draw(
                        in: NSRect(origin: NSPoint(x: x, y: iconY), size: icon.size),
                        from: .zero, operation: .sourceOver, fraction: colored ? 1.0 : 0.9)
                    x += icon.size.width + iconGap
                }
                let textColor: NSColor =
                    colored ? (group.tint ?? .labelColor) : .black
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: textColor,
                ]
                let textY = ((height - group.textSize.height) / 2).rounded()
                group.text.draw(at: NSPoint(x: x, y: textY), withAttributes: attrs)
                x += group.textSize.width
            }
            return true
        }
        image.isTemplate = !colored
        return image
    }
}
