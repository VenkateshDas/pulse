import AppKit

/// Draws the menu-bar label (icon + value per selected stat) into a single
/// template NSImage.
///
/// Why not SwiftUI: MenuBarExtra flattens its label to one image + one
/// string, and SF Symbols interpolated into a Text render with sloppy
/// baselines and spacing. Drawing the label ourselves gives exact baseline
/// alignment and per-group spacing, and `isTemplate` hands tinting to macOS —
/// correct in dark/light menu bars and when highlighted on click, exactly
/// like native menu extras.
@MainActor
enum MenuBarLabelRenderer {
    /// Fully monospaced (not just digits): the value strings are padded to a
    /// fixed width, and spaces must match digit width or the item jiggles.
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private static let iconConfig = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
    /// Gap between stat groups / between an icon and its value.
    private static let groupGap: CGFloat = 9
    private static let iconGap: CGFloat = 3.5
    private static let height: CGFloat = 17

    static func image(
        stats: [MenuBarStat], values: [MenuBarStat: Int], flashSymbol: String?
    ) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.black,
        ]
        var groups: [(icon: NSImage?, text: NSString, textSize: CGSize)] = []
        for (index, stat) in stats.enumerated() {
            // Action feedback: MenuBarFlash briefly swaps the leading icon to
            // the triggered action's symbol, then reverts.
            let symbolName = index == 0 ? (flashSymbol ?? stat.symbol) : stat.symbol
            let icon = NSImage(
                systemSymbolName: symbolName, accessibilityDescription: stat.label)?
                .withSymbolConfiguration(iconConfig)
            let text = stat.text(for: values[stat]) as NSString
            groups.append((icon, text, text.size(withAttributes: attrs)))
        }

        var width: CGFloat = 0
        for (index, group) in groups.enumerated() {
            if index > 0 { width += groupGap }
            if let icon = group.icon { width += icon.size.width + iconGap }
            width += group.textSize.width
        }
        width = ceil(max(width, 1))

        let image = NSImage(
            size: NSSize(width: width, height: height), flipped: false
        ) { _ in
            var x: CGFloat = 0
            for (index, group) in groups.enumerated() {
                if index > 0 { x += groupGap }
                if let icon = group.icon {
                    let iconY = ((height - icon.size.height) / 2).rounded()
                    // Slightly dimmer than the digits (template = alpha only).
                    icon.draw(
                        in: NSRect(origin: NSPoint(x: x, y: iconY), size: icon.size),
                        from: .zero, operation: .sourceOver, fraction: 0.9)
                    x += icon.size.width + iconGap
                }
                let textY = ((height - group.textSize.height) / 2).rounded()
                group.text.draw(at: NSPoint(x: x, y: textY), withAttributes: attrs)
                x += group.textSize.width
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
