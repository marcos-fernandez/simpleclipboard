import Testing
@testable import ClipboardCore

/// A secured app that the user also ignores is hidden among the secured ones, not lost: saving what the list shows
/// in place of what it holds would drop it, and its copies would be recorded in the open once it is no longer
/// ignored.
struct PrivacyListsTests {
    /// "com.both" is secured and ignored: it shows as ignored only.
    private let lists = PrivacyLists(ignored: ["com.both", "com.ignored"], secured: ["com.both", "com.secured"])

    @Test func anIgnoredAppIsNotShownAmongTheSecuredOnes() {
        #expect(lists.shown(.ignored) == ["com.both", "com.ignored"])
        #expect(lists.shown(.secured) == ["com.secured"])
    }

    @Test func addingASecuredAppKeepsTheHiddenOnes() {
        let addition = lists.adding(["com.new"], to: .secured)
        #expect(addition == AppList.Addition(list: ["com.both", "com.secured", "com.new"], refused: []))
    }

    @Test func removingASecuredAppKeepsTheHiddenOnes() {
        #expect(lists.removing("com.secured", from: .secured) == ["com.both"])
    }

    @Test func anAppNoLongerIgnoredIsSecuredAgain() {
        let after = PrivacyLists(ignored: lists.removing("com.both", from: .ignored), secured: lists.secured)
        #expect(after.shown(.secured) == ["com.both", "com.secured"])
    }

    @Test func aSecuredAppCanBeIgnoredAndIsHiddenFromThenOn() {
        let addition = lists.adding(["com.secured"], to: .ignored)
        #expect(addition == AppList.Addition(list: ["com.both", "com.ignored", "com.secured"], refused: []))
        let after = PrivacyLists(ignored: addition.list ?? [], secured: lists.secured)
        #expect(after.shown(.secured) == [])
        #expect(after.secured == ["com.both", "com.secured"])
    }

    @Test func anIgnoredAppIsRefusedAmongTheSecuredOnes() {
        let addition = lists.adding(["com.ignored", "com.both"], to: .secured)
        #expect(addition == AppList.Addition(list: nil, refused: ["com.ignored", "com.both"]))
    }
}
