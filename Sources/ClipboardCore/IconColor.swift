/// The colour of an app's icon, to tint the header of the cards copied from that app.
public enum IconColor {
    public struct RGB: Equatable, Sendable {
        /// Each from 0 to 1.
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// The parts the circle of hues is cut in, to find the one most of the icon's colour is in.
    private static let hueBucketCount = 12
    /// A pixel counts as part of the icon from this alpha, of 255: the rest is its shadow and its soft edge.
    private static let minAlpha = 128
    /// And as coloured from this difference, of 255, between its strongest and its weakest channel: below it, it is
    /// a grey, a white or a black.
    private static let minChroma = 48
    /// The share of the icon's pixels that have to be coloured for the icon to have a colour. Under it the icon is
    /// a grey one with a detail (Terminal, a document), and its header stays as it was rather than take a tint from
    /// a few pixels. Low enough for a logo on a white plate, which is the colour of its icon.
    private static let minColouredShare = 0.10
    /// The share of the icon's colour that its main hue, with the hues next to it, has to hold. Under it the icon
    /// is one of several colours (the petals of Photos), and none of them is its colour.
    private static let minDominantShare = 0.5

    /// The colour of an icon from its pixels, or nil for one without a colour of its own. `pixels`: four bytes
    /// each, red, green, blue and alpha, with the alpha already multiplied into the others, as a bitmap context
    /// gives them.
    ///
    /// It is the colour of the icon's main hue, and not the average of all its colours: the average of an icon of
    /// several colours is a brown that is nowhere in it. Each pixel weighs as much as it is coloured: a vivid part
    /// of the icon says more about it than a pale one.
    public static func color(ofPremultipliedRGBA pixels: [UInt8]) -> RGB? {
        var buckets = Array(repeating: (blue: 0.0, green: 0.0, red: 0.0, weight: 0.0), count: hueBucketCount)
        var coloured = 0
        var opaque = 0

        for offset in stride(from: 0, to: pixels.count - 3, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha >= minAlpha else {
                continue
            }
            opaque += 1
            // Back to the colour of the pixel itself, without its alpha.
            let channels = (0..<3).map { min(255, Int(pixels[offset + $0]) * 255 / alpha) }
            let chroma = (channels.max() ?? 0) - (channels.min() ?? 0)
            guard chroma >= minChroma else {
                continue
            }
            let bucket = hueBucket(red: channels[0], green: channels[1], blue: channels[2], chroma: chroma)
            coloured += 1
            buckets[bucket].red += Double(channels[0] * chroma)
            buckets[bucket].green += Double(channels[1] * chroma)
            buckets[bucket].blue += Double(channels[2] * chroma)
            buckets[bucket].weight += Double(chroma)
        }
        guard opaque > 0, Double(coloured) >= Double(opaque) * minColouredShare else {
            return nil
        }

        // A hue and the two next to it, around the circle: one colour of an icon, with its light and its shade,
        // often falls on both sides of a cut.
        let windows = buckets.indices.map { index in
            [index + hueBucketCount - 1, index, index + 1].map { buckets[$0 % hueBucketCount] }
        }
        let total = buckets.reduce(0) { $0 + $1.weight }
        guard let main = windows.max(by: { weight(of: $0) < weight(of: $1) }),
              weight(of: main) >= total * minDominantShare, weight(of: main) > 0 else {
            return nil
        }
        return RGB(
            red: main.reduce(0) { $0 + $1.red } / weight(of: main) / 255,
            green: main.reduce(0) { $0 + $1.green } / weight(of: main) / 255,
            blue: main.reduce(0) { $0 + $1.blue } / weight(of: main) / 255
        )
    }

    /// The part of the circle of hues a coloured pixel falls in: the first one is centred on red.
    private static func hueBucket(red: Int, green: Int, blue: Int, chroma: Int) -> Int {
        let strongest = max(red, green, blue)
        // In sixths of the circle, as the usual formula of the hue gives it.
        let sixths: Double
        let width = 6.0 / Double(hueBucketCount)

        if strongest == red {
            sixths = Double(green - blue) / Double(chroma)
        } else if strongest == green {
            sixths = 2 + Double(blue - red) / Double(chroma)
        } else {
            sixths = 4 + Double(red - green) / Double(chroma)
        }
        return Int(((sixths + 6 + width / 2) / width).rounded(.down)) % hueBucketCount
    }

    private static func weight(of window: [(blue: Double, green: Double, red: Double, weight: Double)]) -> Double {
        window.reduce(0) { $0 + $1.weight }
    }
}
