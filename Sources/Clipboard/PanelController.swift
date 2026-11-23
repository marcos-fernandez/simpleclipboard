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
    /// Whether there is a search: text of only blanks is none (see `SearchKeys.isSearch`).
    var hasSearch: Bool {
        SearchKeys.isSearch(query)
    }
    /// Selection follows the item, not its position, so new copies or purges don't shift it.
    /// nil means "first result".
    var selectedID: UUID?
    /// Whether the search field had the keyboard when an overlay took it, to give it back when the overlay closes.
    var hadSearchFocusBeforeOverlay = false
    /// Whether the search field has the keyboard. Written by the view; the panel reads it to tell a key that is
    /// typed into the field from one that has to be taken there.
    var isSearchFocused = false
    /// Incremented on every show: the view takes the keyboard out of the search field and the strip goes back to its
    /// first card.
    var showRequest = 0
    /// Active tab. Back to .history when the panel opens after a card was picked.
    var scope: HistoryStore.Scope = .history

    /// Set on every show, from the screen the strip opens on.
    var cardWidth = PanelMetrics.minCardWidth
    /// How many cards fit in view, and how many of them, from the first in view, show a shortcut (see
    /// `CardShortcuts`).
    var cardCount = 1
    var cardShortcutCount = 0
    /// The first card in view: written by the strip as it scrolls, and set to scroll it. nil while the strip has
    /// never been moved, which leaves it at its first card.
    var leadingCardID: UUID?

    /// The position in `results` of the first card in view. nil when that card is no longer there (expired, purged,
    /// deleted from another Mac): the strip stays where it was, so counting from any other card would put the
    /// shortcuts on cards that are off the screen.
    func leadingIndex(in results: [ClipItem]) -> Int? {
        guard let leadingCardID else {
            return results.isEmpty
                ? nil
                : 0
        }
        return results.firstIndex { $0.id == leadingCardID }
    }

    /// Scrolls the strip so that the card at `index` is the first in view, or the nearest one that can be: the
    /// strip keeps the id it is given even when it cannot bring that card to its edge.
    func showFirst(_ index: Int, of results: [ClipItem]) {
        guard !results.isEmpty else {
            leadingCardID = nil
            return
        }
        let reachable = StripLayout.reachableLeadingCard(index, itemCount: results.count, cardCount: cardCount)
        leadingCardID = results[reachable].id
    }

    /// Whether a card that is still drawn has expired. `results(in:)` leaves expired items out, but the strip only
    /// draws again when something it observes changes, and the passing of time is not one of those things.
    func hasExpiredCard(in store: HistoryStore) -> Bool {
        let now = Date()
        return store.search(query, in: effectiveScope(in: store)).contains { $0.isExpired(at: now) }
    }

    /// Falls back to the history tab if the active tag was deleted.
    /// Expired items are left out: the store only purges them every 30 s.
    func results(in store: HistoryStore) -> [ClipItem] {
        let now = Date()
        return store.search(query, in: effectiveScope(in: store)).filter { !$0.isExpired(at: now) }
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

    /// The colour chosen for the tag being created: the next of the row when its overlay opens.
    var newTagColorIndex = 0
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
            newTagColorIndex = TagColors.indexForNewTag(tagCount: store.tags.count)
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
            guard let tag = store.createTag(name: promptText, colorIndex: newTagColorIndex) else {
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
    /// The digit of each key of the number row. By key and not by character, unlike ⌘T below: the digits keep
    /// their place on every layout, and on AZERTY those keys type "&", "é"… unless ⇧ is held.
    private static let digitsByKeyCode = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
    ]
    private static let margin: CGFloat = 8

    private let store: HistoryStore
    private let state = PanelState()
    private let panel: KeyablePanel
    private let onPick: (ClipItem, NSRunningApplication?) -> Void
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    /// Whether the next show starts with no search and on the History tab: the first one, and each one after a card
    /// was picked. A panel that closed without a pick (a click outside, Esc, the hotkey again) opens as it was left,
    /// so a search is not lost to it.
    private var startsClean = true

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
            rootView: HistoryView(
                store: store,
                state: state,
                onDelete: { [weak self] item in
                    self?.delete(item)
                },
                onPick: { [weak self] item in
                    self?.pick(item)
                },
                onRestoreSearchFocus: { [weak self] in
                    self?.focusSearchField(selectingText: false)
                }
            )
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
        if frontApp?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = frontApp
        } else {
            // While we are the frontmost app (an alert, the settings window) there is no app to paste into: the one
            // recorded on an earlier show would receive the paste unseen. The item is only copied.
            previousApp = nil
        }
        // The strip opens with nothing expired in the store, so that `redrawIfAnyCardExpired` only finds what
        // expires while it is open.
        store.purgeExpired()
        if startsClean {
            state.query = ""
            state.scope = .history
            startsClean = false
        }
        // Blanks left in the field are no search to go on with.
        if !state.hasSearch {
            state.query = ""
        }
        state.selectedID = nil
        // Before the overlay goes: the view gives the keyboard back to the field when one closes, and a panel that
        // was hidden with one open would do it now.
        state.hadSearchFocusBeforeOverlay = false
        state.overlay = nil
        ThumbnailCache.forgetMisses()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            return
        }
        let stripWidth = visible.width - 2 * Self.margin
        let layout = StripLayout(
            width: PanelMetrics.cardRowWidth(stripWidth: stripWidth),
            minCardWidth: PanelMetrics.minCardWidth,
            spacing: PanelMetrics.cardSpacing,
            maxCardCount: CardShortcuts.digits.count
        )
        state.cardCount = layout.cardCount
        state.cardWidth = layout.cardWidth
        state.cardShortcutCount = CardShortcuts.count(cardsThatFit: layout.cardCount)
        // Here and not only when the view draws again: a ⌘ digit typed right after the hotkey is handled before
        // that, and would count from the card left first in view the last time.
        state.showFirst(0, of: state.results(in: store))
        panel.setFrame(
            NSRect(
                x: visible.minX + Self.margin,
                y: visible.minY + Self.margin,
                width: stripWidth,
                height: PanelMetrics.stripHeight
            ),
            display: true
        )
        panel.makeKeyAndOrderFront(nil)
        // The keyboard starts on the cards: a window gives it to its first field when it becomes key. With a search
        // kept from before it starts in the field, after its text, to go on with it. Decided here and nowhere
        // else: the view follows what the window does.
        panel.makeFirstResponder(nil)
        state.isSearchFocused = false
        state.showRequest += 1
        if state.hasSearch {
            focusSearchField(selectingText: false)
        }
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        SharePicker.shared.close()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func pick(_ item: ClipItem) {
        // The card may have expired while the panel was open, without a re-render to hide it.
        guard !item.isExpired(at: Date()) else {
            return
        }
        let target = previousApp
        startsClean = true
        hide()
        onPick(item, target)
    }

    /// From the menu of a card, which may not be the selected one.
    private func delete(_ item: ClipItem) {
        let results = state.results(in: store)
        guard let index = results.firstIndex(where: { $0.id == item.id }) else {
            // The card has expired and is still drawn: purging takes it away, which is what was asked for.
            store.purgeExpired()
            return
        }
        remove(at: index, of: results)
    }

    private func remove(at index: Int, of results: [ClipItem]) {
        let wasSelected = state.selectedIndex(in: results) == index
        store.remove(id: results[index].id)
        // The list already in hand minus the removed item, instead of searching again.
        var remaining = results
        remaining.remove(at: index)
        // The card that takes its place becomes the first in view: the removed one would leave the cards without
        // shortcuts until the strip is drawn again.
        if state.leadingCardID == results[index].id {
            state.showFirst(index, of: remaining)
        }
        // The selection moves to the card that took the place only when the removed one had it.
        if wasSelected {
            state.selectedID = remaining.isEmpty
                ? nil
                : remaining[min(index, remaining.count - 1)].id
        }
    }

    /// Puts the keyboard in the search field. `selectingText`: with its text selected, as any field that is entered,
    /// or with the cursor after it. Straight to the AppKit field under the SwiftUI one, and not through the view:
    /// the key that brought the keyboard here is then typed into the field, through an input method too.
    private func focusSearchField(selectingText: Bool = true) {
        guard let field = panel.contentView.flatMap(Self.firstTextField(in:)), panel.makeFirstResponder(field) else {
            return
        }
        if !selectingText {
            field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        }
        state.isSearchFocused = true
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) {
                return field
            }
        }
        return nil
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
        // The share menu hangs from the panel and takes no keys of its own: the first one closes it and does
        // nothing else, so that Esc does not clear the search behind it nor Return paste a card.
        if SharePicker.shared.isOpen {
            SharePicker.shared.close()
            return true
        }
        // While an input method is composing (e.g. Japanese), Return confirms a candidate and arrows move within it.
        if let input = panel.firstResponder as? NSTextInputClient, input.hasMarkedText() {
            return false
        }
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
            if let digit = Self.digitsByKeyCode[Int(event.keyCode)],
               let position = CardShortcuts.position(digit: digit) {
                let results = state.results(in: store)
                // Counted from the first card in view, and only the cards that show the shortcut: the others are
                // off the screen. The key of a digit that has a shortcut is taken either way, so one with no card
                // does not reach the search field.
                if !redrawIfAnyCardExpired(), position < state.cardShortcutCount,
                   let leading = state.leadingIndex(in: results), results.indices.contains(leading + position) {
                    pick(results[leading + position])
                }
                return true
            }
            // By character, like the edit shortcuts: on Dvorak the key at kVK_ANSI_T does not type "t". A layout
            // with no Latin letters (Russian, Greek) types no "t" at all, so there the physical key still counts.
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let isLatin = key.unicodeScalars.allSatisfy(\.isASCII)
            if key == "t" || (!isLatin && Int(event.keyCode) == kVK_ANSI_T) {
                if !redrawIfAnyCardExpired() {
                    openTagPicker()
                }
                return true
            }
            if key == "f" || (!isLatin && Int(event.keyCode) == kVK_ANSI_F) {
                focusSearchField()
                return true
            }
        }
        // The keyboard is on the cards until it is asked for, but typing is still searching: the key goes to the
        // field. Not with ⌘ or ⌃, which are shortcuts, and never the keys handled below.
        if !state.isSearchFocused, modifiers.isDisjoint(with: [.command, .control]),
           SearchKeys.typesText(event.characters) {
            focusSearchField()
            return false
        }
        let results = state.results(in: store)
        let index = state.selectedIndex(in: results)
        switch Int(event.keyCode) {
        case kVK_Escape:
            // With a search, the first Esc is for it: closing would keep the text for the next time the history
            // opens, and the way out of a search would be to delete it by hand.
            if state.hasSearch {
                state.query = ""
            } else {
                hide()
            }
        case kVK_LeftArrow:
            if index > 0 {
                state.selectedID = results[index - 1].id
            }
        case kVK_RightArrow:
            if index + 1 < results.count {
                state.selectedID = results[index + 1].id
            }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if !redrawIfAnyCardExpired(), results.indices.contains(index) {
                pick(results[index])
            }
        case kVK_Delete where event.modifierFlags.contains(.command):
            if !redrawIfAnyCardExpired(), results.indices.contains(index) {
                remove(at: index, of: results)
            }
        default:
            // Paste, select all and undo are for the search field, and with the keyboard on the cards they would
            // go to nobody: the keyboard is taken there first, after its text.
            if !state.isSearchFocused, modifiers.subtracting(.shift) == .command,
               SearchKeys.isEditShortcutOfTheField(event.charactersIgnoringModifiers) {
                focusSearchField(selectingText: false)
            }
            return sendEditShortcut(event)
        }
        return true
    }

    /// Called before a key acts on a card by its position. With an expired card still drawn (see
    /// `PanelState.hasExpiredCard`) the key would act on the neighbour of the card it shows: this purges instead,
    /// which draws the strip again, and returns true, so the key does nothing this time.
    private func redrawIfAnyCardExpired() -> Bool {
        guard state.hasExpiredCard(in: store) else {
            return false
        }
        store.purgeExpired()
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
        // As in `show()`: before a ⌘ digit typed right after the tab switch.
        state.showFirst(0, of: state.results(in: store))
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
