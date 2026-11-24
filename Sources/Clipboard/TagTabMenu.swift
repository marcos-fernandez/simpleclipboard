import AppKit
import ClipboardCore
import SwiftUI

/// The menu of a tag's tab: its name, its colour from a row of dots as the tags of Finder have, and its end.
@MainActor
enum TagTabMenu {
    static func menu(
        colorIndex: Int,
        onDelete: @escaping () -> Void,
        onRecolor: @escaping (Int) -> Void,
        onRename: @escaping () -> Void
    ) -> NSMenu {
        let colors = NSMenuItem()
        let menu = NSMenu()
        let row = NSHostingView(
            rootView: TagColorRow(selected: colorIndex, inset: TagColorRow.menuInset) { [weak menu] index in
                onRecolor(index)
                menu?.cancelTracking()
            }
        )

        row.frame.size = row.fittingSize
        colors.view = row
        menu.addItem(ActionMenuItem(title: "Rename Tag…", handler: onRename))
        menu.addItem(colors)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Delete Tag…", handler: onDelete))
        return menu
    }
}
