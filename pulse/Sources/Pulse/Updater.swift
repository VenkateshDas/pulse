import AppKit
import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// Update checker for Pulse.
///
/// Two mechanisms, chosen at compile time:
///
///   • **Sparkle** (when the SPM dependency is linked) — full in-place auto
///     update: download, verify EdDSA signature, install, relaunch. Requires a
///     Developer ID signed + notarized build and an `SUFeedURL` appcast. Enable
///     by uncommenting the Sparkle dependency in Package.swift.
///
///   • **DIY GitHub check** (default, no signing required) — polls the repo's
///     `releases/latest` endpoint, compares the tag to the running bundle
///     version, and surfaces a "download" nudge. It can't replace a running
///     ad-hoc bundle in place, so it points the user at the DMG; they install
///     manually. This is what ships today.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    /// GitHub repository that publishes Pulse releases (`owner/name`).
    private let repo = "VenkateshDas/pulse"

    /// Minimum gap between automatic (non-user-initiated) checks, so opening the
    /// popover repeatedly doesn't burn the unauthenticated GitHub rate limit.
    private let autoCheckInterval: TimeInterval = 6 * 3600

    struct Release: Equatable {
        let version: String
        let pageURL: URL
        /// The `.dmg` asset, when the release has one attached.
        let downloadURL: URL?
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed
    }

    private(set) var status: Status = .idle
    private var lastChecked: Date?

    #if canImport(Sparkle)
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    /// True when Sparkle is linked (in-place updates). DIY check always runs
    /// otherwise, so the menu item is always shown.
    var usesSparkle: Bool {
        #if canImport(Sparkle)
        return true
        #else
        return false
        #endif
    }

    /// The running app's marketing version (`CFBundleShortVersionString`).
    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    var availableRelease: Release? {
        if case .available(let release) = status { return release }
        return nil
    }

    /// Kick a check. `userInitiated` checks bypass the throttle and surface
    /// failures / "up to date"; background checks stay quiet.
    func checkForUpdates(userInitiated: Bool = false) {
        #if canImport(Sparkle)
        controller.updater.checkForUpdates()
        #else
        // Skip silent background checks in bare SwiftPM runs (no bundle version
        // to compare against) — but still honor an explicit user request.
        if !userInitiated && Bundle.main.bundleIdentifier == nil { return }
        diyCheck(userInitiated: userInitiated)
        #endif
    }

    /// Open the latest release's DMG (or its release page) in the browser.
    func openLatestDownload() {
        guard let release = availableRelease else { return }
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
    }

    // MARK: - DIY GitHub check

    private func diyCheck(userInitiated: Bool) {
        if case .checking = status { return }
        if !userInitiated, let last = lastChecked,
           Date().timeIntervalSince(last) < autoCheckInterval { return }

        status = .checking
        Task {
            do {
                let release = try await fetchLatest()
                lastChecked = Date()
                if let release, Self.isNewer(release.version, than: currentVersion) {
                    status = .available(release)
                } else {
                    status = .upToDate
                }
            } catch {
                // Stay quiet for background checks; only flag explicit requests.
                status = userInitiated ? .failed : .idle
            }
        }
    }

    /// Fetches the newest published release. Uses the *list* endpoint (not
    /// `releases/latest`) because Pulse ships pre-releases (`-beta.N`), and
    /// `releases/latest` only returns full releases — it 404s while every tag is
    /// a pre-release, so beta users would never be notified. Drafts are skipped;
    /// the newest by version wins.
    private func fetchLatest() async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Pulse-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        let releases = try JSONDecoder().decode([GHRelease].self, from: data)
        let newest = releases
            .filter { !$0.draft }
            .max { Self.isNewer(Self.normalize($1.tagName), than: Self.normalize($0.tagName)) }
        guard let gh = newest, let page = URL(string: gh.htmlURL) else { return nil }
        let dmg = gh.assets
            .first { $0.name.lowercased().hasSuffix(".dmg") }
            .flatMap { URL(string: $0.browserDownloadURL) }
        return Release(version: Self.normalize(gh.tagName), pageURL: page, downloadURL: dmg)
    }

    // MARK: - Version comparison

    /// Strip a leading `v` (e.g. `v0.2.0` → `0.2.0`).
    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Semver-ish compare: numeric core dotted components, then prerelease rule
    /// (a release outranks the same core as a prerelease, e.g. `1.0.0` > `1.0.0-beta.1`).
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        compare(lhs, rhs) > 0
    }

    private static func compare(_ a: String, _ b: String) -> Int {
        func split(_ s: String) -> (core: [Int], pre: String) {
            let halves = s.split(separator: "-", maxSplits: 1).map(String.init)
            let core = halves[0].split(separator: ".").map { Int($0) ?? 0 }
            return (core, halves.count > 1 ? halves[1] : "")
        }
        let (ca, pa) = split(a)
        let (cb, pb) = split(b)
        for i in 0 ..< max(ca.count, cb.count) {
            let x = i < ca.count ? ca[i] : 0
            let y = i < cb.count ? cb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        if pa.isEmpty && pb.isEmpty { return 0 }
        if pa.isEmpty { return 1 }   // lhs is a full release, rhs a prerelease
        if pb.isEmpty { return -1 }
        return comparePrerelease(pa, pb)
    }

    /// Compare dot-separated prerelease identifiers (`beta.10` > `beta.9`):
    /// numeric identifiers compare numerically, everything else lexically.
    private static func comparePrerelease(_ a: String, _ b: String) -> Int {
        let ia = a.split(separator: ".").map(String.init)
        let ib = b.split(separator: ".").map(String.init)
        for i in 0 ..< max(ia.count, ib.count) {
            let x = i < ia.count ? ia[i] : ""
            let y = i < ib.count ? ib[i] : ""
            if x == y { continue }
            if let nx = Int(x), let ny = Int(y) { return nx < ny ? -1 : 1 }
            return x < y ? -1 : 1
        }
        return 0
    }
}

// MARK: - GitHub release JSON

private struct GHRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }
}
