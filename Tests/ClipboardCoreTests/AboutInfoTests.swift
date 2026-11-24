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

    @Test func theContributorsAreNamedInAlphabeticalOrder() {
        // The order must not say that one of them comes first.
        let names = Config.contributors.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func theAuthorIsNotNamedAgainAmongTheContributors() {
        #expect(!Config.contributors.contains(Config.author))
    }

    @Test func everyoneLinksToADifferentProfileOnGitHub() {
        let profiles = ([Config.author] + Config.contributors).map(\.profileURL.absoluteString)
        #expect(profiles.allSatisfy { $0.hasPrefix("https://github.com/") })
        #expect(Set(profiles).count == profiles.count)
    }

    @Test func theRepositoryIsTheOneTheReleasesComeFrom() {
        #expect(Config.releasesPageURL.absoluteString.hasPrefix(Config.repositoryURL.absoluteString + "/"))
    }
}
