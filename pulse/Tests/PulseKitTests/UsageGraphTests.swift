import Foundation
import Testing

@testable import PulseKit

@Suite("UsageGraphScanner")
struct UsageGraphTests {
    /// Resolved via `realpath` (no `/var` → `/private/var` symlink —
    /// `resolvingSymlinksInPath()` doesn't collapse this one) so paths built
    /// here match what `FileManager.contentsOfDirectory` hands back from a
    /// real listing.
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageGraphTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let real = realpath(dir.path, nil) else { return dir }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real))
    }

    // MARK: Text refs

    @Test func textRefFindsPathInDotfile() async throws {
        let home = tempDir()
        let target = home.appendingPathComponent("dev-tools/miniforge3")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let zshrc = home.appendingPathComponent(".zshrc")
        try "export PATH=\"\(target.path)/bin:$PATH\"\n".write(to: zshrc, atomically: true, encoding: .utf8)

        let scanner = UsageGraphScanner(
            cache: UsageIndexCache(directory: tempDir()),
            home: home.path,
            brewPrefixes: [],
            textRefFiles: ["~/.zshrc"],
            plistDirs: [],
            appDirectories: [],
            binDirectories: [],
            symlinkRoots: [])

        let edges = await scanner.referrers(for: target)
        #expect(edges.count == 1)
        #expect(edges.first?.signal == .textRef)
        #expect(edges.first?.detail == ".zshrc:1")
    }

    @Test func textRefIgnoresUnrelatedLines() async throws {
        let home = tempDir()
        let target = home.appendingPathComponent("dev-tools/miniforge3")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let zshrc = home.appendingPathComponent(".zshrc")
        try "alias ll='ls -la'\nexport EDITOR=vim\n".write(to: zshrc, atomically: true, encoding: .utf8)

        let scanner = UsageGraphScanner(
            cache: UsageIndexCache(directory: tempDir()),
            home: home.path,
            brewPrefixes: [],
            textRefFiles: ["~/.zshrc"],
            plistDirs: [], appDirectories: [], binDirectories: [], symlinkRoots: [])

        let edges = await scanner.referrers(for: target)
        #expect(edges.isEmpty)
    }

    // MARK: Symlinks

    @Test func symlinkPointingIntoTargetIsFound() async throws {
        let root = tempDir()
        let target = root.appendingPathComponent("Cellar/miniforge/25.0")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let optDir = root.appendingPathComponent("opt")
        try FileManager.default.createDirectory(at: optDir, withIntermediateDirectories: true)
        let link = optDir.appendingPathComponent("miniforge")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let scanner = UsageGraphScanner(
            cache: UsageIndexCache(directory: tempDir()),
            home: root.path,
            brewPrefixes: [],
            textRefFiles: [], plistDirs: [], appDirectories: [], binDirectories: [],
            symlinkRoots: [optDir.path])

        let edges = await scanner.referrers(for: target)
        #expect(edges.count == 1)
        #expect(edges.first?.signal == .symlink)
        #expect(edges.first?.source.path == link.path)
    }

    @Test func symlinkNotPointingIntoTargetIsIgnored() async throws {
        let root = tempDir()
        let target = root.appendingPathComponent("Cellar/miniforge/25.0")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let optDir = root.appendingPathComponent("opt")
        try FileManager.default.createDirectory(at: optDir, withIntermediateDirectories: true)
        let link = optDir.appendingPathComponent("other")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)

        let scanner = UsageGraphScanner(
            cache: UsageIndexCache(directory: tempDir()),
            home: root.path,
            brewPrefixes: [],
            textRefFiles: [], plistDirs: [], appDirectories: [], binDirectories: [],
            symlinkRoots: [optDir.path])

        let edges = await scanner.referrers(for: target)
        #expect(edges.isEmpty)
    }

    // MARK: Native Homebrew receipts

    @Test func homebrewReceiptFindsInstalledDependencyWithoutBrew() async throws {
        let prefix = tempDir()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let cellar = prefix.appendingPathComponent("Cellar")
        let target = cellar.appendingPathComponent("libfoo")
        let receipt = cellar.appendingPathComponent("consumer/1.0/INSTALL_RECEIPT.json")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"runtime_dependencies":[{"full_name":"vendor/tap/libfoo","version":"1.0"}]}"#.utf8).write(to: receipt)
        let scanner = UsageGraphScanner(
            cache: UsageIndexCache(directory: prefix.appendingPathComponent("cache")),
            home: prefix.path, brewPrefixes: [prefix.path], textRefFiles: [],
            plistDirs: [], appDirectories: [], binDirectories: [], symlinkRoots: [])
        let edges = await scanner.referrers(for: target)
        #expect(edges.count == 1)
        #expect(edges.first?.signal == .homebrew)
        #expect(edges.first?.source.path == prefix.appendingPathComponent("opt/consumer").path)
    }

    // MARK: Cache

    @Test func cacheHitSkipsRecrawl() async throws {
        let cacheDir = tempDir()
        let cache = UsageIndexCache(directory: cacheDir)
        let target = URL(fileURLWithPath: "/tmp/some-target")
        let edge = UsageEdge(
            source: URL(fileURLWithPath: "/tmp/referrer"), target: target, signal: .symlink,
            detail: "pre-seeded")
        cache.store(.symlink, edges: [edge])

        let scanner = UsageGraphScanner(
            cache: cache, home: tempDir().path,
            brewPrefixes: ["/nonexistent-brew-prefix-for-test"],
            textRefFiles: [], plistDirs: [], appDirectories: [], binDirectories: [],
            symlinkRoots: ["/nonexistent-root-for-test"])

        let edges = await scanner.referrers(for: target)
        #expect(edges.map(\.detail) == ["pre-seeded"])
        // Cached evidence must survive without touching the absent scan root.
        #expect(cache.load(.symlink)?.map(\.detail) == ["pre-seeded"])
    }

    @Test func forceRescanBypassesCache() async throws {
        let cacheDir = tempDir()
        let cache = UsageIndexCache(directory: cacheDir)
        let root = tempDir()
        let target = root.appendingPathComponent("dev-tools/miniforge3")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let zshrc = root.appendingPathComponent(".zshrc")
        try "\(target.path)\n".write(to: zshrc, atomically: true, encoding: .utf8)

        // Seed a stale cache with no edges for this target.
        cache.store(.textRef, edges: [])

        let scanner = UsageGraphScanner(
            cache: cache, home: root.path,
            brewPrefixes: ["/nonexistent-brew-prefix-for-test"],
            textRefFiles: ["~/.zshrc"], plistDirs: [], appDirectories: [], binDirectories: [],
            symlinkRoots: [])

        let stale = await scanner.referrers(for: target)
        #expect(stale.isEmpty)

        let fresh = await scanner.referrers(for: target, forceRescan: [.textRef])
        #expect(fresh.count == 1)
    }
}
