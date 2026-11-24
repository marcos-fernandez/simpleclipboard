/// A list of apps of the Privacy settings ("Ignored Apps", "Secured Apps"), by bundle identifier.
public enum AppList {
    /// The list in use. `stored`: what was saved, nil when nothing was. Without anything saved, `defaults`; a saved
    /// empty list is the user's choice and stays empty.
    public static func list(stored: [String]?, defaults: Set<String>) -> [String] {
        guard let stored else {
            return defaults.sorted()
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

    /// What comes of adding `bundleIDs` to `list` while `other` is the other list.
    public struct Addition: Equatable {
        /// The list to save; nil when nothing was added. Saving it anyway would stop the list following its defaults.
        public let list: [String]?
        /// The apps that `other` has: an app is in one list only, so they are not added.
        public let refused: [String]
    }

    public static func addition(of bundleIDs: [String], to list: [String], other: [String]) -> Addition {
        let refused = adding(bundleIDs.filter(other.contains), to: [])
        let added = adding(bundleIDs.filter { !other.contains($0) }, to: list)
        return Addition(
            list: added == list
                ? nil
                : added,
            refused: refused
        )
    }

    /// `list` without the apps of `other`. For a list read from its defaults while the other one was saved by the
    /// user: an app must not show in both.
    public static func excluding(_ other: [String], from list: [String]) -> [String] {
        list.filter { !other.contains($0) }
    }

    public static func removing(_ bundleID: String, from list: [String]) -> [String] {
        list.filter { $0 != bundleID }
    }
}
