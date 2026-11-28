import Foundation
import Testing
@testable import ClipboardCore

/// Tagged items are the user's permanent collection (named, coloured collections):
/// losing one silently is the worst failure this feature can have.
@MainActor
struct HistoryStoreTagTests {
    let persistence = InMemoryPersistence()
    let clock = TestClock()
    let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
    let onePassword = SourceApp(bundleID: "com.1password.1password", name: "1Password")
    let fortyDays: TimeInterval = 40 * 24 * 60 * 60

    func makeStore() -> HistoryStore {
        HistoryStore(persistence: persistence, now: { [clock] in clock.current })
    }

    func addTagged(_ text: String, to store: HistoryStore) throws -> (item: ClipItem, tag: ClipboardCore.Tag) {
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let item = try #require(store.add(.text(text), source: safari, concealed: false))
        #expect(store.setTag(itemID: item.id, tagID: tag.id))
        return (item, tag)
    }

    // MARK: catalogue

    @Test func tagNameIsTrimmedAndTagsArePersisted() {
        let store = makeStore()
        store.createTag(name: "  Work ", colorIndex: 3)

        #expect(store.tags.map(\.name) == ["Work"])
        #expect(persistence.storedTags == store.tags)
    }

    @Test(arguments: ["", "   ", "\n"])
    func blankTagNameIsRejected(name: String) {
        let store = makeStore()

        #expect(store.createTag(name: name, colorIndex: 0) == nil)
        #expect(store.tags.isEmpty)
    }

    @Test(arguments: [-1, Config.tagColorCount])
    func colourOutsideThePaletteIsRejected(colorIndex: Int) {
        let store = makeStore()

        #expect(store.createTag(name: "Work", colorIndex: colorIndex) == nil)
    }

    // MARK: tagging

    @Test func concealedItemsCannotBeTagged() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let secret = try #require(store.add(.text("s3cr3t"), source: onePassword, concealed: true))

        #expect(!store.setTag(itemID: secret.id, tagID: tag.id))
        #expect(store.items[0].tagID == nil)
    }

    @Test func unknownTagIsRejected() throws {
        let store = makeStore()
        let item = try #require(store.add(.text("a"), source: safari, concealed: false))

        #expect(!store.setTag(itemID: item.id, tagID: UUID()))
        #expect(store.items[0].tagID == nil)
    }

    @Test func tagIsPersistedWithTheItem() throws {
        let store = makeStore()
        let (item, tag) = try addTagged("a", to: store)

        #expect(persistence.stored.first { $0.id == item.id }?.tagID == tag.id)
    }

    @Test func untaggingAnOldItemKeepsItAsIfJustCopied() throws {
        // Removing a tag must never make the item vanish at once.
        let store = makeStore()
        let (item, _) = try addTagged("old", to: store)
        clock.advance(fortyDays)
        store.add(.text("recent"), source: safari, concealed: false)

        #expect(store.setTag(itemID: item.id, tagID: nil))
        store.purgeExpired()

        #expect(store.items.map(\.text) == ["old", "recent"])
        #expect(store.items[0].createdAt == clock.current)
        #expect(store.items[0].tagID == nil)
    }

    // MARK: retention

    @Test func taggedItemOutlivesTheThirtyDayLimit() throws {
        let store = makeStore()
        let (item, _) = try addTagged("saved", to: store)
        clock.advance(Config.maxAge * 2)

        store.purgeExpired()

        #expect(store.items.map(\.id) == [item.id])
        #expect(makeStore().items.map(\.id) == [item.id])
    }

    @Test func taggedImageSurvivesThePurgeAndItsPNGStaysOnDisk() throws {
        // Tagged items are permanent; images live in a separate file that the purge
        // deletes when no remaining item refers to it.
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let image = try #require(store.add(.image(Data([1, 2, 3])), source: safari, concealed: false))
        let fileName = try #require(image.imageFileName)
        #expect(store.setTag(itemID: image.id, tagID: tag.id))
        store.add(.text("ephemeral"), source: safari, concealed: false)
        clock.advance(Config.maxAge * 2)

        store.purgeExpired()

        #expect(store.items.map(\.id) == [image.id])
        #expect(persistence.images[fileName] == Data([1, 2, 3]))
        #expect(store.imageData(for: try #require(store.items.first)) == Data([1, 2, 3]))
    }

    @Test func capCountsOnlyUntaggedItems() throws {
        // 500+ new copies must not push a tagged item out.
        let store = makeStore()
        let (item, _) = try addTagged("saved", to: store)
        for index in 0...Config.maxItems {
            store.add(.text("item \(index)"), source: safari, concealed: false)
        }

        #expect(store.items.contains { $0.id == item.id })
        #expect(store.items.filter { $0.tagID == nil }.count == Config.maxItems)
        #expect(!store.items.contains { $0.text == "item 0" })
    }

    @Test func orphanTagAfterLosingTagsFileDoesNotPurgeTheItemAtLaunch() {
        // Review focus 1: a missing tags.json leaves orphan tagIDs (an unreadable one keeps them, see
        // below); the pinned item must not be dropped by the 30-day rule on the next launch.
        let pinned = ClipItem(
            createdAt: clock.current, kind: .text, text: "pinned", imageFileName: nil,
            contentHash: "h", source: safari, isConcealed: false, expiresAt: nil, tagID: UUID()
        )
        persistence.stored = [pinned]
        clock.advance(Config.maxAge * 2)

        let store = makeStore()

        #expect(store.items.map(\.id) == [pinned.id])
        #expect(store.items[0].tagID == nil)
        #expect(store.items[0].createdAt == clock.current)
        #expect(persistence.stored.first?.tagID == nil)
    }

    func taggedItem(_ text: String, tagID: UUID) -> ClipItem {
        ClipItem(
            createdAt: clock.current, kind: .text, text: text, imageFileName: nil,
            contentHash: "hash-\(text)", source: safari, isConcealed: false, expiresAt: nil, tagID: tagID
        )
    }

    @Test func itemsKeepTheirTagsWhenTheTagsFileIsUnreadable() {
        // A damaged tags file loses names and colours, not which items belong together. Untagging the items
        // would save that loss over history.json too, so a repaired tags file or the other Macs (through sync)
        // could no longer give the tags back, and the items would start to expire.
        let work = UUID()
        let home = UUID()
        persistence.stored = [taggedItem("a", tagID: work), taggedItem("b", tagID: home), taggedItem("c", tagID: work)]
        persistence.tagsWereLost = true
        clock.advance(Config.maxAge * 2)

        let store = makeStore()

        #expect(store.items.map(\.tagID) == [work, home, work])
        #expect(persistence.stored.map(\.tagID) == [work, home, work])
        #expect(store.tags.map(\.id) == [work, home])
        #expect(persistence.storedTags.map(\.id) == [work, home])
    }

    @Test func tagsRecreatedForAnUnreadableFileNeverWinOverTheRealOnes() throws {
        // Each stands in for a tag that may still exist on another Mac. Two with the same name would be fused into
        // one by the merge, and one that won over the real version, even a tag never stamped (saved before sync),
        // would replace the user's name and colour on every Mac.
        let work = UUID()
        let home = UUID()
        persistence.stored = [taggedItem("a", tagID: work), taggedItem("b", tagID: home)]
        persistence.tagsWereLost = true
        let store = makeStore()
        let local = SyncState(
            deviceID: "Z", publishedAt: clock.current, items: [], tags: store.syncSnapshot().tags, deletions: []
        )
        let real = SyncTag(id: work, name: "Work", colorIndex: 3, changedAt: SyncState.unstamped)
        let remote = SyncState(deviceID: "A", publishedAt: clock.current, items: [], tags: [real], deletions: [])

        let merged = SyncMerge.merge(local: local, remotes: [remote], concealedHashes: [], now: clock.current)

        #expect(Set(store.tags.map(\.name)).count == 2)
        #expect(merged.tags.map(\.id) == [work, home])
        #expect(merged.tags.first == real)
    }

    // MARK: dedup

    @Test func recopyingATaggedItemKeepsItsTagAndMovesItFirst() throws {
        let store = makeStore()
        let (_, tag) = try addTagged("a", to: store)
        store.add(.text("b"), source: safari, concealed: false)

        let recopied = try #require(store.add(.text("a"), source: safari, concealed: false))

        #expect(recopied.tagID == tag.id)
        #expect(store.items.map(\.text) == ["a", "b"])
        #expect(store.items[0].tagID == tag.id)
    }

    @Test func concealedCopyOfATaggedValueRemovesItFromDiskAndIsNotTagged() throws {
        // Review focus 3 / user decision: a password must never stay on disk, even if tagged.
        let store = makeStore()
        _ = try addTagged("s3cr3t", to: store)

        store.add(.text("s3cr3t"), source: onePassword, concealed: true)

        #expect(store.items.count == 1)
        #expect(store.items[0].isConcealed)
        #expect(store.items[0].tagID == nil)
        #expect(persistence.stored.isEmpty)
    }

    // MARK: clearing

    @Test func clearingHistoryKeepsTaggedItems() throws {
        // Review focus 4 / user decision: tagged items are permanent.
        let store = makeStore()
        let (item, _) = try addTagged("saved", to: store)
        store.add(.text("ephemeral"), source: safari, concealed: false)

        store.removeUntagged()

        #expect(store.items.map(\.id) == [item.id])
        #expect(persistence.stored.map(\.id) == [item.id])
    }

    // MARK: editing

    @Test func renameTrimsAndRejectsBlankNames() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))

        #expect(store.renameTag(id: tag.id, name: "  Invoices "))
        #expect(!store.renameTag(id: tag.id, name: "   "))
        #expect(store.tags.map(\.name) == ["Invoices"])
        #expect(persistence.storedTags.map(\.name) == ["Invoices"])
    }

    @Test func recolorRejectsColoursOutsideThePalette() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))

        #expect(store.recolorTag(id: tag.id, colorIndex: 5))
        #expect(!store.recolorTag(id: tag.id, colorIndex: Config.tagColorCount))
        #expect(store.tags.map(\.colorIndex) == [5])
    }

    @Test func deletingATagKeepsAllItsItems() throws {
        // Deleting a tag never deletes its (possibly very old) items.
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let a = try #require(store.add(.text("a"), source: safari, concealed: false))
        let b = try #require(store.add(.text("b"), source: safari, concealed: false))
        store.setTag(itemID: a.id, tagID: tag.id)
        store.setTag(itemID: b.id, tagID: tag.id)
        clock.advance(fortyDays)
        store.add(.text("c"), source: safari, concealed: false)

        store.deleteTag(id: tag.id)
        store.purgeExpired()

        #expect(store.tags.isEmpty)
        #expect(store.items.map(\.text) == ["b", "a", "c"])
        #expect(store.items.allSatisfy { $0.tagID == nil })
        #expect(persistence.storedTags.isEmpty)
        #expect(persistence.stored.count == 3)
    }

    // MARK: scoped search

    @Test func tagTabOnlyShowsItsOwnItems() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Invoices", colorIndex: 0))
        let april = try #require(store.add(.text("invoice april"), source: safari, concealed: false))
        store.add(.text("invoice may"), source: safari, concealed: false)
        store.setTag(itemID: april.id, tagID: tag.id)

        #expect(store.search("", in: .tag(tag.id)).map(\.text) == ["invoice april"])
        #expect(store.search("invoice", in: .tag(tag.id)).map(\.text) == ["invoice april"])
        #expect(store.search("invoice", in: .history).count == 2)
    }

    @Test func historyTabSearchStillHidesConcealedItems() {
        let store = makeStore()
        store.add(.text("s3cr3t"), source: onePassword, concealed: true)

        #expect(store.search("s3cr", in: .history).isEmpty)
        #expect(store.search("", in: .history).count == 1)
    }

    // MARK: reload (restore)

    @Test func reloadFromDiskReplacesStateAndDropsInMemoryConcealedItems() {
        // After a restore the store must show exactly the restored data.
        let store = makeStore()
        store.add(.text("s3cr3t"), source: onePassword, concealed: true)
        store.add(.text("local"), source: safari, concealed: false)
        let restoredTag = Tag(name: "Restored", colorIndex: 2)
        persistence.stored = [
            ClipItem(
                createdAt: clock.current, kind: .text, text: "restored", imageFileName: nil,
                contentHash: "r", source: safari, isConcealed: false, expiresAt: nil, tagID: restoredTag.id
            ),
        ]
        persistence.storedTags = [restoredTag]

        store.reloadFromDisk(markingChanges: true)

        #expect(store.items.map(\.text) == ["restored"])
        #expect(store.items[0].tagID == restoredTag.id)
        // A restore counts as a tag change now, so sync does not take it for older than a deletion elsewhere.
        // The order of its items too, even the lack of one: it is the restored one that has to stay.
        var stampedTag = restoredTag
        stampedTag.changedAt = clock.current
        stampedTag.itemOrderChangedAt = clock.current
        #expect(store.tags == [stampedTag])
    }
}
