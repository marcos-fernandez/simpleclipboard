import Foundation
import Testing
@testable import ClipboardCore

/// Two Macs are two local folders sharing one temporary "iCloud Drive" folder. Sync must make them equal without
/// ever putting a concealed item in iCloud or deleting local data because of a file it cannot read.
@MainActor
struct SyncServiceTests {
    let root: URL
    let iCloud: URL
    let syncFolder: URL
    let clock = TestClock()
    let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
    let onePassword = SourceApp(bundleID: "com.1password.1password", name: "1Password")
    let fileManager = FileManager.default

    @MainActor
    struct Mac {
        let directory: URL
        let store: HistoryStore
        let sync: SyncService

        @discardableResult
        func round() -> SyncStatus {
            sync.sync(store)
        }
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncServiceTests-\(UUID().uuidString)", isDirectory: true)
        iCloud = root.appendingPathComponent("iCloud", isDirectory: true)
        syncFolder = iCloud.appendingPathComponent("SimpleClipboard/Sync", isDirectory: true)
        try FileManager.default.createDirectory(at: iCloud, withIntermediateDirectories: true)
        // Deletions must be later than SyncState.unstamped (2001), as every real clock is: TestClock's default
        // (1970) would let the lastChange of an untagged item beat every deletion.
        clock.current = Date(timeIntervalSinceReferenceDate: 800_000_000)
    }

    /// Each simulated Mac has its own machine ID, so the real one of the Mac running the tests never decides anything.
    func makeMac(_ name: String, enabled: Bool = true) throws -> Mac {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        let store = HistoryStore(persistence: FilePersistence(directory: directory), now: { [clock] in clock.current })
        let sync = makeSync(directory: directory, machineID: name)
        if enabled {
            try sync.enable()
            store.deletionRecorder = { [sync] in sync.record($0) }
        }
        return Mac(directory: directory, store: store, sync: sync)
    }

    func makeSync(directory: URL, machineID: String) -> SyncService {
        SyncService(localDirectory: directory, iCloudDriveRoot: iCloud, now: { [clock] in clock.current }, machineID: machineID)
    }

    func savedSettings(in directory: URL) throws -> SyncSettings {
        try JSONDecoder().decode(SyncSettings.self, from: Data(contentsOf: directory.appendingPathComponent("sync.json")))
    }

    /// Looks under `folder`, by default all of iCloud Drive. `Backup/` is a copy of the history, so a value that was
    /// saved before it was copied from 1Password is legitimately in it: pass `syncFolder` to check only what sync publishes.
    func iCloudContains(_ text: String, in folder: URL? = nil) throws -> Bool {
        let files = fileManager.enumerator(at: folder ?? iCloud, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for file in files where (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            if try Data(contentsOf: file).range(of: Data(text.utf8)) != nil {
                return true
            }
        }
        return false
    }

    func publishedFile() throws -> URL {
        let devices = syncFolder.appendingPathComponent("devices", isDirectory: true)
        let name = try #require(try fileManager.contentsOfDirectory(atPath: devices.path).first { $0.hasSuffix(".json") })
        return devices.appendingPathComponent(name)
    }

    @Test func twoMacsEndUpWithTheSameHistoryAndImages() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        a.store.add(.text("one"), source: safari, concealed: false)
        clock.advance(1)
        a.store.add(.image(Data([1, 2, 3])), source: safari, concealed: false)
        clock.advance(1)
        b.store.add(.text("two"), source: safari, concealed: false)

        #expect(a.round() == .synced(clock.current))
        #expect(b.round() == .synced(clock.current))
        a.round()

        #expect(a.store.items.map(\.contentHash) == b.store.items.map(\.contentHash))
        #expect(a.store.items.count == 3)
        let image = try #require(b.store.items.first { $0.kind == .image })
        #expect(b.store.imageData(for: image) == Data([1, 2, 3]))
    }

    @Test func aDeletionReachesTheOtherMac() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let one = try #require(a.store.add(.text("one"), source: safari, concealed: false))
        clock.advance(1)
        a.store.add(.text("two"), source: safari, concealed: false)
        a.round()
        b.round()
        clock.advance(1)
        a.store.remove(id: one.id)
        a.round()
        b.round()
        #expect(b.store.items.map(\.text) == ["two"])
    }

    // "Clear History…" hands all its deletions to SyncService in one call, which saves them together: none may be
    // lost on the way, in memory or in sync.json after a relaunch.
    @Test func clearingTheHistoryRemovesEveryUntaggedItemOnTheOtherMac() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let work = try #require(a.store.createTag(name: "Work", colorIndex: 0))
        for text in ["one", "two", "three"] {
            a.store.add(.text(text), source: safari, concealed: false)
            clock.advance(1)
        }
        let kept = try #require(a.store.add(.text("pinned"), source: safari, concealed: false))
        a.store.setTag(itemID: kept.id, tagID: work.id)
        a.round()
        b.round()
        clock.advance(1)
        a.store.removeUntagged()
        let relaunched = makeSync(directory: a.directory, machineID: "A")
        relaunched.sync(a.store)
        b.round()
        #expect(b.store.items.map(\.text) == ["pinned"])
    }

    @Test func concealedItemsNeverReachICloud() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        a.store.add(.text("secret123"), source: onePassword, concealed: true)
        a.store.add(.text("visible"), source: safari, concealed: false)
        a.round()
        b.round()
        #expect(try !iCloudContains("secret123"))
        #expect(b.store.items.map(\.text) == ["visible"])
    }

    // A value copied from 1Password must not stay as plain text on the other Mac.
    @Test func copyingASavedValueFrom1PasswordRemovesItOnTheOtherMac() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        a.store.add(.text("key"), source: safari, concealed: false)
        a.round()
        b.round()
        clock.advance(1)
        a.store.add(.text("key"), source: onePassword, concealed: true)
        a.round()
        b.round()
        #expect(b.store.items.isEmpty)
    }

    @Test func anImageAlreadyInICloudIsNeverRewritten() throws {
        let a = try makeMac("A")
        let item = try #require(a.store.add(.image(Data([1, 2, 3])), source: safari, concealed: false))
        let shared = syncFolder.appendingPathComponent("images/\(try #require(item.imageFileName))")
        try fileManager.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([9]).write(to: shared)
        a.round()
        #expect(try Data(contentsOf: shared) == Data([9]))
    }

    // An image deleted everywhere can stay in Sync/images for a while. When a Mac copies it again, the PNG is not
    // rewritten, so it keeps its old date; another Mac that still holds this Mac's previous file would take it for
    // unused and past the grace, delete it, and the item would be missing there.
    @Test func anImageUsedAgainGetsTheGracePeriodAgain() throws {
        let a = try makeMac("A")
        a.round()
        let file = try publishedFile()
        let previous = try Data(contentsOf: file)
        clock.advance(1)
        let item = try #require(a.store.add(.image(Data([1, 2, 3])), source: safari, concealed: false))
        let shared = syncFolder.appendingPathComponent("images/\(try #require(item.imageFileName))")
        try Data([1, 2, 3]).write(to: shared)
        try fileManager.setAttributes([.modificationDate: clock.current.addingTimeInterval(-Config.syncImageGrace - 60)], ofItemAtPath: shared.path)
        a.round()
        try previous.write(to: file)
        try makeMac("B").round()
        #expect(fileManager.fileExists(atPath: shared.path))
    }

    @Test func unusedImagesAreRemovedOnlyAfterTheGracePeriod() throws {
        let a = try makeMac("A")
        a.round()
        let images = syncFolder.appendingPathComponent("images", isDirectory: true)
        let old = images.appendingPathComponent("old.png")
        let recent = images.appendingPathComponent("recent.png")
        try Data([1]).write(to: old)
        try Data([2]).write(to: recent)
        try fileManager.setAttributes([.modificationDate: clock.current.addingTimeInterval(-Config.syncImageGrace - 60)], ofItemAtPath: old.path)
        try fileManager.setAttributes([.modificationDate: clock.current], ofItemAtPath: recent.path)
        a.round()
        #expect(!fileManager.fileExists(atPath: old.path))
        #expect(fileManager.fileExists(atPath: recent.path))
    }

    // An unreadable file may be the one that uses an image: nothing is judged unused that round.
    @Test func noImageIsRemovedWhileAFileCannotBeRead() throws {
        let a = try makeMac("A")
        a.round()
        let old = syncFolder.appendingPathComponent("images/old.png")
        try Data([1]).write(to: old)
        try fileManager.setAttributes([.modificationDate: clock.current.addingTimeInterval(-Config.syncImageGrace - 60)], ofItemAtPath: old.path)
        try Data("not json".utf8).write(to: syncFolder.appendingPathComponent("devices/X.json"))
        a.round()
        #expect(fileManager.fileExists(atPath: old.path))
    }

    // A Mac silent for longer than the retention is taken for gone. Its file, readable or not, is left in place (it
    // may come back, and deleting another Mac's file cannot be undone) but must not block for ever: no new Mac could
    // join, images would never be cleaned up and the menu would report a newer version that is long gone.
    @Test func aFileUntouchedForLongerThanTheRetentionNoLongerBlocks() throws {
        let a = try makeMac("A")
        a.round()
        let devices = syncFolder.appendingPathComponent("devices", isDirectory: true)
        let corrupt = devices.appendingPathComponent("X.json")
        let newer = devices.appendingPathComponent("Y.json")
        try Data("not json".utf8).write(to: corrupt)
        try Data(#"{"version": 99}"#.utf8).write(to: newer)
        let longAgo = clock.current.addingTimeInterval(-Config.syncRetention - 60)
        for file in [corrupt, newer] {
            try fileManager.setAttributes([.modificationDate: longAgo], ofItemAtPath: file.path)
        }
        let old = syncFolder.appendingPathComponent("images/old.png")
        try Data([1]).write(to: old)
        try fileManager.setAttributes([.modificationDate: clock.current.addingTimeInterval(-Config.syncImageGrace - 60)], ofItemAtPath: old.path)

        #expect(try makeMac("B").round() == .synced(clock.current))
        #expect(a.round() == .synced(clock.current))
        #expect(!fileManager.fileExists(atPath: old.path))
        #expect(fileManager.fileExists(atPath: corrupt.path))
        #expect(fileManager.fileExists(atPath: newer.path))
    }

    // The merge already ignores a Mac silent for longer than the retention; its images must not stay in iCloud
    // Drive for ever just because its file is still there.
    @Test func aSilentMacNoLongerKeepsItsImages() throws {
        let a = try makeMac("A")
        a.round()
        let old = syncFolder.appendingPathComponent("images/old.png")
        try Data([1]).write(to: old)
        try fileManager.setAttributes([.modificationDate: clock.current.addingTimeInterval(-Config.syncImageGrace - 60)], ofItemAtPath: old.path)
        let silent = SyncState(
            deviceID: "X", publishedAt: clock.current.addingTimeInterval(-Config.syncRetention - 60),
            items: [
                SyncItem(
                    contentHash: "old", kind: .image, text: nil, imageFileName: "old.png", createdAt: clock.current,
                    sourceAppBundleID: nil, sourceAppName: nil, tagID: nil, tagChangedAt: SyncState.unstamped
                ),
            ],
            tags: [], deletions: []
        )
        try JSONEncoder().encode(silent).write(to: syncFolder.appendingPathComponent("devices/X.json"))
        a.round()
        #expect(!fileManager.fileExists(atPath: old.path))
    }

    @Test func anImageItemWaitsForItsImage() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let item = try #require(a.store.add(.image(Data([1, 2, 3])), source: safari, concealed: false))
        a.round()
        let shared = syncFolder.appendingPathComponent("images/\(try #require(item.imageFileName))")
        try fileManager.removeItem(at: shared)
        b.round()
        #expect(b.store.items.isEmpty)
        try Data([1, 2, 3]).write(to: shared)
        b.round()
        #expect(b.store.items.map(\.contentHash) == [item.contentHash])
    }

    // The image name comes from another Mac's file: "../history.json" must not reach this Mac's own data. Without
    // the check the item would be accepted, since that path exists locally, and the store would read history.json
    // as an image.
    @Test func anImageNameOutsideTheFolderIsIgnored() throws {
        let a = try makeMac("A")
        a.store.add(.text("one"), source: safari, concealed: false)
        a.round()
        let history = a.directory.appendingPathComponent("history.json")
        let before = try Data(contentsOf: history)
        let escapingNames: [String] = ["../history.json", "/"]
        let escaping = escapingNames.map { name in
            SyncItem(
                contentHash: "escaping\(name)", kind: .image, text: nil, imageFileName: name, createdAt: clock.current,
                sourceAppBundleID: nil, sourceAppName: nil, tagID: nil, tagChangedAt: SyncState.unstamped
            )
        }
        let remote = SyncState(deviceID: "other", publishedAt: clock.current, items: escaping, tags: [], deletions: [])
        try JSONEncoder().encode(remote).write(to: syncFolder.appendingPathComponent("devices/other.json"))
        a.round()
        #expect(a.store.items.map(\.text) == ["one"])
        #expect(try Data(contentsOf: history) == before)
    }

    func remoteItem(_ hash: String, kind: ClipItem.Kind = .text, text: String? = nil, imageFileName: String? = nil) -> SyncItem {
        SyncItem(
            contentHash: hash, kind: kind, text: text, imageFileName: imageFileName, createdAt: clock.current,
            sourceAppBundleID: nil, sourceAppName: nil, tagID: nil, tagChangedAt: SyncState.unstamped
        )
    }

    func publishRemote(_ items: [SyncItem], as deviceID: String = "other", inFile name: String = "other") throws {
        let remote = SyncState(deviceID: deviceID, publishedAt: clock.current, items: items, tags: [], deletions: [])
        try JSONEncoder().encode(remote).write(to: syncFolder.appendingPathComponent("devices/\(name).json"))
    }

    // A file in iCloud Drive is not trusted more than the clipboard: what the app would never save from a copy (too
    // big, or an item without its content) must not get in through another Mac's file either.
    @Test func syncedItemsOverTheLimitsOrWithoutContentAreIgnored() throws {
        let a = try makeMac("A")
        a.store.add(.text("one"), source: safari, concealed: false)
        a.round()
        let huge = syncFolder.appendingPathComponent("images/huge.png")
        try Data(count: Config.maxImageBytes + 1).write(to: huge)
        try publishRemote([
            remoteItem("long", text: String(repeating: "x", count: Config.maxTextBytes + 1)),
            remoteItem("huge", kind: .image, imageFileName: "huge.png"),
            remoteItem("noText"),
            remoteItem("noImage", kind: .image),
        ])
        a.round()
        #expect(a.store.items.map(\.text) == ["one"])
        #expect(!fileManager.fileExists(atPath: a.directory.appendingPathComponent("images/huge.png").path))
    }

    // Each Mac writes only <its device ID>.json. A file whose content names another device is a copy or a forgery:
    // merging it would mix in a Mac that is not there, or, with this Mac's own ID, its own past state.
    @Test func aFileWhoseDeviceIDDoesNotMatchItsNameIsIgnored() throws {
        let a = try makeMac("A")
        a.round()
        try publishRemote([remoteItem("forged", text: "forged")], as: "someone-else")
        a.round()
        #expect(a.store.items.isEmpty)
    }

    // Copying a symlink would put a link to anywhere on the disk into this Mac's images folder, and the store would
    // read through it.
    @Test func aSharedImageThatIsNotARegularFileIsIgnored() throws {
        let a = try makeMac("A")
        a.round()
        let outside = root.appendingPathComponent("outside.png")
        try Data([1, 2, 3]).write(to: outside)
        try fileManager.createSymbolicLink(at: syncFolder.appendingPathComponent("images/link.png"), withDestinationURL: outside)
        try publishRemote([remoteItem("link", kind: .image, imageFileName: "link.png")])
        a.round()
        #expect(a.store.items.isEmpty)
        #expect((try? fileManager.destinationOfSymbolicLink(atPath: a.directory.appendingPathComponent("images/link.png").path)) == nil)
    }

    // The image name of a local item comes from history.json: "../secret" would make publishing copy a file from
    // outside the images folder into iCloud Drive, or write outside Sync/images.
    @Test func aLocalImageNameOutsideTheFolderIsNeverPublished() throws {
        let directory = root.appendingPathComponent("A", isDirectory: true)
        try fileManager.createDirectory(at: directory.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("private-content".utf8).write(to: directory.appendingPathComponent("secret.png"))
        FilePersistence(directory: directory).save([
            ClipItem(
                createdAt: clock.current, kind: .image, text: nil, imageFileName: "../secret.png", contentHash: "escaping",
                source: safari, isConcealed: false, expiresAt: nil
            ),
        ])
        let a = try makeMac("A")
        #expect(a.store.items.count == 1)
        a.round()
        #expect(try !iCloudContains("private-content"))
    }

    // The grace counts from when the image reached iCloud, not from its age: a backlog image can be weeks old, and
    // another Mac that sees the PNG before this Mac's file lists it must not take it for unused and delete it.
    @Test func aPublishedOldImageGetsTheFullGracePeriod() throws {
        let a = try makeMac("A")
        let item = try #require(a.store.add(.image(Data([1, 2, 3])), source: safari, concealed: false))
        let name = try #require(item.imageFileName)
        let local = a.directory.appendingPathComponent("images/\(name)")
        try fileManager.setAttributes([.modificationDate: clock.current.addingTimeInterval(-20 * 24 * 60 * 60)], ofItemAtPath: local.path)
        a.round()
        try fileManager.removeItem(at: publishedFile())
        try makeMac("B").round()
        #expect(fileManager.fileExists(atPath: syncFolder.appendingPathComponent("images/\(name)").path))
    }

    // Before it joins, a Mac adopts tags by name only from files it has read. Publishing anyway would give the other
    // Mac tags under IDs of their own, and since absence is not a deletion both would keep the same tag twice.
    @Test func aJoiningMacWaitsForEveryFileBeforePublishing() throws {
        let a = try makeMac("A")
        let workA = try #require(a.store.createTag(name: "Work", colorIndex: 0))
        a.round()
        let aFile = try publishedFile()
        let aBytes = try Data(contentsOf: aFile)
        try Data("not json".utf8).write(to: aFile)
        let devices = aFile.deletingLastPathComponent()

        let b = try makeMac("B")
        b.store.createTag(name: "work", colorIndex: 3)
        let tagsBefore = b.store.tags
        #expect(tagsBefore.map(\.name) == ["work"])
        #expect(b.round() == .waitingForOtherMacs)
        #expect(try fileManager.contentsOfDirectory(atPath: devices.path) == [aFile.lastPathComponent])
        #expect(b.store.tags == tagsBefore)

        try aBytes.write(to: aFile)
        #expect(b.round() == .synced(clock.current))
        #expect(b.store.tags.map(\.id) == [workA.id])
        let bFile = try #require(try fileManager.contentsOfDirectory(atPath: devices.path).first { $0 != aFile.lastPathComponent })
        let published = try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: devices.appendingPathComponent(bFile)))
        #expect(published.tags.map(\.id) == [workA.id])
    }

    // iCloud Drive uploads every rewrite of a file to the other Macs: a round with nothing new must leave this Mac's
    // file alone until the daily refresh. Its date is pinned in the past so a rewrite cannot go unnoticed.
    @Test func aQuietRoundRewritesNothing() throws {
        let a = try makeMac("A")
        a.store.add(.text("one"), source: safari, concealed: false)
        a.round()
        let file = try publishedFile()
        let pinned = Date(timeIntervalSinceReferenceDate: 700_000_000)
        try fileManager.setAttributes([.modificationDate: pinned], ofItemAtPath: file.path)
        let bytes = try Data(contentsOf: file)
        clock.advance(Config.syncRefreshInterval / 2)
        a.round()
        #expect(try fileManager.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == pinned)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func unreadableOrNewerFilesNeverDeleteLocalData() throws {
        let a = try makeMac("A")
        a.store.add(.text("one"), source: safari, concealed: false)
        a.round()
        try Data("not json".utf8).write(to: syncFolder.appendingPathComponent("devices/X.json"))
        try Data(#"{"version": \#(SyncState.currentVersion + 1)}"#.utf8).write(to: syncFolder.appendingPathComponent("devices/Y.json"))
        #expect(a.round() == .newerVersionElsewhere)
        #expect(a.store.items.map(\.text) == ["one"])
    }

    // A newer app may only add fields, so its file can decode in full: its version must still keep it out, or this
    // Mac would merge data it cannot interpret.
    @Test func aNewerFileThatDecodesIsStillSkipped() throws {
        let a = try makeMac("A")
        a.round()
        let newer = SyncState(
            version: SyncState.currentVersion + 1, deviceID: "Y", publishedAt: clock.current,
            items: [
                SyncItem(
                    contentHash: "newer", kind: .text, text: "newer", imageFileName: nil, createdAt: clock.current,
                    sourceAppBundleID: nil, sourceAppName: nil, tagID: nil, tagChangedAt: SyncState.unstamped
                ),
            ],
            tags: [], deletions: []
        )
        try JSONEncoder().encode(newer).write(to: syncFolder.appendingPathComponent("devices/Y.json"))
        #expect(a.round() == .newerVersionElsewhere)
        #expect(a.store.items.isEmpty)
    }

    @Test func withSyncOffNothingIsWritten() throws {
        let a = try makeMac("A", enabled: false)
        a.store.add(.text("one"), source: safari, concealed: false)
        #expect(a.round() == .off)
        #expect(!fileManager.fileExists(atPath: syncFolder.path))
    }

    @Test func syncCannotBeTurnedOnWithoutICloudDrive() {
        let sync = SyncService(localDirectory: root.appendingPathComponent("C"), iCloudDriveRoot: root.appendingPathComponent("missing"))
        #expect(throws: SyncError.iCloudUnavailable) {
            try sync.enable()
        }
    }

    @Test func aJoiningMacReusesTagsByName() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let workA = try #require(a.store.createTag(name: "Work", colorIndex: 0))
        let one = try #require(a.store.add(.text("one"), source: safari, concealed: false))
        a.store.setTag(itemID: one.id, tagID: workA.id)
        let workB = try #require(b.store.createTag(name: "work", colorIndex: 3))
        let two = try #require(b.store.add(.text("two"), source: safari, concealed: false))
        b.store.setTag(itemID: two.id, tagID: workB.id)
        a.round()
        b.round()
        a.round()
        #expect(a.store.tags.map(\.id) == [workA.id])
        #expect(b.store.tags.map(\.id) == [workA.id])
        #expect(b.store.items.allSatisfy { $0.tagID == workA.id })
    }

    // A corrupt tags.json on one Mac leaves its items pointing to a tag it no longer has; the store keeps them tagged
    // under a stand-in. Neither an "untag" nor the stand-in's name may spread to the other Macs: it is not something
    // the user did, and the real tag comes back from them.
    @Test func aCorruptTagsFileOnOneMacDoesNotUntagItsItemsOnTheOthers() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let work = try #require(a.store.createTag(name: "Work", colorIndex: 0))
        let one = try #require(a.store.add(.text("one"), source: safari, concealed: false))
        a.store.setTag(itemID: one.id, tagID: work.id)
        a.round()
        b.round()
        try Data("{".utf8).write(to: a.directory.appendingPathComponent("tags.json"))
        // Without the copy of the last save there is nothing to recover the tags from.
        try FileManager.default.removeItem(at: a.directory.appendingPathComponent("tags.json.prev"))
        clock.advance(60)
        let relaunched = HistoryStore(persistence: FilePersistence(directory: a.directory), now: { [clock] in clock.current })
        relaunched.deletionRecorder = { [sync = a.sync] in sync.record($0) }
        #expect(relaunched.items.first?.tagID == work.id)
        #expect(relaunched.tags.map(\.name) != ["Work"])

        let aAfterRelaunch = Mac(directory: a.directory, store: relaunched, sync: a.sync)
        aAfterRelaunch.round()
        b.round()
        aAfterRelaunch.round()
        #expect(b.store.items.first?.tagID == work.id)
        #expect(b.store.tags.map(\.id) == [work.id])
        #expect(relaunched.items.first?.tagID == work.id)
        #expect(relaunched.tags.map(\.id) == [work.id])
        #expect(relaunched.tags.map(\.name) == ["Work"])
        #expect(b.store.tags.map(\.name) == ["Work"])
    }

    // Probe P3: both Macs enable sync before either can see the other's file, so neither adopts the other's tag by
    // name. Each then publishes its own "Work" and, without fusing in the merge, both Macs keep two for good.
    @Test func twoMacsThatJoinAtOnceEndWithOneTag() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let workA = try #require(a.store.createTag(name: "Work", colorIndex: 0))
        let one = try #require(a.store.add(.text("one"), source: safari, concealed: false))
        a.store.setTag(itemID: one.id, tagID: workA.id)
        let workB = try #require(b.store.createTag(name: "work", colorIndex: 3))
        let two = try #require(b.store.add(.text("two"), source: safari, concealed: false))
        b.store.setTag(itemID: two.id, tagID: workB.id)
        a.round()
        // B's iCloud has not listed A's new file yet.
        let aFile = try publishedFile()
        let hidden = root.appendingPathComponent("hidden.json")
        try fileManager.moveItem(at: aFile, to: hidden)
        b.round()
        try fileManager.moveItem(at: hidden, to: aFile)
        a.round()
        b.round()
        a.round()

        let winner = try #require([workA.id, workB.id].min { $0.uuidString < $1.uuidString })
        #expect(a.store.tags.map(\.id) == [winner])
        #expect(b.store.tags.map(\.id) == [winner])
        #expect(a.store.items.count == 2)
        #expect(b.store.items.count == 2)
        #expect(a.store.items.allSatisfy { $0.tagID == winner })
        #expect(b.store.items.allSatisfy { $0.tagID == winner })
    }

    // Renaming a tag to the name of another fuses the two. The renamed tag vanishes in the same round, so its new
    // name is never published, and the other Mac's file still lists it under its old name: without a record of the
    // fusion it came back, and the item with it. Which tag survives depends on the ids, so both orders are run.
    @Test(arguments: [true, false])
    func renamingATagToAnExistingNameKeepsOneTagOnBothMacs(renamingTheLargerID: Bool) throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let first = try #require(a.store.createTag(name: "Work", colorIndex: 0))
        let second = try #require(a.store.createTag(name: "Home", colorIndex: 1))
        let (kept, renamed) = (first.id.uuidString < second.id.uuidString) == renamingTheLargerID
            ? (first, second)
            : (second, first)
        let x = try #require(a.store.add(.text("x"), source: safari, concealed: false))
        clock.advance(1)
        a.store.setTag(itemID: x.id, tagID: renamed.id)
        a.round()
        b.round()
        a.round()

        clock.advance(60)
        b.store.renameTag(id: renamed.id, name: kept.name)
        for _ in 0..<3 {
            clock.advance(30)
            b.round()
            a.round()
        }

        let survivor = min(kept.id.uuidString, renamed.id.uuidString)
        for mac in [a, b] {
            #expect(mac.store.tags.map(\.name) == [kept.name])
            #expect(mac.store.tags.map(\.id.uuidString) == [survivor])
            #expect(mac.store.items.map(\.tagID?.uuidString) == [survivor])
        }
        // Settled: further rounds publish nothing new, so the two Macs do not keep rewriting their files.
        let devices = syncFolder.appendingPathComponent("devices", isDirectory: true)
        let published = try fileManager.contentsOfDirectory(atPath: devices.path).sorted()
            .map { try Data(contentsOf: devices.appendingPathComponent($0)) }
        clock.advance(30)
        b.round()
        a.round()
        #expect(try fileManager.contentsOfDirectory(atPath: devices.path).sorted()
            .map { try Data(contentsOf: devices.appendingPathComponent($0)) } == published)
    }

    // After two tags fused, a file that still lists the fused one (a Mac that has not synced since) must not split
    // them again when the surviving tag is renamed later.
    @Test func renamingTheSurvivorOfAFusionDoesNotBringTheOtherTagBack() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let c = try makeMac("C")
        _ = try #require(a.store.createTag(name: "Work", colorIndex: 0))
        let home = try #require(a.store.createTag(name: "Home", colorIndex: 1))
        let x = try #require(a.store.add(.text("x"), source: safari, concealed: false))
        a.store.setTag(itemID: x.id, tagID: home.id)
        for mac in [a, b, c, a] {
            mac.round()
        }
        clock.advance(60)
        b.store.renameTag(id: home.id, name: "Work")
        b.round()
        a.round()
        b.round()
        let survivor = try #require(b.store.tags.first)
        // C stays away; its file still lists Home.
        clock.advance(60)
        a.store.renameTag(id: survivor.id, name: "Office")
        for _ in 0..<2 {
            a.round()
            b.round()
        }
        for mac in [a, b] {
            #expect(mac.store.tags.map(\.name) == ["Office"])
            #expect(mac.store.items.map(\.tagID) == [survivor.id])
        }
    }

    @Test func deletionsSurviveARelaunch() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        let one = try #require(a.store.add(.text("one"), source: safari, concealed: false))
        a.round()
        b.round()
        clock.advance(1)
        a.store.remove(id: one.id)
        let relaunched = makeSync(directory: a.directory, machineID: "A")
        relaunched.sync(a.store)
        b.round()
        #expect(b.store.items.isEmpty)
    }

    // A quiet Mac must not be taken for gone after the retention.
    @Test func aQuietMacPublishesAgainEveryDay() throws {
        let a = try makeMac("A")
        a.round()
        let file = try publishedFile()
        let first = try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: file)).publishedAt
        clock.advance(Config.syncRefreshInterval + 1)
        a.round()
        let second = try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: file)).publishedAt
        #expect(second > first)
    }

    // sync.json holds the device ID: restoring the backup on another Mac must never copy it.
    @Test func syncSettingsStayOutOfTheBackup() throws {
        let a = try makeMac("A")
        a.store.add(.text("one"), source: safari, concealed: false)
        a.round()
        try BackupService(localDirectory: a.directory, iCloudDriveRoot: iCloud).backUp()
        #expect(fileManager.fileExists(atPath: a.directory.appendingPathComponent("sync.json").path))
        #expect(!fileManager.fileExists(atPath: iCloud.appendingPathComponent("SimpleClipboard/Backup/sync.json").path))
    }

    // Restoring on one Mac leaves both Macs with what was restored.
    @Test func restoringOnOneMacReachesTheOther() throws {
        let a = try makeMac("A")
        let b = try makeMac("B")
        a.store.add(.text("one"), source: safari, concealed: false)
        let backup = BackupService(localDirectory: a.directory, iCloudDriveRoot: iCloud)
        try backup.backUp()
        clock.advance(1)
        a.store.add(.text("two"), source: safari, concealed: false)
        a.round()
        b.round()
        clock.advance(1)
        try backup.restore()
        a.store.reloadFromDisk(markingChanges: true)
        a.round()
        b.round()
        #expect(b.store.items.map(\.text) == ["one"])
    }

    // The first-launch restore only fills an empty new Mac. If it stamped what it restored as changed now, enabling
    // sync afterwards would let that old data beat everything the other Mac did since its last backup: the deleted
    // item and the removed tag come back, the old tag name returns, and a value copied from 1Password is published
    // in plain text. The normal merge rules must decide, using the stamps the backup carries.
    @Test func aNewMacRestoredOnFirstLaunchKeepsTheOtherMacsLaterChanges() throws {
        let a = try makeMac("A")
        let work = try #require(a.store.createTag(name: "Work", colorIndex: 0))
        let deleted = try #require(a.store.add(.text("delete"), source: safari, concealed: false))
        a.store.setTag(itemID: deleted.id, tagID: work.id)
        clock.advance(1)
        let untagged = try #require(a.store.add(.text("untagged"), source: safari, concealed: false))
        a.store.setTag(itemID: untagged.id, tagID: work.id)
        clock.advance(1)
        a.store.add(.text("synthetic-key"), source: safari, concealed: false)
        a.round()
        try BackupService(localDirectory: a.directory, iCloudDriveRoot: iCloud).backUp()

        // After that backup, on A: delete an item, untag another, rename the tag, and copy from 1Password a value
        // that was saved as plain text.
        clock.advance(600)
        a.store.remove(id: deleted.id)
        a.store.setTag(itemID: untagged.id, tagID: nil)
        a.store.renameTag(id: work.id, name: "Office")
        a.store.add(.text("synthetic-key"), source: onePassword, concealed: true)
        a.round()

        // A new Mac B restores the backup at first launch (sync off) and the user turns sync on later.
        clock.advance(600)
        let b = try makeMac("B", enabled: false)
        try BackupService(localDirectory: b.directory, iCloudDriveRoot: iCloud).restore()
        b.store.reloadFromDisk(markingChanges: false)
        clock.advance(60)
        try b.sync.enable()
        b.store.deletionRecorder = { [sync = b.sync] in sync.record($0) }
        b.round()
        a.round()
        b.round()

        let visibleOnA = a.store.items.filter { !$0.isConcealed }
        #expect(visibleOnA.map(\.text) == ["untagged"])
        #expect(b.store.items.map(\.text) == ["untagged"])
        #expect(a.store.tags.map(\.name) == ["Office"])
        #expect(b.store.tags.map(\.name) == ["Office"])
        #expect(visibleOnA.allSatisfy { $0.tagID == nil })
        #expect(b.store.items.allSatisfy { $0.tagID == nil })
        // Backup/ legitimately holds the plain-text copy; what sync publishes must not.
        #expect(try !iCloudContains("synthetic-key", in: syncFolder))
    }

    // Migration Assistant or a Time Machine restore copies the whole data folder, sync.json included. With the same
    // device ID each Mac would skip the other's file as its own and both would write it, so they would never sync.
    @Test func aSyncFileCopiedToAnotherMacGetsANewDeviceID() throws {
        let a = try makeMac("A")
        a.store.add(.text("one"), source: safari, concealed: false)
        a.round()
        let copied = root.appendingPathComponent("B", isDirectory: true)
        try fileManager.copyItem(at: a.directory, to: copied)

        let bSync = makeSync(directory: copied, machineID: "B")
        let bStore = HistoryStore(persistence: FilePersistence(directory: copied), now: { [clock] in clock.current })
        bStore.deletionRecorder = { [bSync] in bSync.record($0) }
        let b = Mac(directory: copied, store: bStore, sync: bSync)
        #expect(b.sync.isEnabled)
        #expect(try savedSettings(in: b.directory).deviceID != savedSettings(in: a.directory).deviceID)

        clock.advance(1)
        b.store.add(.text("two"), source: safari, concealed: false)
        b.round()
        a.round()
        #expect(a.store.items.map(\.text) == ["two", "one"])
        #expect(b.store.items.map(\.text) == ["two", "one"])
        let devices = syncFolder.appendingPathComponent("devices", isDirectory: true)
        #expect(try fileManager.contentsOfDirectory(atPath: devices.path).count == 2)
    }

    // A sync.json written before the machine ID existed cannot be told apart from a copy: it is taken as this Mac's,
    // or every Mac that updates would publish a second file and look like a new Mac to the others.
    @Test func aSyncFileWithoutMachineIDKeepsItsDeviceID() throws {
        let a = try makeMac("A")
        a.round()
        let settingsURL = a.directory.appendingPathComponent("sync.json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        json["machineID"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: settingsURL)
        let before = try savedSettings(in: a.directory)
        #expect(before.machineID == nil)

        let relaunched = makeSync(directory: a.directory, machineID: "A")
        let after = try savedSettings(in: a.directory)
        #expect(after.deviceID == before.deviceID)
        #expect(after.hasJoined)
        #expect(after.machineID == "A")
        #expect(relaunched.sync(a.store) == .synced(clock.current))
    }

    // Relaunching on the same Mac must not look like a copy: a new device ID would leave its old file behind as a
    // Mac that never comes back.
    @Test func theSameMacKeepsItsDeviceIDAcrossRelaunches() throws {
        let a = try makeMac("A")
        a.round()
        let before = try savedSettings(in: a.directory)
        _ = makeSync(directory: a.directory, machineID: "A")
        #expect(try savedSettings(in: a.directory) == before)
    }
}
