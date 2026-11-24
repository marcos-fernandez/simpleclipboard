import AppKit
import ClipboardCore
import os

/// macOS has no clipboard-change notification, so we poll `changeCount`.
@MainActor
final class ClipboardMonitor {
    private static let logger = Logger(subsystem: Config.bundleID, category: "ClipboardMonitor")

    private let pasteboard = NSPasteboard.general
    /// Converts and hashes off the main thread, and adds to the store in the order copied.
    private let captures: CaptureQueue
    private var lastChangeCount: Int
    private var timer: Timer?
    /// Apps that lost focus since the previous poll (e.g. 1Password handing focus back to the browser).
    private var recentlyDeactivated: Set<String> = []
    private let concealedSourceBundleIDs: @MainActor () -> Set<String>
    private let ignoredSourceBundleIDs: @MainActor () -> Set<String>

    /// `concealedSourceBundleIDs`: the apps whose copies are kept hidden; `ignoredSourceBundleIDs`: the apps nothing
    /// is copied from. Both asked at every copy, so a change in the settings counts from the next one.
    init(
        store: HistoryStore,
        concealedSourceBundleIDs: @escaping @MainActor () -> Set<String>,
        ignoredSourceBundleIDs: @escaping @MainActor () -> Set<String>
    ) {
        self.concealedSourceBundleIDs = concealedSourceBundleIDs
        self.ignoredSourceBundleIDs = ignoredSourceBundleIDs
        captures = CaptureQueue(store: store) { tiff in
            NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        }
        lastChangeCount = pasteboard.changeCount
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundleID = app?.bundleIdentifier else {
                return
            }
            MainActor.assumeIsolated {
                _ = self?.recentlyDeactivated.insert(bundleID)
            }
        }
    }

    func start() {
        let timer = Timer(timeInterval: Config.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        // .common keeps polling while a menu or modal alert is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let recentSourceBundleIDs = recentlyDeactivated
        recentlyDeactivated.removeAll()
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = changeCount

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        let frontApp = NSWorkspace.shared.frontmostApplication
        let classification = PasteboardClassifier.classify(
            types: types,
            sourceBundleID: frontApp?.bundleIdentifier,
            recentSourceBundleIDs: recentSourceBundleIDs,
            concealedSourceBundleIDs: concealedSourceBundleIDs(),
            ignoredSourceBundleIDs: ignoredSourceBundleIDs()
        )
        guard classification != .ignore, let capture = readCapture() else {
            return
        }
        let source = SourceApp(bundleID: frontApp?.bundleIdentifier, name: frontApp?.localizedName)
        captures.add(capture, source: source, concealed: classification == .concealed)
        Self.logger.debug("Read a copy, concealed=\(classification == .concealed)")
    }

    /// Adds the copies still being converted (at quit).
    func flush() {
        captures.flush()
    }

    /// Text wins over image, unless the text is blank. Only read here: a TIFF is converted later, off the main thread.
    private func readCapture() -> PasteboardCapture? {
        PasteboardContent.choose(text: pasteboard.string(forType: .string)) {
            if let png = pasteboard.data(forType: .png) {
                return .png(png)
            }
            return pasteboard.data(forType: .tiff).map(PasteboardImage.tiff)
        }
    }
}
