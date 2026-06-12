import Foundation

/// Compact, Finder-style (decimal) byte formatting: "12.4 GB", "512 MB".
public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func string(_ bytes: UInt64) -> String {
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) B"
        }
        let digits = value < 10 ? 1 : (value < 100 ? 1 : 0)
        return String(format: "%.\(digits)f %@", value, units[unitIndex])
    }
}
