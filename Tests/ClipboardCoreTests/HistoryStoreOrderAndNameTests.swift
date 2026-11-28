import Foundation
import Testing
@testable import ClipboardCore

/// The order the user gives the items of a tag, and the name given to an item: both are the user's own work, kept
/// through copies, pastes, restarts and the sync between Macs.
@MainActor
struct HistoryStoreOrderAndNameTests {
    let persistence = InMemoryPersistence()
    let clock = TestClock()
    let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
    let onePassword = SourceApp(bundleID: "com.1password.1password", name: "1Password")

    func makeStore() -> HistoryStore {
        HistoryStore(persistence: persistence, now: { [clock] in clock.current })
    }

    /// A tag with one item per text, copied in that order: the tag shows them the other way round, newest first.
    func addTagged(_ texts: [String], to store: HistoryStore) throws -> (items: [ClipItem], tag: ClipboardCore.Tag) {
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        var items: [ClipItem] = []
        for text in texts {
            clock.advance(1)
            let item = try #require(store.add(.text(text), source: safari, concealed: false))
            #expect(store.setTag(itemID: item.id, tagID: tag.id))
            items.append(item)
        }
        return (items, tag)
    }

    func texts(of store: HistoryStore, in tag: ClipboardCore.Tag) -> [String?] {
        store.search("", in: .tag(tag.id)).map(\.text)
    }

    /// A tag as an app from before the order saved it: three items, "three" the newest, and no order.
    func storeWithATagSavedWithoutAnOrder() -> (store: HistoryStore, tag: ClipboardCore.Tag) {
        let tag = Tag(name: "Work", colorIndex: 0, changedAt: clock.current)
        let texts = ["three", "two", "one"]
        persistence.storedTags = [tag]
        persistence.stored = texts.enumerated().map { index, text in
            ClipItem(
                createdAt: clock.current.addingTimeInterval(-Double(index)), kind: .text, text: text,
                imageFileName: nil, contentHash: "hash-\(text)", source: safari, isConcealed: false, expiresAt: nil,
                tagID: tag.id, tagChangedAt: clock.current
            )
        }
        return (makeStore(), tag)
    }

    func state(_ device: String, of store: HistoryStore) -> SyncState {
        let snapshot = store.syncSnapshot()
        return SyncState(
            deviceID: device, publishedAt: clock.current, items: snapshot.items, tags: snapshot.tags, deletions: []
        )
    }

    // MARK: order

    @Test func eachItemGivenATagGoesFirstInItAndIsWrittenInItsOrder() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)

        #expect(texts(of: store, in: tagged.tag) == ["three", "two", "one"])
        #expect(store.tags[0].itemOrder == store.search("", in: .tag(tagged.tag.id)).map(\.contentHash))
        #expect(persistence.storedTags == store.tags)
    }

    @Test func aTagSavedWithoutAnOrderShowsItsItemsNewestFirst() {
        let saved = storeWithATagSavedWithoutAnOrder()

        #expect(texts(of: saved.store, in: saved.tag) == ["three", "two", "one"])
        #expect(saved.store.tags[0].itemOrder == nil)
    }

    // Pasting dates the item now. In a tag that is still by date that would take it to the front: the order on
    // show is written down first, so the tag stays as the user sees it.
    @Test func pastingAnItemOfATagSavedWithoutAnOrderLeavesItWhereItIs() throws {
        let saved = storeWithATagSavedWithoutAnOrder()
        let one = try #require(saved.store.items.first { $0.text == "one" })
        clock.advance(60)

        saved.store.promote(id: one.id)

        #expect(texts(of: saved.store, in: saved.tag) == ["three", "two", "one"])
        #expect(saved.store.items.map(\.text) == ["one", "three", "two"])
        #expect(saved.store.tags[0].itemOrder == ["hash-three", "hash-two", "hash-one"])
        #expect(saved.store.tags[0].itemOrderChangedAt == clock.current)
    }

    @Test func copyingAgainAnItemOfATagThatDoesNotListItLeavesItWhereItIs() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)
        // As saved by an app from before the order.
        persistence.storedTags[0].itemOrder = nil
        let relaunched = makeStore()
        clock.advance(60)

        relaunched.add(.text("one"), source: safari, concealed: false)

        #expect(texts(of: relaunched, in: tagged.tag) == ["three", "two", "one"])
        #expect(relaunched.items.map(\.text) == ["one", "three", "two"])
    }

    // The stamp of a tag is renewed by choosing the tag again and by a restore: neither is a move.
    @Test func anItemItsTagDoesNotListStaysWhereItIsWhenItsTagIsChosenAgain() throws {
        let saved = storeWithATagSavedWithoutAnOrder()
        // An order that lists only one of the three, as after a merge with a Mac that knows nothing of the order:
        // the other two go before it, newest first.
        persistence.storedTags[0].itemOrder = ["hash-three"]
        let store = makeStore()
        let one = try #require(store.items.first { $0.text == "one" })
        #expect(texts(of: store, in: saved.tag) == ["two", "one", "three"])
        clock.advance(60)

        #expect(store.setTag(itemID: one.id, tagID: saved.tag.id))

        #expect(texts(of: store, in: saved.tag) == ["two", "one", "three"])
    }

    // Left in the order, it would go back to its old place when a Mac that knows nothing of the order gives it
    // the tag again, and not first as an item that comes in.
    @Test func anItemThatLeavesATagLeavesItsOrder() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)
        clock.advance(60)

        store.setTag(itemID: tagged.items[1].id, tagID: nil)

        #expect(store.tags[0].itemOrder == [tagged.items[2].contentHash, tagged.items[0].contentHash])
        #expect(store.tags[0].itemOrderChangedAt == clock.current)
    }

    @Test func anItemMovedToAnotherTagLeavesTheOrderOfTheFirstAndGoesFirstInTheSecond() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        let home = try #require(store.createTag(name: "Home", colorIndex: 1))
        let other = try #require(store.add(.text("other"), source: safari, concealed: false))
        store.setTag(itemID: other.id, tagID: home.id)

        store.setTag(itemID: tagged.items[0].id, tagID: home.id)

        #expect(texts(of: store, in: tagged.tag) == ["two"])
        #expect(store.tags[0].itemOrder == [tagged.items[1].contentHash])
        #expect(texts(of: store, in: home) == ["one", "other"])
    }

    @Test func anItemMovedForwardTakesThePlaceOfTheOtherAndTheOnesBetweenMoveBack() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)

        #expect(store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[2].id))

        #expect(texts(of: store, in: tagged.tag) == ["one", "three", "two"])
        #expect(persistence.storedTags == store.tags)
    }

    @Test func anItemMovedBackTakesThePlaceOfTheOtherAndTheOnesBetweenMoveForward() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)

        #expect(store.moveItem(id: tagged.items[2].id, toPlaceOf: tagged.items[0].id))

        #expect(texts(of: store, in: tagged.tag) == ["two", "one", "three"])
    }

    @Test func movingAnItemIsStampedForTheOtherMacs() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        clock.advance(60)

        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[1].id)

        #expect(store.tags[0].itemOrderChangedAt == clock.current)
        // The name and the colour of the tag did not change.
        #expect(store.tags[0].changedAt == tagged.tag.changedAt)
    }

    @Test func anItemLeftWhereItIsChangesNothing() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)

        let tagsBefore = store.tags
        clock.advance(60)

        #expect(store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[0].id))

        #expect(store.tags == tagsBefore)
    }

    @Test func anItemIsNotMovedToThePlaceOfOneOfAnotherTagOrOfTheHistory() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        let loose = try #require(store.add(.text("loose"), source: safari, concealed: false))
        let tagsBefore = store.tags

        #expect(!store.moveItem(id: tagged.items[0].id, toPlaceOf: loose.id))
        #expect(!store.moveItem(id: loose.id, toPlaceOf: tagged.items[0].id))
        #expect(store.tags == tagsBefore)
    }

    // The point of the order: pasting an item dates it now, which puts it first in the history, and it must not
    // put it first in its tag.
    @Test func pastingOrCopyingAgainAnItemLeavesItWhereItIsInItsTag() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[2].id)
        clock.advance(60)

        store.promote(id: tagged.items[1].id)
        store.add(.text("three"), source: safari, concealed: false)

        #expect(texts(of: store, in: tagged.tag) == ["one", "three", "two"])
        #expect(store.items.map(\.text) == ["three", "two", "one"])
    }

    @Test func anItemGivenATagThatHasAnOrderGoesFirst() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[1].id)
        clock.advance(60)
        let new = try #require(store.add(.text("new"), source: safari, concealed: false))

        store.setTag(itemID: new.id, tagID: tagged.tag.id)

        #expect(texts(of: store, in: tagged.tag) == ["new", "one", "two"])
    }

    // By when they were tagged and not by when they were copied: the one just tagged is the one looked for.
    @Test func ofTheItemsTaggedSinceTheOrderWasGivenTheLastOneTaggedGoesFirst() throws {
        let store = makeStore()
        let older = try #require(store.add(.text("older"), source: safari, concealed: false))
        clock.advance(60)
        let newer = try #require(store.add(.text("newer"), source: safari, concealed: false))
        let tagged = try addTagged(["one", "two"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[1].id)
        clock.advance(60)

        store.setTag(itemID: newer.id, tagID: tagged.tag.id)
        clock.advance(60)
        store.setTag(itemID: older.id, tagID: tagged.tag.id)

        #expect(texts(of: store, in: tagged.tag) == ["older", "newer", "one", "two"])
    }

    // It is the tag marked in the menu of the card, and the first option of the picker in the tab of that tag.
    @Test func choosingTheTagAnItemAlreadyHasLeavesItWhereItIs() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[2].id)
        let tagsBefore = store.tags
        clock.advance(60)

        #expect(store.setTag(itemID: tagged.items[2].id, tagID: tagged.tag.id))

        #expect(texts(of: store, in: tagged.tag) == ["one", "three", "two"])
        // The order was not touched, so the other Macs are not told of a new one.
        #expect(store.tags == tagsBefore)
    }

    // It left the tag and came back: it is a new arrival, not the item that had a place there.
    @Test func anItemGivenItsTagAgainGoesFirstAndNotWhereItWas() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[2].id)
        store.setTag(itemID: tagged.items[1].id, tagID: nil)
        clock.advance(60)

        store.setTag(itemID: tagged.items[1].id, tagID: tagged.tag.id)

        #expect(texts(of: store, in: tagged.tag) == ["two", "one", "three"])
        #expect(store.tags[0].itemOrderChangedAt == clock.current)
    }

    @Test func aSearchInATagKeepsItsOrder() throws {
        let store = makeStore()
        let tagged = try addTagged(["alpha one", "beta", "alpha two"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[2].id)

        #expect(store.search("alpha", in: .tag(tagged.tag.id)).map(\.text) == ["alpha one", "alpha two"])
    }

    @Test func theOrderIsReadBackAtTheNextLaunch() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[2].id)

        let relaunched = makeStore()

        #expect(texts(of: relaunched, in: tagged.tag) == ["one", "three", "two"])
    }

    // MARK: name

    @Test func aNamedItemIsCalledByItsNameAndAnotherByItsApp() throws {
        let store = makeStore()
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        #expect(store.items[0].displayName == "Safari")
        clock.advance(60)

        #expect(store.renameItem(id: item.id, name: "  Greeting "))

        #expect(store.items[0].customName == "Greeting")
        #expect(store.items[0].displayName == "Greeting")
        #expect(store.items[0].customNameChangedAt == clock.current)
        #expect(persistence.stored == store.items)
    }

    @Test(arguments: ["", "   ", "\n"])
    func aBlankNameTakesTheNameAway(name: String) throws {
        let store = makeStore()
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        store.renameItem(id: item.id, name: "Greeting")
        clock.advance(60)

        #expect(store.renameItem(id: item.id, name: name))

        #expect(store.items[0].customName == nil)
        #expect(store.items[0].displayName == "Safari")
        // Stamped: taking a name away is a change other Macs have to apply.
        #expect(store.items[0].customNameChangedAt == clock.current)
    }

    @Test func theSameNameAgainIsNoChange() throws {
        let store = makeStore()
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        store.renameItem(id: item.id, name: "Greeting")
        let stamp = store.items[0].customNameChangedAt
        clock.advance(60)

        #expect(store.renameItem(id: item.id, name: "Greeting"))

        #expect(store.items[0].customNameChangedAt == stamp)
    }

    @Test func concealedItemsCannotBeNamed() throws {
        let store = makeStore()
        let secret = try #require(store.add(.text("s3cr3t"), source: onePassword, concealed: true))

        #expect(!store.renameItem(id: secret.id, name: "Password"))
        #expect(store.items[0].customName == nil)
    }

    @Test func copyingAnItemAgainKeepsItsName() throws {
        let store = makeStore()
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        store.renameItem(id: item.id, name: "Greeting")
        let stamp = store.items[0].customNameChangedAt
        clock.advance(60)

        store.add(.text("hello"), source: safari, concealed: false)

        #expect(store.items.map(\.customName) == ["Greeting"])
        #expect(store.items[0].customNameChangedAt == stamp)
    }

    @Test func anItemIsFoundByItsName() throws {
        let store = makeStore()
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        store.add(.text("other"), source: safari, concealed: false)
        store.renameItem(id: item.id, name: "Greeting")

        #expect(store.search("greet").map(\.text) == ["hello"])
    }

    // MARK: sync

    @Test func theNameAndTheOrderArePublishedAndTakenFromAMerge() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[1].id)
        store.renameItem(id: tagged.items[0].id, name: "First")
        let snapshot = store.syncSnapshot()
        let other = HistoryStore(persistence: InMemoryPersistence(), now: { [clock] in clock.current })

        #expect(other.applySync(SyncMerge.Result(items: snapshot.items, tags: snapshot.tags)))

        #expect(other.search("", in: .tag(tagged.tag.id)).map(\.customName) == ["First", nil])
        #expect(other.tags == store.tags)
        // A second round with the same data changes nothing: the stamps come back as they were sent.
        #expect(!other.applySync(SyncMerge.Result(items: snapshot.items, tags: snapshot.tags)))
    }

    // The whole way: what one Mac publishes, merged with what the other has, and applied there.
    @Test func theNameAndTheOrderReachAnotherMacThroughTheMerge() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[1].id)
        store.renameItem(id: tagged.items[0].id, name: "First")
        let other = HistoryStore(persistence: InMemoryPersistence(), now: { [clock] in clock.current })
        other.add(.text("its own"), source: safari, concealed: false)

        let result = SyncMerge.merge(
            local: state("B", of: other), remotes: [state("A", of: store)], concealedHashes: [], now: clock.current
        )
        #expect(other.applySync(result))

        #expect(other.search("", in: .tag(tagged.tag.id)).map(\.text) == ["one", "two"])
        #expect(other.search("", in: .tag(tagged.tag.id)).map(\.customName) == ["First", nil])
        #expect(other.items.map(\.text).contains("its own"))
        // Merged again with what it now has, nothing is left to apply.
        let again = SyncMerge.merge(
            local: state("B", of: other), remotes: [state("A", of: store)], concealedHashes: [], now: clock.current
        )
        #expect(!other.applySync(again))
    }

    // A restore is the user saying which data is right: against another Mac that named the item and moved it later,
    // what was restored is what both end with.
    @Test func whatARestoreBringsBackWinsOverALaterNameAndOrderOnAnotherMac() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        store.renameItem(id: tagged.items[0].id, name: "Restored")
        let other = HistoryStore(persistence: InMemoryPersistence(), now: { [clock] in clock.current })
        other.applySync(SyncMerge.Result(items: store.syncSnapshot().items, tags: store.syncSnapshot().tags))
        clock.advance(60)
        other.renameItem(id: other.items[1].id, name: "Later")
        other.moveItem(id: other.items[0].id, toPlaceOf: other.items[1].id)
        clock.advance(60)

        store.reloadFromDisk(markingChanges: true)
        let result = SyncMerge.merge(
            local: state("B", of: other), remotes: [state("A", of: store)], concealedHashes: [], now: clock.current
        )
        other.applySync(result)

        #expect(other.search("", in: .tag(tagged.tag.id)).map(\.text) == ["two", "one"])
        #expect(other.search("", in: .tag(tagged.tag.id)).map(\.customName) == [nil, "Restored"])
    }

    // MARK: files saved before

    @Test func whatWasSavedBeforeTheNamesAndTheOrderIsReadAsItIs() throws {
        let decoder = JSONDecoder()
        let item = """
            {"id":"173BD2D1-FE79-452C-B3EA-DEFDE5DC8F99","createdAt":817415678.2,"kind":"text","text":"hello",
            "contentHash":"abc","sourceAppBundleID":"com.apple.Safari","sourceAppName":"Safari","isConcealed":false,
            "tagID":"4C4C0352-7BB0-457C-8164-240FD96F11F5","tagChangedAt":817298645.7}
            """
        let tag = """
            {"id":"4C4C0352-7BB0-457C-8164-240FD96F11F5","name":"Work","colorIndex":0,"changedAt":817201709.7}
            """
        let syncItem = """
            {"contentHash":"abc","kind":"text","text":"hello","createdAt":817415678.2,"sourceAppName":"Safari",
            "tagID":"4C4C0352-7BB0-457C-8164-240FD96F11F5","tagChangedAt":817298645.7}
            """

        let savedItem = try decoder.decode(ClipItem.self, from: Data(item.utf8))
        let savedTag = try decoder.decode(ClipboardCore.Tag.self, from: Data(tag.utf8))
        let publishedItem = try decoder.decode(SyncItem.self, from: Data(syncItem.utf8))
        let publishedTag = try decoder.decode(SyncTag.self, from: Data(tag.utf8))

        #expect(savedItem.customName == nil && savedItem.customNameChangedAt == nil)
        #expect(savedItem.displayName == "Safari")
        #expect(savedTag.itemOrder == nil && savedTag.itemOrderChangedAt == nil)
        #expect(publishedItem.customName == nil && publishedItem.customNameChangedAt == nil)
        #expect(publishedTag.itemOrder == nil && publishedTag.itemOrderChangedAt == nil)
    }

    @Test func aRestoreMakesItsNamesAndItsOrderWinOverTheOtherMacs() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[1].id)
        store.renameItem(id: tagged.items[0].id, name: "First")
        clock.advance(60)

        store.reloadFromDisk(markingChanges: true)

        #expect(store.tags[0].itemOrderChangedAt == clock.current)
        #expect(store.items.allSatisfy { $0.customNameChangedAt == $0.tagChangedAt })
        #expect(store.items.allSatisfy { ($0.customNameChangedAt ?? .distantPast) >= clock.current })
    }
}
