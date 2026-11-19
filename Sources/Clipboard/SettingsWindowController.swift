import AppKit
import ClipboardCore
import SwiftUI

/// The app has no main menu, so ⌘W and Esc never close the window on their own.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Caps Lock is a device-independent flag too; drop it so "only ⌘" compares cleanly.
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: SettingsWindow
    private let onBecomeKey: @MainActor () -> Void

    /// `onBecomeKey`: called whenever the window opens or comes back to the front, to refresh what it shows.
    init(
        state: SettingsState, actions: SettingsActions, onBecomeKey: @escaping @MainActor () -> Void
    ) {
        self.onBecomeKey = onBecomeKey
        window = SettingsWindow(
            contentRect: .zero,
            // The sidebar runs under the title bar, as in System Settings.
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.delegate = self
        // Kept for the next time it is opened.
        window.isReleasedWhenClosed = false
        // The app's name is what Mission Control shows; in the window, the pane's name is the header of the view.
        window.title = Config.appName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(
            rootView: SettingsView(state: state, actions: actions)
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
