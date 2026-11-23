/// The apps nothing is copied from ("Never Copy From" in the settings), by bundle identifier.
public enum IgnoredApps {
    /// The list in use. `stored`: what was saved, nil when nothing was. Without anything saved, the apps of
    /// `Config`; a saved empty list is the user's choice and stays empty.
    public static func list(stored: [String]?) -> [String] {
        guard let stored else {
            return Config.ignoredSourceBundleIDs.sorted()
        }
        return adding(stored, to: [])
    }

    /// `list` with the `bundleIDs` it did not have.
    public static func adding(_ bundleIDs: [String], to list: [String]) -> [String] {
        var result = list
        for bundleID in bundleIDs where !result.contains(bundleID) {
            result.append(bundleID)
        }
        return result
    }

    public static func removing(_ bundleID: String, from list: [String]) -> [String] {
        list.filter { $0 != bundleID }
    }
}
