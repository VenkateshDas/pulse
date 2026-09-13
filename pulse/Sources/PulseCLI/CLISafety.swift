import AppKit
import PulseKit

public enum CLISafety {
    public static func contains(_ parent: String, _ child: String) -> Bool { child == parent || child.hasPrefix(parent + "/") }
    public static func refusal(path: String, home: String, excluded: Set<String> = [], activePaths: [String] = []) -> String? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().path
        guard resolved == url.path else { return "Symlink paths are not eligible" }
        guard contains(home, resolved), resolved != home else { return "Outside a specific user-home target" }
        let protected = [".Trash", ".codex", ".claude", ".cursor", ".gemini", ".ssh", ".gnupg", "Library/Application Support/Pulse"]
        for rel in protected {
            let root = home + "/" + rel
            if contains(root, resolved) || contains(resolved, root) { return "Protected user data or Pulse state" }
        }
        for root in excluded where contains(root, resolved) || contains(resolved, root) { return "Protected in Pulse settings" }
        if activePaths.contains(where: { contains(resolved, $0) }) { return "Open files or running application inside target" }
        if BundleGuard.isProtected(bundleID: url.lastPathComponent) { return "Protected system application cache" }
        return nil
    }
    public static func exactApp(_ query: String, apps: [InstalledApp]) throws -> InstalledApp {
        let expanded = NSString(string: query).expandingTildeInPath
        let matches = apps.filter { $0.path == expanded || $0.name.caseInsensitiveCompare(query) == .orderedSame || $0.bundleID.caseInsensitiveCompare(query) == .orderedSame }
        guard matches.count == 1 else { throw CLIUsageError(matches.isEmpty ? "No exact app match; use uninstall --list" : "Ambiguous app; use its full path") }
        return matches[0]
    }
    @MainActor public static func activePaths() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
    }
}
