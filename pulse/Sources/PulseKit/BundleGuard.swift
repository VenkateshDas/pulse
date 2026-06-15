import Foundation

/// System-critical bundle allowlist to protect essential macOS and core apps
/// from being flagged or removed during cleanup operations.
public enum BundleGuard {
    private static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.controlcenter", // and its variants
        "com.apple.Spotlight",
        "com.apple.loginwindow",
        "com.apple.Preview",
        "com.apple.TextEdit",
        "com.apple.Notes",
        "com.apple.reminders",
        "com.apple.iCal",
        "com.apple.AddressBook",
        "com.apple.Photos",
        "com.apple.AppStore",
        "com.apple.calculator",
        "com.apple.ScreenSharing",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.apple.DiskUtility"
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
