import AppKit
import SwiftUI

/// The system's radio button. SwiftUI only has it inside a radio group, which lays its buttons out by itself.
struct RadioButton: NSViewRepresentable {
    let title: String
    let isOn: Bool
    let action: () -> Void

    /// From the leading edge of the button to its title: what lines something up with the title.
    @MainActor static let titleInset: CGFloat = {
        let button = NSButton(radioButtonWithTitle: " ", target: nil, action: nil)

        button.sizeToFit()
        return button.cell?.titleRect(forBounds: button.bounds).minX ?? 0
    }()

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void = {}
        var isOn = false

        @objc func clicked(_ sender: NSButton) {
            // A click turns the button on by itself. What it shows is what is chosen, which the click may not
            // change: back to it, and the view is updated if it does.
            sender.state = isOn ? .on : .off
            action()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSButton {
        NSButton(radioButtonWithTitle: title, target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.isOn = isOn
        button.state = isOn ? .on : .off
        button.title = title
    }
}
