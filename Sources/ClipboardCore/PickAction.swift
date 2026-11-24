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

    /// What the welcome of the first launch starts on. A new install starts on copying, which needs no permission.
    /// One that ran before and is asked all the same (it came from the old app name, its login item was never
    /// registered) starts on what it was doing, chosen or not: the welcome must not change it unnoticed.
    public static func atWelcome(isNewInstall: Bool, stored: String?) -> PickAction {
        isNewInstall
            ? .copyToClipboard
            : PickAction(stored: stored)
    }
}
