import AppKit
import ClipboardCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: ClosableWindow
    private let onBecomeKey: @MainActor () -> Void

    /// `onBecomeKey`: called whenever the window opens or comes back to the front, to refresh what it shows.
    init(
        state: SettingsState, setOpensAtLogin: @escaping @MainActor (Bool) -> Void,
        onBecomeKey: @escaping @MainActor () -> Void
    ) {
        self.onBecomeKey = onBecomeKey
        window = ClosableWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.delegate = self
        window.title = "\(Config.appName) Settings"
        // Kept for the next time it is opened.
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsView(state: state, setOpensAtLogin: setOpensAtLogin)
        )
    }

    /// True while the user is in the window: false when it is closed or behind another app.
    var isKey: Bool {
        window.isKeyWindow
    }

    func show() {
        // Before the window is drawn: it would open with the values of the last time and then change.
        onBecomeKey()
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey()
    }

    /// With no window left the app would stay active and unseen: the next ⇧⌘V has to see the user's app in front.
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }
}
