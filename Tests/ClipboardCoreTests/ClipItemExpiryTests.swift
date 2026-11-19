import Foundation
import Testing
@testable import ClipboardCore

/// The purge timer only runs every 30 s: the panel checks expiry itself so an expired password is neither listed
/// nor pasted in between. The boundary must match the store's purge.
struct ClipItemExpiryTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func item(expiresAt: Date?) -> ClipItem {
        ClipItem(
            createdAt: now.addingTimeInterval(-60), kind: .text, text: "secret", imageFileName: nil,
            contentHash: "h", source: SourceApp(bundleID: nil, name: nil),
            isConcealed: expiresAt != nil, expiresAt: expiresAt
        )
    }

    @Test func itemWithoutExpiryNeverExpires() {
        #expect(!item(expiresAt: nil).isExpired(at: now))
    }

    @Test func concealedItemIsAliveBeforeItsExpiry() {
        #expect(!item(expiresAt: now.addingTimeInterval(1)).isExpired(at: now))
    }

    @Test func concealedItemIsExpiredAtItsExpiryLikeThePurge() {
        #expect(item(expiresAt: now).isExpired(at: now))
        #expect(item(expiresAt: now.addingTimeInterval(-1)).isExpired(at: now))
    }
}
