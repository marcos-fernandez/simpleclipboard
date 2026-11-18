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
