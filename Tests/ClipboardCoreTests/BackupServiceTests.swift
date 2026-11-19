import Foundation
import Testing
@testable import ClipboardCore

/// The backup is the user's only way to recover history and tags on a new Mac;
/// a failed backup must never destroy the previous good one.
struct BackupServiceTests {
    let root: URL
    let local: URL
    let iCloud: URL
    let fileManager = FailingCopyFileManager()

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupTests-\(UUID().uuidString)", isDirectory: true)
        local = root.appendingPathComponent("Clipboard", isDirectory: true)
        iCloud = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iCloud, withIntermediateDirectories: true)
    }

    var backupDirectory: URL {
        iCloud.appendingPathComponent("\(Config.appName)/Backup", isDirectory: true)
    }

    func makeService() -> BackupService {
        BackupService(localDirectory: local, iCloudDriveRoot: iCloud, fileManager: fileManager)
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Valid history.json content told apart by `marker`: restore() refuses files it cannot decode.
    func historyJSON(_ marker: String) -> String {
        #"[{"id":"00000000-0000-0000-0000-000000000001","createdAt":0,"kind":"text","text":"\#(marker)","contentHash":"\#(marker)","isConcealed":false}]"#
    }

    /// Valid tags.json content told apart by `marker`.
    func tagsJSON(_ marker: String) -> String {
        #"[{"id":"00000000-0000-0000-0000-000000000002","name":"\#(marker)","colorIndex":0}]"#
    }

    func writeLocalData(history: String) throws {
        try write(historyJSON(history), to: local.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: local.appendingPathComponent("tags.json"))
        try write("png", to: local.appendingPathComponent("images/a.png"))
    }

    // MARK: availability

    @Test func unavailableWithoutTheICloudDriveFolder() throws {
        try FileManager.default.removeItem(at: iCloud)
        let service = makeService()

        #expect(!service.isAvailable)
        #expect(throws: BackupError.iCloudUnavailable) {
            try service.backUp()
        }
    }

    // MARK: round trip

    @Test func backUpAndRestoreRoundTripIncludingImages() throws {
        // Restoring on another Mac brings everything back as it was.
        try writeLocalData(history: "v1")
        let service = makeService()
        try service.backUp()
        try FileManager.default.removeItem(at: local)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)

        try service.restore()

        #expect(service.hasBackup)
        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("v1"))
        #expect(read(local.appendingPathComponent("tags.json")) == tagsJSON("tags"))
        #expect(read(local.appendingPathComponent("images/a.png")) == "png")
        #expect(!FileManager.default.fileExists(atPath: iCloud.appendingPathComponent("\(Config.appName)/Backup.tmp").path))
    }

    @Test func restoredFilesAreReadByFilePersistence() throws {
        let tag = Tag(name: "Work", colorIndex: 1)
        FilePersistence(directory: local).saveTags([tag])
        FilePersistence(directory: local).save([])
        let service = makeService()
        try service.backUp()
        FilePersistence(directory: local).saveTags([])

        try service.restore()

        #expect(FilePersistence(directory: local).loadTags() == [tag])
    }

    @Test func restoreAlwaysLeavesAnImagesDirectory() throws {
        // Review focus 2: FilePersistence only creates images/ at launch; without it
        // every image copied after a restore would be silently dropped.
        try write(historyJSON("v1"), to: local.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: local.appendingPathComponent("tags.json"))
        let service = makeService()
        try service.backUp()

        try service.restore()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: local.appendingPathComponent("images").path, isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
    }

    @Test func backupFromAnInstallWithoutTagsFileIsRestorable() throws {
        // A v1 install has no tags.json until the first tag change; its backup must
        // not be refused by restore() as incomplete forever.
        try write(historyJSON("v1"), to: local.appendingPathComponent("history.json"))
        try write("png", to: local.appendingPathComponent("images/a.png"))
        let service = makeService()
        try service.backUp()

        try service.restore()

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("v1"))
        #expect(read(local.appendingPathComponent("tags.json")) == "[]")
        #expect(read(local.appendingPathComponent("images/a.png")) == "png")
    }

    // MARK: failures

    @Test func corruptBackupIsRefusedAndLocalDataIsUntouched() throws {
        // Loading an undecodable history would start empty, delete the local images and
        // let the next hourly backup upload the empty history: refuse it before the swap.
        try writeLocalData(history: "local")
        try write("not json", to: backupDirectory.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: backupDirectory.appendingPathComponent("tags.json"))

        #expect(throws: BackupError.corruptBackup) {
            try makeService().restore()
        }

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("local"))
        #expect(read(local.appendingPathComponent("tags.json")) == tagsJSON("tags"))
        #expect(read(local.appendingPathComponent("images/a.png")) == "png")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Clipboard.restore.tmp").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Clipboard.restore.old").path))
    }

    @Test func backupWithCorruptTagsIsRefused() throws {
        // A corrupt tags.json would orphan every tagged item after the restore.
        try writeLocalData(history: "local")
        try write(historyJSON("v1"), to: backupDirectory.appendingPathComponent("history.json"))
        try write("not json", to: backupDirectory.appendingPathComponent("tags.json"))

        #expect(throws: BackupError.corruptBackup) {
            try makeService().restore()
        }
        #expect(read(local.appendingPathComponent("tags.json")) == tagsJSON("tags"))
    }

    @Test func backupMissingAnImageItsHistoryListsIsRefusedAndLocalDataIsUntouched() throws {
        // The restore replaces the local images folder: an image item restored without its file is lost for good,
        // and iCloud may simply not have listed that file yet.
        try writeLocalData(history: "local")
        let imageItem = #"[{"id":"00000000-0000-0000-0000-000000000001","createdAt":0,"kind":"image","imageFileName":"b.png","contentHash":"b","isConcealed":false}]"#
        try write(imageItem, to: backupDirectory.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: backupDirectory.appendingPathComponent("tags.json"))
        try FileManager.default.createDirectory(at: backupDirectory.appendingPathComponent("images"), withIntermediateDirectories: true)

        #expect(throws: BackupError.incompleteBackup) {
            try makeService().restore()
        }

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("local"))
        #expect(read(local.appendingPathComponent("images/a.png")) == "png")
    }

    @Test func backupWhoseImagesFolderIsALinkIsRefused() throws {
        // A link restored as the local images folder points somewhere else: the next save would delete there
        // everything the history does not name.
        try writeLocalData(history: "local")
        let elsewhere = root.appendingPathComponent("Projects", isDirectory: true)
        try write("code", to: elsewhere.appendingPathComponent("main.swift"))
        try write(historyJSON("v1"), to: backupDirectory.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: backupDirectory.appendingPathComponent("tags.json"))
        try FileManager.default.createSymbolicLink(
            at: backupDirectory.appendingPathComponent("images"), withDestinationURL: elsewhere
        )

        #expect(throws: BackupError.corruptBackup) {
            try makeService().restore()
        }

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("local"))
        #expect(read(elsewhere.appendingPathComponent("main.swift")) == "code")
    }

    @Test func backupWithAnythingButFilesInItsImagesFolderIsRefused() throws {
        // backUp() only ever copies image files: a folder or a link in there was not made by the app.
        try writeLocalData(history: "local")
        try write(historyJSON("v1"), to: backupDirectory.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: backupDirectory.appendingPathComponent("tags.json"))
        try write("x", to: backupDirectory.appendingPathComponent("images/folder/x.png"))

        #expect(throws: BackupError.corruptBackup) {
            try makeService().restore()
        }

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("local"))
    }

    @Test func failureHalfWayThroughKeepsThePreviousBackup() throws {
        try writeLocalData(history: "v1")
        let service = makeService()
        try service.backUp()
        try writeLocalData(history: "v2")
        fileManager.failWhenCopying = "images"

        #expect(throws: CocoaError.self) {
            try service.backUp()
        }

        #expect(read(backupDirectory.appendingPathComponent("history.json")) == historyJSON("v1"))
        #expect(read(backupDirectory.appendingPathComponent("images/a.png")) == "png")
    }

    @Test func failedRestoreLeavesLocalDataUntouched() throws {
        try writeLocalData(history: "v1")
        let service = makeService()
        try service.backUp()
        try writeLocalData(history: "local")
        fileManager.failWhenCopying = "images"

        #expect(throws: CocoaError.self) {
            try service.restore()
        }

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("local"))
    }

    @Test func staleTemporaryFolderFromACrashIsReplaced() throws {
        // Review focus 5.
        try write("junk", to: iCloud.appendingPathComponent("\(Config.appName)/Backup.tmp/junk.txt"))
        try writeLocalData(history: "v1")

        try makeService().backUp()

        #expect(read(backupDirectory.appendingPathComponent("history.json")) == historyJSON("v1"))
        #expect(!FileManager.default.fileExists(atPath: backupDirectory.appendingPathComponent("junk.txt").path))
    }

    @Test func backUpWithNoLocalHistoryFailsAndKeepsThePreviousBackup() throws {
        // Review focus 5: a fresh install must not replace a good backup with nothing.
        try write(historyJSON("v1"), to: backupDirectory.appendingPathComponent("history.json"))

        #expect(throws: BackupError.nothingToBackUp) {
            try makeService().backUp()
        }
        #expect(read(backupDirectory.appendingPathComponent("history.json")) == historyJSON("v1"))
    }

    @Test func restoreWithoutBackupOrWithAnIncompleteOneFails() throws {
        let service = makeService()
        #expect(!service.hasBackup)
        #expect(throws: BackupError.noBackup) {
            try service.restore()
        }

        // iCloud has not downloaded history.json yet.
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        #expect(throws: BackupError.incompleteBackup) {
            try service.restore()
        }
    }

    @Test func restoreWithoutTagsFileFailsAndKeepsLocalData() throws {
        // A partial iCloud download must not wipe the local tags.
        try writeLocalData(history: "local")
        try write(historyJSON("v1"), to: backupDirectory.appendingPathComponent("history.json"))

        #expect(throws: BackupError.incompleteBackup) {
            try makeService().restore()
        }
        #expect(read(local.appendingPathComponent("tags.json")) == tagsJSON("tags"))
        #expect(read(local.appendingPathComponent("images/a.png")) == "png")
    }

    @Test func restoreWithICloudPlaceholderImagesFailsAndKeepsLocalData() throws {
        // ".a.png.icloud" is an image iCloud has not downloaded yet.
        try writeLocalData(history: "local")
        try write(historyJSON("v1"), to: backupDirectory.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: backupDirectory.appendingPathComponent("tags.json"))
        try write("", to: backupDirectory.appendingPathComponent("images/.a.png.icloud"))

        #expect(throws: BackupError.incompleteBackup) {
            try makeService().restore()
        }
        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("local"))
        #expect(read(local.appendingPathComponent("images/a.png")) == "png")
    }

    @Test func failureSwappingInRestoredFilesRollsBackToTheLocalData() throws {
        // Local has no images/, so only the staged images/ move fails, after
        // history.json and tags.json were already swapped in.
        try writeLocalData(history: "v1")
        let service = makeService()
        try service.backUp()
        try FileManager.default.removeItem(at: local.appendingPathComponent("images"))
        try write(historyJSON("local"), to: local.appendingPathComponent("history.json"))
        try write(tagsJSON("localTags"), to: local.appendingPathComponent("tags.json"))
        fileManager.failWhenMoving = "images"

        #expect(throws: CocoaError.self) {
            try service.restore()
        }

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("local"))
        #expect(read(local.appendingPathComponent("tags.json")) == tagsJSON("localTags"))
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("images").path))
    }

    @Test func failureSettingAsideLocalImagesRollsBackToTheLocalData() throws {
        try writeLocalData(history: "v1")
        let service = makeService()
        try service.backUp()
        try writeLocalData(history: "local")
        fileManager.failWhenMoving = "images"

        #expect(throws: CocoaError.self) {
            try service.restore()
        }

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("local"))
        #expect(read(local.appendingPathComponent("tags.json")) == tagsJSON("tags"))
        #expect(read(local.appendingPathComponent("images/a.png")) == "png")
    }

    var leftoverRestoreFolder: URL {
        root.appendingPathComponent("Clipboard.restore.old", isDirectory: true)
    }

    func preservedFolders() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Clipboard.restore.old-") }
    }

    @Test func leftoverRestoreFolderIsNeverDeleted() throws {
        // After a crash mid-swap it can hold the only copy of the user's original data.
        try write(historyJSON("v1"), to: local.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: local.appendingPathComponent("tags.json"))
        let service = makeService()
        try service.backUp()
        try write(historyJSON("orig"), to: leftoverRestoreFolder.appendingPathComponent("history.json"))
        try write(tagsJSON("origTags"), to: leftoverRestoreFolder.appendingPathComponent("tags.json"))

        try service.restore()

        #expect(!FileManager.default.fileExists(atPath: leftoverRestoreFolder.path))
        let preserved = try preservedFolders()
        #expect(preserved.count == 1)
        #expect(read(preserved[0].appendingPathComponent("history.json")) == historyJSON("orig"))
        #expect(read(preserved[0].appendingPathComponent("tags.json")) == tagsJSON("origTags"))
        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("v1"))
    }

    @Test func itemsMissingLocallyAreMovedBackFromALeftoverRestoreFolder() throws {
        try writeLocalData(history: "v1")
        let service = makeService()
        try service.backUp()
        try FileManager.default.removeItem(at: local.appendingPathComponent("history.json"))
        try FileManager.default.removeItem(at: local.appendingPathComponent("images"))
        try write(historyJSON("orig"), to: leftoverRestoreFolder.appendingPathComponent("history.json"))
        try write(tagsJSON("origTags"), to: leftoverRestoreFolder.appendingPathComponent("tags.json"))
        try write("origPng", to: leftoverRestoreFolder.appendingPathComponent("images/b.png"))
        fileManager.failWhenCopying = "images"

        // The restore itself fails, so the data moved back from the leftover folder must stay.
        #expect(throws: CocoaError.self) {
            try service.restore()
        }

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("orig"))
        #expect(read(local.appendingPathComponent("images/b.png")) == "origPng")
        let preserved = try preservedFolders()
        #expect(preserved.count == 1)
        #expect(read(preserved[0].appendingPathComponent("tags.json")) == tagsJSON("origTags"))
    }

    @Test func failureReplacingTheBackupKeepsThePreviousBackupRestorable() throws {
        try writeLocalData(history: "v1")
        let service = makeService()
        try service.backUp()
        try writeLocalData(history: "v2")
        fileManager.failWhenMoving = "Backup.tmp"

        #expect(throws: CocoaError.self) {
            try service.backUp()
        }
        fileManager.failWhenMoving = nil

        #expect(service.hasBackup)
        try service.restore()
        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("v1"))
    }

    @Test func interruptedBackupSwapLeavingOnlyTheOldBackupIsRecovered() throws {
        // A crash between renaming Backup to Backup.old and Backup.tmp to Backup.
        let old = iCloud.appendingPathComponent("\(Config.appName)/Backup.old", isDirectory: true)
        try write(historyJSON("v1"), to: old.appendingPathComponent("history.json"))
        try write(tagsJSON("tags"), to: old.appendingPathComponent("tags.json"))
        let service = makeService()

        #expect(service.hasBackup)
        try service.restore()

        #expect(read(local.appendingPathComponent("history.json")) == historyJSON("v1"))
        #expect(FileManager.default.fileExists(atPath: backupDirectory.path))
    }

    // MARK: change detection

    @Test func changesAreDetectedFromModificationDates() throws {
        // The hourly backup must skip when nothing changed, also across relaunches.
        try writeLocalData(history: "v1")
        let service = makeService()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for path in ["history.json", "tags.json", "images"] {
            try FileManager.default.setAttributes(
                [.modificationDate: t0], ofItemAtPath: local.appendingPathComponent(path).path
            )
        }

        #expect(service.hasChanges(since: nil))
        #expect(!service.hasChanges(since: t0.addingTimeInterval(10)))

        try FileManager.default.setAttributes(
            [.modificationDate: t0.addingTimeInterval(20)],
            ofItemAtPath: local.appendingPathComponent("images").path
        )
        #expect(service.hasChanges(since: t0.addingTimeInterval(10)))
    }

    @Test func nothingToBackUpMeansNoChanges() {
        #expect(!makeService().hasChanges(since: nil))
    }
}
