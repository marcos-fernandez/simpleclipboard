import Foundation
import os

/// Writes the store's saves (`saveHistory`) on a background queue: the store saves the whole history after every
/// change, and encoding and writing it on the main thread froze the clipboard polling and the panel.
///
/// - Order: one serial writer that always takes the latest state handed over. A state still waiting is replaced by
///   a newer one, so an earlier state never lands after a later one.
/// - Crash: what is lost is at most the latest state handed over and not written yet (normally the last fraction of
///   a second), including the removal from disk of a value just copied again as concealed. `flush()` writes it:
///   call it before anything reads the files from disk (backup, restore, quit).
/// - Images: written and read on the caller's thread, as before (the store writes an image before listing it).
///   Unused ones are deleted on the main thread, only after a successful save, keeping every image listed by the
///   last history written, by the one being written and by the latest handed over: so no history on disk, now or
///   after a later save fails, lists a deleted image. On the main thread the deletion cannot fall between
///   `SyncService` finding an image in images/ and the store listing it.
///
/// `@unchecked Sendable`: the wrapped persistence is not thread-safe. The writer queue only calls its `save` and
/// `saveTags`; the main thread calls everything else, either after `flush()` (the queue is then idle, and only the
/// main thread hands it work) or, for the image methods, touching only the images folder, which saves never touch.
/// The state shared with the writer is behind a lock.
public final class BackgroundPersistence: HistoryPersistence, @unchecked Sendable {
    private struct State {
        /// The latest state handed over and not taken by the writer yet.
        var pending: (items: [ClipItem], tags: [Tag], images: Set<String>)?
        /// Images listed by the state being written.
        var writing: Set<String>?
        /// Images listed by the last history written, until its unused images are deleted.
        var written: Set<String>?
        /// Images listed by the latest state handed over.
        var latest: Set<String> = []
    }

    private let inner: HistoryPersistence
    private let queue = DispatchQueue(label: "\(Config.bundleID).persistence", qos: .userInitiated)
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(wrapping inner: HistoryPersistence) {
        self.inner = inner
    }

    public func saveHistory(_ items: [ClipItem], tags: [Tag]) {
        let images = Set(items.compactMap(\.imageFileName))
        state.withLock { state in
            state.pending = (items, tags, images)
            state.latest = images
        }
        queue.async {
            self.writePending()
        }
    }

    /// Waits until every state handed over is written, then deletes the images no history lists any more.
    public func flush() {
        queue.sync {}
        deleteUnusedImages()
    }

    public func load() -> [ClipItem] {
        flush()
        return inner.load()
    }

    @discardableResult
    public func save(_ items: [ClipItem]) -> Bool {
        flush()
        return inner.save(items)
    }

    public func loadTags() -> [Tag] {
        flush()
        return inner.loadTags()
    }

    public var tagsWereLost: Bool {
        inner.tagsWereLost
    }

    public func saveTags(_ tags: [Tag]) {
        flush()
        inner.saveTags(tags)
    }

    public func writeImage(_ data: Data, named name: String) throws {
        try inner.writeImage(data, named: name)
    }

    public func readImage(named name: String) -> Data? {
        inner.readImage(named: name)
    }

    public func deleteImages(notIn keep: Set<String>) {
        flush()
        inner.deleteImages(notIn: keep)
    }

    /// On the main thread (see the type's comment). Does nothing until a new history has been written.
    func deleteUnusedImages() {
        let keep = state.withLock { state -> Set<String>? in
            guard let written = state.written else {
                return nil
            }
            state.written = nil
            return written.union(state.writing ?? []).union(state.latest)
        }
        if let keep {
            inner.deleteImages(notIn: keep)
        }
    }

    /// On the writer queue. Each `saveHistory` schedules one call; a call that finds nothing waiting does nothing.
    private func writePending() {
        let job = state.withLock { state in
            let job = state.pending
            state.pending = nil
            state.writing = job?.images
            return job
        }
        guard let job else {
            return
        }
        let saved = inner.save(job.items)
        inner.saveTags(job.tags)
        state.withLock { state in
            state.writing = nil
            if saved {
                state.written = job.images
            }
        }
        if saved {
            DispatchQueue.main.async {
                self.deleteUnusedImages()
            }
        }
    }
}
