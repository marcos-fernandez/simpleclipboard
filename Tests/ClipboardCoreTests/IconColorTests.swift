import Testing
@testable import ClipboardCore

/// The header of a card takes the colour of its app's icon: a wrong one is worse than the grey it had.
struct IconColorTests {
    private static let blue: [UInt8] = [0, 0, 255, 255]
    private static let green: [UInt8] = [0, 255, 0, 255]
    private static let grey: [UInt8] = [128, 128, 128, 255]
    private static let orange: [UInt8] = [255, 128, 0, 255]
    private static let purple: [UInt8] = [128, 0, 255, 255]
    private static let red: [UInt8] = [255, 0, 0, 255]
    private static let transparent: [UInt8] = [0, 0, 0, 0]

    private func pixels(_ parts: (pixel: [UInt8], count: Int)...) -> [UInt8] {
        parts.flatMap { part in Array(repeating: part.pixel, count: part.count).flatMap { $0 } }
    }

    @Test func anIconOfOneColourHasThatColour() {
        #expect(IconColor.color(ofPremultipliedRGBA: pixels((Self.red, 100))) == .init(red: 1, green: 0, blue: 0))
    }

    @Test func whatIsTransparentDoesNotCount() {
        // Most of the square of an icon is empty around its shape.
        let icon = pixels((Self.transparent, 900), (Self.blue, 100))
        #expect(IconColor.color(ofPremultipliedRGBA: icon) == .init(red: 0, green: 0, blue: 1))
    }

    @Test(arguments: [[128, 128, 128, 255], [255, 255, 255, 255], [0, 0, 0, 255], [40, 44, 52, 255]] as [[UInt8]])
    func anIconWithoutColourHasNone(pixel: [UInt8]) {
        #expect(IconColor.color(ofPremultipliedRGBA: pixels((pixel, 100))) == nil)
    }

    @Test func aDetailOfColourOnAGreyIconIsNotItsColour() {
        // The prompt of a terminal, the corner of a document.
        #expect(IconColor.color(ofPremultipliedRGBA: pixels((Self.grey, 95), (Self.red, 5))) == nil)
    }

    @Test func aLargeEnoughPartOfColourOnAGreyIconIsItsColour() {
        let icon = pixels((Self.grey, 70), (Self.red, 30))
        #expect(IconColor.color(ofPremultipliedRGBA: icon) == .init(red: 1, green: 0, blue: 0))
    }

    @Test func theVividPartWeighsMoreThanThePaleOne() throws {
        // As many pale blue pixels as red ones: the icon reads as red.
        let paleBlue: [UInt8] = [150, 150, 210, 255]
        let color = try #require(IconColor.color(ofPremultipliedRGBA: pixels((paleBlue, 50), (Self.red, 50))))
        #expect(color.red > color.blue)
    }

    @Test func theAlphaMultipliedIntoAPixelIsTakenOut() {
        // A half-transparent pure red, as a bitmap context holds it.
        let icon = pixels(([128, 0, 0, 128], 100))
        #expect(IconColor.color(ofPremultipliedRGBA: icon) == .init(red: 1, green: 0, blue: 0))
    }

    @Test func anIconOfSeveralColoursHasNone() {
        // The petals of Photos: their average is a brown that is nowhere in the icon.
        let icon = pixels((Self.red, 20), (Self.orange, 20), (Self.green, 20), (Self.blue, 20), (Self.purple, 20))
        #expect(IconColor.color(ofPremultipliedRGBA: icon) == nil)
    }

    @Test func theMainColourIsNotMixedWithTheOthers() {
        let icon = pixels((Self.red, 70), (Self.blue, 30))
        #expect(IconColor.color(ofPremultipliedRGBA: icon) == .init(red: 1, green: 0, blue: 0))
    }

    @Test func coloursNextToEachOtherAreOne() throws {
        // A red that goes to orange is one colour with its light, and not two that share the icon.
        let icon = pixels((Self.red, 40), (Self.orange, 40), (Self.blue, 20))
        let color = try #require(IconColor.color(ofPremultipliedRGBA: icon))
        #expect(color.red == 1)
        #expect(color.green > 0 && color.green < 0.5)
        #expect(color.blue == 0)
    }

    @Test func theMainColourHoldsHalfOfTheColourOrThereIsNone() {
        let half = pixels((Self.red, 50), (Self.green, 25), (Self.blue, 25))
        let lessThanHalf = pixels((Self.red, 49), (Self.green, 26), (Self.blue, 25))
        #expect(IconColor.color(ofPremultipliedRGBA: half) == .init(red: 1, green: 0, blue: 0))
        #expect(IconColor.color(ofPremultipliedRGBA: lessThanHalf) == nil)
    }

    @Test func aPixelIsPartOfTheIconFromHalfItsAlpha() {
        #expect(IconColor.color(ofPremultipliedRGBA: pixels(([127, 0, 0, 127], 100))) == nil)
        #expect(IconColor.color(ofPremultipliedRGBA: pixels(([128, 0, 0, 128], 100))) != nil)
    }

    @Test func aPixelIsColouredFromADifferenceBetweenItsChannels() {
        #expect(IconColor.color(ofPremultipliedRGBA: pixels(([100, 100, 147, 255], 100))) == nil)
        #expect(IconColor.color(ofPremultipliedRGBA: pixels(([100, 100, 148, 255], 100))) != nil)
    }

    @Test func anIconHasAColourFromAShareOfColouredPixels() {
        #expect(IconColor.color(ofPremultipliedRGBA: pixels((Self.grey, 91), (Self.red, 9))) == nil)
        #expect(IconColor.color(ofPremultipliedRGBA: pixels((Self.grey, 90), (Self.red, 10))) != nil)
    }

    @Test func anEmptyIconHasNoColour() {
        #expect(IconColor.color(ofPremultipliedRGBA: []) == nil)
        #expect(IconColor.color(ofPremultipliedRGBA: pixels((Self.transparent, 100))) == nil)
    }
}
