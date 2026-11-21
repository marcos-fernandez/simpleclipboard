/// Whether the app's item is in the menu bar. With it hidden, its menu opens from a wrench next to the search field
/// of the history.
public enum MenuBarIcon {
    /// `stored`: the saved setting, missing until the user changes it, when the item is shown as before the setting
    /// existed. `hotkeyRegistered`: whether ⇧⌘V opens the history. Without it the item is shown whatever the
    /// setting: it is then the only way into the app.
    public static func isShown(stored: Bool?, hotkeyRegistered: Bool) -> Bool {
        (stored ?? true) || !hotkeyRegistered
    }
}
