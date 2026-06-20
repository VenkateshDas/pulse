import Foundation

/// System-critical bundle allowlist to protect essential macOS and core apps
/// from being flagged or removed during cleanup operations.
public enum BundleGuard {
    // All entries MUST be lowercase — isProtected lowercases the input
    // before checking this set, so mixed-case entries silently fail.
    private static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.safari",
        "com.apple.mail",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.controlcenter",
        "com.apple.spotlight",
        "com.apple.loginwindow",
        "com.apple.preview",
        "com.apple.textedit",
        "com.apple.notes",
        "com.apple.reminders",
        "com.apple.ical",
        "com.apple.addressbook",
        "com.apple.photos",
        "com.apple.appstore",
        "com.apple.calculator",
        "com.apple.screensharing",
        "com.apple.activitymonitor",
        "com.apple.console",
        "com.apple.diskutility"
    ]

    /// Checks if a bundle ID is explicitly protected.
    public static func isProtected(bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        if protectedBundleIDs.contains(id) {
            return true
        }
        if id.hasPrefix("com.apple.controlcenter") {
            return true
        }
        return false
    }
}
