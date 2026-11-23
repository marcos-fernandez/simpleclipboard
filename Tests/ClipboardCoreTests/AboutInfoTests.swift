import Testing
@testable import ClipboardCore

/// The About pane is where a user reads which version to mention in a bug report.
struct AboutInfoTests {
    @Test func theBundleVersionIsShown() {
        #expect(AboutInfo.versionText(shortVersion: "1.4.2") == "Version 1.4.2")
    }

    @Test func aBinaryOutsideTheAppBundleSaysItIsADevelopmentBuild() {
        // `swift run` has no Info.plist: no version rather than an invented one.
        #expect(AboutInfo.versionText(shortVersion: nil) == "Development build")
        #expect(AboutInfo.versionText(shortVersion: "") == "Development build")
    }

    @Test func theRepositoryIsTheOneTheReleasesComeFrom() {
        #expect(Config.releasesPageURL.absoluteString.hasPrefix(Config.repositoryURL.absoluteString + "/"))
    }
}
