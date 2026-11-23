import Foundation
import Testing
@testable import ClipboardCore

struct PauseTests {
    private let end = Date(timeIntervalSince1970: 1_000_000)

    @Test func withoutAnEndThereIsNoPause() {
        #expect(!Pause.isActive(until: nil, now: end))
    }

    @Test func thePauseLastsUntilItsEnd() {
        #expect(Pause.isActive(until: end, now: end.addingTimeInterval(-1)))
        #expect(!Pause.isActive(until: end, now: end))
        #expect(!Pause.isActive(until: end, now: end.addingTimeInterval(1)))
    }

    @Test func anEndFurtherAwayThanTheLongestPauseIsNoPause() {
        let longest = 8.0 * 60 * 60
        #expect(Pause.isActive(until: end, now: end.addingTimeInterval(-longest)))
        #expect(!Pause.isActive(until: end, now: end.addingTimeInterval(-longest - 1)))
    }

    @Test func theDurationsGoFromShortestToLongest() {
        #expect(Pause.durations == Pause.durations.sorted())
    }

    @Test func aDurationIsNamedInMinutesOrInHours() {
        #expect(Pause.durations.map(Pause.title(of:)) == [
            "For 5 Minutes", "For 15 Minutes", "For 30 Minutes", "For 1 Hour", "For 4 Hours", "For 8 Hours",
        ])
    }
}
