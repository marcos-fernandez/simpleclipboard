import AppKit
import ClipboardCore
import os

/// macOS has no clipboard-change notification, so we poll `changeCount`.
@MainActor
final class ClipboardMonitor {
    private static let logger = Logger(subsystem: Config.bundleID, category: "ClipboardMonitor")

    private let pasteboard = NSPasteboard.general
    private let store: HistoryStore
    private var lastChangeCount: Int
    private var timer: Timer?
    /// Apps that lost focus since the previous poll (e.g. 1Password handing focus back to the browser).
    private var recentlyDeactivated: Set<String> = []

    init(store: HistoryStore) {
        self.store = store
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
            recentSourceBundleIDs: recentSourceBundleIDs
        )
        guard classification != .ignore, let content = readContent() else {
            return
        }
        let source = SourceApp(bundleID: frontApp?.bundleIdentifier, name: frontApp?.localizedName)
        let item = store.add(content, source: source, concealed: classification == .concealed)
        Self.logger.debug("Captured kind=\(item?.kind.rawValue ?? "none", privacy: .public) concealed=\(classification == .concealed)")
    }

    /// Text wins over image : if there is text, kind = .text.
    private func readContent() -> ClipContent? {
        if let text = pasteboard.string(forType: .string) {
            return .text(text)
        }
        if let png = pasteboard.data(forType: .png) {
            return .image(png)
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return .image(png)
        }
        return nil
    }
}
