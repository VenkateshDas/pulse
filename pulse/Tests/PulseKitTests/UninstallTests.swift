import Foundation
import Testing

@testable import PulseKit

// MARK: - Helpers

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-uninstall-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeDir(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

private func touch(_ url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data([0x00]).write(to: url)
}

private let spotify = AppIdentity.make(
    bundleID: "com.spotify.client", bundleName: "Spotify", displayName: "Spotify",
    bundleStem: "Spotify")

// MARK: - Classification

@Suite("Uninstall classification")
struct UninstallClassificationTests {
    @Test func exactBundleIDIsSafe() {
        let match = UninstallScanner.classify(name: "com.spotify.client", identity: spotify)
        #expect(match?.grade == .safe)
    }

    @Test func bundleIDPlistIsSafe() {
        let match = UninstallScanner.classify(name: "com.spotify.client.plist", identity: spotify)
        #expect(match?.grade == .safe)
    }

    @Test func groupContainerEmbeddingBundleIDIsSafe() {
        let match = UninstallScanner.classify(name: "group.com.spotify.client", identity: spotify)
        #expect(match?.grade == .safe)
    }

    @Test func vendorPrefixIsCareful() {
        let match = UninstallScanner.classify(name: "com.spotify.helper", identity: spotify)
        #expect(match?.grade == .careful)
    }

    @Test func exactDisplayNameFolderIsCareful() {
        let match = UninstallScanner.classify(name: "Spotify", identity: spotify)
        #expect(match?.grade == .careful)
    }

    @Test func bundleIDMatchIsBoundaryAwareNotSubstring() {
        // The critical guard: uninstalling Chrome must NOT match a *different*
        // app (ChromeCanary) whose bundle ID merely shares a prefix.
        let chrome = AppIdentity.make(
            bundleID: "com.google.Chrome", bundleName: "Google Chrome",
            displayName: "Google Chrome", bundleStem: "Google Chrome")
        // A sibling app shares the vendor, so CAREFUL (needs an explicit tick)
        // is acceptable — but it must never be SAFE / pre-selected.
        let sibling = UninstallScanner.classify(
            name: "com.google.ChromeCanary", identity: chrome)
        #expect(sibling?.grade != .safe)
        // Exact + sub-component matches still resolve SAFE.
        #expect(UninstallScanner.classify(name: "com.google.Chrome", identity: chrome)?.grade == .safe)
        #expect(
            UninstallScanner.classify(name: "com.google.Chrome.helper", identity: chrome)?.grade
                == .safe)
    }

    @Test func bundleIDMustBeAnchoredNotInfixOrSuffix() {
        // An unrelated longer reverse-DNS name that merely CONTAINS the id as a
        // sub-namespace must not be graded SAFE (the residual infix/suffix hole).
        let app = AppIdentity.make(
            bundleID: "foo.bar.baz", bundleName: "Baz", displayName: "Baz", bundleStem: "Baz")
        #expect(UninstallScanner.classify(name: "com.foo.bar.baz", identity: app)?.grade != .safe)
        // Anchored matches still resolve: exact, file, and group container.
        #expect(UninstallScanner.classify(name: "foo.bar.baz", identity: app)?.grade == .safe)
        #expect(UninstallScanner.classify(name: "foo.bar.baz.plist", identity: app)?.grade == .safe)
        #expect(
            UninstallScanner.classify(name: "group.foo.bar.baz", identity: app)?.grade == .safe)
    }

    @Test func vendorMatchIsBoundaryAware() {
        // `com.spotifyx.*` shares no real vendor with `com.spotify.*`.
        let match = UninstallScanner.classify(name: "com.spotifyx.app", identity: spotify)
        #expect(match?.grade != .safe)
        #expect(match?.grade != .careful)
    }

    @Test func weakNameTokenIsReviewNeverSafe() {
        // The Pearcleaner trap: a personal file whose name merely contains the
        // app token must surface as REVIEW, never auto-selectable.
        let match = UninstallScanner.classify(
            name: "Spotify wrapped screenshot.png", identity: spotify)
        #expect(match?.grade == .review)
    }

    @Test func unrelatedNameDoesNotMatch() {
        #expect(UninstallScanner.classify(name: "com.apple.Safari", identity: spotify) == nil)
        #expect(UninstallScanner.classify(name: "Documents", identity: spotify) == nil)
        #expect(UninstallScanner.classify(name: "Google Chrome", identity: spotify) == nil)
    }

    @Test func appleVendorPrefixIsNotMatchedBroadly() {
        // com.apple is denylisted as a vendor prefix — exact IDs still match,
        // but a sibling com.apple.* folder must not be swept in.
        let apple = AppIdentity.make(
            bundleID: "com.apple.Numbers", bundleName: "Numbers", displayName: "Numbers",
            bundleStem: "Numbers")
        #expect(UninstallScanner.classify(name: "com.apple.Pages", identity: apple) == nil)
        #expect(UninstallScanner.classify(name: "com.apple.Numbers", identity: apple)?.grade == .safe)
    }
}

// MARK: - Identity

@Suite("Uninstall identity")
struct UninstallIdentityTests {
    @Test func vendorPrefixIsFirstTwoComponents() {
        #expect(spotify.vendorPrefix == "com.spotify")
    }

    @Test func shortBundleIDHasNoVendorPrefix() {
        let id = AppIdentity.make(
            bundleID: "com.foo", bundleName: "Foo", displayName: nil, bundleStem: "Foo")
        #expect(id.vendorPrefix == nil)
    }

    @Test func tokensSkipShortAndGenericWords() {
        let id = AppIdentity.make(
            bundleID: "com.acme.bigeditor", bundleName: "Big App Editor",
            displayName: "Big App Editor", bundleStem: "Big App Editor")
        // "big"/"app" dropped (too short / stop-word); "editor" kept.
        #expect(id.nameTokens.contains("editor"))
        #expect(!id.nameTokens.contains("app"))
        #expect(!id.nameTokens.contains("big"))
    }
}

// MARK: - Leftover scan

@Suite("Uninstall leftover scan")
struct UninstallLeftoverScanTests {
    @Test func findsResidueAcrossLibraryLocationsByGrade() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let userLib = root.appendingPathComponent("Library")

        // SAFE — bundle-ID-named cache + prefs plist.
        try makeDir(userLib.appendingPathComponent("Caches/com.spotify.client"))
        try touch(userLib.appendingPathComponent("Preferences/com.spotify.client.plist"))
        // CAREFUL — vendor-prefixed app support folder.
        try makeDir(userLib.appendingPathComponent("Application Support/com.spotify.helper"))
        // REVIEW — weak name token only.
        try makeDir(userLib.appendingPathComponent("Logs/Spotify debug notes"))
        // Unrelated — must not appear.
        try makeDir(userLib.appendingPathComponent("Caches/com.apple.Safari"))

        let scanner = UninstallScanner(userLibrary: userLib, systemLibrary: nil, appDirectories: [])
        let items = scanner.scanLeftovers(for: spotify)
        let byGrade = Dictionary(grouping: items, by: \.grade)

        #expect(byGrade[.safe]?.count == 2)
        #expect(byGrade[.careful]?.count == 1)
        #expect(byGrade[.review]?.count == 1)
        #expect(!items.contains { $0.path.contains("com.apple.Safari") })
        // SAFE rows sort before REVIEW.
        #expect(items.first?.grade == .safe)
    }

    @Test func rootOwnedSystemHelpersAreReviewNotSafe() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let userLib = root.appendingPathComponent("Library")
        let sysLib = root.appendingPathComponent("SystemLibrary")

        // Exact bundle-ID match, but in root-owned PrivilegedHelperTools — must
        // not be pre-selected since it can't be staged without admin.
        try touch(sysLib.appendingPathComponent("PrivilegedHelperTools/com.spotify.client"))
        try touch(sysLib.appendingPathComponent("LaunchDaemons/com.spotify.client.plist"))

        let scanner = UninstallScanner(
            userLibrary: userLib, systemLibrary: sysLib, appDirectories: [])
        let items = scanner.scanLeftovers(for: spotify)

        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.grade == .review })
    }

    @Test func anySystemLibraryLeftoverIsReviewNotStageable() throws {
        // Generalized beyond helpers/daemons: a bundle-ID-named dir under any
        // root-owned /Library location must be REVIEW (can't be Vault-staged),
        // not SAFE — otherwise it becomes a perpetually-failed staging target.
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let userLib = root.appendingPathComponent("Library")
        let sysLib = root.appendingPathComponent("SystemLibrary")

        try makeDir(sysLib.appendingPathComponent("Application Support/com.spotify.client"))
        try touch(sysLib.appendingPathComponent("Preferences/com.spotify.client.plist"))

        let scanner = UninstallScanner(
            userLibrary: userLib, systemLibrary: sysLib, appDirectories: [])
        let items = scanner.scanLeftovers(for: spotify)

        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.grade == .review })
    }
}

// MARK: - Orphan scan

@Suite("Uninstall orphan scan")
struct UninstallOrphanScanTests {
    @Test func flagsResidueWhoseBundleIsGone() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let userLib = root.appendingPathComponent("Library")

        try makeDir(userLib.appendingPathComponent("Caches/com.deadapp.gone"))
        try makeDir(userLib.appendingPathComponent("Caches/com.liveapp.present"))
        try makeDir(userLib.appendingPathComponent("Caches/NotABundleID"))

        let scanner = UninstallScanner(userLibrary: userLib, systemLibrary: nil, appDirectories: [])
        let orphans = scanner.scanOrphans { bundleID in bundleID == "com.liveapp.present" }

        #expect(orphans.contains { $0.path.contains("com.deadapp.gone") })
        #expect(!orphans.contains { $0.path.contains("com.liveapp.present") })
        // Non-bundle-ID-shaped names are ignored entirely.
        #expect(!orphans.contains { $0.path.contains("NotABundleID") })
        #expect(orphans.allSatisfy { $0.grade == .careful })
    }

    @Test func bundleIDExtractionRequiresReverseDNSShape() {
        #expect(UninstallScanner.bundleID(fromResidueName: "com.foo.bar") == "com.foo.bar")
        #expect(UninstallScanner.bundleID(fromResidueName: "com.foo.bar.plist") == "com.foo.bar")
        #expect(UninstallScanner.bundleID(fromResidueName: "group.com.foo.bar") == "com.foo.bar")
        #expect(UninstallScanner.bundleID(fromResidueName: "Spotify") == nil)
        #expect(UninstallScanner.bundleID(fromResidueName: "two.parts") == nil)
        // Numeric cache dirs are not bundle IDs — first component must be a TLD.
        #expect(UninstallScanner.bundleID(fromResidueName: "12.34.567") == nil)
    }
}
