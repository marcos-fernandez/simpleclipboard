/// Whether the app's item is in the menu bar. Shown or hidden, its menu also opens from the button at the start of
/// the search row of the history.
public enum MenuBarIcon {
    /// The "Show in Menu Bar" setting. `stored`: the saved value, missing until the user changes it, when the item is
    /// shown as before the setting existed.
    public static func isOn(stored: Bool?) -> Bool {
        stored ?? true
    }

    /// `stored`: as in `isOn(stored:)`. `hotkeyRegistered`: whether ⇧⌘V could be registered. Without it the item is
    /// shown whatever the setting: nothing else would open the history.
    public static func isShown(stored: Bool?, hotkeyRegistered: Bool) -> Bool {
        isOn(stored: stored) || !hotkeyRegistered
    }
}
