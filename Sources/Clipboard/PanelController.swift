import AppKit
import Carbon.HIToolbox
import ClipboardCore
import Observation
import SwiftUI

/// SwiftUI overlays inside the strip (not separate windows, so the panel keeps key focus).
enum PanelOverlay: Equatable {
    case tagPicker(itemID: UUID)
    case newTag(itemID: UUID)
    case renameTag(tagID: UUID)
    case deleteTag(tagID: UUID)
}

enum TagPickerOption: Hashable {
    case tag(UUID)
    case newTag
    case removeTag
}

@MainActor
@Observable
final class PanelState {
    var query = ""
    /// Selection follows the item, not its position, so new copies or purges don't shift it.
    /// nil means "first result".
    var selectedID: UUID?
    /// Incremented on every show so the view focuses the search field.
    var focusRequest = 0
    /// Active tab. Reset to .history every time the panel opens.
    var scope: HistoryStore.Scope = .history

    /// Falls back to the history tab if the active tag was deleted.
    func results(in store: HistoryStore) -> [ClipItem] {
        store.search(query, in: effectiveScope(in: store))
    }

    func scopes(in store: HistoryStore) -> [HistoryStore.Scope] {
        [.history] + store.tags.map { .tag($0.id) }
    }

    func effectiveScope(in store: HistoryStore) -> HistoryStore.Scope {
        if case .tag(let tagID) = scope, !store.tags.contains(where: { $0.id == tagID }) {
            return .history
        }
        return scope
    }

    func selectedIndex(in results: [ClipItem]) -> Int {
        results.firstIndex { $0.id == selectedID } ?? 0
    }

    var overlay: PanelOverlay?
    var pickerIndex = 0
    var promptText = ""

    func pickerOptions(for itemID: UUID, in store: HistoryStore) -> [TagPickerOption] {
        var options = store.tags.map { TagPickerOption.tag($0.id) } + [.newTag]
        if store.items.first(where: { $0.id == itemID })?.tagID != nil {
            options.append(.removeTag)
        }
        return options
    }

    func apply(_ option: TagPickerOption, to itemID: UUID, in store: HistoryStore) {
        switch option {
        case .tag(let tagID):
            store.setTag(itemID: itemID, tagID: tagID)
            overlay = nil
        case .removeTag:
            store.setTag(itemID: itemID, tagID: nil)
            overlay = nil
        case .newTag:
            promptText = ""
            overlay = .newTag(itemID: itemID)
        }
    }

    /// Blank names are refused by the store; the overlay simply stays open.
    func submitPrompt(in store: HistoryStore) {
        switch overlay {
        case .newTag(let itemID):
            // The item can expire or be deleted from another Mac while the prompt is open; a tag created
            // then would be left with no items.
            guard store.items.contains(where: { $0.id == itemID }) else {
                overlay = nil
                return
            }
            let colorIndex = store.tags.count % Config.tagColorCount
            guard let tag = store.createTag(name: promptText, colorIndex: colorIndex) else {
                return
            }
            store.setTag(itemID: itemID, tagID: tag.id)
        case .renameTag(let tagID):
            guard store.tags.contains(where: { $0.id == tagID }) else {
                overlay = nil
                return
            }
            guard store.renameTag(id: tagID, name: promptText) else {
                return
            }
        default:
            return
        }
        overlay = nil
    }

    func confirmDelete(in store: HistoryStore) {
        guard case .deleteTag(let tagID) = overlay else {
            return
        }
        store.deleteTag(id: tagID)
        if scope == .tag(tagID) {
            scope = .history
        }
        selectedID = nil
        overlay = nil
    }

    func startRename(_ tag: Tag) {
        promptText = tag.name
        overlay = .renameTag(tagID: tag.id)
    }
}

/// Borderless panels refuse key status by default; we need it for the search field.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let height: CGFloat = 330
    private static let margin: CGFloat = 8

    private let store: HistoryStore
    private let state = PanelState()
    private let panel: KeyablePanel
    private let onPick: (ClipItem, NSRunningApplication?) -> Void
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(store: HistoryStore, onPick: @escaping (ClipItem, NSRunningApplication?) -> Void) {
        self.store = store
        self.onPick = onPick
        // Non-activating: the app the user was typing in stays frontmost.
        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: HistoryView(store: store, state: state) { [weak self] item in
                self?.pick(item)
            }
        )
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let frontApp = NSWorkspace.shared.frontmostApplication
        // When we are frontmost (e.g. one of our alerts), there is no app to paste into: an app recorded on an
        // earlier show would receive the paste unseen.
        previousApp = frontApp?.processIdentifier == NSRunningApplication.current.processIdentifier
            ? nil
            : frontApp
        state.query = ""
        state.selectedID = nil
        state.scope = .history
        state.overlay = nil

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            return
        }
        panel.setFrame(
            NSRect(
                x: visible.minX + Self.margin,
                y: visible.minY + Self.margin,
                width: visible.width - 2 * Self.margin,
                height: Self.height
            ),
            display: true
        )
        panel.makeKeyAndOrderFront(nil)
        state.focusRequest += 1
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func pick(_ item: ClipItem) {
        let target = previousApp
        hide()
        onPick(item, target)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else {
            return
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            let handled = MainActor.assumeIsolated {
                self.handle(event)
            }
            return handled
                ? nil
                : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Returns true when the key was handled; arrows never move the text cursor.
    private func handle(_ event: NSEvent) -> Bool {
        if state.overlay != nil {
            return handleOverlayKey(event)
        }
        // Arrow keys carry .numericPad/.function; drop them so "only ⌘" compares cleanly.
        // Exact match keeps ⌘ arrow combos with other modifiers out of tab switching (they fall through to the card-selection cases).
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        if modifiers == .command {
            switch Int(event.keyCode) {
            case kVK_LeftArrow:
                switchTab(by: -1)
                return true
            case kVK_RightArrow:
                switchTab(by: 1)
                return true
            default:
                break
            }
            // By character, like the edit shortcuts: on Dvorak the key at kVK_ANSI_T does not type "t".
            if event.charactersIgnoringModifiers?.lowercased() == "t" {
                openTagPicker()
                return true
            }
        }
        let results = state.results(in: store)
        let index = state.selectedIndex(in: results)
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
        case kVK_LeftArrow:
            if index > 0 {
                state.selectedID = results[index - 1].id
            }
        case kVK_RightArrow:
            if index + 1 < results.count {
                state.selectedID = results[index + 1].id
            }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if results.indices.contains(index) {
                pick(results[index])
            }
        case kVK_Delete where event.modifierFlags.contains(.command):
            if results.indices.contains(index) {
                store.remove(id: results[index].id)
                let remaining = state.results(in: store)
                state.selectedID = remaining.isEmpty
                    ? nil
                    : remaining[min(index, remaining.count - 1)].id
            }
        default:
            return sendEditShortcut(event)
        }
        return true
    }

    private func openTagPicker() {
        let results = state.results(in: store)
        let index = state.selectedIndex(in: results)
        guard results.indices.contains(index), !results[index].isConcealed else {
            return
        }
        state.pickerIndex = 0
        state.overlay = .tagPicker(itemID: results[index].id)
    }

    /// While an overlay is open, Esc closes only the overlay; text prompts get the other keys.
    private func handleOverlayKey(_ event: NSEvent) -> Bool {
        guard let overlay = state.overlay else {
            return false
        }
        if Int(event.keyCode) == kVK_Escape {
            state.overlay = nil
            return true
        }
        switch overlay {
        case .tagPicker(let itemID):
            let options = state.pickerOptions(for: itemID, in: store)
            // The options can shrink while the picker is open (e.g. a tag deleted); never empty ("new tag").
            state.pickerIndex = min(max(0, state.pickerIndex), options.count - 1)
            switch Int(event.keyCode) {
            case kVK_UpArrow:
                state.pickerIndex = max(0, state.pickerIndex - 1)
            case kVK_DownArrow:
                state.pickerIndex = min(options.count - 1, state.pickerIndex + 1)
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if options.indices.contains(state.pickerIndex) {
                    state.apply(options[state.pickerIndex], to: itemID, in: store)
                }
            default:
                break
            }
            return true
        case .newTag, .renameTag:
            // Return is handled by the text field's onSubmit.
            return sendEditShortcut(event)
        case .deleteTag:
            if [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) {
                state.confirmDelete(in: store)
            }
            return true
        }
    }

    private func switchTab(by offset: Int) {
        let scopes = state.scopes(in: store)
        let current = scopes.firstIndex(of: state.effectiveScope(in: store)) ?? 0
        let next = current + offset
        guard scopes.indices.contains(next) else {
            return
        }
        state.scope = scopes[next]
        state.selectedID = nil
    }

    /// The app has no main menu, so ⌘V/⌘C/⌘X/⌘A/⌘Z never reach the search field on their own.
    private func sendEditShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        let action: Selector
        switch (key, modifiers.contains(.shift)) {
        case ("v", false):
            action = #selector(NSText.paste(_:))
        case ("c", false):
            action = #selector(NSText.copy(_:))
        case ("x", false):
            action = #selector(NSText.cut(_:))
        case ("a", false):
            action = #selector(NSText.selectAll(_:))
        case ("z", false):
            action = Selector(("undo:"))
        case ("z", true):
            action = Selector(("redo:"))
        default:
            return false
        }
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        let handled = NSApp.sendAction(action, to: nil, from: nil)
        // Text copied or cut in the panel is not a new clip: mark it as ours, as Paster does, so the monitor skips
        // it. Only when something was written, or another app's pending copy would be marked and lost.
        if [#selector(NSText.copy(_:)), #selector(NSText.cut(_:))].contains(action),
           pasteboard.changeCount != changeCount {
            let marker = NSPasteboard.PasteboardType(Config.ownMarkerType)
            pasteboard.addTypes([marker], owner: nil)
            pasteboard.setData(Data(), forType: marker)
        }
        return handled
    }
}
