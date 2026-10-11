import Foundation
import Testing
import PulseKit
@testable import Pulse

@Suite("App removal recovery")
struct UninstallRecoveryTests {
    private func fixture(bundleID: String = "com.pulse.fixture.removal") throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-removal-\(UUID())")
        let app = directory.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleIdentifier": bundleID, "CFBundleName": "Fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return (directory, app)
    }

    @Test func nativeMoveIsRecordedAndRestorable() async throws {
        let (directory, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = UndoJournal(storeURL: directory.appendingPathComponent("journal.json"))
        #expect(await UninstallModel.moveAppToTrash(app, journal: journal))
        #expect(!FileManager.default.fileExists(atPath: app.path))
        let entries = try await journal.snapshot()
        let entry = try #require(entries.first)
        #expect(entry.items.first?.originalPath == app.path)
        #expect(try await journal.restore(entry.id) == 1)
        #expect(FileManager.default.fileExists(atPath: app.path))
    }

    @Test func journalFailureLeavesAppInPlace() async throws {
        let (directory, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: blocker)
        let journal = UndoJournal(storeURL: blocker.appendingPathComponent("journal.json"))
        #expect(await !UninstallModel.moveAppToTrash(app, journal: journal))
        #expect(FileManager.default.fileExists(atPath: app.path))
    }

    @Test func protectedBundleCannotBeMoved() async throws {
        let (directory, app) = try fixture(bundleID: "com.apple.finder")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = UndoJournal(storeURL: directory.appendingPathComponent("journal.json"))
        #expect(await !UninstallModel.moveAppToTrash(app, journal: journal))
        #expect(FileManager.default.fileExists(atPath: app.path))
        #expect(try await journal.snapshot().isEmpty)
    }
}
