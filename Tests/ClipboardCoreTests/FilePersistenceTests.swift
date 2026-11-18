import Foundation
import Testing
@testable import ClipboardCore

/// History must survive app restarts, and a damaged file must never stop the app
/// from starting (the user would lose clipboard capture entirely).
struct FilePersistenceTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func makeItem(_ text: String) -> ClipItem {
        ClipItem(
            createdAt: Date(timeIntervalSince1970: 1_000_000.123),
            kind: .text,
            text: text,
            imageFileName: nil,
            contentHash: "hash-\(text)",
            source: SourceApp(bundleID: "com.apple.Safari", name: "Safari"),
            isConcealed: false,
            expiresAt: nil
        )
    }

    @Test func missingFileLoadsEmptyHistory() {
        #expect(FilePersistence(directory: directory).load().isEmpty)
    }

    @Test func savedHistoryIsReadBackByANewInstance() {
        let items = [makeItem("one"), makeItem("two")]
        FilePersistence(directory: directory).save(items)

        #expect(FilePersistence(directory: directory).load() == items)
    }

    @Test func corruptFileIsMovedAsideAndHistoryStartsEmpty() throws {
        let historyURL = directory.appendingPathComponent("history.json")
        try Data("not json".utf8).write(to: historyURL)

        let loaded = FilePersistence(directory: directory).load()

        #expect(loaded.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: historyURL.path))
        let backup = try Data(contentsOf: directory.appendingPathComponent("history.json.bak"))
        #expect(String(decoding: backup, as: UTF8.self) == "not json")
    }

    @Test func fileThatExistsButCannotBeReadIsMovedAsideNotOverwritten() throws {
        // A read failure is not "no history": treating it as empty would let the next save
        // replace the user's history with an empty list.
        let historyURL = directory.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)
        let persistence = FilePersistence(directory: directory)

        #expect(persistence.load().isEmpty)
        persistence.save([makeItem("new")])

        var isDirectory: ObjCBool = false
        let backupPath = directory.appendingPathComponent("history.json.bak").path
        #expect(FileManager.default.fileExists(atPath: backupPath, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(FilePersistence(directory: directory).load().map(\.text) == ["new"])
    }

    @Test func repeatedCorruptionNeverDeletesAnEarlierBackup() throws {
        // The first .bak may be the only copy of the user's history; a later corruption
        // (even within the same second) must be kept next to it, not replace it.
        let historyURL = directory.appendingPathComponent("history.json")
        for content in ["first", "second", "third"] {
            try Data(content.utf8).write(to: historyURL)
            #expect(FilePersistence(directory: directory).load().isEmpty)
        }

        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("history.json.bak") }
        let contents = try backups.map { name in
            String(decoding: try Data(contentsOf: directory.appendingPathComponent(name)), as: UTF8.self)
        }
        #expect(backups.contains("history.json.bak"))
        #expect(Set(contents) == ["first", "second", "third"])
    }

    @Test func fileThatCannotBeMovedAsideIsNotOverwrittenBySave() throws {
        // If the damaged file stays in place, saving would destroy it: the user's data wins
        // over recording new copies until the file can be dealt with.
        let historyURL = directory.appendingPathComponent("history.json")
        try Data("not json".utf8).write(to: historyURL)
        let persistence = FilePersistence(directory: directory)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        #expect(persistence.load().isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        persistence.save([makeItem("new")])

        #expect(String(decoding: try Data(contentsOf: historyURL), as: UTF8.self) == "not json")
    }

    @Test func imagesAreKeptWhileTheDamagedHistoryIsStillInPlace() throws {
        // The history left in place may be recovered by hand; deleting the images it points to
        // (the store asks for that on every save) would leave it pointing at nothing.
        let historyURL = directory.appendingPathComponent("history.json")
        try Data("not json".utf8).write(to: historyURL)
        let persistence = FilePersistence(directory: directory)
        try persistence.writeImage(Data([1, 2, 3]), named: "a.png")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        #expect(persistence.load().isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        persistence.deleteImages(notIn: [])

        #expect(persistence.readImage(named: "a.png") == Data([1, 2, 3]))
    }

    @Test func savingResumesOnceTheUnmovableFileIsGone() throws {
        // Refusing to save is only a guard for the damaged file, not a permanent stop.
        let historyURL = directory.appendingPathComponent("history.json")
        try Data("not json".utf8).write(to: historyURL)
        let persistence = FilePersistence(directory: directory)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        _ = persistence.load()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        try FileManager.default.removeItem(at: historyURL)
        #expect(persistence.load().isEmpty)
        persistence.save([makeItem("new")])

        #expect(FilePersistence(directory: directory).load().map(\.text) == ["new"])
    }

    @Test func imagesAreWrittenReadAndPrunedByName() throws {
        let persistence = FilePersistence(directory: directory)
        try persistence.writeImage(Data([1, 2, 3]), named: "keep.png")
        try persistence.writeImage(Data([4, 5, 6]), named: "drop.png")

        persistence.deleteImages(notIn: ["keep.png"])

        #expect(persistence.readImage(named: "keep.png") == Data([1, 2, 3]))
        #expect(persistence.readImage(named: "drop.png") == nil)
    }

    // MARK: tags

    @Test func historyWrittenBeforeTagsExistedIsStillRead() throws {
        // Users upgrading must keep their history without a migration.
        let legacy = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":0,"kind":"text",\
        "text":"stale","contentHash":"h","isConcealed":false}]
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("history.json"))

        let loaded = FilePersistence(directory: directory).load()

        #expect(loaded.map(\.text) == ["stale"])
        #expect(loaded.first?.tagID == nil)
    }

    @Test func tagIDIsSavedWithTheItem() {
        var item = makeItem("one")
        item.tagID = UUID()
        FilePersistence(directory: directory).save([item])

        #expect(FilePersistence(directory: directory).load() == [item])
    }

    @Test func missingTagsFileLoadsNoTags() {
        #expect(FilePersistence(directory: directory).loadTags().isEmpty)
    }

    @Test func savedTagsAreReadBackByANewInstance() {
        let tags = [Tag(name: "Work", colorIndex: 0), Tag(name: "Home", colorIndex: 7)]
        FilePersistence(directory: directory).saveTags(tags)

        #expect(FilePersistence(directory: directory).loadTags() == tags)
    }

    @Test func corruptTagsFileIsMovedAsideAndTagsStartEmpty() throws {
        // A damaged tags.json must not stop the app; the user can recover it from .bak.
        let tagsURL = directory.appendingPathComponent("tags.json")
        try Data("not json".utf8).write(to: tagsURL)

        let loaded = FilePersistence(directory: directory).loadTags()

        #expect(loaded.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: tagsURL.path))
        let backup = try Data(contentsOf: directory.appendingPathComponent("tags.json.bak"))
        #expect(String(decoding: backup, as: UTF8.self) == "not json")
    }
}
