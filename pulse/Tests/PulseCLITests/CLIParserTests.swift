import Foundation
import Testing
@testable import PulseCLI
import PulseKit

@Suite struct CLIParserTests {
    @Test func grammar() throws {
        let parser = CLIParser(arguments: ["--json", "procs", "--by=mem", "-n", "5"])
        try parser.validate()
        #expect(parser.subcommand == "procs")
        #expect(parser.hasFlag("json"))
        #expect(parser.intOption("limit") == 5)
        #expect(parser.stringOption("by") == "mem")
        let negative = CLIParser(arguments: ["display", "set", "-0.3"])
        try negative.validate()
        #expect(negative.positional == ["set", "-0.3"])
        let literal = CLIParser(arguments: ["verdict", "--", "--odd-folder"])
        try literal.validate()
        #expect(literal.positional == ["--odd-folder"])
    }
    @Test(arguments: [
        ["clean", "--yes"], ["clean", "--force"], ["clean", "--target"],
        ["clean", "--target=", "--yes"], ["procs", "--limit", "-1"],
        ["procs", "--limit", "abc"], ["procs", "--by", "disk"],
        ["procs", "--limit", "3", "--limit", "4"], ["vitals", "--jsno"],
        ["vitals", "--json=false"], ["display", "set", "nan"], ["display", "set", "1.1"],
        ["sleep", "prevent", "--until", "inf"], ["sleep", "allow", "--until", "5"],
        ["uninstall", "--yes"], ["duplicates", "/tmp", "--min-size-mb", "0"]
    ]) func rejectsBadInputs(args: [String]) {
        #expect(throws: CLIUsageError.self) { try CLIParser(arguments: args).validate() }
    }
    @Test func deletionGate() throws {
        for command in ["clean", "uninstall"] {
            let args = command == "clean" ? [command, "--target", "/tmp/cache"] : [command, "Example"]
            #expect(CLIParser(arguments: args).isDryRun)
            #expect(!CLIParser(arguments: args + ["--yes"]).isDryRun)
            #expect(CLIParser(arguments: args + ["--yes", "--dry-run"]).isDryRun)
        }
        #expect(CLIParser(arguments: ["clean", "--scan", "--yes"]).isDryRun)
    }
}

@Suite struct CLIOutputTests {
    @Test func attentionSchemaPreservesRemedy() throws {
        let item = AttentionItem(id: "hot", title: "Hot process", detail: "Inspect it", severity: .warn, action: .quitProcess(pid: 123, name: "Example"))
        let json = try CLIOutput.json(AttentionDTO(item: item))
        let value = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let remedy = try #require(value["remedy"] as? [String: Any])
        #expect(remedy["kind"] as? String == "quitProcess")
        #expect(remedy["pid"] as? Int == 123)
        #expect(value["severity"] as? String == "warn")
    }
    @Test func stableJSON() throws {
        struct Fixture: Encodable { let date: Date; let bytes: UInt64; let enabled: Bool }
        let json = try CLIOutput.json(Fixture(date: Date(timeIntervalSince1970: 0), bytes: 42, enabled: true))
        #expect(json == #"{"bytes":42,"date":"1970-01-01T00:00:00Z","enabled":true}"#)
        #expect(CLIOutput(isJSON: true).red("plain") == "plain")
        #expect(throws: EncodingError.self) { try CLIOutput.json(["bad": Double.nan]) }
    }
}

@Suite struct CLISafetyTests {
    @Test func protectedAndActivePaths() {
        let home = "/Users/example"
        #expect(CLISafety.refusal(path: "/System/Applications/Finder.app", home: home) != nil)
        #expect(CLISafety.refusal(path: home + "/.codex", home: home) != nil)
        #expect(CLISafety.refusal(path: home + "/Library", home: home) != nil)
        #expect(CLISafety.refusal(path: home + "/Library/Caches/tool", home: home, excluded: [home + "/Library/Caches/tool/sub"]) != nil)
        #expect(CLISafety.refusal(path: home + "/Library/Caches/tool", home: home, activePaths: [home + "/Library/Caches/tool/open.db"]) != nil)
        #expect(CLISafety.refusal(path: home + "/Library/Caches/tool", home: home, activePaths: [home + "/Library/Caches/tool-other/open.db"]) == nil)
        #expect(BundleGuard.isProtected(bundleID: "COM.APPLE.FINDER"))
    }
    @Test func exactAppSelection() throws {
        let apps = [InstalledApp(name: "Example", bundleID: "org.example.app", version: "1", path: "/Applications/Example.app", sizeBytes: 1, lastUsedDays: nil)]
        #expect(try CLISafety.exactApp("Example", apps: apps).path == apps[0].path)
        #expect(throws: CLIUsageError.self) { try CLISafety.exactApp("Exam", apps: apps) }
        #expect(throws: CLIUsageError.self) { try CLISafety.exactApp("Example", apps: apps + apps) }
    }
}

@Suite struct CLIJournalTests {
    @Test func separateInstancesPreserveEntriesAndRestoreConflicts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("journal.json")
        let a = UndoJournal(storeURL: path), b = UndoJournal(storeURL: path)
        let original = root.appendingPathComponent("original"), trash = root.appendingPathComponent("trashed")
        try Data("original".utf8).write(to: original)
        try Data("recover".utf8).write(to: trash)
        let entry = UndoEntry(op: "fixture", items: [.init(originalPath: original.path, trashPath: trash.path)], bytesFreed: 7)
        try await a.recordChecked(entry)
        try await b.recordChecked(.init(op: "other", items: [], bytesFreed: 0))
        #expect(try await a.snapshot().count == 2)
        #expect(try await b.restore(entry.id) == 0)
        #expect(try String(contentsOf: original, encoding: .utf8) == "original")
        try FileManager.default.removeItem(at: original)
        #expect(try await a.restore(entry.id) == 1)
        #expect(try String(contentsOf: original, encoding: .utf8) == "recover")
        #expect(try await b.snapshot().count == 1)
    }
    @Test func corruptJournalFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("journal.json")
        try Data("corrupt".utf8).write(to: path)
        let journal = UndoJournal(storeURL: path)
        do { try await journal.recordChecked(.init(op: "test", items: [], bytesFreed: 0)); Issue.record("Expected failure") }
        catch { }
        #expect(try String(contentsOf: path, encoding: .utf8) == "corrupt")
    }
}

@Suite struct CLIControlTests {
    @Test @MainActor func rejectsInvalidControlMessages() async {
        let unknown = await AppControlServer.handle(.init(action: "execute.shell"))
        #expect(unknown.error != nil)
        let invalidDuration = await AppControlServer.handle(.init(action: "sleep.prevent", value: -5))
        #expect(invalidDuration.error != nil)
    }
}
