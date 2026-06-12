import Foundation
import Testing

@testable import PulseKit

// MARK: - Helpers

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeFile(at url: URL, megabytes: Int) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = Data(repeating: 0xAB, count: megabytes * 1_000_000)
    try data.write(to: url)
}

private func setModified(_ url: URL, daysAgo: Int) throws {
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSinceNow: -Double(daysAgo) * 86400)],
        ofItemAtPath: url.path)
}

// MARK: - SafetyVault

@Suite("SafetyVault")
struct SafetyVaultTests {
    @Test func stagingMovesFilesAndPersistsAManifest() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let victim = root.appendingPathComponent("data/cache.bin")
        try writeFile(at: victim, megabytes: 1)

        let vault = SafetyVault(rootURL: root.appendingPathComponent("vault"))
        let session = try vault.stage(
            items: [(path: victim.path, label: "cache", sizeBytes: 1_000_000)],
            title: "test clean")

        #expect(!FileManager.default.fileExists(atPath: victim.path))
        #expect(session.items.count == 1)
        // ISO8601 round-trip truncates sub-second precision, so compare
        // fields rather than whole structs.
        let reloaded = vault.sessions()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.id == session.id)
        #expect(reloaded.first?.items == session.items)
        #expect(reloaded.first?.totalBytes == 1_000_000)
    }

    @Test func restorePutsFilesBackAndRemovesTheSession() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let victim = root.appendingPathComponent("data/cache.bin")
        try writeFile(at: victim, megabytes: 1)

        let vault = SafetyVault(rootURL: root.appendingPathComponent("vault"))
        let session = try vault.stage(
            items: [(path: victim.path, label: "cache", sizeBytes: 1_000_000)],
            title: "test clean")
        let restored = try vault.restore(session)

        #expect(restored == 1)
        #expect(FileManager.default.fileExists(atPath: victim.path))
        #expect(vault.sessions().isEmpty)
    }

    @Test func restoreCollisionKeepsBothFiles() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let victim = root.appendingPathComponent("data/cache.bin")
        try writeFile(at: victim, megabytes: 1)

        let vault = SafetyVault(rootURL: root.appendingPathComponent("vault"))
        let session = try vault.stage(
            items: [(path: victim.path, label: "cache", sizeBytes: 1_000_000)],
            title: "test clean")
        // Something recreated the original path before the restore.
        try writeFile(at: victim, megabytes: 1)
        try vault.restore(session)

        let sibling = root.appendingPathComponent("data/cache (restored).bin")
        #expect(FileManager.default.fileExists(atPath: victim.path))
        #expect(FileManager.default.fileExists(atPath: sibling.path))
    }

    @Test func expiredSessionsArePurgedAndCountedAsFreed() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let victim = root.appendingPathComponent("data/old.bin")
        try writeFile(at: victim, megabytes: 2)

        let vault = SafetyVault(rootURL: root.appendingPathComponent("vault"))
        try vault.stage(
            items: [(path: victim.path, label: "old", sizeBytes: 2_000_000)],
            title: "old clean",
            date: Date(timeIntervalSinceNow: -8 * 86400))
        let freed = vault.purgeExpired()

        #expect(freed == 2_000_000)
        #expect(vault.sessions().isEmpty)
    }

    @Test func stagingSkipsVanishedPathsAndThrowsWhenNothingStages() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("data/real.bin")
        try writeFile(at: real, megabytes: 1)

        let vault = SafetyVault(rootURL: root.appendingPathComponent("vault"))
        let session = try vault.stage(
            items: [
                (path: real.path, label: "real", sizeBytes: 1_000_000),
                (path: root.appendingPathComponent("gone.bin").path, label: "gone", sizeBytes: 9),
            ],
            title: "partial")
        #expect(session.items.count == 1)
        #expect(session.items[0].label == "real")

        #expect(throws: (any Error).self) {
            try vault.stage(
                items: [(path: root.appendingPathComponent("nope").path, label: "x", sizeBytes: 1)],
                title: "empty")
        }
    }
}

// MARK: - SmartScanner

@Suite("SmartScanner")
struct SmartScannerTests {
    @Test func oldInstallersAreFlaggedCarefulAndFreshOnesIgnored() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let old = home.appendingPathComponent("Downloads/Docker.dmg")
        let fresh = home.appendingPathComponent("Downloads/New.dmg")
        try writeFile(at: old, megabytes: 6)
        try writeFile(at: fresh, megabytes: 6)
        try setModified(old, daysAgo: 40)

        let scan = SmartScanner(home: home).scan()
        let installers = scan.items.filter { $0.category == "Old installers" }
        #expect(installers.count == 1)
        #expect(installers.first?.label == "Docker.dmg")
        #expect(installers.first?.grade == .careful)
        #expect((installers.first?.idleDays ?? 0) >= 39)
    }

    @Test func cachesExpandIntoPerAppSafeRows() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeFile(
            at: home.appendingPathComponent("Library/Caches/com.example.app/blob.bin"),
            megabytes: 11)
        try writeFile(
            at: home.appendingPathComponent("Library/Caches/tiny.app/blob.bin"),
            megabytes: 1)

        let scan = SmartScanner(home: home).scan()
        let caches = scan.items.filter { $0.category == "App caches" }
        #expect(caches.count == 1)
        #expect(caches.first?.label == "com.example.app")
        #expect(caches.first?.grade == .safe)
    }

    @Test func staleNodeModulesIsCarefulButActiveProjectIsLeftAlone() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let stale = home.appendingPathComponent("code/stale-app")
        try writeFile(at: stale.appendingPathComponent("node_modules/dep/big.bin"), megabytes: 21)
        try writeFile(at: stale.appendingPathComponent("index.js"), megabytes: 1)
        try setModified(stale.appendingPathComponent("index.js"), daysAgo: 90)

        let active = home.appendingPathComponent("code/active-app")
        try writeFile(at: active.appendingPathComponent("node_modules/dep/big.bin"), megabytes: 21)
        try writeFile(at: active.appendingPathComponent("index.js"), megabytes: 1)

        let scan = SmartScanner(home: home).scan()
        let junk = scan.items.filter { $0.category == "Stale dev junk" }
        #expect(junk.count == 1)
        #expect(junk.first?.label.contains("stale-app") == true)
        #expect(junk.first?.grade == .careful)
        #expect((junk.first?.idleDays ?? 0) >= SmartScanner.staleProjectDays)
    }

    @Test func topFoldersCarrySizesAndSafetyTints() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeFile(at: home.appendingPathComponent("Movies/raw.mov"), megabytes: 60)

        let scan = SmartScanner(home: home).scan()
        let movies = scan.topFolders.first { $0.name == "Movies" }
        #expect(movies != nil)
        #expect(movies?.grade == .review)
        #expect((movies?.sizeBytes ?? 0) >= 59_000_000)
        #expect(scan.scannedFiles >= 1)
    }

    @Test func reviewTierExistsForIOSBackupsAndIsNeverSafe() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeFile(
            at: home.appendingPathComponent(
                "Library/Application Support/MobileSync/Backup/device/blob.bin"),
            megabytes: 11)

        let scan = SmartScanner(home: home).scan()
        let backups = scan.items.filter { $0.category == "iOS backups" }
        #expect(backups.count == 1)
        #expect(backups.first?.grade == .review)
        // Grade ordering puts review last.
        #expect(scan.items.last?.grade == .review)
    }
}
