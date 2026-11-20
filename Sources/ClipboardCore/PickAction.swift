/// What happens when an item is picked from the history.
public enum PickAction: String, Sendable {
    /// The item is pasted into the app the user was in; needs the Accessibility permission.
    case pasteDirectly
    /// The item is left on the pasteboard for the user to paste.
    case copyToClipboard

    /// `stored`: the saved setting. Missing or unknown, it is `pasteDirectly`: what the app did before the setting
    /// existed.
    public init(stored: String?) {
        self = stored.flatMap(PickAction.init(rawValue:)) ?? .pasteDirectly
    }
}
