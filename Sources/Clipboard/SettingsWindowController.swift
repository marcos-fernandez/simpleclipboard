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
        state: SettingsState, setOpensAtLogin: @escaping @MainActor (Bool) -> Void,
        onBecomeKey: @escaping @MainActor () -> Void
    ) {
        self.onBecomeKey = onBecomeKey
        window = SettingsWindow(
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

    func show() {
        // Before the window is drawn: it would open with the values of the last time and then change.
        onBecomeKey()
        if !window.isVisible {
            window.center()
        }
        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey()
    }

    /// With no window left the app would stay active and unseen: the next ⇧⌘V has to see the user's app in front.
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }
}
