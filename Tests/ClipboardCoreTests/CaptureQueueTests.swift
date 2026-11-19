import Foundation
import os
import Testing
@testable import ClipboardCore

/// Converting a large TIFF to PNG and hashing it took seconds on the main thread, freezing ⇧⌘V and the panel. Moved
/// off it, the history must still read as it was copied: same order, same classification, nothing half-added.
@MainActor
struct CaptureQueueTests {
    let persistence = InMemoryPersistence()
    let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
    let onePassword = SourceApp(bundleID: "com.1password.1password", name: "1Password")
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    /// Calls to the converter, and whether any ran on the main thread.
    let conversions = OSAllocatedUnfairLock(initialState: (count: 0, onMain: false))

    func makeQueue(converting result: Data?) -> (HistoryStore, CaptureQueue) {
        let store = HistoryStore(persistence: persistence)
        let queue = CaptureQueue(store: store) { [conversions] _ in
            conversions.withLock { $0 = ($0.count + 1, $0.onMain || Thread.isMainThread) }
            return result
        }
        return (store, queue)
    }

    @Test func capturesAreAddedInTheOrderTheyWereCopied() {
        // A text copied while a large image was still converting is the newer copy: it must not jump ahead of it.
        let (store, queue) = makeQueue(converting: png)
        queue.add(.image(.tiff(Data([1]))), source: safari, concealed: false)
        queue.add(.text("copied after"), source: safari, concealed: false)

        queue.flush()

        #expect(store.items.map(\.kind) == [.text, .image])
        #expect(store.imageData(for: store.items[1]) == png)
    }

    @Test func theConversionRunsOffTheMainThread() {
        let (_, queue) = makeQueue(converting: png)
        queue.add(.image(.tiff(Data([1]))), source: safari, concealed: false)

        queue.flush()

        #expect(conversions.withLock { $0 } == (1, false))
    }

    @Test func aCaptureThatCannotBeConvertedIsDroppedAndTheNextOneIsStillAdded() {
        let (store, queue) = makeQueue(converting: nil)
        queue.add(.image(.tiff(Data([1]))), source: safari, concealed: false)
        queue.add(.text("next"), source: safari, concealed: false)

        queue.flush()

        #expect(store.items.map(\.text) == ["next"])
        #expect(persistence.images.isEmpty)
    }

    @Test func aConvertedImageOverTheLimitIsDropped() {
        let (store, queue) = makeQueue(converting: Data(count: Config.maxImageBytes + 1))
        queue.add(.image(.tiff(Data([1]))), source: safari, concealed: false)

        queue.flush()

        #expect(store.items.isEmpty)
        #expect(persistence.images.isEmpty)
    }

    @Test func aTIFFLargerThanTheImageLimitIsStillConverted() {
        // A TIFF is uncompressed: its size says little about the PNG it becomes, which is what the limit is for.
        let (store, queue) = makeQueue(converting: png)
        queue.add(.image(.tiff(Data(count: Config.maxImageBytes + 1))), source: safari, concealed: false)

        queue.flush()

        #expect(store.items.count == 1)
    }

    @Test func aTIFFOverItsBoundIsRefusedWithoutConverting() {
        // Beyond it the PNG could only fit with a compression no real image reaches: converting would burn seconds
        // and memory for nothing.
        let (store, queue) = makeQueue(converting: png)
        queue.add(.image(.tiff(Data(count: Config.maxTIFFBytes + 1))), source: safari, concealed: false)

        queue.flush()

        #expect(store.items.isEmpty)
        #expect(conversions.withLock { $0.count } == 0)
    }

    @Test func aPNGOverTheLimitIsRefusedBeforeQueueing() {
        let (store, queue) = makeQueue(converting: png)
        queue.add(.image(.png(Data(count: Config.maxImageBytes + 1))), source: safari, concealed: false)

        queue.flush()

        #expect(store.items.isEmpty)
    }

    @Test func aConcealedImageStaysInMemoryOnly() {
        // The classification is made when the copy is read; converting later must not turn a 1Password image into
        // a file on disk.
        let (store, queue) = makeQueue(converting: png)
        queue.add(.image(.tiff(Data([1]))), source: onePassword, concealed: true)

        queue.flush()

        #expect(store.items.map(\.isConcealed) == [true])
        #expect(store.items.first?.sourceAppBundleID == onePassword.bundleID)
        #expect(store.imageData(for: store.items[0]) == png)
        #expect(persistence.images.isEmpty)
        #expect(persistence.stored.isEmpty)
    }
}
