import Foundation
import Testing
@testable import ClipboardCore

/// Office apps put both text and an image of it on the pasteboard: the text must win, or text copies would turn
/// into pictures. Only text the store would reject anyway must not hide the image.
struct PasteboardContentTests {
    let png = Data([0x89, 0x50, 0x4E, 0x47])

    @Test func textWinsOverImage() {
        #expect(PasteboardContent.choose(text: "Quarterly report", image: { .png(png) }) == .text("Quarterly report"))
    }

    @Test func blankTextFallsThroughToImage() {
        #expect(PasteboardContent.choose(text: " \n\t", image: { .png(png) }) == .image(.png(png)))
    }

    @Test func blankTextWithoutImageRecordsNothing() {
        #expect(PasteboardContent.choose(text: "  ", image: { nil }) == nil)
    }

    @Test func imageIsNotReadWhenTextWins() {
        // Reading the image may convert a TIFF to PNG: wasted work when the text is kept.
        var imageRead = false
        _ = PasteboardContent.choose(text: "hello", image: {
            imageRead = true
            return .png(png)
        })
        #expect(!imageRead)
    }
}
