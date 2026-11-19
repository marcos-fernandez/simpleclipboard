import Foundation
import Testing
@testable import ClipboardCore

/// Sync compares change times across Macs and replays deletions. A missing stamp makes an old change look new
/// (a tag lost on the other Mac); a missing deletion brings back on one Mac what was deleted on the other.
@MainActor
struct HistoryStoreSyncTests {
    let persistence = InMemoryPersistence()
    let clock = TestClock()
    let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
    let onePassword = SourceApp(bundleID: "com.1password.1password", name: "1Password")

    func makeStore() -> HistoryStore {
        HistoryStore(persistence: persistence, now: { [clock] in clock.current })
    }

    /// Collects what the store hands over to sync, one entry per call: how many times the recorder is called matters,
    /// because `SyncService` saves its file once per call.
    @MainActor
    final class Recorder {
        var calls: [[SyncDeletion]] = []

        var deletions: [SyncDeletion] {
            calls.flatMap { $0 }
        }
    }

    func recording(_ store: HistoryStore) -> Recorder {
        let recorder = Recorder()
        store.deletionRecorder = { recorder.calls.append($0) }
        return recorder
    }

    // MARK: stamps

    @Test func everyTagChangeIsStamped() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        #expect(tag.changedAt == clock.current)
        clock.advance(10)
        store.renameTag(id: tag.id, name: "Office")
        #expect(store.tags.first?.changedAt == clock.current)
        clock.advance(10)
        store.recolorTag(id: tag.id, colorIndex: 2)
        #expect(store.tags.first?.changedAt == clock.current)
        clock.advance(10)
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        store.setTag(itemID: item.id, tagID: tag.id)
        #expect(store.items.first?.tagChangedAt == clock.current)
        clock.advance(10)
        store.setTag(itemID: item.id, tagID: nil)
        #expect(store.items.first?.tagChangedAt == clock.current)
        #expect(store.items.first?.createdAt == clock.current)
    }

    // If a re-copy stamped the tag as changed now, it would beat a newer tag set on the other Mac.
    @Test func copyingAgainKeepsWhenTheTagWasSet() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let item = try #require(store.add(.text("hello"), source: safari, concealed: false))
        store.setTag(itemID: item.id, tagID: tag.id)
        let taggedAt = clock.current
        clock.advance(60)
        store.add(.text("hello"), source: safari, concealed: false)
        #expect(store.items.first?.tagID == tag.id)
        #expect(store.items.first?.tagChangedAt == taggedAt)
    }

    // A tags file that is missing or corrupt at launch is not a user decision. Stamping the untag as changed now would
    // beat the tagged version every other Mac still has (the newest tag change wins), and the tag would be lost
    // everywhere. The stamp stays, so on a tie the merge ("having a tag wins") gives the tag back from the others.
    @Test func clearingAnOrphanedTagKeepsWhenTheTagWasSet() {
        let taggedAt = Date(timeIntervalSince1970: 500_000)
        let stamped = ClipItem(
            createdAt: clock.current, kind: .text, text: "with date", imageFileName: nil,
            contentHash: "a", source: safari, isConcealed: false, expiresAt: nil, tagID: UUID(), tagChangedAt: taggedAt
        )
        let unstamped = ClipItem(
            createdAt: clock.current, kind: .text, text: "without date", imageFileName: nil,
            contentHash: "b", source: safari, isConcealed: false, expiresAt: nil, tagID: UUID(), tagChangedAt: nil
        )
        persistence.stored = [stamped, unstamped]
        clock.advance(60)
        let store = makeStore()
        #expect(store.items.allSatisfy { $0.tagID == nil })
        #expect(store.items.first { $0.contentHash == "a" }?.tagChangedAt == taggedAt)
        #expect(store.items.first { $0.contentHash == "b" }?.tagChangedAt == nil)
        // It still counts as just copied, so the 30-day rule does not purge it at launch.
        #expect(store.items.allSatisfy { $0.createdAt == clock.current })
    }

    @Test func filesSavedBeforeSyncStillLoad() throws {
        let item = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","createdAt":0,"kind":"text","text":"hello","contentHash":"h","isConcealed":false}"#
        let tag = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FE","name":"Work","colorIndex":0}"#
        #expect(try JSONDecoder().decode(ClipItem.self, from: Data(item.utf8)).tagChangedAt == nil)
        #expect(try JSONDecoder().decode(ClipboardCore.Tag.self, from: Data(tag.utf8)).changedAt == nil)
    }

    // MARK: deletions

    // The store hands every deletion to whatever recorder is connected; whether to keep it (sync on, or off after
    // joining) is `SyncService.record`'s decision. Without one nothing is handed over and nothing breaks.
    @Test func deletionsAreHandedOverToTheConnectedRecorder() throws {
        let store = makeStore()
        let first = try #require(store.add(.text("one"), source: safari, concealed: false))
        store.remove(id: first.id)
        let recorder = recording(store)
        let second = try #require(store.add(.text("two"), source: safari, concealed: false))
        clock.advance(5)
        store.remove(id: second.id)
        #expect(recorder.deletions == [.item(second.contentHash, at: clock.current)])
    }

    @Test func clearingTheHistoryDeletesOnlyUntaggedItems() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let kept = try #require(store.add(.text("pinned"), source: safari, concealed: false))
        store.setTag(itemID: kept.id, tagID: tag.id)
        let cleared = try #require(store.add(.text("loose"), source: safari, concealed: false))
        let recorder = recording(store)
        store.removeUntagged()
        #expect(recorder.deletions == [.item(cleared.contentHash, at: clock.current)])
    }

    // SyncService saves sync.json once per call: "Clear History…" with 1000 items must be one call, not 1000
    // rewrites of a file that holds up to 90 days of deletions, on the main thread.
    @Test func clearingTheHistoryHandsOverAllItsDeletionsInOneCall() throws {
        let store = makeStore()
        let first = try #require(store.add(.text("one"), source: safari, concealed: false))
        let second = try #require(store.add(.text("two"), source: safari, concealed: false))
        let third = try #require(store.add(.text("three"), source: safari, concealed: false))
        let recorder = recording(store)
        clock.advance(5)
        store.removeUntagged()
        #expect(recorder.calls.count == 1)
        #expect(Set(recorder.calls.first ?? []) == [
            .item(first.contentHash, at: clock.current),
            .item(second.contentHash, at: clock.current),
            .item(third.contentHash, at: clock.current),
        ])
    }

    // Same reason for a restore, which also records a tag deletion: items and tags go out together.
    @Test func aRestoreHandsOverItsItemAndTagDeletionsInOneCall() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let gone = try #require(store.add(.text("one"), source: safari, concealed: false))
        let alsoGone = try #require(store.add(.text("two"), source: safari, concealed: false))
        let recorder = recording(store)
        clock.advance(60)
        persistence.stored = []
        persistence.storedTags = []
        store.reloadFromDisk(markingChanges: true)
        #expect(recorder.calls.count == 1)
        #expect(Set(recorder.calls.first ?? []) == [
            .item(gone.contentHash, at: clock.current),
            .item(alsoGone.contentHash, at: clock.current),
            .tag(tag.id, at: clock.current),
        ])
    }

    // An empty call would still make SyncService rewrite sync.json for nothing.
    @Test func anOperationWithNothingToDeleteDoesNotCallTheRecorder() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let kept = try #require(store.add(.text("pinned"), source: safari, concealed: false))
        store.setTag(itemID: kept.id, tagID: tag.id)
        let recorder = recording(store)
        store.removeUntagged()
        store.reloadFromDisk(markingChanges: true)
        #expect(recorder.calls.isEmpty)
    }

    @Test func deletingATagIsHandedOver() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let recorder = recording(store)
        // Later than the tag's stamp: a deletion in the same instant would be dated just after it (`stamp(after:)`).
        clock.advance(1)
        store.deleteTag(id: tag.id)
        #expect(recorder.deletions == [.tag(tag.id, at: clock.current)])
    }

    // A value copied from 1Password must not stay as plain text on the other Mac.
    @Test func copyingASavedValueFrom1PasswordDeletesItEverywhere() throws {
        let store = makeStore()
        let saved = try #require(store.add(.text("key"), source: safari, concealed: false))
        let recorder = recording(store)
        clock.advance(5)
        store.add(.text("key"), source: onePassword, concealed: true)
        #expect(recorder.deletions == [.item(saved.contentHash, at: clock.current)])
    }

    @Test func concealedItemsAreNeverHandedOver() throws {
        let store = makeStore()
        let recorder = recording(store)
        let secret = try #require(store.add(.text("key"), source: onePassword, concealed: true))
        store.remove(id: secret.id)
        #expect(recorder.deletions.isEmpty)
    }

    // T1 privacy guards: the content hash is an unsalted SHA-256, so a deletion for a concealed value would let anyone
    // who can read the iCloud file check guesses at a 1Password secret. The tests below cover each path that records
    // deletions.

    // "Clear History…" clears concealed items from memory too, but only the plain item's hash may be handed over;
    // the fixture mixes both so the recorded list is checked exactly.
    @Test func clearingTheHistoryNeverRecordsADeletionForAConcealedItem() throws {
        let store = makeStore()
        let plain = try #require(store.add(.text("visible"), source: safari, concealed: false))
        store.add(.text("secret"), source: onePassword, concealed: true)
        let recorder = recording(store)
        clock.advance(5)
        store.removeUntagged()
        #expect(recorder.calls == [[.item(plain.contentHash, at: clock.current)]])
    }

    // With nothing but concealed items there is nothing to publish: no hash may leak, and the recorder must not be
    // called with an empty list either (SyncService would rewrite sync.json for nothing).
    @Test func clearingTheHistoryWithOnlyConcealedItemsRecordsNothing() {
        let store = makeStore()
        store.add(.text("secret"), source: onePassword, concealed: true)
        let recorder = recording(store)
        store.removeUntagged()
        #expect(recorder.calls.isEmpty)
    }

    // A restore drops the in-memory concealed items because they are not in the backup, but that is not a deletion
    // other Macs may hear about: only the plain item missing from the backup is handed over.
    @Test func restoringNeverRecordsADeletionForAConcealedItem() throws {
        let store = makeStore()
        let plain = try #require(store.add(.text("visible"), source: safari, concealed: false))
        store.add(.text("secret"), source: onePassword, concealed: true)
        let recorder = recording(store)
        clock.advance(60)
        persistence.stored = []
        store.reloadFromDisk(markingChanges: true)
        #expect(recorder.calls == [[.item(plain.contentHash, at: clock.current)]])
    }

    // Only a value that was saved in plain text becomes a deletion when it is copied from 1Password. Copying one that
    // is already concealed again must record nothing, or every re-copy would publish the secret's hash.
    @Test func copyingAnAlreadyConcealedValueFrom1PasswordAgainRecordsNothing() {
        let store = makeStore()
        store.add(.text("key"), source: onePassword, concealed: true)
        let recorder = recording(store)
        clock.advance(5)
        store.add(.text("key"), source: onePassword, concealed: true)
        #expect(recorder.calls.isEmpty)
    }

    // Restoring on one Mac must bring the items back on the other (stamped now, order kept) and remove there
    // what the backup did not have.
    @Test func restoringStampsWhatCameBackAndDeletesWhatIsGone() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let kept = try #require(store.add(.text("one"), source: safari, concealed: false))
        let gone = try #require(store.add(.text("two"), source: safari, concealed: false))
        let recorder = recording(store)
        clock.advance(60)
        persistence.stored = persistence.stored.filter { $0.id == kept.id }
        persistence.storedTags = []
        store.reloadFromDisk(markingChanges: true)
        #expect(Set(recorder.deletions) == [.item(gone.contentHash, at: clock.current), .tag(tag.id, at: clock.current)])
        #expect(store.items.map(\.createdAt) == [kept.createdAt])
        #expect(store.items.map(\.tagChangedAt) == [clock.current])
    }

    // The first-launch restore must not claim the backup as "changed now" nor delete anything: it only fills an empty
    // Mac, and whatever the other Macs did since the backup has to win in the merge.
    @Test func reloadingWithoutMarkingChangesKeepsTheBackupStampsAndRecordsNothing() throws {
        let store = makeStore()
        let tag = try #require(store.createTag(name: "Work", colorIndex: 0))
        let kept = try #require(store.add(.text("one"), source: safari, concealed: false))
        store.add(.text("two"), source: safari, concealed: false)
        let recorder = recording(store)
        clock.advance(60)
        let taggedAt = Date(timeIntervalSince1970: 500_000)
        let changedAt = Date(timeIntervalSince1970: 600_000)
        var backedUp = kept
        backedUp.tagID = tag.id
        backedUp.tagChangedAt = taggedAt
        var backedUpTag = tag
        backedUpTag.changedAt = changedAt
        persistence.stored = [backedUp]
        persistence.storedTags = [backedUpTag]
        store.reloadFromDisk(markingChanges: false)
        #expect(recorder.calls.isEmpty)
        #expect(store.items.map(\.tagChangedAt) == [taggedAt])
        #expect(store.tags.map(\.changedAt) == [changedAt])
        #expect(store.items.map(\.createdAt) == [kept.createdAt])
    }

    // MARK: bridge

    func remote(_ text: String, at date: Date) -> SyncItem {
        SyncItem(
            contentHash: "remote-\(text)", kind: .text, text: text, imageFileName: nil, createdAt: date,
            sourceAppBundleID: nil, sourceAppName: nil, tagID: nil, tagChangedAt: SyncState.unstamped
        )
    }

    // MARK: clocks that disagree

    // An item stamped by a Mac whose clock is an hour ahead: a deletion here dated by this clock alone would be
    // older than the item and lose in the merge. It is dated just after the item's stamp.
    @Test func aDeletionIsDatedAfterAStampFromAClockAhead() throws {
        // A real date: TestClock's default (1970) is decades before the "never changed" stamp the item carries.
        clock.current = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = makeStore()
        let ahead = clock.current.addingTimeInterval(60 * 60)
        store.applySync(SyncMerge.Result(items: [remote("x", at: ahead)], tags: []))
        let recorder = recording(store)
        store.remove(id: try #require(store.items.first).id)
        let deletedAt = try #require(recorder.deletions.first?.deletedAt)
        #expect(deletedAt > ahead)
        #expect(deletedAt < ahead.addingTimeInterval(1))
    }

    // A clock more than a day ahead is broken, not skewed. Following it would date this Mac's changes that far ahead,
    // where they beat every real later change on every Mac and escape the retention: such a stamp is not followed.
    @Test func aStampMoreThanADayAheadIsNotFollowed() throws {
        clock.current = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = makeStore()
        let farAhead = clock.current.addingTimeInterval(365 * 24 * 60 * 60)
        store.applySync(SyncMerge.Result(items: [remote("x", at: farAhead)], tags: []))
        let recorder = recording(store)
        store.remove(id: try #require(store.items.first).id)
        #expect(recorder.deletions == [.item("remote-x", at: clock.current)])
    }

    @Test func snapshotNeverContainsConcealedItems() {
        let store = makeStore()
        store.add(.text("visible"), source: safari, concealed: false)
        store.add(.text("secret"), source: onePassword, concealed: true)
        #expect(store.syncSnapshot().items.map(\.text) == ["visible"])
        #expect(store.concealedHashes.count == 1)
    }

    // The panel tracks items by ID, and concealed items live only on this Mac: a sync round must keep both.
    @Test func applyingKeepsConcealedItemsAndLocalIDs() throws {
        let store = makeStore()
        let kept = try #require(store.add(.text("one"), source: safari, concealed: false))
        clock.advance(1)
        store.add(.text("secret"), source: onePassword, concealed: true)
        clock.advance(10)
        let changed = store.applySync(SyncMerge.Result(items: [remote("two", at: clock.current), SyncItem(kept)], tags: []))
        #expect(changed)
        #expect(store.items.map(\.text) == ["two", "secret", "one"])
        #expect(store.items.first { $0.text == "one" }?.id == kept.id)
        #expect(persistence.stored.map(\.text) == ["two", "one"])
    }

    // A quiet round must write nothing: a save would make the hourly backup think something changed.
    @Test func applyingTheSameDataSavesNothing() {
        let store = makeStore()
        let result = SyncMerge.Result(items: [remote("two", at: clock.current)], tags: [])
        store.applySync(result)
        let saves = persistence.saveCount
        #expect(!store.applySync(result))
        #expect(persistence.saveCount == saves)
    }

    // Items made here and tags saved before sync have no stamp, but what this Mac publishes carries the "never
    // changed" date: if that counted as a change, every newly copied item would cost one save on the first round.
    @Test func applyingWhatThisMacPublishesSavesNothing() {
        let persistence = InMemoryPersistence(storedTags: [ClipboardCore.Tag(name: "Work", colorIndex: 0)])
        let store = HistoryStore(persistence: persistence, now: { [clock] in clock.current })
        store.add(.text("one"), source: safari, concealed: false)
        let saves = persistence.saveCount
        let snapshot = store.syncSnapshot()
        #expect(!store.applySync(SyncMerge.Result(items: snapshot.items, tags: snapshot.tags)))
        #expect(persistence.saveCount == saves)
    }

    // A concealed item counts toward the local cap but not toward the merge's, so another Mac can still list the
    // item the local prune drops: applying that must not save again every round until the concealed item expires.
    @Test func applyingAtTheCapWithAConcealedItemSavesNothing() throws {
        let store = makeStore()
        let oldest = try #require(store.add(.text("item 0"), source: safari, concealed: false))
        let prunedOldest = SyncItem(oldest)
        for index in 1..<Config.maxItems {
            clock.advance(1)
            store.add(.text("item \(index)"), source: safari, concealed: false)
        }
        clock.advance(1)
        store.add(.text("secret"), source: onePassword, concealed: true)
        #expect(!store.items.contains { $0.text == "item 0" })
        let saves = persistence.saveCount
        let result = SyncMerge.Result(items: store.syncSnapshot().items + [prunedOldest], tags: [])
        #expect(!store.applySync(result))
        #expect(persistence.saveCount == saves)
    }

    @Test func applyingRemovesWhatTheMergeLeftOutWithItsImage() throws {
        let store = makeStore()
        let kept = try #require(store.add(.text("one"), source: safari, concealed: false))
        let image = try #require(store.add(.image(Data([1, 2, 3])), source: safari, concealed: false))
        store.applySync(SyncMerge.Result(items: [SyncItem(kept)], tags: []))
        #expect(store.items.map(\.id) == [kept.id])
        #expect(persistence.images[try #require(image.imageFileName)] == nil)
    }

    @MainActor
    final class Counter {
        var value = 0
    }

    // The app publishes to other Macs a moment after each save; a save that is not announced never leaves the Mac.
    @Test func everySaveIsAnnounced() {
        let store = makeStore()
        let saves = Counter()
        store.onPersist = { saves.value += 1 }
        store.add(.text("hello"), source: safari, concealed: false)
        #expect(saves.value == 1)
    }
}
