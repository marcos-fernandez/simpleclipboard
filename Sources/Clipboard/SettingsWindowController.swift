import AppKit
import Carbon.HIToolbox
import ClipboardCore
import SwiftUI

/// The app has no main menu, so ⌘W and Esc never close the window on their own.
final class SettingsWindow: NSWindow {
    /// Called with -1 or 1 when ↑ or ↓ reaches the window, that is, when nothing in it (a list, a text field) took
    /// the key: the rows of the sidebar are drawn by hand and the keyboard would not reach them otherwise.
    var onMoveSelection: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            onMoveSelection?(-1)
        case kVK_DownArrow:
            onMoveSelection?(1)
        default:
            super.keyDown(with: event)
        }
    }

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
        // Not on show: it would sit across the sidebar and the pane, above the header that already names the pane.
        // It is still what Mission Control and VoiceOver say (see `SettingsPane.windowTitle`).
        window.title = state.pane.windowTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(
            rootView: SettingsView(state: state, actions: actions) { [window] pane in
                window.title = pane.windowTitle
            }
        )
        window.onMoveSelection = { offset in
            state.movePane(by: offset)
        }
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
