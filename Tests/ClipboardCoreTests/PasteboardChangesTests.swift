import Testing
@testable import ClipboardCore

/// The promise of a pause: what is copied meanwhile is not kept, then or later.
struct PasteboardChangesTests {
    @Test func whatThePasteboardHeldAtTheStartIsNotRead() {
        var changes = PasteboardChanges(changeCount: 7)
        #expect(!changes.hasCopyToRead(changeCount: 7) { false })
    }

    @Test func aChangeIsReadOnce() {
        var changes = PasteboardChanges(changeCount: 7)
        #expect(changes.hasCopyToRead(changeCount: 8) { false })
        #expect(!changes.hasCopyToRead(changeCount: 8) { false })
    }

    @Test func aCopyMadeWhilePausedIsNotReadWhenThePauseEnds() {
        var changes = PasteboardChanges(changeCount: 7)
        #expect(!changes.hasCopyToRead(changeCount: 8) { true })
        // The pause is over and the pasteboard still holds that copy.
        #expect(!changes.hasCopyToRead(changeCount: 8) { false })
        // The next copy is read as any other.
        #expect(changes.hasCopyToRead(changeCount: 9) { false })
    }

    @Test func thePauseIsOnlyAskedAboutAChange() {
        var asked = 0
        var changes = PasteboardChanges(changeCount: 7)
        _ = changes.hasCopyToRead(changeCount: 7) {
            asked += 1
            return false
        }
        #expect(asked == 0)
    }
}
