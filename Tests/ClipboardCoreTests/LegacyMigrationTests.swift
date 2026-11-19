import Foundation
import Testing
@testable import ClipboardCore

/// The app was renamed from Clipboard to SimpleClipboard. Users must keep their history,
/// tags, iCloud backup and backup state; a second launch must never touch anything again.
struct LegacyMigrationTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: directories

    @Test func legacyDirectoryIsMovedWhenTheNewOneDoesNotExist() throws {
        let legacy = root.appendingPathComponent("Clipboard", isDirectory: true)
        let current = root.appendingPathComponent("SimpleClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: legacy.appendingPathComponent("history.json"))

        #expect(try LegacyMigration.moveDirectory(from: legacy, to: current, recognisedBy: ["history.json"]))

        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        let moved = try Data(contentsOf: current.appendingPathComponent("history.json"))
        #expect(String(decoding: moved, as: UTF8.self) == "history")
    }

    @Test func existingNewDirectoryIsNeverOverwritten() throws {
        // After the first launch the new folder holds the live data; a stale legacy
        // folder (e.g. recreated by an old copy of the app) must not replace it.
        let legacy = root.appendingPathComponent("Clipboard", isDirectory: true)
        let current = root.appendingPathComponent("SimpleClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("history.json"))
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: current.appendingPathComponent("history.json"))

        #expect(try !LegacyMigration.moveDirectory(from: legacy, to: current, recognisedBy: ["history.json"]))

        let kept = try Data(contentsOf: current.appendingPathComponent("history.json"))
        #expect(String(decoding: kept, as: UTF8.self) == "new")
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func nothingHappensWithoutALegacyDirectory() throws {
        let current = root.appendingPathComponent("SimpleClipboard", isDirectory: true)

        #expect(try !LegacyMigration.moveDirectory(
            from: root.appendingPathComponent("Clipboard"), to: current, recognisedBy: ["history.json"]
        ))
        #expect(!FileManager.default.fileExists(atPath: current.path))
    }

    @Test func aClipboardFolderThatIsNotTheOldAppsIsLeftAlone() throws {
        // "Clipboard" is a common name: on a fresh install, another app's folder or the user's own would be taken
        // over, and the images in its images/ deleted by the first save.
        let legacy = root.appendingPathComponent("Clipboard", isDirectory: true)
        let current = root.appendingPathComponent("SimpleClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("theirs".utf8).write(to: legacy.appendingPathComponent("images/photo.png"))

        #expect(try !LegacyMigration.moveDirectory(from: legacy, to: current, recognisedBy: ["history.json"]))

        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("images/photo.png").path))
        #expect(!FileManager.default.fileExists(atPath: current.path))
    }

    @Test(arguments: ["Backup", "Sync"])
    func theOldICloudFolderIsRecognisedByAnyOfItsFolders(name: String) throws {
        // The old app's iCloud Drive folder holds only a backup, only sync data, or both.
        let legacy = root.appendingPathComponent("Clipboard", isDirectory: true)
        let current = root.appendingPathComponent("SimpleClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent(name), withIntermediateDirectories: true)

        #expect(try LegacyMigration.moveDirectory(from: legacy, to: current, recognisedBy: ["Backup", "Sync"]))
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent(name).path))
    }

    // MARK: defaults

    @Test func backupStateIsCopiedWithoutOverwritingNewValues() throws {
        // Losing lastBackupDate or the first-launch decision would re-run the
        // first-launch restore logic on a Mac that already settled it.
        let legacyName = "LegacyMigrationTests.legacy.\(UUID().uuidString)"
        let currentName = "LegacyMigrationTests.current.\(UUID().uuidString)"
        let legacy = try #require(UserDefaults(suiteName: legacyName))
        let current = try #require(UserDefaults(suiteName: currentName))
        defer {
            legacy.removePersistentDomain(forName: legacyName)
            current.removePersistentDomain(forName: currentName)
        }
        let date = Date(timeIntervalSince1970: 1_000_000)
        legacy.set(date, forKey: "lastBackupDate")
        legacy.set(true, forKey: "backupBootstrapDone")
        legacy.set(true, forKey: "loginItemRegistered")
        current.set(false, forKey: "backupBootstrapDone")

        LegacyMigration.copyDefaults(
            keys: ["lastBackupDate", "backupBootstrapDone", "backupBootstrapLocalWasEmpty"],
            from: legacy,
            to: current
        )

        #expect(current.object(forKey: "lastBackupDate") as? Date == date)
        #expect(current.bool(forKey: "backupBootstrapDone") == false)
        #expect(current.object(forKey: "backupBootstrapLocalWasEmpty") == nil)
        #expect(current.object(forKey: "loginItemRegistered") == nil)
    }
}
