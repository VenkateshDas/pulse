import AppKit

/// Fast thread-safe cache for file and directory icons.
/// Avoids synchronous LaunchServices / disk I/O on main-thread SwiftUI rendering.
@MainActor
enum FileIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 500
        return c
    }()

    public static let folderIcon: NSImage = {
        NSWorkspace.shared.icon(forFile: "/Applications")
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

        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: nsPath)
        if !ext.isEmpty && ext != "app" {
            cache.setObject(icon, forKey: extKey)
        }
        return icon
    }
}
