import Foundation
@testable import ClipboardCore

final class InMemoryPersistence: HistoryPersistence {
    var stored: [ClipItem]
    var storedTags: [Tag]
    var images: [String: Data] = [:]
    var failImageWrites = false
    var saveCount = 0

    init(stored: [ClipItem] = [], storedTags: [Tag] = []) {
        self.stored = stored
        self.storedTags = storedTags
    }

    func load() -> [ClipItem] { stored }
    func save(_ items: [ClipItem]) {
        stored = items
        saveCount += 1
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
