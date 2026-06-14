import CoreServices
import Foundation

/// One application discovered on disk, the subject of an uninstall.
public struct InstalledApp: Identifiable, Sendable, Equatable {
    /// The bundle path doubles as a stable identity.
    public var id: String { path }
    public let name: String
    public let bundleID: String
    public let version: String
    public let path: String
    public let sizeBytes: UInt64
    /// Days since the app was last opened (Spotlight `kMDItemLastUsedDate`),
    /// nil when Spotlight has no record.
    public let lastUsedDays: Int?

    public init(
        name: String, bundleID: String, version: String, path: String,
        sizeBytes: UInt64, lastUsedDays: Int?
    ) {
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastUsedDays = lastUsedDays
    }
}

/// Reverse-DNS / display-name identity pulled from a bundle's Info.plist —
/// the basis for every confidence-graded leftover match.
public struct AppIdentity: Sendable, Equatable {
    public let bundleID: String
    /// Vendor reverse-DNS prefix (`com.spotify.client` → `com.spotify`),
    /// nil when the bundle ID has fewer than three components.
    public let vendorPrefix: String?
    /// Distinct display names (CFBundleName / CFBundleDisplayName / bundle stem).
    public let displayNames: [String]
    /// Lowercased word tokens (≥4 chars) for the weak REVIEW tier.
    public let nameTokens: [String]

    public init(
        bundleID: String, vendorPrefix: String?, displayNames: [String], nameTokens: [String]
    ) {
        self.bundleID = bundleID
        self.vendorPrefix = vendorPrefix
        self.displayNames = displayNames
        self.nameTokens = nameTokens
    }

    /// Builds an identity from a bundle's Info.plist values plus its file name.
    public static func make(
        bundleID: String, bundleName: String?, displayName: String?, bundleStem: String
    ) -> AppIdentity {
        let id = bundleID.lowercased()
        let components = id.split(separator: ".")
        let vendor = components.count >= 3 ? components.prefix(2).joined(separator: ".") : nil

        var names: [String] = []
        for candidate in [displayName, bundleName, bundleStem] {
            guard let candidate, !candidate.isEmpty, !names.contains(candidate) else { continue }
            names.append(candidate)
        }

        // Tokens: distinct ≥4-char words across the display names, minus a few
        // generic stop-words that would over-match the REVIEW tier.
        let stop: Set<String> = ["app", "data", "cache", "helper", "agent", "the"]
        var tokens: [String] = []
        for name in names {
            for raw in name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let token = String(raw)
                if token.count >= 4, !stop.contains(token), !tokens.contains(token) {
                    tokens.append(token)
                }
            }
        }
        return AppIdentity(
            bundleID: id, vendorPrefix: vendor, displayNames: names, nameTokens: tokens)
    }
}

/// Confidence-graded leftover scanner — the heart of §3.14. Pure
/// FileManager/Bundle/Spotlight; no subprocess ever. Aggressive about
/// *finding* residue, never destructive: every grade maps to the same
/// safety UX as Smart Clean, and the caller stages everything to the Vault.
public struct UninstallScanner: Sendable {
    public let userLibrary: URL
    public let systemLibrary: URL?
    public let appDirectories: [URL]
    public let now: Date

    /// Vendor prefixes too broad to match on (would sweep dozens of
    /// system folders) — exact bundle-ID matches still apply.
    static let vendorDenylist: Set<String> = ["com.apple"]

    public init(
        userLibrary: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library"),
        systemLibrary: URL? = URL(fileURLWithPath: "/Library"),
        appDirectories: [URL] = UninstallScanner.defaultAppDirectories,
        now: Date = .now
    ) {
        self.userLibrary = userLibrary
        self.systemLibrary = systemLibrary
        self.appDirectories = appDirectories
        self.now = now
    }

    public static let defaultAppDirectories: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
    }()

    // MARK: - Residue locations

    /// (relative dir, human category) of every known macOS residue location,
    /// resolved against both `~/Library` and `/Library`.
    static let residueDirs: [(rel: String, category: String)] = [
        ("Application Support", "Application Support"),
        ("Caches", "Caches"),
        ("HTTPStorages", "HTTP storage"),
        ("Logs", "Logs"),
        ("Preferences", "Preferences"),
        ("Saved Application State", "Saved state"),
        ("Containers", "Container"),
        ("Group Containers", "Group container"),
        ("WebKit", "WebKit data"),
        ("Cookies", "Cookies"),
        ("Application Scripts", "App scripts"),
        ("LaunchAgents", "Launch agent"),
    ]

    /// System-`/Library`-only residue: privileged helpers and daemons.
    static let systemOnlyResidueDirs: [(rel: String, category: String)] = [
        ("LaunchDaemons", "Launch daemon"),
        ("PrivilegedHelperTools", "Privileged helper"),
    ]

    /// Categories that live in root-owned `/Library` — removable only with
    /// admin rights, so they're always surfaced REVIEW (never pre-selected).
    static let systemOnlyCategories: Set<String> = ["Launch daemon", "Privileged helper"]

    // MARK: - Installed apps

    /// Every app under the scanned application directories, newest-used first.
    public func installedApps() -> [InstalledApp] {
        var seen: Set<String> = []
        var out: [InstalledApp] = []
        for dir in appDirectories {
            guard
                let entries = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])
            else { continue }
            for entry in entries where entry.pathExtension == "app" {
                guard !seen.contains(entry.path) else { continue }
                guard let info = Self.infoPlist(forApp: entry) else { continue }
                let bundleID = info["CFBundleIdentifier"] as? String ?? ""
                guard !bundleID.isEmpty else { continue }
                seen.insert(entry.path)
                let name =
                    (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? entry.deletingPathExtension().lastPathComponent
                let version =
                    (info["CFBundleShortVersionString"] as? String)
                    ?? (info["CFBundleVersion"] as? String) ?? "—"
                out.append(
                    InstalledApp(
                        name: name, bundleID: bundleID, version: version,
                        path: entry.path,
                        sizeBytes: SmartScanner.directorySize(entry),
                        lastUsedDays: lastUsedDays(of: entry)))
            }
        }
        return out.sorted {
            // Recently used first; unknown-last-used sinks to the bottom.
            ($0.lastUsedDays ?? Int.max) < ($1.lastUsedDays ?? Int.max)
        }
    }

    /// Reads identity from a dropped or selected `.app` bundle.
    public func identity(forApp appURL: URL) -> AppIdentity? {
        guard let info = Self.infoPlist(forApp: appURL),
            let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty
        else { return nil }
        return AppIdentity.make(
            bundleID: bundleID,
            bundleName: info["CFBundleName"] as? String,
            displayName: info["CFBundleDisplayName"] as? String,
            bundleStem: appURL.deletingPathExtension().lastPathComponent)
    }

    /// Builds the `InstalledApp` record for an arbitrary `.app` (drop path).
    public func describeApp(at appURL: URL) -> InstalledApp? {
        guard let info = Self.infoPlist(forApp: appURL),
            let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty
        else { return nil }
        let name =
            (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let version =
            (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String) ?? "—"
        return InstalledApp(
            name: name, bundleID: bundleID, version: version, path: appURL.path,
            sizeBytes: SmartScanner.directorySize(appURL),
            lastUsedDays: lastUsedDays(of: appURL))
    }

    // MARK: - Leftover scan

    /// Confidence-graded leftovers for one app, sorted SAFE → REVIEW then by
    /// size. Each row carries an explainable reason and a Vault-ready path.
    public func scanLeftovers(for identity: AppIdentity) -> [CleanItem] {
        var out: [CleanItem] = []
        var seenPaths: Set<String> = []

        for (root, dirs) in residueRoots() {
            for spec in dirs {
                let dir = root.appendingPathComponent(spec.rel)
                guard let children = Self.shallowChildren(of: dir) else { continue }
                for child in children {
                    let name = child.lastPathComponent
                    guard let match = Self.classify(name: name, identity: identity) else { continue }
                    guard !seenPaths.contains(child.path) else { continue }
                    seenPaths.insert(child.path)
                    // Root-owned system helpers/daemons can't be staged without
                    // admin, so never pre-select them — surface as REVIEW
                    // (awareness) instead of dishonestly claiming SAFE.
                    let systemOwned = Self.systemOnlyCategories.contains(spec.category)
                    let grade = systemOwned ? .review : match.grade
                    let detail =
                        systemOwned
                        ? match.reason + " — needs admin to remove, review manually"
                        : match.reason
                    out.append(
                        CleanItem(
                            category: spec.category,
                            label: name,
                            detail: detail,
                            path: child.path,
                            sizeBytes: Self.itemSize(child),
                            idleDays: idleDays(of: child),
                            grade: grade))
                }
            }
        }

        out += receipts(for: identity, seen: &seenPaths)

        out.sort {
            $0.grade.rank != $1.grade.rank
                ? $0.grade.rank < $1.grade.rank
                : $0.sizeBytes > $1.sizeBytes
        }
        // Cap the weak REVIEW tier so a noisy name token can't flood the list.
        let review = out.filter { $0.grade == .review }.prefix(25)
        let strong = out.filter { $0.grade != .review }
        return strong + Array(review)
    }

    // MARK: - Orphan scan

    /// Residue whose owning bundle ID no longer resolves to an installed app.
    /// Graded CAREFUL — high-signal debris, but never pre-selected since no
    /// app icon vouches for it. `resolver` returns true when the bundle ID
    /// is still installed (injected for tests).
    public func scanOrphans(resolver: (String) -> Bool) -> [CleanItem] {
        var out: [CleanItem] = []
        var seenPaths: Set<String> = []
        var verdictCache: [String: Bool] = [:]

        for (root, dirs) in residueRoots() {
            for spec in dirs {
                let dir = root.appendingPathComponent(spec.rel)
                guard let children = Self.shallowChildren(of: dir) else { continue }
                for child in children {
                    let name = child.lastPathComponent
                    guard let bundleID = Self.bundleID(fromResidueName: name) else { continue }
                    guard !seenPaths.contains(child.path) else { continue }
                    let installed: Bool
                    if let cached = verdictCache[bundleID] {
                        installed = cached
                    } else {
                        installed = resolver(bundleID)
                        verdictCache[bundleID] = installed
                    }
                    guard !installed else { continue }
                    seenPaths.insert(child.path)
                    out.append(
                        CleanItem(
                            category: spec.category,
                            label: name,
                            detail: "owning app \(bundleID) is not installed",
                            path: child.path,
                            sizeBytes: Self.itemSize(child),
                            idleDays: idleDays(of: child),
                            grade: .careful))
                }
            }
        }
        out.sort { $0.sizeBytes > $1.sizeBytes }
        return out
    }

    // MARK: - Classification

    /// Maps a residue file/folder name onto a safety grade by match confidence.
    /// Returns nil for names that don't relate to the app at all — the guard
    /// against the substring-sweep false positives competitors ship.
    static func classify(name: String, identity: AppIdentity) -> (grade: SafetyGrade, reason: String)? {
        let stem = (name as NSString).deletingPathExtension.lowercased()
        let lower = name.lowercased()
        let bid = identity.bundleID

        // SAFE — the bundle ID appears as a contiguous run of dot components.
        // Boundary-aware so uninstalling `com.google.Chrome` never matches a
        // *different* app's `com.google.ChromeCanary` data (covers exact files,
        // `<id>.plist`, `<id>.savedState`, and `group.<id>` containers).
        if Self.componentRun(name, contains: bid) {
            return (.safe, "matches bundle ID \(bid)")
        }

        // CAREFUL — vendor reverse-DNS prefix (`com.spotify.*`), same
        // component-boundary rule so `com.spotifyx.*` is not swept in.
        if let vendor = identity.vendorPrefix, !vendorDenylist.contains(vendor),
            Self.componentRun(name, contains: vendor)
        {
            return (.careful, "matches vendor prefix \(vendor)")
        }

        // CAREFUL — folder named exactly the app/display name.
        for display in identity.displayNames where stem == display.lowercased() {
            return (.careful, "folder named “\(display)”")
        }

        // REVIEW — weak name-token substring. Surfaced for awareness only;
        // never bulk-selectable. This is the tier that catches the
        // "Chrome → ChromeAI screenshot" trap and refuses to auto-act.
        for token in identity.nameTokens where lower.contains(token) {
            return (.review, "name contains “\(token)” — verify before removing")
        }
        return nil
    }

    // MARK: - Receipts

    /// Install receipts (`/var/db/receipts/<id>.{plist,bom}`), surfaced
    /// read-only for awareness — root-owned, so REVIEW (never bulk-selected).
    private func receipts(for identity: AppIdentity, seen: inout Set<String>) -> [CleanItem] {
        let receiptsDir = URL(fileURLWithPath: "/var/db/receipts")
        var out: [CleanItem] = []
        for ext in ["plist", "bom"] {
            let url = receiptsDir.appendingPathComponent("\(identity.bundleID).\(ext)")
            guard FileManager.default.fileExists(atPath: url.path), !seen.contains(url.path)
            else { continue }
            seen.insert(url.path)
            out.append(
                CleanItem(
                    category: "Install receipt",
                    label: url.lastPathComponent,
                    detail: "install record — read-only, kept for awareness",
                    path: url.path,
                    sizeBytes: Self.itemSize(url),
                    idleDays: idleDays(of: url),
                    grade: .review))
        }
        return out
    }

    // MARK: - Helpers

    private func residueRoots() -> [(root: URL, dirs: [(rel: String, category: String)])] {
        var roots: [(URL, [(rel: String, category: String)])] = [(userLibrary, Self.residueDirs)]
        if let systemLibrary {
            roots.append((systemLibrary, Self.residueDirs + Self.systemOnlyResidueDirs))
        }
        return roots
    }

    /// Top-level children of a residue dir, or nil when it doesn't exist.
    /// Shallow by design — the scan stays a bounded sweep, never a disk walk.
    static func shallowChildren(of dir: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [])
    }

    /// True when `query`'s dot-delimited components appear as a contiguous
    /// run inside `name`'s components — the boundary-aware test that stops
    /// `com.google.chrome` from matching `com.google.chromecanary`.
    static func componentRun(_ name: String, contains query: String) -> Bool {
        let comps = name.lowercased().split(separator: ".").map(String.init)
        let q = query.lowercased().split(separator: ".").map(String.init)
        guard !q.isEmpty, comps.count >= q.count else { return false }
        for start in 0...(comps.count - q.count)
        where Array(comps[start..<start + q.count]) == q {
            return true
        }
        return false
    }

    /// Extracts a reverse-DNS bundle ID from a residue name, or nil when the
    /// name isn't a bundle-ID-shaped string (≥3 dot components, ASCII).
    static func bundleID(fromResidueName name: String) -> String? {
        // Strip only real residue extensions — a bundle ID's last component
        // (`com.foo.bar`) is not a file extension and must be kept.
        let knownExtensions: Set<String> = ["plist", "bom", "savedState"]
        let ext = (name as NSString).pathExtension
        let stem =
            knownExtensions.contains(ext) ? (name as NSString).deletingPathExtension : name
        // Strip an Apple group-container prefix so `group.com.x.y` resolves to
        // the underlying app bundle ID.
        let candidate = stem.hasPrefix("group.") ? String(stem.dropFirst("group.".count)) : stem
        let parts = candidate.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        for part in parts {
            guard part.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
                !part.isEmpty
            else { return nil }
        }
        // First component must look like a TLD-ish token (com/org/io/net/...):
        // 2–5 chars, all letters — rejects numeric cache dirs like `12.34.567`.
        guard let first = parts.first, first.count >= 2, first.count <= 5,
            first.allSatisfy(\.isLetter)
        else { return nil }
        return candidate
    }

    static func infoPlist(forApp appURL: URL) -> [String: Any]? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist
    }

    /// Size of a file or directory tree (matches what removal frees).
    static func itemSize(_ url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true {
            return UInt64(values.totalFileAllocatedSize ?? 0)
        }
        return SmartScanner.directorySize(url)
    }

    private func idleDays(of url: URL) -> Int? {
        guard
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        else { return nil }
        return max(0, Int(now.timeIntervalSince(modified) / 86400))
    }

    /// Days since the bundle was last opened, via Spotlight metadata. Best
    /// effort — returns nil when Spotlight has no record (an API call, not a
    /// subprocess).
    private func lastUsedDays(of url: URL) -> Int? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
            let value = MDItemCopyAttribute(item, kMDItemLastUsedDate),
            let date = value as? Date
        else { return nil }
        return max(0, Int(now.timeIntervalSince(date) / 86400))
    }
}
