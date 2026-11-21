import AppKit

/// The system's share menu, for the menu of a card and for the share button: shown from a view, kept while it is
/// open, and known to be open, so the panel can leave its keys alone meanwhile.
///
/// `@preconcurrency`: AppKit does not say that the picker calls its delegate on the main thread, which it does.
@MainActor
final class SharePicker: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    static let shared = SharePicker()

    private(set) var isOpen = false
    /// Kept after it closes too, until the next one: the service chosen in it is still at work.
    private var picker: NSSharingServicePicker?

    func show(_ items: [Any], from view: NSView) {
        guard !items.isEmpty else {
            return
        }
        close()
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        self.picker = picker
        isOpen = true
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func close() {
        guard isOpen else {
            return
        }
        isOpen = false
        picker?.close()
    }

    /// With a service or with none: either way the menu is gone.
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        isOpen = false
    }
}
