import Foundation
@testable import ClipboardCore

final class InMemoryPersistence: HistoryPersistence {
    var stored: [ClipItem]
    var storedTags: [Tag]
    var images: [String: Data] = [:]
    var failImageWrites = false
    var failSaves = false
    var tagsWereLost = false
    var saveCount = 0

    init(stored: [ClipItem] = [], storedTags: [Tag] = []) {
        self.stored = stored
        self.storedTags = storedTags
    }

    func load() -> [ClipItem] { stored }
    func save(_ items: [ClipItem]) -> Bool {
        guard !failSaves else {
            return false
        }
        stored = items
        saveCount += 1
        return true
    }
    func loadTags() -> [Tag] { storedTags }
    func saveTags(_ tags: [Tag]) { storedTags = tags }

    func writeImage(_ data: Data, named name: String) throws {
        if failImageWrites {
            throw CocoaError(.fileWriteUnknown)
        }
        images[name] = data
    }

    func readImage(named name: String) -> Data? { images[name] }

    func deleteImages(notIn keep: Set<String>) {
        images = images.filter { keep.contains($0.key) }
    }
}

/// Holds every save until the test lets it through, so a test can hand states over while an older one is being
/// written. Semaphores, not sleeps: each step waits for the exact event it needs.
final class GatedPersistence: HistoryPersistence, @unchecked Sendable {
    let inner = InMemoryPersistence()
    /// The texts of each history saved, in the order the saves were made.
    private(set) var savedTexts: [[String?]] = []
    private let entered = DispatchSemaphore(value: 0)
    private let gate = DispatchSemaphore(value: 0)

    /// Returns once a save has started and is waiting at the gate.
    func waitUntilSaving() {
        entered.wait()
    }

    /// Lets the save waiting at the gate go on.
    func release() {
        gate.signal()
    }

    func load() -> [ClipItem] { inner.load() }
    func save(_ items: [ClipItem]) -> Bool {
        entered.signal()
        gate.wait()
        savedTexts.append(items.map(\.text))
        return inner.save(items)
    }
    var tagsWereLost: Bool { inner.tagsWereLost }
    func loadTags() -> [Tag] { inner.loadTags() }
    func saveTags(_ tags: [Tag]) { inner.saveTags(tags) }
    func writeImage(_ data: Data, named name: String) throws { try inner.writeImage(data, named: name) }
    func readImage(named name: String) -> Data? { inner.readImage(named: name) }
    func deleteImages(notIn keep: Set<String>) { inner.deleteImages(notIn: keep) }
}

final class TestClock {
    var current = Date(timeIntervalSince1970: 1_000_000)

    func advance(_ seconds: TimeInterval) {
        current += seconds
    }
}

/// Makes one copy fail half-way through a backup, the way a full disk or a
/// file evicted by iCloud would.
final class FailingCopyFileManager: FileManager, @unchecked Sendable {
    var failWhenCopying: String?
    var failWhenMoving: String?

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent == failWhenCopying {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent == failWhenMoving {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
