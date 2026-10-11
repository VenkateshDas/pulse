import AppKit
import SwiftUI

/// Fast thread-safe cache for file and directory icons.
/// Avoids synchronous LaunchServices / disk I/O on main-thread SwiftUI rendering.
@MainActor
enum FileIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        c.totalCostLimit = 2 * 1024 * 1024
        return c
    }()

    public static let folderIcon: NSImage = {
        thumbnail(NSWorkspace.shared.icon(forFile: "/Applications"))
    }()

    public static func icon(forPath path: String, isDirectory: Bool = false) -> NSImage {
        let nsPath = path as NSString
        if let cached = cache.object(forKey: nsPath) {
            return cached
        }

        let ext = nsPath.pathExtension.lowercased()
        if isDirectory && ext.isEmpty {
            return folderIcon
        }

        // Cache common file extensions
        let extKey = "ext:\(ext)" as NSString
        if !ext.isEmpty, ext != "app", let cachedExt = cache.object(forKey: extKey) {
            return cachedExt
        }

        let icon = thumbnail(NSWorkspace.shared.icon(forFile: path))
        cache.setObject(icon, forKey: nsPath, cost: 64 * 64 * 4)
        if !ext.isEmpty && ext != "app" {
            cache.setObject(icon, forKey: extKey, cost: 64 * 64 * 4)
        }
        return icon
    }

    /// Rendering must not wait for LaunchServices or icon rasterisation.
    static func loadIcon(forPath path: String,
                         loader: @escaping @Sendable (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }) async -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = await Task.detached(priority: .utility) {
            thumbnail(loader(path))
        }.value
        cache.setObject(image, forKey: path as NSString, cost: 64 * 64 * 4)
        return image
    }

    /// Retain only the 2× raster needed for a 32pt list icon. App icons can
    /// otherwise retain much larger representations after a page is closed.
    nonisolated private static func thumbnail(_ source: NSImage) -> NSImage {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero,
                    operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = NSSize(width: 32, height: 32)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

}

/// Keep the resolved image local to its row; hover and sampling never reload it.
struct FileIconView: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable() }
            else { Image(systemName: "doc").resizable().scaledToFit() }
        }
        .accessibilityHidden(true)
        .task(id: path) {
            image = nil
            let loaded = await FileIconCache.loadIcon(forPath: path)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
