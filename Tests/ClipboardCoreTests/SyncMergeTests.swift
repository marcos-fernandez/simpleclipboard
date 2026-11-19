import Foundation
import Testing
@testable import ClipboardCore

/// The merge decides what every Mac ends up showing. A wrong rule here loses a tag, brings back a deletion or
/// leaves two Macs different for good, so each rule is pinned here.
struct SyncMergeTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let day: TimeInterval = 24 * 60 * 60
    let work = UUID()
    let home = UUID()
    /// Fixed ids, because the fusion of same-named tags picks the smaller id.
    let smaller = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let larger = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func at(_ secondsAgo: TimeInterval) -> Date {
        now.addingTimeInterval(-secondsAgo)
    }

    func item(_ text: String, createdAgo: TimeInterval, tag: UUID? = nil, taggedAgo: TimeInterval? = nil, app: String? = nil) -> SyncItem {
        SyncItem(
            contentHash: "hash-\(text)", kind: .text, text: text, imageFileName: nil, createdAt: at(createdAgo),
            sourceAppBundleID: app, sourceAppName: app, tagID: tag,
            tagChangedAt: taggedAgo.map(at) ?? SyncState.unstamped
        )
    }

    func tag(_ id: UUID, _ name: String, changedAgo: TimeInterval = 1000) -> SyncTag {
        SyncTag(id: id, name: name, colorIndex: 0, changedAt: at(changedAgo))
    }

    func state(
        _ device: String, items: [SyncItem] = [], tags: [SyncTag] = [], deletions: [SyncDeletion] = [],
        publishedAgo: TimeInterval = 0
    ) -> SyncState {
        SyncState(deviceID: device, publishedAt: at(publishedAgo), items: items, tags: tags, deletions: deletions)
    }

    func merge(_ local: SyncState, _ remotes: SyncState..., concealed: Set<String> = []) -> SyncMerge.Result {
        SyncMerge.merge(local: local, remotes: remotes, concealedHashes: concealed, now: now)
    }

    @Test func newestCopyDecidesTheDateAndTheSourceApp() {
        let result = merge(
            state("A", items: [item("hello", createdAgo: 100, app: "Safari")]),
            state("B", items: [item("hello", createdAgo: 10, app: "Notes")])
        )
        #expect(result.items.map(\.createdAt) == [at(10)])
        #expect(result.items.map(\.sourceAppName) == ["Notes"])
    }

    // A re-copy on one Mac and a tag set a bit earlier on the other must both survive: taking the whole item from
    // the newest change would lose the tag.
    @Test func copyingAgainOnOneMacKeepsTheTagSetOnTheOther() {
        let result = merge(
            state("A", items: [item("hello", createdAgo: 1000, tag: work, taggedAgo: 50)], tags: [tag(work, "Work")]),
            state("B", items: [item("hello", createdAgo: 10)])
        )
        #expect(result.items.map(\.createdAt) == [at(10)])
        #expect(result.items.map(\.tagID) == [work])
    }

    @Test func newestTagChangeWinsEvenWhenItRemovesTheTag() {
        let result = merge(
            state("A", items: [item("hello", createdAgo: 1000, tag: work, taggedAgo: 50)], tags: [tag(work, "Work")]),
            state("B", items: [item("hello", createdAgo: 5, taggedAgo: 5)])
        )
        #expect(result.items.map(\.tagID) == [nil])
    }

    // Joining two histories saved before sync: no side has a tag date, and a tag must not be lost.
    @Test func withoutTagDatesHavingATagWins() {
        let tagged = state("A", items: [item("hello", createdAgo: 100, tag: work)], tags: [tag(work, "Work")])
        let plain = state("B", items: [item("hello", createdAgo: 100)])
        #expect(merge(tagged, plain).items.map(\.tagID) == [work])
        #expect(merge(plain, tagged).items.map(\.tagID) == [work])
    }

    @Test func tiesGoToTheHigherDeviceIDWhicheverMacMerges() {
        let tags = [tag(work, "Work"), tag(home, "Home")]
        let a = state("A", items: [item("hello", createdAgo: 100, tag: work, taggedAgo: 50)], tags: tags)
        let b = state("B", items: [item("hello", createdAgo: 100, tag: home, taggedAgo: 50)], tags: tags)
        #expect(merge(a, b).items.map(\.tagID) == [home])
        #expect(merge(b, a).items.map(\.tagID) == [home])
    }

    @Test func deletionAfterTheLastChangeRemovesTheItem() {
        let result = merge(
            state("A", deletions: [.item("hash-hello", at: at(5))]),
            state("B", items: [item("hello", createdAgo: 100)])
        )
        #expect(result.items.isEmpty)
    }

    @Test func copyingAgainAfterADeletionBringsTheItemBack() {
        let result = merge(
            state("A", deletions: [.item("hash-hello", at: at(50))]),
            state("B", items: [item("hello", createdAgo: 10)])
        )
        #expect(result.items.map(\.contentHash) == ["hash-hello"])
    }

    // Restoring the backup on one Mac stamps what came back as changed now (createdAt unchanged), so it beats a
    // deletion made earlier on the other Mac.
    @Test func itemRestoredAfterADeletionComesBackWithItsDate() {
        let result = merge(
            state("A", deletions: [.item("hash-hello", at: at(20))]),
            state("B", items: [item("hello", createdAgo: 1000, taggedAgo: 5)])
        )
        #expect(result.items.map(\.createdAt) == [at(1000)])
    }

    @Test func itemsOfADeletedTagGoBackToTheHistoryWithoutExpiring() {
        let result = merge(
            state("A", deletions: [.tag(work, at: at(5))]),
            state(
                "B", items: [item("hello", createdAgo: 40 * day, tag: work, taggedAgo: 40 * day)],
                tags: [tag(work, "Work", changedAgo: 40 * day)]
            )
        )
        #expect(result.tags.isEmpty)
        #expect(result.items.map(\.tagID) == [nil])
        #expect(result.items.map(\.createdAt) == [at(5)])
    }

    // Item X is deleted at t1 and its tag at t2 (last change of X < t1 < t2). The deletion of X is compared with X's own
    // last change, before the orphan rule re-dates it to t2: re-dating first would make t2 the last change, the
    // deletion at t1 would no longer apply and X, which the user deleted, would come back on every Mac.
    @Test func anItemDeletedBeforeItsTagWasDeletedStaysDeleted() {
        let result = merge(
            state(
                "A", items: [item("hello", createdAgo: 1000, tag: work, taggedAgo: 1000)],
                tags: [tag(work, "Work", changedAgo: 1000)]
            ),
            state("B", deletions: [.item("hash-hello", at: at(500)), .tag(work, at: at(10))])
        )
        #expect(result.tags.isEmpty)
        #expect(result.items.isEmpty)
    }

    // Two Macs that join before either sees the other's file each publish their own "Work". Without fusing, every
    // Mac keeps both for good (absence is not a deletion) and the items stay split between them. The smaller id wins
    // because every Mac must pick the same one whatever order the files arrive in; the larger id sits in the first
    // file here, so "first seen wins" would give the wrong answer.
    @Test func sameNamedTagsBecomeOne() {
        let first = state("A", items: [item("one", createdAgo: 10, tag: larger, taggedAgo: 10)], tags: [tag(larger, "Work")])
        let second = state("B", items: [item("two", createdAgo: 20, tag: smaller, taggedAgo: 20)], tags: [tag(smaller, "Work")])
        let result = merge(state("C"), first, second)
        #expect(result.tags.map(\.id) == [smaller])
        #expect(result.items.map(\.text) == ["one", "two"])
        #expect(result.items.map(\.tagID) == [smaller, smaller])
        #expect(merge(state("C"), second, first) == result)
    }

    // The name key is the one adoption uses (trimmed, case-insensitive): the same tag typed with a stray space or in
    // lowercase on another Mac is still the same tag to the user. The winner keeps its own name.
    @Test func sameNameIgnoresCaseAndSpaces() {
        let result = merge(
            state("C"),
            state("A", tags: [tag(larger, " work ")]),
            state("B", tags: [tag(smaller, "Work")])
        )
        #expect(result.tags.map(\.id) == [smaller])
        #expect(result.tags.map(\.name) == ["Work"])
    }

    // A deleted tag is gone, not a namesake to merge into: fusing before the deletion is applied would let the
    // deleted smaller id take the surviving tag's items with it. Its own items follow the orphan rule (untagged).
    @Test func aDeletedTagIsNotFusedIntoItsNamesake() {
        let result = merge(
            state("C"),
            state(
                "A",
                items: [
                    item("deleted", createdAgo: 100, tag: smaller, taggedAgo: 100),
                    item("alive", createdAgo: 100, tag: larger, taggedAgo: 100),
                ],
                tags: [tag(smaller, "Work", changedAgo: 100), tag(larger, "Work", changedAgo: 100)]
            ),
            state("B", deletions: [.tag(smaller, at: at(5))])
        )
        #expect(result.tags.map(\.id) == [larger])
        #expect(result.items.first { $0.text == "alive" }?.tagID == larger)
        #expect(result.items.first { $0.text == "deleted" }?.tagID == nil)
    }

    // Fusing is recorded so that it outlives the name match: a rename into an existing name is never published
    // otherwise (the renamed tag vanishes in the same merge), and renaming the winner later would split them again.
    @Test func aFusionIsRecordedNoEarlierThanTheFusedTag() {
        let result = merge(
            state("A", tags: [tag(smaller, "Work"), tag(larger, "Work", changedAgo: -60)])
        )
        #expect(result.fusions == [.tag(larger, fusedInto: smaller, at: at(-60))])
        var again = state("A", tags: result.tags, deletions: result.fusions)
        again.items = result.items
        #expect(merge(again).fusions.isEmpty)
    }

    // A Mac that has not merged since still lists the fused tag under its old name. The recorded fusion must take it
    // and its items to the winner, whatever the winner is called now, instead of bringing it back.
    @Test func aRecordedFusionBeatsAFileThatStillListsTheFusedTag() {
        let stale = state(
            "A", items: [item("hello", createdAgo: 100, tag: larger, taggedAgo: 100)],
            tags: [tag(smaller, "Work", changedAgo: 1000), tag(larger, "Home", changedAgo: 1000)]
        )
        let fused = state(
            "B", items: [item("hello", createdAgo: 100, tag: smaller, taggedAgo: 100)],
            tags: [tag(smaller, "Office", changedAgo: 5)], deletions: [.tag(larger, fusedInto: smaller, at: at(50))]
        )
        let fromA = merge(stale, fused)
        #expect(fromA.tags.map(\.name) == ["Office"])
        #expect(fromA.items.map(\.tagID) == [smaller])
        #expect(merge(fused, stale) == fromA)
    }

    // Unlike a plain deletion, a fused tag's items follow the winner, also into the history when the winner is
    // deleted: a plain tombstone would make them orphans on the Macs that still have the fused tag.
    @Test func itemsOfAFusedTagFollowTheWinnerEvenWhenItIsDeleted() {
        let stale = state(
            "A", items: [item("hello", createdAgo: 100, tag: larger, taggedAgo: 100)],
            tags: [tag(larger, "Work", changedAgo: 1000)]
        )
        let fused = state("B", tags: [tag(smaller, "Work")], deletions: [.tag(larger, fusedInto: smaller, at: at(50))])
        #expect(merge(stale, fused).items.map(\.tagID) == [smaller])
        let deleted = state("C", deletions: [.tag(smaller, at: at(10))])
        let result = merge(stale, fused, deleted)
        #expect(result.tags.isEmpty)
        #expect(result.items.map(\.tagID) == [nil])
        #expect(result.items.map(\.createdAt) == [at(10)])
    }

    // A later change on a Mac that never saw the fusion is a real change, as with a deletion: it brings the tag back.
    @Test func aChangeAfterTheFusionBringsTheTagBack() {
        let result = merge(
            state("A", tags: [tag(larger, "Home", changedAgo: 5)]),
            state("B", tags: [tag(smaller, "Work")], deletions: [.tag(larger, fusedInto: smaller, at: at(50))])
        )
        #expect(Set(result.tags.map(\.name)) == ["Home", "Work"])
    }

    @Test func newestTagChangeWinsAndALaterDeletionRemovesTheTag() {
        let renamed = merge(
            state("A", tags: [tag(work, "Work", changedAgo: 100)]),
            state("B", tags: [tag(work, "Office", changedAgo: 10)])
        )
        #expect(renamed.tags.map(\.name) == ["Office"])
        let deleted = merge(
            state("A", deletions: [.tag(work, at: at(5))]),
            state("B", tags: [tag(work, "Office", changedAgo: 10)])
        )
        #expect(deleted.tags.isEmpty)
    }

    // Whatever order the files arrive in and however often a Mac merges, all Macs must end up equal.
    @Test func twoMacsConvergeAndMergingAgainChangesNothing() {
        let a = state(
            "A", items: [item("one", createdAgo: 30, tag: work, taggedAgo: 30), item("two", createdAgo: 20)],
            tags: [tag(work, "Work")], deletions: [.item("hash-three", at: at(1))]
        )
        let b = state(
            "B", items: [item("two", createdAgo: 5), item("three", createdAgo: 60), item("four", createdAgo: 2)],
            tags: [tag(home, "Home")]
        )
        let fromA = merge(a, b)
        let fromB = merge(b, a)
        #expect(fromA.items == fromB.items)
        #expect(Set(fromA.tags.map(\.id)) == Set(fromB.tags.map(\.id)))
        #expect(fromA.items.map(\.text) == ["four", "two", "one"])

        var again = a
        again.items = fromA.items
        again.tags = fromA.tags
        #expect(merge(again, b) == fromA)
    }

    @Test func aMacSilentForLongerThanTheRetentionIsIgnored() {
        let result = merge(
            state("A"),
            state("B", items: [item("old", createdAgo: 10)], publishedAgo: Config.syncRetention + day)
        )
        #expect(result.items.isEmpty)
    }

    @Test func deletionsAreForgottenAfterTheRetention() {
        let old = Config.syncRetention + 2 * day
        let result = merge(
            state("A", deletions: [.item("hash-hello", at: at(Config.syncRetention + day))]),
            state("B", items: [item("hello", createdAgo: old, tag: work, taggedAgo: old)], tags: [tag(work, "Work")])
        )
        #expect(result.items.map(\.contentHash) == ["hash-hello"])
    }

    @Test func aLocalConcealedItemWinsOverASyncedCopy() {
        let result = merge(state("A"), state("B", items: [item("secret", createdAgo: 10)]), concealed: ["hash-secret"])
        #expect(result.items.isEmpty)
    }

    @Test func limitsApplyToUntaggedItemsOnly() {
        let recent = (0...Config.maxItems).map { item("n\($0)", createdAgo: TimeInterval($0)) }
        let old = [item("old", createdAgo: 31 * day), item("pinned", createdAgo: 31 * day, tag: work, taggedAgo: 31 * day)]
        let result = merge(state("A", items: recent + old, tags: [tag(work, "Work")]), state("B"))
        #expect(result.items.filter { $0.tagID == nil }.count == Config.maxItems)
        #expect(!result.items.contains { $0.text == "old" })
        #expect(!result.items.contains { $0.text == "n\(Config.maxItems)" })
        #expect(result.items.contains { $0.text == "pinned" })
    }

    @Test func joiningReusesARemoteTagWithTheSameName() {
        let local = state("B", items: [item("hello", createdAgo: 10, tag: home, taggedAgo: 10)], tags: [tag(home, " work ")])
        let remote = state("A", tags: [tag(work, "Work")])
        let adopted = SyncMerge.adoptingRemoteTags(local, remotes: [remote], now: now)
        let result = SyncMerge.merge(local: adopted, remotes: [remote], concealedHashes: [], now: now)
        #expect(result.tags.map(\.id) == [work])
        #expect(result.items.map(\.tagID) == [work])
    }

    // The merge ignores a Mac silent for longer than the retention, so adopting its tag would leave the local one
    // replaced by an ID the merge then drops: the user's tag would vanish and its items fall back to plain history.
    @Test func joiningIgnoresATagOfASilentMac() {
        let local = state("B", items: [item("hello", createdAgo: 10, tag: home, taggedAgo: 10)], tags: [tag(home, " work ")])
        let silent = state("A", tags: [tag(work, "Work")], publishedAgo: Config.syncRetention + day)
        let adopted = SyncMerge.adoptingRemoteTags(local, remotes: [silent], now: now)
        let result = SyncMerge.merge(local: adopted, remotes: [silent], concealedHashes: [], now: now)
        #expect(result.tags.map(\.id) == [home])
        #expect(result.items.map(\.tagID) == [home])
    }

    // Same trap when a lagging file still lists a tag that another Mac deleted later: the merge drops that tag, so
    // the local one must not be swapped for it.
    @Test func joiningIgnoresATagDeletedElsewhere() {
        let local = state("B", items: [item("hello", createdAgo: 10, tag: home, taggedAgo: 10)], tags: [tag(home, " work ")])
        let lagging = state("A", tags: [tag(work, "Work", changedAgo: 100)])
        let deleter = state("C", deletions: [.tag(work, at: at(5))])
        let adopted = SyncMerge.adoptingRemoteTags(local, remotes: [lagging, deleter], now: now)
        let result = SyncMerge.merge(local: adopted, remotes: [lagging, deleter], concealedHashes: [], now: now)
        #expect(result.tags.map(\.id) == [home])
        #expect(result.items.map(\.tagID) == [home])
    }
}
