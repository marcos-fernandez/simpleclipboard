import Foundation
import Testing
@testable import ClipboardCore

struct UpdateCheckTests {
    private static func release(_ json: String, status: Int = 200) -> @Sendable () async throws -> (Data, URLResponse) {
        {
            let response = HTTPURLResponse(
                url: Config.latestReleaseAPIURL, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (Data(json.utf8), response)
        }
    }

    private static func check(current: String?, json: String, status: Int = 200) async -> UpdateCheckResult {
        await UpdateCheck.check(currentVersion: current, fetch: release(json, status: status))
    }

    // MARK: versions

    @Test func componentsCompareAsNumbersNotText() throws {
        // As text "1.10.0" < "1.9.0": a user on 1.9.0 would never hear of 1.10.0.
        #expect(try #require(AppVersion("1.10.0")) > #require(AppVersion("1.9.0")))
    }

    @Test(arguments: [("1.0", "1.0.0"), ("1", "1.0.0"), ("2.0.0.0", "2")])
    func missingComponentsCountAsZero(short: String, long: String) throws {
        // Tags and Info.plist do not always spell the same version alike; otherwise "1.0" would be older than "1.0.0".
        #expect(try #require(AppVersion(short)) == #require(AppVersion(long)))
    }

    @Test func aLongerVersionWithANonZeroTailIsNewer() throws {
        #expect(try #require(AppVersion("1.0.1")) > #require(AppVersion("1.0")))
    }

    @Test func theTagsLeadingVIsIgnored() throws {
        // Tags are v1.2.0, the bundle version (the tag minus the v) is 1.2.0: the same release.
        #expect(try #require(AppVersion("v1.2.0")) == #require(AppVersion("1.2.0")))
    }

    @Test(arguments: ["", "v", "1.2.0-beta", "1..2", "1.2.", ".1", "+1.0", "-1.0", "1.x", "vv1.0", " 1.0", "١.٢",
                      "99999999999999999999.0"])
    func garbageIsNotAVersion(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func theMenuShowsTheParsedNumbersNotTheTag() throws {
        // Leading zeros and the v are dropped: what is shown is rebuilt in our code, not text from the network.
        #expect(try #require(AppVersion("v01.2.0")).description == "1.2.0")
    }

    // MARK: checks

    @Test func aNewerReleaseIsReported() async throws {
        #expect(await Self.check(current: "1.0.0", json: #"{"tag_name": "v1.2.0"}"#)
            == .available(try #require(AppVersion("1.2.0"))))
    }

    @Test func theSameReleaseIsNotAnUpdate() async {
        // The release's own build must not nag about itself, however the two versions are spelled.
        #expect(await Self.check(current: "1.0", json: #"{"tag_name": "v1.0.0"}"#) == .upToDate)
    }

    @Test func anOlderReleaseIsNotAnUpdate() async {
        // A build from a newer tag than the latest release (e.g. before its release is published) is up to date.
        #expect(await Self.check(current: "1.3.0", json: #"{"tag_name": "v1.2.0"}"#) == .upToDate)
    }

    @Test func otherFieldsOfTheReleaseAreIgnored() async throws {
        #expect(await Self.check(
            current: "1.9.0",
            json: #"{"tag_name": "v1.10.0", "html_url": "https://example.com", "assets": [], "draft": false}"#
        ) == .available(try #require(AppVersion("1.10.0"))))
    }

    @Test(arguments: [
        "not json",
        "{}",
        #"{"name": "v2.0.0"}"#,
        #"{"tag_name": 2}"#,
        #"{"tag_name": "latest"}"#,
        #"{"tag_name": "v2.0.0-rc1"}"#,
        #"[{"tag_name": "v2.0.0"}]"#,
    ])
    func anUnusableAnswerIsAFailureNotUpToDate(json: String) async {
        // A failure keeps an update already found on show; "up to date" would hide it.
        #expect(await Self.check(current: "1.0.0", json: json) == .failed)
    }

    @Test(arguments: [403, 404, 500, 304])
    func aNon200AnswerIsAFailureEvenWithAReleaseInIt(status: Int) async {
        // A rate limit or error page is not GitHub's latest release, whatever its body says.
        #expect(await Self.check(current: "1.0.0", json: #"{"tag_name": "v2.0.0"}"#, status: status) == .failed)
    }

    @Test func aFetchThatThrowsIsAFailure() async {
        let result = await UpdateCheck.check(currentVersion: "1.0.0") {
            throw URLError(.notConnectedToInternet)
        }
        #expect(result == .failed)
    }

    @Test(arguments: [nil, "", "1.0 (dev)"] as [String?])
    func anUnknownRunningVersionNeverReportsAnUpdate(current: String?) async {
        // A build without a usable version (e.g. run straight from `swift build`) cannot tell whether it is older.
        #expect(await Self.check(current: current, json: #"{"tag_name": "v99.0.0"}"#) == .failed)
    }

    // MARK: what the menu shows

    @Test func aFailedCheckKeepsAnUpdateAlreadyFound() throws {
        // Going offline for a day must not make the update item come and go.
        let shown = try #require(AppVersion("1.2.0"))
        #expect(UpdateCheckResult.failed.availableUpdate(replacing: shown) == shown)
        #expect(UpdateCheckResult.failed.availableUpdate(replacing: nil) == nil)
    }

    @Test func anUpToDateCheckClearsTheUpdate() throws {
        // E.g. the release was withdrawn: the menu and icon go back to how they are without an update.
        let shown = try #require(AppVersion("1.2.0"))
        #expect(UpdateCheckResult.upToDate.availableUpdate(replacing: shown) == nil)
    }

    @Test func aNewerReleaseReplacesTheOneShown() throws {
        let newer = try #require(AppVersion("1.3.0"))
        #expect(UpdateCheckResult.available(newer).availableUpdate(replacing: AppVersion("1.2.0")) == newer)
    }

    // The app looks every hour because timers stand still during sleep; this is what keeps those looks from
    // becoming a request to GitHub every hour, while a check that got no answer is retried at the next look.
    @Test func aCheckIsDueOnlyADayAfterTheLastAnswer() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateCheck.isDue(lastAnswer: nil, now: now))
        #expect(!UpdateCheck.isDue(lastAnswer: now.addingTimeInterval(-Config.updateCheckPollInterval), now: now))
        #expect(!UpdateCheck.isDue(lastAnswer: now.addingTimeInterval(-Config.updateCheckInterval + 1), now: now))
        #expect(UpdateCheck.isDue(lastAnswer: now.addingTimeInterval(-Config.updateCheckInterval), now: now))
    }

    @Test func theSessionKeepsNothingBetweenChecks() {
        // The app's only network request: no cookies or cached answers that could identify or follow the user.
        let configuration = UpdateCheck.makeSession().configuration
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForResource == Config.updateCheckTimeout)
    }

    @Test func nothingIsSaidOfACheckNobodyAskedFor() {
        #expect(ManualUpdateCheck.notAsked.text == nil)
    }

    @Test(arguments: [UpdateCheckResult.upToDate, .failed])
    func aCheckTheUserAskedForAlwaysEndsInAnAnswerOnShow(result: UpdateCheckResult) {
        // The daily check is silent when there is nothing new or it fails; after a click, silence would read as
        // the button doing nothing.
        #expect(ManualUpdateCheck.checking.text != nil)
        #expect(ManualUpdateCheck.answered(result).text != nil)
    }

    @Test func beingUpToDateAndAFailedCheckDoNotReadTheSame() {
        // A check that failed says nothing about whether there is an update.
        #expect(ManualUpdateCheck.answered(.upToDate).text != ManualUpdateCheck.answered(.failed).text)
    }

    @Test func theUpdateFoundIsNamedByItsVersion() throws {
        let version = try #require(AppVersion("v1.17.0"))
        #expect(ManualUpdateCheck.answered(.available(version)).text?.contains("1.17.0") == true)
    }
}
