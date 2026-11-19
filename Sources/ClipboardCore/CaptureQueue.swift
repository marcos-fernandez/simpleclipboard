import Foundation
import os

/// Hands what the monitor reads from the pasteboard to the store. The pasteboard is read on the main thread, at the
/// copy, with its classification and source app; converting a TIFF to PNG and hashing take seconds for a large image,
/// so they run on a serial background queue, and the store gets each copy back on the main thread in the order they
/// were made, text included (a text copied after an image must not jump ahead of it). A copy that is over the limits
/// or cannot be converted is dropped there, and the next one goes on.
@MainActor
public final class CaptureQueue {
    private struct Capture: Sendable {
        let prepared: HistoryStore.PreparedContent
        let source: SourceApp
        let concealed: Bool
    }

    private nonisolated static let logger = Logger(subsystem: Config.bundleID, category: "CaptureQueue")

    private let store: HistoryStore
    private let convertTIFF: @Sendable (Data) -> Data?
    private let worker = DispatchQueue(label: "\(Config.bundleID).capture", qos: .userInitiated)
    /// Copies prepared by the worker, in order, waiting for the main thread.
    private let ready = OSAllocatedUnfairLock<[Capture]>(initialState: [])

    /// `convertTIFF` returns PNG bytes, or nil when the TIFF cannot be read; it runs on the background queue.
    public init(store: HistoryStore, convertTIFF: @escaping @Sendable (Data) -> Data?) {
        self.store = store
        self.convertTIFF = convertTIFF
    }

    public func add(_ capture: PasteboardCapture, source: SourceApp, concealed: Bool) {
        // Sizes known without converting are checked here, so a hopeless copy is not even queued.
        switch capture {
        case .image(.png(let data)) where data.count > Config.maxImageBytes,
             .image(.tiff(let data)) where data.count > Config.maxTIFFBytes:
            Self.logger.notice("Dropping image of \(data.count, privacy: .public) bytes, over the limit")
            return
        default:
            break
        }
        worker.async { [ready, convertTIFF] in
            guard let prepared = Self.prepare(capture, convertTIFF: convertTIFF) else {
                return
            }
            ready.withLock { $0.append(Capture(prepared: prepared, source: source, concealed: concealed)) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.deliver()
                }
            }
        }
    }

    /// Waits for every copy queued so far and adds it to the store (at quit, and in tests).
    public func flush() {
        worker.sync {}
        deliver()
    }

    private nonisolated static func prepare(
        _ capture: PasteboardCapture, convertTIFF: (Data) -> Data?
    ) -> HistoryStore.PreparedContent? {
        switch capture {
        case .text(let text):
            return HistoryStore.prepare(.text(text))
        case .image(.png(let data)):
            return HistoryStore.prepare(.image(data))
        case .image(.tiff(let data)):
            guard let png = convertTIFF(data) else {
                logger.notice("Dropping an image that cannot be converted to PNG")
                return nil
            }
            return HistoryStore.prepare(.image(png))
        }
    }

    private func deliver() {
        let captures = ready.withLock { ready in
            let captures = ready
            ready = []
            return captures
        }
        for capture in captures {
            store.add(capture.prepared, source: capture.source, concealed: capture.concealed)
        }
    }
}
