import AppKit
import ClipboardCore
import SwiftUI

/// The app has no main menu, so ⌘W and Esc never close the window on their own.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
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
    init(state: SettingsState, actions: SettingsActions, onBecomeKey: @escaping @MainActor () -> Void) {
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
        window.contentViewController = NSHostingController(rootView: SettingsView(state: state, actions: actions))
    }

    var isVisible: Bool {
        window.isVisible
    }

    func show() {
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey()
    }
}
