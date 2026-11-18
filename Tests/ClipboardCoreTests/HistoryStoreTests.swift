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

    // MARK: concealed (1Password)

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
