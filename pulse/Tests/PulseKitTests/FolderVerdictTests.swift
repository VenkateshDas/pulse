import Foundation
import Testing

@testable import PulseKit

// MARK: - Fingerprint

@Suite("FingerprintCatalog")
struct FingerprintTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FingerprintTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let real = realpath(dir.path, nil) else { return dir }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real))
    }

    @Test func venvByPyvenvCfg() throws {
        let dir = tempDir().appendingPathComponent(".venv")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("pyvenv.cfg").path, contents: Data())
        let species = FingerprintCatalog.identify(dir)
        #expect(species?.id == "python-venv")
        #expect(species?.regenerable == true)
        #expect(species?.regenCommand?.contains("venv") == true)
    }

    @Test func condaRootBeatsSingleEnv() throws {
        let dir = tempDir().appendingPathComponent("miniforge3")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("conda-meta"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("envs"), withIntermediateDirectories: true)
        #expect(FingerprintCatalog.identify(dir)?.id == "conda-root")
    }

    @Test func condaEnvWithoutEnvsDir() throws {
        let dir = tempDir().appendingPathComponent("myenv")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("conda-meta"), withIntermediateDirectories: true)
        #expect(FingerprintCatalog.identify(dir)?.id == "conda-env")
    }

    @Test func nodeModulesNeedsSiblingPackageJson() throws {
        let project = tempDir()
        let modules = project.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        // Without package.json: not recognized.
        #expect(FingerprintCatalog.identify(modules)?.id != "node-modules")
        FileManager.default.createFile(
            atPath: project.appendingPathComponent("package.json").path, contents: Data())
        #expect(FingerprintCatalog.identify(modules)?.id == "node-modules")
    }

    @Test func cargoTargetNeedsSiblingCargoToml() throws {
        let project = tempDir()
        let target = project.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: project.appendingPathComponent("Cargo.toml").path, contents: Data())
        #expect(FingerprintCatalog.identify(target)?.id == "cargo-target")
    }

    @Test func brewFormulaFromCellarPath() {
        let url = URL(fileURLWithPath: "/opt/homebrew/Cellar/wget/1.24.5")
        let species = FingerprintCatalog.identify(url)
        #expect(species?.id == "brew-formula")
        #expect(species?.regenCommand == "brew reinstall wget")
    }

    @Test func installerByExtension() {
        let species = FingerprintCatalog.identify(
            URL(fileURLWithPath: "/tmp/SomeApp-1.2.dmg"))
        #expect(species?.id == "installer")
        #expect(species?.regenerable == true)
    }

    @Test func iosBackupIsNotRegenerable() {
        let url = URL(
            fileURLWithPath:
                "/Users/x/Library/Application Support/MobileSync/Backup/abc123")
        let species = FingerprintCatalog.identify(url)
        #expect(species?.id == "ios-backup")
        #expect(species?.regenerable == false)
    }

    @Test func gitProjectIsNotBlindlyRegenerable() throws {
        let dir = tempDir().appendingPathComponent("my-project")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let species = FingerprintCatalog.identify(dir)
        #expect(species?.id == "git-project")
        #expect(species?.regenerable == false)
    }

    @Test func unknownFolderReturnsNil() throws {
        let dir = tempDir().appendingPathComponent("random-stuff")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(FingerprintCatalog.identify(dir) == nil)
    }
}

// MARK: - Shell history

@Suite("ShellHistoryProbe")
struct ShellHistoryTests {
    @Test func parsesZshExtendedFormat() {
        let (command, timestamp) = ShellHistoryProbe.parseHistoryLine(
            ": 1720000000:0;wget https://example.com")
        #expect(command == "wget https://example.com")
        #expect(timestamp == Date(timeIntervalSince1970: 1_720_000_000))
    }

    @Test func parsesPlainFormat() {
        let (command, timestamp) = ShellHistoryProbe.parseHistoryLine("ls -la /tmp")
        #expect(command == "ls -la /tmp")
        #expect(timestamp == nil)
    }

    @Test func matchesFirstTokenSkippingSudoAndEnv() {
        let names: Set<String> = ["wget"]
        #expect(
            ShellHistoryProbe.matchedName(
                command: "sudo wget -O file url", names: names, targetPath: "") == "wget")
        #expect(
            ShellHistoryProbe.matchedName(
                command: "HTTPS_PROXY=x wget url", names: names, targetPath: "") == "wget")
        #expect(
            ShellHistoryProbe.matchedName(
                command: "/opt/homebrew/bin/wget url", names: names, targetPath: "") == "wget")
        // wget as argument, not command — no match.
        #expect(
            ShellHistoryProbe.matchedName(
                command: "man wget", names: names, targetPath: "") == nil)
    }

    @Test func matchesRawTargetPathAnywhere() {
        let name = ShellHistoryProbe.matchedName(
            command: "cd /Users/x/dev-tools/miniforge3/envs", names: [],
            targetPath: "/Users/x/dev-tools/miniforge3")
        #expect(name == "miniforge3")
    }

    @Test func hitsAggregateCountAndLatestTimestamp() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("hist-\(UUID().uuidString)")
        try """
        : 1700000000:0;wget url1
        : 1720000000:0;wget url2
        ls -la
        """.write(to: file, atomically: true, encoding: .utf8)

        let probe = ShellHistoryProbe(historyFiles: [file])
        let hits = probe.hits(names: ["wget"], targetPath: "")
        #expect(hits.count == 1)
        #expect(hits.first?.count == 2)
        #expect(hits.first?.lastUsed == Date(timeIntervalSince1970: 1_720_000_000))
    }
}

// MARK: - Staleness

@Suite("StalenessProbe")
struct StalenessTests {
    @Test func newestMTimeWinsAcrossTree() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-\(UUID().uuidString)")
        let deep = dir.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let oldFile = dir.appendingPathComponent("old.txt")
        let newFile = deep.appendingPathComponent("new.txt")
        try "old".write(to: oldFile, atomically: true, encoding: .utf8)
        try "new".write(to: newFile, atomically: true, encoding: .utf8)
        let past = Date(timeIntervalSinceNow: -86400 * 100)
        try FileManager.default.setAttributes(
            [.modificationDate: past], ofItemAtPath: oldFile.path)

        let result = StalenessProbe.scan(dir)
        let newest = try #require(result.newestModified)
        #expect(newest.timeIntervalSinceNow > -3600)
        #expect(result.fileCount >= 2)
        #expect(result.truncated == false)
    }

    @Test func singleFileReportsItself() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("single-\(UUID().uuidString).dmg")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let result = StalenessProbe.scan(file)
        #expect(result.fileCount == 1)
        #expect(result.newestModified != nil)
    }
}

// MARK: - ActivityStore

@Suite("ActivityStore")
struct ActivityStoreTests {
    private func makeStore(home: String = "/Users/tester") -> (ActivityStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("activity-\(UUID().uuidString).json")
        return (ActivityStore(storeURL: url, homePath: home), url)
    }

    @Test func rollupCapsDepthBelowHome() {
        let (store, _) = makeStore()
        #expect(
            store.rollupKey(for: "/Users/tester/a/b/c/d/e/file.txt")
                == "/Users/tester/a/b/c/d")
        #expect(store.rollupKey(for: "/Users/tester/a") == "/Users/tester/a")
        #expect(
            store.rollupKey(for: "/opt/homebrew/Cellar/wget/1.2/bin/wget")
                == "/opt/homebrew/Cellar/wget")
        #expect(store.rollupKey(for: "relative/path") == nil)
    }

    @Test func summaryMatchesInsideAndContainingBuckets() async {
        let (store, _) = makeStore()
        let when = Date(timeIntervalSince1970: 1_720_000_000)
        await store.recordOpens(
            paths: [("/Users/tester/dev/proj/venv/bin/python", "python3")], at: when)

        // Query deeper than the roll-up bucket: bucket contains target.
        let deep = await store.summary(under: "/Users/tester/dev/proj/venv/bin")
        #expect(deep.lastOpen == when)
        #expect(deep.lastOpenProcess == "python3")

        // Query shallower: target contains bucket.
        let shallow = await store.summary(under: "/Users/tester/dev")
        #expect(shallow.lastOpen == when)

        // Unrelated path: nothing.
        let other = await store.summary(under: "/Users/tester/other")
        #expect(other.lastOpen == nil)
    }

    @Test func persistsAcrossInstances() async {
        let (store, url) = makeStore()
        let when = Date(timeIntervalSince1970: 1_720_000_000)
        await store.recordWrites(paths: ["/Users/tester/dev/proj/file"], at: when)
        await store.saveIfDirty()

        let reloaded = ActivityStore(storeURL: url, homePath: "/Users/tester")
        let summary = await reloaded.summary(under: "/Users/tester/dev/proj")
        #expect(summary.lastWrite == when)
    }
}

// MARK: - Handle sampler (live)

@Suite("UsageObserver sampler")
struct UsageObserverSamplerTests {
    /// Live sweep of this user's processes: must not crash, and every path
    /// returned must be under an interesting prefix (home, brew, /Applications).
    @Test func sampleOpenFilesReturnsOnlyInterestingPaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let prefixes = [home, "/opt/homebrew", "/usr/local", "/Applications"]
        let samples = UsageObserver.sampleOpenFiles(maxFDsPerProcess: 256)
        for sample in samples.prefix(200) {
            #expect(prefixes.contains { sample.path.hasPrefix($0) })
            #expect(!sample.process.isEmpty)
        }
    }
}

// MARK: - Verdict synthesis

@Suite("FolderVerdictEngine synthesis")
struct VerdictSynthesisTests {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    private func staleness(daysOld: Int) -> StalenessProbe.Result {
        StalenessProbe.Result(
            newestModified: now.addingTimeInterval(-Double(daysOld) * 86400),
            fileCount: 10, sizeBytes: 1_000_000, truncated: false)
    }

    private let venv = FolderSpecies(
        id: "python-venv", name: "Python virtual environment", explanation: "x",
        regenerable: true, regenCommand: "python3 -m venv .venv")
    private let backup = FolderSpecies(
        id: "ios-backup", name: "iPhone backup", explanation: "x", regenerable: false)

    @Test func regenerableStaleUnreferencedIsSafeToDelete() {
        let verdict = FolderVerdictEngine.synthesize(
            targetPath: "/x", species: venv, staleness: staleness(daysOld: 90),
            spotlightDays: nil, historyHits: [], references: [], activity: nil, now: now)
        #expect(verdict.verdict == .safeToDelete)
        #expect(verdict.regenCommand == "python3 -m venv .venv")
    }

    @Test func recentMTimeMeansInUse() {
        let verdict = FolderVerdictEngine.synthesize(
            targetPath: "/x", species: venv, staleness: staleness(daysOld: 2),
            spotlightDays: nil, historyHits: [], references: [], activity: nil, now: now)
        #expect(verdict.verdict == .inUse)
    }

    @Test func recentShellHistoryMeansInUse() {
        let hit = ShellHistoryProbe.Hit(
            command: "wget", count: 3, lastUsed: now.addingTimeInterval(-86400 * 3))
        let verdict = FolderVerdictEngine.synthesize(
            targetPath: "/x", species: venv, staleness: staleness(daysOld: 90),
            spotlightDays: nil, historyHits: [hit], references: [], activity: nil, now: now)
        #expect(verdict.verdict == .inUse)
    }

    @Test func recentObservedActivityMeansInUse() {
        let activity = ActivitySummary(
            lastWrite: nil, lastOpen: now.addingTimeInterval(-86400 * 5),
            lastOpenProcess: "python3",
            trackingSince: now.addingTimeInterval(-86400 * 60))
        let verdict = FolderVerdictEngine.synthesize(
            targetPath: "/x", species: venv, staleness: staleness(daysOld: 90),
            spotlightDays: nil, historyHits: [], references: [], activity: activity, now: now)
        #expect(verdict.verdict == .inUse)
        #expect(verdict.evidence.contains { $0.kind == .observer && $0.headline.contains("python3") })
    }

    @Test func regenerableButReferencedIsLikelyUnusedNotSafe() {
        let edge = UsageEdge(
            source: URL(fileURLWithPath: "/Users/x/.zshrc"),
            target: URL(fileURLWithPath: "/x"), signal: .textRef, detail: ".zshrc:3")
        let verdict = FolderVerdictEngine.synthesize(
            targetPath: "/x", species: venv, staleness: staleness(daysOld: 90),
            spotlightDays: nil, historyHits: [], references: [edge], activity: nil, now: now)
        #expect(verdict.verdict == .likelyUnused)
    }

    @Test func irreplaceableStaleIsReviewNeverDelete() {
        let verdict = FolderVerdictEngine.synthesize(
            targetPath: "/x", species: backup, staleness: staleness(daysOld: 400),
            spotlightDays: nil, historyHits: [], references: [], activity: nil, now: now)
        #expect(verdict.verdict == .staleReview)
        #expect(verdict.regenCommand == nil)
    }

    @Test func unrecognizedRecentishIsUnknown() {
        let verdict = FolderVerdictEngine.synthesize(
            targetPath: "/x", species: nil, staleness: staleness(daysOld: 60),
            spotlightDays: nil, historyHits: [], references: [], activity: nil, now: now)
        #expect(verdict.verdict == .unknown)
    }

    @Test func evidenceAlwaysIncludesIdentityAndReferences() {
        let verdict = FolderVerdictEngine.synthesize(
            targetPath: "/x", species: nil, staleness: staleness(daysOld: 10),
            spotlightDays: nil, historyHits: [], references: [], activity: nil, now: now)
        #expect(verdict.evidence.contains { $0.kind == .identity })
        #expect(verdict.evidence.contains { $0.kind == .references })
        #expect(verdict.evidence.contains { $0.kind == .staleness })
    }
}
