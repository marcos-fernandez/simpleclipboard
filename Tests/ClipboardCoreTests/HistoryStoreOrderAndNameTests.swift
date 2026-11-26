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

    // MARK: order

    @Test func aTagWithoutAnOrderShowsItsItemsNewestFirst() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two", "three"], to: store)

        #expect(texts(of: store, in: tagged.tag) == ["three", "two", "one"])
        #expect(store.tags[0].itemOrder == nil)
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

        #expect(store.moveItem(id: tagged.items[0].id, toPlaceOf: tagged.items[0].id))

        #expect(store.tags[0].itemOrder == nil)
        #expect(store.tags[0].itemOrderChangedAt == nil)
    }

    @Test func anItemIsNotMovedToThePlaceOfOneOfAnotherTagOrOfTheHistory() throws {
        let store = makeStore()
        let tagged = try addTagged(["one", "two"], to: store)
        let loose = try #require(store.add(.text("loose"), source: safari, concealed: false))

        #expect(!store.moveItem(id: tagged.items[0].id, toPlaceOf: loose.id))
        #expect(!store.moveItem(id: loose.id, toPlaceOf: tagged.items[0].id))
        #expect(store.tags[0].itemOrder == nil)
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
