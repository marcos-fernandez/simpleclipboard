/// The two lists of the Privacy settings together, as they are saved, and what comes of changing one. Ignored wins
/// over secured: a secured app that is also ignored shows as ignored only, and stays in what the secured list
/// holds, so it is secured again once it is no longer ignored. Hence what a list shows and what is saved for it
/// are not the same, and which of the two a change starts from is decided here.
public struct PrivacyLists: Equatable, Sendable {
    public enum Kind: CaseIterable, Sendable {
        case ignored
        case secured
    }

    /// What each list holds, whole: for the secured one, with the apps that the ignored one hides.
    public let ignored: [String]
    public let secured: [String]

    public init(ignored: [String], secured: [String]) {
        self.ignored = ignored
        self.secured = secured
    }

    /// The apps a list shows and acts on.
    public func shown(_ kind: Kind) -> [String] {
        switch kind {
        case .ignored:
            return ignored
        case .secured:
            return AppList.excluding(ignored, from: secured)
        }
    }

    /// What comes of adding `bundleIDs` to a list: the whole list to save, hidden apps included. An app goes into
    /// the ignored ones whatever the secured list holds, and is hidden there from then on; the other way round
    /// would add an app nobody sees, so it is refused.
    public func adding(_ bundleIDs: [String], to kind: Kind) -> AppList.Addition {
        switch kind {
        case .ignored:
            return AppList.addition(of: bundleIDs, to: ignored, other: [])
        case .secured:
            return AppList.addition(of: bundleIDs, to: secured, other: ignored)
        }
    }

    /// The whole list to save once `bundleID` is taken out of it, hidden apps included.
    public func removing(_ bundleID: String, from kind: Kind) -> [String] {
        switch kind {
        case .ignored:
            return AppList.removing(bundleID, from: ignored)
        case .secured:
            return AppList.removing(bundleID, from: secured)
        }
    }
}
