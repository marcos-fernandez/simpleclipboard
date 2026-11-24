import AppKit
import SwiftUI

/// The system's share menu, opened from a button. In AppKit: the menu is shown from the view it belongs to.
struct ShareButton: NSViewRepresentable {
    let isEnabled: Bool
    /// What to share, asked when the button is pressed.
    let items: () -> [Any]

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share") ?? NSImage(),
            target: context.coordinator,
            action: #selector(Coordinator.share(_:))
        )
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.isEnabled = isEnabled
        button.toolTip = "Share"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.isEnabled = isEnabled
        context.coordinator.items = items
    }

    @MainActor
    final class Coordinator: NSObject {
        var items: () -> [Any]

        init(items: @escaping () -> [Any]) {
            self.items = items
        }

        @objc func share(_ sender: NSButton) {
            SharePicker.shared.show(items(), from: sender)
        }
    }
}
