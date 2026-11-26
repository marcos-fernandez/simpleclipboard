import AppKit
import ClipboardCore
import SwiftUI

/// The menu of a card of the history: what the keyboard does to the selected one, for any card and by name.
@MainActor
enum CardMenu {
    /// Of the dot of a tag as the image of its menu item, which a menu draws smaller than text.
    private static let dotSize: CGFloat = 10

    /// `card`: the view of the card, which the share menu comes out of. `shareItems`: what the card shares, asked
    /// when "Share…" is chosen and not before, since an image is read whole from the disk; nil for a card with
    /// nothing to share (one from a secured app, an image whose file is gone).
    static func menu(
        card: NSView,
        item: ClipItem,
        tags: [Tag],
        onDelete: @escaping () -> Void,
        onNewTag: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onSetTag: @escaping (UUID?) -> Void,
        shareItems: (() -> [Any])?
    ) -> NSMenu {
        let delete = ActionMenuItem(title: "Delete", handler: onDelete)
        let menu = NSMenu()
        let removeTag = ActionMenuItem(title: "Remove Tag") {
            onSetTag(nil)
        }
        let rename = ActionMenuItem(title: "Rename…", handler: onRename)
        let tag = NSMenuItem(title: "Tag", action: nil, keyEquivalent: "")
        let tagMenu = NSMenu()

        // Shown, not taken: the menu is not there when the key is pressed, the panel handles it.
        delete.keyEquivalent = "\u{8}"
        delete.keyEquivalentModifierMask = .command
        for existing in tags {
            let entry = ActionMenuItem(title: existing.name) {
                onSetTag(existing.id)
            }
            entry.image = dot(TagPalette.color(existing.colorIndex))
            entry.state = existing.id == item.tagID
                ? .on
                : .off
            tagMenu.addItem(entry)
        }
        if !tags.isEmpty {
            tagMenu.addItem(.separator())
        }
        tagMenu.addItem(ActionMenuItem(title: "New Tag…", handler: onNewTag))
        tag.submenu = tagMenu
        // What is copied from a secured app is never tagged.
        tag.isEnabled = !item.isConcealed
        removeTag.isEnabled = !item.isConcealed && item.tagID != nil
        // What is copied from a secured app is never named either.
        rename.isEnabled = !item.isConcealed

        // Manual enabling: with auto-enabling, AppKit would re-enable the items, which all have a target.
        menu.autoenablesItems = false
        menu.addItem(tag)
        menu.addItem(removeTag)
        menu.addItem(.separator())
        menu.addItem(rename)
        menu.addItem(.separator())
        // The system's share menu comes out of the card once this menu has closed, as it comes out of the share
        // button: the system's ready-made share item does nothing in a menu of this panel.
        if let shareItems {
            menu.addItem(ActionMenuItem(title: "Share…") { [weak card] in
                if let card {
                    SharePicker.shared.show(shareItems(), from: card)
                }
            })
            menu.addItem(.separator())
        }
        menu.addItem(delete)
        return menu
    }

    /// The dot of a tag before its name, as an image: a menu item takes no view.
    private static func dot(_ color: Color) -> NSImage {
        NSImage(size: NSSize(width: dotSize, height: dotSize), flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
