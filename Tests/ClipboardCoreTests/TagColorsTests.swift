import Testing
@testable import ClipboardCore

struct TagColorsTests {
    @Test func everyColourIsOfferedOnce() {
        // A number missing from the order is a colour nobody can choose; one repeated shows twice.
        #expect(TagColors.order.sorted() == Array(0..<Config.tagColorCount))
    }

    @Test func newTagsTakeTheColoursInTheOrderShownAndStartAgain() {
        let indices = (0..<(TagColors.order.count + 2)).map { TagColors.indexForNewTag(tagCount: $0) }
        #expect(indices == TagColors.order + TagColors.order.prefix(2))
    }
}
