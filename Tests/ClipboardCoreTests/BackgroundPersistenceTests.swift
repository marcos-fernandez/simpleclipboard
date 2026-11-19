import Foundation
import Testing
@testable import ClipboardCore

/// The store saves the whole history after every change; written on the main thread, that froze the panel and the
/// clipboard polling. Written in the background, the files must still end up exactly as they would have: in order,
/// the latest state last, and never an image deleted while a history that lists it is (or may end up) on disk.
@MainActor
struct BackgroundPersistenceTests {
    let gated = GatedPersistence()
    let png = Data([1, 2, 3])

    func text(_ value: String) -> ClipItem {
        ClipItem(
            createdAt: Date(timeIntervalSince1970: 1_000_000), kind: .text, text: value, imageFileName: nil,
            contentHash: "hash-\(value)", source: SourceApp(bundleID: nil, name: nil), isConcealed: false, expiresAt: nil
        )
    }

    func image(_ name: String) -> ClipItem {
        ClipItem(
            createdAt: Date(timeIntervalSince1970: 1_000_000), kind: .image, text: nil, imageFileName: name,
            contentHash: "hash-\(name)", source: SourceApp(bundleID: nil, name: nil), isConcealed: false, expiresAt: nil
        )
    }

    @Test func statesAreWrittenInOrderAndAWaitingStateIsReplacedByANewerOne() {
        // Writing every intermediate state would only delay the latest one; writing an older one after a newer one
        // would bring back what the user just deleted.
        let persistence = BackgroundPersistence(wrapping: gated)
        persistence.saveHistory([text("one")], tags: [])
        gated.waitUntilSaving()
        persistence.saveHistory([text("two")], tags: [])
        persistence.saveHistory([text("three")], tags: [])

        gated.release()
        gated.waitUntilSaving()
        gated.release()
        persistence.flush()

        #expect(gated.savedTexts == [["one"], ["three"]])
        #expect(gated.inner.stored.map(\.text) == ["three"])
    }

    @Test func tagsAreWrittenWithTheirHistory() {
        let persistence = BackgroundPersistence(wrapping: gated)
        let tags = [Tag(name: "Work", colorIndex: 0)]
        persistence.saveHistory([text("one")], tags: tags)
        gated.release()
        persistence.flush()

        #expect(gated.inner.storedTags == tags)
    }

    @Test func imagesNoLongerListedAreDeletedOnceTheHistoryIsWritten() throws {
        // Without it, every deleted or expired image would stay on disk (and in the backup) for ever.
        let persistence = BackgroundPersistence(wrapping: gated)
        try persistence.writeImage(png, named: "a.png")
        persistence.saveHistory([image("a.png")], tags: [])
        gated.release()
        persistence.flush()
        #expect(gated.inner.images["a.png"] == png)

        persistence.saveHistory([], tags: [])
        gated.release()
        persistence.flush()

        #expect(gated.inner.images.isEmpty)
    }

    @Test func imagesAreKeptWhenTheHistoryCannotBeSaved() throws {
        // The history left on disk still lists the image: deleting it would leave an item pointing at nothing.
        let persistence = BackgroundPersistence(wrapping: gated)
        try persistence.writeImage(png, named: "a.png")
        persistence.saveHistory([image("a.png")], tags: [])
        gated.release()
        persistence.flush()
        gated.inner.failSaves = true

        persistence.saveHistory([], tags: [])
        gated.release()
        persistence.flush()

        #expect(gated.inner.stored.map(\.imageFileName) == ["a.png"])
        #expect(gated.inner.images["a.png"] == png)
    }

    @Test func anImageListedByTheLatestStateSurvivesTheEndOfAnOlderSave() throws {
        // The store writes a new image, or sync copies one into images/, and only then hands over the state that
        // lists it; an older save finishing in between must not take it for unused.
        let persistence = BackgroundPersistence(wrapping: gated)
        persistence.saveHistory([text("zero")], tags: [])
        gated.waitUntilSaving()
        gated.release()
        persistence.saveHistory([text("one")], tags: [])
        gated.waitUntilSaving()
        try persistence.writeImage(png, named: "new.png")
        persistence.saveHistory([image("new.png")], tags: [])

        persistence.deleteUnusedImages()

        #expect(gated.inner.images["new.png"] == png)
        gated.release()
        gated.waitUntilSaving()
        gated.release()
        persistence.flush()
        #expect(gated.inner.stored.map(\.imageFileName) == ["new.png"])
        #expect(gated.inner.images["new.png"] == png)
    }

    @Test func anImageListedByTheStateBeingWrittenIsKeptEvenIfTheLatestDropsIt() throws {
        // If the latest state then fails to save, the one being written now stays on disk, listing the image.
        let persistence = BackgroundPersistence(wrapping: gated)
        try persistence.writeImage(png, named: "a.png")
        persistence.saveHistory([text("zero")], tags: [])
        gated.waitUntilSaving()
        gated.release()
        persistence.saveHistory([image("a.png")], tags: [])
        gated.waitUntilSaving()
        persistence.saveHistory([], tags: [])

        persistence.deleteUnusedImages()

        #expect(gated.inner.images["a.png"] == png)
        gated.release()
        gated.waitUntilSaving()
        gated.inner.failSaves = true
        gated.release()
        persistence.flush()
        #expect(gated.inner.stored.map(\.imageFileName) == ["a.png"])
        #expect(gated.inner.images["a.png"] == png)
    }

    @Test func loadingWaitsForTheStatesHandedOver() {
        // A restore replaces the files and then loads them: a write still on its way would land on top of the
        // restored files, and a load that does not wait would read an older history.
        let persistence = BackgroundPersistence(wrapping: gated)
        persistence.saveHistory([text("one")], tags: [Tag(name: "Work", colorIndex: 0)])
        gated.waitUntilSaving()
        DispatchQueue.global().async { [gated] in
            gated.release()
        }

        #expect(persistence.load().map(\.text) == ["one"])
        #expect(persistence.loadTags().map(\.name) == ["Work"])
    }

    @Test func aStoreOnFilesFindsItsLatestChangesOnDiskAfterAFlush() throws {
        // What the backup copies and what the next launch loads is what is on disk.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let persistence = BackgroundPersistence(wrapping: FilePersistence(directory: directory))
        let store = HistoryStore(persistence: persistence)
        let source = SourceApp(bundleID: nil, name: nil)
        store.add(.text("one"), source: source, concealed: false)
        store.add(.text("two"), source: source, concealed: false)

        persistence.flush()

        #expect(FilePersistence(directory: directory).load().map(\.text) == ["two", "one"])
    }
}
