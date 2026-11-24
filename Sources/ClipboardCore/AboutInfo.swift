import Foundation

/// Someone who makes the app, its author or a contributor, and where to find them.
public struct Author: Equatable, Sendable {
    public let name: String
    public let profileURL: URL

    public init(name: String, profileURL: URL) {
        self.name = name
        self.profileURL = profileURL
    }
}

/// What the About pane of the settings says under the app's name.
public enum AboutInfo {
    /// `shortVersion`: the bundle's `CFBundleShortVersionString`, nil when the binary runs outside the app bundle
    /// (`swift run`). Its `CFBundleVersion` is always 1, so it is not shown.
    public static func versionText(shortVersion: String?) -> String {
        guard let shortVersion, !shortVersion.isEmpty else {
            return "Development build"
        }
        return "Version \(shortVersion)"
    }
}
