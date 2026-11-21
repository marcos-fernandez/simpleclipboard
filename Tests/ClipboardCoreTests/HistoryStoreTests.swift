import Foundation
import Testing
@testable import ClipboardCore

@MainActor
struct HistoryStoreTests {
    let persistence = InMemoryPersistence()
    let clock = TestClock()
    let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
    let onePassword = SourceApp(bundleID: "com.1password.1password", name: "1Password")

    func makeStore() -> HistoryStore {
        HistoryStore(persistence: persistence, now: { [clock] in clock.current })
    }

    // MARK: capture

    @Test func newCopyGoesFirst() {
        let store = makeStore()
        store.add(.text("first"), source: safari, concealed: false)
        store.add(.text("second"), source: safari, concealed: false)

        #expect(store.items.map(\.text) == ["second", "first"])
    }

    @Test(arguments: ["", "   ", "\n\t "])
    func blankTextIsNotRecorded(text: String) {
        // Review focus 3: a blank card is noise the user has to scroll past.
        let store = makeStore()
        #expect(store.add(.text(text), source: safari, concealed: false) == nil)
        #expect(store.items.isEmpty)
    }

    // Every change rewrites the whole history and republishes it to iCloud, so one huge
    // item stored once would make every later copy slow. Oversized content is never stored.

    @Test func textOverTheLimitIsNotRecordedNorSaved() {
        let store = makeStore()
        let huge = String(repeating: "a", count: Config.maxTextBytes + 1)

        #expect(store.add(.text(huge), source: safari, concealed: false) == nil)
        #expect(store.items.isEmpty)
        #expect(persistence.saveCount == 0)
    }

    @Test func textLimitCountsUTF8BytesNotCharacters() {
        // What gets written and synced is UTF-8, so "é" (2 bytes) counts twice.
        let store = makeStore()
        let accented = String(repeating: "é", count: Config.maxTextBytes / 2 + 1)

        #expect(store.add(.text(accented), source: safari, concealed: false) == nil)
        #expect(store.items.isEmpty)
    }

    @Test func textExactlyAtTheLimitIsKept() {
        // The limit is meant to stop pathological copies, not to cut off a legitimate one at the edge.
        let store = makeStore()
        let atLimit = String(repeating: "a", count: Config.maxTextBytes)

        #expect(store.add(.text(atLimit), source: safari, concealed: false) != nil)
        #expect(store.items.count == 1)
    }

    @Test func imageOverTheLimitIsNotWrittenNorRecorded() {
        let store = makeStore()
        let huge = Data(count: Config.maxImageBytes + 1)

        #expect(store.add(.image(huge), source: safari, concealed: false) == nil)
        #expect(store.items.isEmpty)
        #expect(persistence.images.isEmpty)
        #expect(persistence.saveCount == 0)
    }

    @Test func imageExactlyAtTheLimitIsKept() {
        let store = makeStore()
        let atLimit = Data(count: Config.maxImageBytes)

        #expect(store.add(.image(atLimit), source: safari, concealed: false) != nil)
        #expect(store.items.count == 1)
        #expect(persistence.images.count == 1)
    }

    @Test func recopyingMovesTheItemToTheFrontWithoutDuplicating() {
        let store = makeStore()
        store.add(.text("a"), source: safari, concealed: false)
        store.add(.text("b"), source: safari, concealed: false)
        store.add(.text("a"), source: safari, concealed: false)

        #expect(store.items.map(\.text) == ["a", "b"])
    }

    // MARK: retention

    /// A typical month of copying (~800 items) must fit, so the cap is 1000.
    @Test func historyIsCappedAtMaxItemsDroppingTheOldest() {
        #expect(Config.maxItems == 1000)
        let store = makeStore()
        for index in 0...Config.maxItems {
            store.add(.text("item \(index)"), source: safari, concealed: false)
        }

        #expect(store.items.count == Config.maxItems)
        #expect(store.items.last?.text == "item 1")
    }

    @Test func itemsOlderThan30DaysAreDropped() {
        let store = makeStore()
        store.add(.text("old"), source: safari, concealed: false)
        clock.advance(Config.maxAge + 1)
        store.add(.text("new"), source: safari, concealed: false)

        #expect(store.items.map(\.text) == ["new"])
        #expect(persistence.stored.map(\.text) == ["new"])
    }

    @Test func itemsOlderThan30DaysOnDiskAreDroppedAtLaunch() {
        makeStore().add(.text("old"), source: safari, concealed: false)
        clock.advance(Config.maxAge + 1)

        #expect(makeStore().items.isEmpty)
    }

    // MARK: concealed

    @Test func aChangedLifetimeCountsForTheConcealedItemsAddedAfterIt() {
        let store = makeStore()
        store.add(.text("first"), source: onePassword, concealed: true)
        store.concealedLifetime = 60
        store.add(.text("second"), source: onePassword, concealed: true)

        clock.advance(61)
        store.purgeExpired()
        #expect(store.items.map(\.text) == ["first"])

        clock.advance(Config.concealedLifetime)
        store.purgeExpired()
        #expect(store.items.isEmpty)
    }

    @Test func concealedItemSurvivesJustUnder10MinutesAndIsGoneAfter() {
        let store = makeStore()
        store.add(.text("s3cr3t"), source: onePassword, concealed: true)

        clock.advance(Config.concealedLifetime - 1)
        store.purgeExpired()
        #expect(store.items.count == 1)

        clock.advance(2)
        store.purgeExpired()
        #expect(store.items.isEmpty)
    }

    @Test func concealedItemsNeverReachDisk() {
        let store = makeStore()
        store.add(.text("s3cr3t"), source: onePassword, concealed: true)
        store.add(.image(Data([9, 9, 9])), source: onePassword, concealed: true)
        store.add(.text("normal"), source: safari, concealed: false)

        #expect(persistence.stored.map(\.text) == ["normal"])
        #expect(persistence.images.isEmpty)
        #expect(store.imageData(for: store.items[1]) == Data([9, 9, 9]))
    }

    @Test func concealedCopyOfAPersistedValueRemovesItFromDisk() {
        // Review focus 4: a password once copied by hand must not stay on disk
        // after it is copied again from 1Password.
        let store = makeStore()
        store.add(.text("s3cr3t"), source: safari, concealed: false)
        store.add(.text("s3cr3t"), source: onePassword, concealed: true)

        #expect(store.items.count == 1)
        #expect(store.items[0].isConcealed)
        #expect(persistence.stored.isEmpty)
    }

    // MARK: search

    @Test func searchIgnoresCaseAndAccents() {
        let store = makeStore()
        store.add(.text("Canción de Ñandú"), source: safari, concealed: false)
        store.add(.text("something else"), source: safari, concealed: false)

        #expect(store.search("cancion de nandu").map(\.text) == ["Canción de Ñandú"])
    }

    @Test func searchNeverRevealsConcealedItems() {
        // Review focus 1: typing part of a password must not single out its card.
        let store = makeStore()
        store.add(.text("s3cr3t"), source: onePassword, concealed: true)

        #expect(store.search("s3cr").isEmpty)
    }

    @Test func emptySearchShowsEverythingIncludingConcealed() {
        let store = makeStore()
        store.add(.text("s3cr3t"), source: onePassword, concealed: true)
        store.add(.text("hello"), source: safari, concealed: false)

        #expect(store.search("  ").count == 2)
    }

    // The panel asks for the results on every body pass and on every key press: each search reads every text (up to
    // 2 MiB each) on the main thread, so the same question must be answered once until the store changes, and a change
    // must never leave the panel showing the old answer.

    @Test func repeatingASearchDoesNotSearchAgain() {
        let store = makeStore()
        store.add(.text("hello"), source: safari, concealed: false)

        let first = store.search("hel")
        let second = store.search("hel")

        #expect(first == second)
        #expect(store.searchCount == 1)
    }

    @Test func aDifferentQueryOrScopeSearchesAgain() throws {
        let store = makeStore()
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        store.setTag(itemID: item.id, tagID: tag.id)

        #expect(store.search("hel").map(\.text) == ["hello"])
        #expect(store.search("xyz").isEmpty)
        #expect(store.search("hel", in: .tag(tag.id)).map(\.text) == ["hello"])
        #expect(store.searchCount == 3)
    }

    @Test func aCaptureIsFoundBySearchAfterTheSameQueryWasCached() {
        let store = makeStore()
        store.add(.text("hello"), source: safari, concealed: false)
        _ = store.search("hel")

        store.add(.text("help"), source: safari, concealed: false)

        #expect(store.search("hel").map(\.text) == ["help", "hello"])
    }

    @Test func aRemovedItemLeavesTheCachedResults() throws {
        let store = makeStore()
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        _ = store.search("")

        store.remove(id: item.id)

        #expect(store.search("").isEmpty)
    }

    @Test func aTagChangeIsSeenByTheCachedTagScope() throws {
        let store = makeStore()
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        #expect(store.search("", in: .tag(tag.id)).isEmpty)

        store.setTag(itemID: item.id, tagID: tag.id)

        #expect(store.search("", in: .tag(tag.id)).map(\.text) == ["hello"])
    }

    @Test func aPurgedConcealedItemIsNotKeptAliveByTheCache() {
        // The cached results hold the item itself: kept after the purge, they would keep a secret in memory.
        let store = makeStore()
        store.add(.text("s3cr3t"), source: onePassword, concealed: true)
        #expect(store.search("").count == 1)

        clock.advance(Config.concealedLifetime + 1)
        store.purgeExpired()

        #expect(store.search("").isEmpty)
    }

    @Test func aSyncRoundIsSeenByTheCachedSearch() {
        let store = makeStore()
        _ = store.search("")
        let remote = SyncItem(
            contentHash: "hash-remote", kind: .text, text: "from another Mac", imageFileName: nil,
            createdAt: clock.current, sourceAppBundleID: nil, sourceAppName: nil,
            tagID: nil, tagChangedAt: SyncState.unstamped
        )

        store.applySync(SyncMerge.Result(items: [remote], tags: []))

        #expect(store.search("").map(\.text) == ["from another Mac"])
    }

    @Test func aReloadFromDiskIsSeenByTheCachedSearch() {
        let store = makeStore()
        store.add(.text("before restore"), source: safari, concealed: false)
        _ = store.search("")
        persistence.stored = []

        store.reloadFromDisk(markingChanges: false)

        #expect(store.search("").isEmpty)
    }

    // MARK: images

    @Test func recopyingTheSameImageKeepsItsFile() {
        // Review focus 5: dedup removes the old item; its PNG is shared with the new one.
        let store = makeStore()
        let png = Data([1, 2, 3])
        store.add(.image(png), source: safari, concealed: false)
        store.add(.text("in between"), source: safari, concealed: false)
        store.add(.image(png), source: safari, concealed: false)

        #expect(store.items.count == 2)
        #expect(store.imageData(for: store.items[0]) == png)
        #expect(persistence.images.count == 1)
    }

    @Test func imageThatCannotBeWrittenIsDropped() {
        persistence.failImageWrites = true
        let store = makeStore()

        #expect(store.add(.image(Data([1])), source: safari, concealed: false) == nil)
        #expect(store.items.isEmpty)
    }

    @Test func removingAnImageDeletesItsFile() throws {
        let store = makeStore()
        let item = try #require(store.add(.image(Data([1])), source: safari, concealed: false))

        store.remove(id: item.id)

        #expect(store.items.isEmpty)
        #expect(persistence.images.isEmpty)
    }

    @Test func imagesAreKeptWhenTheHistoryCannotBeSaved() throws {
        // A failed save (disk full) leaves the history on disk still listing the item: deleting its image
        // anyway would leave that item pointing at nothing on the next launch.
        let store = makeStore()
        let item = try #require(store.add(.image(Data([1])), source: safari, concealed: false))
        persistence.failSaves = true

        store.remove(id: item.id)

        #expect(persistence.stored.map(\.id) == [item.id])
        #expect(persistence.images.count == 1)
    }

    // MARK: user actions

    @Test func pastingAnOldItemPromotesItToTheFront() throws {
        let store = makeStore()
        let first = try #require(store.add(.text("a"), source: safari, concealed: false))
        store.add(.text("b"), source: safari, concealed: false)
        clock.advance(60)

        store.promote(id: first.id)

        #expect(store.items.map(\.text) == ["a", "b"])
        #expect(store.items[0].createdAt == clock.current)
        #expect(persistence.stored.map(\.text) == ["a", "b"])
    }

    @Test func clearingHistoryEmptiesMemoryAndDiskWhenNothingIsTagged() {
        let store = makeStore()
        store.add(.text("a"), source: safari, concealed: false)
        store.add(.image(Data([1])), source: safari, concealed: false)

        store.removeUntagged()

        #expect(store.items.isEmpty)
        #expect(persistence.stored.isEmpty)
        #expect(persistence.images.isEmpty)
    }
}
