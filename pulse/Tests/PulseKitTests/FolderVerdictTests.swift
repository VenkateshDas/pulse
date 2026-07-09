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
            ShellHistoryProbe.match(
                command: "sudo wget -O file url", names: names, targetPath: "")?.name == "wget")
        #expect(
            ShellHistoryProbe.match(
                command: "HTTPS_PROXY=x wget url", names: names, targetPath: "")?.name == "wget")
        #expect(
            ShellHistoryProbe.match(
                command: "/opt/homebrew/bin/wget url", names: names, targetPath: "")?.name
                == "wget")
        // wget as argument, not command — no match.
        #expect(
            ShellHistoryProbe.match(
                command: "man wget", names: names, targetPath: "") == nil)
    }

    @Test func invocationIsRanButPathMentionIsOnlyMentioned() {
        let ran = ShellHistoryProbe.match(
            command: "wget url", names: ["wget"], targetPath: "/x")
        #expect(ran?.kind == .ran)
        let mentioned = ShellHistoryProbe.match(
            command: "cd /Users/x/dev-tools/miniforge3/envs", names: [],
            targetPath: "/Users/x/dev-tools/miniforge3")
        #expect(mentioned?.name == "miniforge3")
        #expect(mentioned?.kind == .mentioned)
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
    @Test func newestContentMTimeWinsAcrossTree() throws {
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
        let newest = try #require(result.newestContent)
        #expect(newest.timeIntervalSinceNow > -3600)
        #expect(result.newestContentName == "new.txt")
        #expect(result.fileCount >= 2)
        #expect(result.truncated == false)
    }

    /// The .hermes bug: dead app's folder where only housekeeping churns.
    /// Content staleness must see through .DS_Store and log writes.
    @Test func housekeepingChurnDoesNotCountAsContent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("logs"), withIntermediateDirectories: true)
        let config = dir.appendingPathComponent("config.yaml")
        try "cfg".write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -86400 * 200)],
            ofItemAtPath: config.path)
        // Touched today: Finder metadata, a log, a file inside logs/.
        try "x".write(
            to: dir.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        try "x".write(
            to: dir.appendingPathComponent("telemetry.log"), atomically: true, encoding: .utf8)
        try "x".write(
            to: dir.appendingPathComponent("logs/run.txt"), atomically: true, encoding: .utf8)

        let result = StalenessProbe.scan(dir)
        let content = try #require(result.newestContent)
        // Content date is the 200-day-old config, not today's housekeeping.
        #expect(content.timeIntervalSinceNow < -86400 * 199)
        #expect(result.newestContentName == "config.yaml")
        let any = try #require(result.newestAny)
        #expect(any.timeIntervalSinceNow > -3600)
    }

    @Test func singleFileReportsItself() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("single-\(UUID().uuidString).dmg")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let result = StalenessProbe.scan(file)
        #expect(result.fileCount == 1)
        #expect(result.newestContent != nil)
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

    private func staleness(daysOld: Int, noisyToday: Bool = false) -> StalenessProbe.Result {
        let content = now.addingTimeInterval(-Double(daysOld) * 86400)
        return StalenessProbe.Result(
            newestContent: content, newestContentName: "config.yaml",
            newestAny: noisyToday ? now : content,
            fileCount: 10, sizeBytes: 1_000_000, truncated: false)
    }

    /// Shorthand with the new knobs defaulted to the quiet case.
    private func synth(
        species: FolderSpecies? = nil, staleness: StalenessProbe.Result,
        spotlightDays: Int? = nil, isDirectory: Bool = true,
        historyHits: [ShellHistoryProbe.Hit] = [],
        liveness: OwnerLivenessProbe.Liveness = .notApplicable,
        references: [UsageEdge] = [], activity: ActivitySummary? = nil
    ) -> FolderVerdict {
        FolderVerdictEngine.synthesize(
            targetPath: "/x", species: species, staleness: staleness,
            spotlightDays: spotlightDays, targetIsDirectory: isDirectory,
            historyHits: historyHits, liveness: liveness,
            references: references, activity: activity, now: now)
    }

    private let venv = FolderSpecies(
        id: "python-venv", name: "Python virtual environment", explanation: "x",
        regenerable: true, regenCommand: "python3 -m venv .venv")
    private let backup = FolderSpecies(
        id: "ios-backup", name: "iPhone backup", explanation: "x", regenerable: false)
    private let zshrcRef = UsageEdge(
        source: URL(fileURLWithPath: "/Users/x/.zshrc"),
        target: URL(fileURLWithPath: "/x"), signal: .textRef, detail: ".zshrc:3")
    private let symlinkRef = UsageEdge(
        source: URL(fileURLWithPath: "/usr/local/bin/hermes"),
        target: URL(fileURLWithPath: "/x"), signal: .symlink, detail: "symlink")

    @Test func regenerableStaleUnreferencedIsSafeToDelete() {
        let verdict = synth(species: venv, staleness: staleness(daysOld: 90))
        #expect(verdict.verdict == .safeToDelete)
        #expect(verdict.regenCommand == "python3 -m venv .venv")
    }

    @Test func recentContentMTimeMeansInUse() {
        let verdict = synth(species: venv, staleness: staleness(daysOld: 2))
        #expect(verdict.verdict == .inUse)
    }

    // The .hermes case: owner uninstalled, only housekeeping churns.
    @Test func uninstalledOwnerWithStaleContentIsSafeToDelete() {
        let verdict = synth(
            staleness: staleness(daysOld: 200, noisyToday: true),
            liveness: .missing(toolName: "hermes"),
            references: [symlinkRef])
        #expect(verdict.verdict == .safeToDelete)
        #expect(verdict.headline.contains("hermes"))
        // Leftover symlink surfaced as cleanup pointer, leaning delete.
        #expect(verdict.evidence.contains { $0.kind == .references && $0.favorsDeletion == true })
    }

    // The .nvm guard: no binary exists, but .zshrc sources it every launch.
    @Test func uninstalledOwnerWithRcReferenceIsNeverSafeToDelete() {
        let verdict = synth(
            staleness: staleness(daysOld: 200),
            liveness: .missing(toolName: "nvm"),
            references: [zshrcRef])
        #expect(verdict.verdict == .likelyUnused)
        #expect(verdict.headline.contains("shell config"))
    }

    // Spotlight "opened today" on a directory is browse noise (often us).
    @Test func recentSpotlightOnDirectoryDoesNotBlockDeletion() {
        let verdict = synth(
            species: venv, staleness: staleness(daysOld: 90), spotlightDays: 0,
            isDirectory: true)
        #expect(verdict.verdict == .safeToDelete)
    }

    @Test func recentSpotlightOnFileCountsAsUse() {
        let verdict = synth(
            species: venv, staleness: staleness(daysOld: 90), spotlightDays: 0,
            isDirectory: false)
        #expect(verdict.verdict == .inUse)
    }

    @Test func recentRanHistoryMeansInUse() {
        let hit = ShellHistoryProbe.Hit(
            command: "wget", kind: .ran, count: 3,
            lastUsed: now.addingTimeInterval(-86400 * 3))
        let verdict = synth(species: venv, staleness: staleness(daysOld: 90), historyHits: [hit])
        #expect(verdict.verdict == .inUse)
    }

    // Path mentions (old cd, stale export) must not keep a folder alive —
    // and neither may date-unknown hits.
    @Test func mentionedOrUndatedHistoryHitsDoNotBlockDeletion() {
        let mentioned = ShellHistoryProbe.Hit(
            command: ".hermes", kind: .mentioned, count: 7, lastUsed: now)
        let undatedRan = ShellHistoryProbe.Hit(
            command: "hermes", kind: .ran, count: 2, lastUsed: nil)
        let verdict = synth(
            species: venv, staleness: staleness(daysOld: 90),
            historyHits: [mentioned, undatedRan])
        #expect(verdict.verdict == .safeToDelete)
    }

    @Test func recentObservedOpenWithValidWindowMeansInUse() {
        let activity = ActivitySummary(
            lastWrite: nil, lastOpen: now.addingTimeInterval(-86400 * 5),
            lastOpenProcess: "python3",
            trackingSince: now.addingTimeInterval(-86400 * 60))
        let verdict = synth(species: venv, staleness: staleness(daysOld: 90), activity: activity)
        #expect(verdict.verdict == .inUse)
        #expect(verdict.evidence.contains { $0.kind == .observer && $0.headline.contains("python3") })
    }

    // The "watching for 0 days" bug: a fresh observer's sightings are the
    // ambient startup burst, not proof of use.
    @Test func observerIgnoredUntilWindowIsValid() {
        let activity = ActivitySummary(
            lastWrite: now, lastOpen: now, lastOpenProcess: "SomeApp",
            trackingSince: now.addingTimeInterval(-3600))
        let verdict = synth(species: venv, staleness: staleness(daysOld: 90), activity: activity)
        #expect(verdict.verdict == .safeToDelete)
    }

    // FSEvents writes have no process attribution (.DS_Store looks like a
    // real write) — informational only.
    @Test func unattributedWriteDoesNotBlockDeletion() {
        let activity = ActivitySummary(
            lastWrite: now, lastOpen: nil, lastOpenProcess: nil,
            trackingSince: now.addingTimeInterval(-86400 * 60))
        let verdict = synth(species: venv, staleness: staleness(daysOld: 90), activity: activity)
        #expect(verdict.verdict == .safeToDelete)
    }

    @Test func regenerableButReferencedIsLikelyUnusedNotSafe() {
        let verdict = synth(
            species: venv, staleness: staleness(daysOld: 90), references: [zshrcRef])
        #expect(verdict.verdict == .likelyUnused)
    }

    @Test func irreplaceableStaleIsReviewNeverDelete() {
        let verdict = synth(species: backup, staleness: staleness(daysOld: 400))
        #expect(verdict.verdict == .staleReview)
        #expect(verdict.regenCommand == nil)
    }

    @Test func unrecognizedRecentishIsUnknown() {
        let verdict = synth(staleness: staleness(daysOld: 60))
        #expect(verdict.verdict == .unknown)
    }

    @Test func evidenceAlwaysIncludesIdentityAndReferences() {
        let verdict = synth(staleness: staleness(daysOld: 10))
        #expect(verdict.evidence.contains { $0.kind == .identity })
        #expect(verdict.evidence.contains { $0.kind == .references })
        #expect(verdict.evidence.contains { $0.kind == .staleness })
    }
}

// MARK: - Owner liveness

@Suite("OwnerLivenessProbe")
struct OwnerLivenessTests {
    @Test func toolNameShapes() {
        let home = "/Users/tester"
        #expect(
            OwnerLivenessProbe.toolName(
                for: URL(fileURLWithPath: "/Users/tester/.hermes"), home: home) == "hermes")
        #expect(
            OwnerLivenessProbe.toolName(
                for: URL(fileURLWithPath: "/Users/tester/.config/hermes"), home: home)
                == "hermes")
        #expect(
            OwnerLivenessProbe.toolName(
                for: URL(fileURLWithPath: "/Users/tester/Library/Application Support/Hermes"),
                home: home) == "Hermes")
        // Non-tool shapes: deep paths, visible home folders.
        #expect(
            OwnerLivenessProbe.toolName(
                for: URL(fileURLWithPath: "/Users/tester/Documents"), home: home) == nil)
        #expect(
            OwnerLivenessProbe.toolName(
                for: URL(fileURLWithPath: "/Users/tester/dev/project/.venv"), home: home) == nil)
    }

    @Test func missingWhenNothingInstalled() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("owner-\(UUID().uuidString)").path
        let probe = OwnerLivenessProbe(
            binDirectories: [empty], appDirectories: [empty], cellarDirectories: [empty])
        #expect(probe.check(toolName: "hermes") == .missing(toolName: "hermes"))
    }

    @Test func installedViaExecutable() throws {
        let bin = FileManager.default.temporaryDirectory
            .appendingPathComponent("owner-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let exe = bin.appendingPathComponent("hermes")
        FileManager.default.createFile(atPath: exe.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let probe = OwnerLivenessProbe(
            binDirectories: [bin.path], appDirectories: [], cellarDirectories: [])
        #expect(probe.check(toolName: "hermes") == .installed(at: exe.path))
    }

    @Test func installedViaAppBundlePrefixMatch() throws {
        let apps = FileManager.default.temporaryDirectory
            .appendingPathComponent("owner-apps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: apps.appendingPathComponent("Docker.app"), withIntermediateDirectories: true)
        let probe = OwnerLivenessProbe(
            binDirectories: [], appDirectories: [apps.path], cellarDirectories: [])
        #expect(probe.check(toolName: "docker") == .installed(at: apps.path + "/Docker.app"))
    }

    @Test func aliasResolvesGnupgToGpg() throws {
        let bin = FileManager.default.temporaryDirectory
            .appendingPathComponent("owner-alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let gpg = bin.appendingPathComponent("gpg")
        FileManager.default.createFile(atPath: gpg.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: gpg.path)
        let probe = OwnerLivenessProbe(
            binDirectories: [bin.path], appDirectories: [], cellarDirectories: [])
        #expect(probe.check(toolName: "gnupg") == .installed(at: gpg.path))
    }
}

// MARK: - Noise process filter

@Suite("UsageObserver noise filter")
struct NoiseProcessTests {
    @Test func systemDaemonsAreNoise() {
        #expect(UsageObserver.isNoiseProcess(
            name: "corespotlightd", executablePath: "/System/Library/Frameworks/x"))
        #expect(UsageObserver.isNoiseProcess(
            name: "UserEventAgent", executablePath: "/usr/libexec/UserEventAgent"))
        #expect(UsageObserver.isNoiseProcess(
            name: "mdworker_shared", executablePath: ""))
        #expect(UsageObserver.isNoiseProcess(name: "Finder", executablePath: ""))
        #expect(UsageObserver.isNoiseProcess(name: "Pulse", executablePath: ""))
    }

    @Test func userToolsAreSignal() {
        #expect(!UsageObserver.isNoiseProcess(
            name: "python3", executablePath: "/opt/homebrew/bin/python3"))
        #expect(!UsageObserver.isNoiseProcess(
            name: "Xcode", executablePath: "/Applications/Xcode.app/Contents/MacOS/Xcode"))
    }
}
