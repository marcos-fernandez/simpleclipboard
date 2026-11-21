import AppKit
import SwiftUI

/// A context menu built in AppKit, laid over the view it belongs to. A SwiftUI context menu takes items with a name
/// and little else: no row of colour dots, no dot before the name of a tag, no mark on the one in use.
struct AppKitContextMenu: NSViewRepresentable {
    /// Called each time the menu is about to open, so it shows what is true then. It is given the view the menu
    /// opens from: what an item shows next (the system's share menu) needs a view to come out of.
    let build: (NSView) -> NSMenu

    func makeNSView(context: Context) -> MenuView {
        let view = MenuView()
        view.build = build
        return view
    }

    func updateNSView(_ view: MenuView, context: Context) {
        view.build = build
    }

    /// It takes only the clicks that open a menu; the others go through to the view under it.
    final class MenuView: NSView {
        var build: ((NSView) -> NSMenu)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else {
                return nil
            }
            let opensMenu = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return opensMenu
                ? super.hitTest(point)
                : nil
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = build?(self)
            // Only what the app puts in it: the system adds items of its own to a context menu otherwise.
            menu?.allowsContextMenuPlugIns = false
            return menu
        }
    }
}

/// A menu item that runs a closure: these menus are rebuilt each time they open and have no object to send an action
/// to.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func run() {
        handler()
    }
}
