/// Which symbol the menu-bar item shows.
public enum StatusIcon {
    public static let plainSymbol = "doc.on.clipboard"
    /// There is no clipboard with an arrow down among the system's symbols: a document with one is the nearest.
    static let downloadingSymbol = "arrow.down.doc"
    static let updateSymbol = "arrow.up.doc.on.clipboard"

    /// A download under way wins over the notice of the update it comes from: the arrow turns down, so the icon
    /// says that choosing the update started something.
    public static func symbol(hasUpdate: Bool, isDownloading: Bool) -> String {
        if isDownloading {
            return downloadingSymbol
        }
        return hasUpdate
            ? updateSymbol
            : plainSymbol
    }
}
