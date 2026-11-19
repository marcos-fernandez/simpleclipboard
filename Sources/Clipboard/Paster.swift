import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipboardCore
import os

@MainActor
enum Paster {
    private static let logger = Logger(subsystem: Config.bundleID, category: "Paster")

    /// Puts the item on the pasteboard, returns focus to `target` and sends ⌘V.
    /// Without Accessibility permission it only copies.
    /// Returns whether the item was put on the pasteboard, so the caller does not treat a failed paste as a use.
    @discardableResult
    static func paste(_ item: ClipItem, imageData: Data?, into target: NSRunningApplication?) -> Bool {
        if item.kind == .image, imageData == nil {
            logger.error("Image file missing for selected item; nothing pasted")
            return false
        }
        write(item, imageData: imageData)
        if item.isConcealed {
            clearPasteboardLater()
        }
        // Without a live target, ⌘V would land in whatever is frontmost, possibly one of our own alerts.
        guard let target, !target.isTerminated else {
            logger.info("No app to paste into; item copied but not pasted")
            return true
        }
        target.activate()
        guard AXIsProcessTrusted() else {
            logger.info("No Accessibility permission; item copied but not pasted")
            return true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            sendCommandV()
        }
        return true
    }

    private static func write(_ item: ClipItem, imageData: Data?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let marker = NSPasteboard.PasteboardType(Config.ownMarkerType)
        pasteboard.setData(Data(), forType: marker)
        if item.isConcealed {
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(Config.concealedType))
        }
        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            if let imageData {
                pasteboard.setData(imageData, forType: .png)
            }
        }
    }

    /// The pasteboard's change count right after we put a concealed value on it; nil once it is cleared.
    private static var concealedChangeCount: Int?

    /// Clears a pasted password after a while, unless something else was copied meanwhile.
    private static func clearPasteboardLater() {
        let changeCount = NSPasteboard.general.changeCount
        concealedChangeCount = changeCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Config.concealedPasteboardLifetime))
            if concealedChangeCount == changeCount {
                clearConcealedValue()
            }
        }
    }

    /// Clears the pasteboard now if it still holds the concealed value we put there. Called at quit: the timer of
    /// `clearPasteboardLater` dies with the app and would leave the password on the system pasteboard.
    /// Not reached when the app is killed (SIGKILL, or SIGTERM without AppKit's termination).
    static func clearConcealedValue() {
        if let changeCount = concealedChangeCount, NSPasteboard.general.changeCount == changeCount {
            NSPasteboard.general.clearContents()
        }
        concealedChangeCount = nil
    }

    /// Simulates a full physical ⌘V (⌘ down, V down, V up, ⌘ up) on the session tap.
    /// Chromium web content (e.g. Gmail fields) ignores a lone V event that only carries the ⌘ flag.
    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // NX_DEVICELCMDKEYMASK: tells receivers it was the left ⌘ key, as real hardware does.
        let commandFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0000_0008)
        // Resolved per paste so it matches the layout active right now.
        let keyV = KeyboardLayout.keyCodeForV()
        let keys: [(CGKeyCode, Bool, CGEventFlags)] = [
            (CGKeyCode(kVK_Command), true, commandFlags),
            (keyV, true, commandFlags),
            (keyV, false, commandFlags),
            (CGKeyCode(kVK_Command), false, []),
        ]
        for (keyCode, keyDown, flags) in keys {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cgSessionEventTap)
        }
    }
}
