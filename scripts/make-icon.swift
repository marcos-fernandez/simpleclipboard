// Draws the 1024×1024 app icon: fanned clipboard cards on an indigo→violet squircle.
// Usage: swift scripts/make-icon.swift <output.png>
// scripts/make-icon.sh turns the PNG into scripts/AppIcon.icns.
import AppKit

let size: CGFloat = 1024
// Apple's macOS icon grid: the shape sits 100 pt inside the canvas.
let shapeRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let shapeRadius: CGFloat = 185

struct Card {
    let center: CGPoint
    let angle: CGFloat
    let header: NSColor
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func drawBackground(in context: CGContext) {
    let shape = CGPath(roundedRect: shapeRect, cornerWidth: shapeRadius, cornerHeight: shapeRadius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(shape)
    context.setFillColor(color(0x5856D6).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x4F46E5).cgColor, color(0x9333EA).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: shapeRect.minX, y: shapeRect.maxY),
        end: CGPoint(x: shapeRect.maxX, y: shapeRect.minY),
        options: []
    )
    context.restoreGState()
}

func drawCard(_ card: Card, in context: CGContext) {
    let width: CGFloat = 330
    let height: CGFloat = 420
    let radius: CGFloat = 40
    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.translateBy(x: card.center.x, y: card.center.y)
    context.rotate(by: card.angle * .pi / 180)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(body)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    // Coloured header, like a tagged card in the strip.
    context.saveGState()
    context.addPath(body)
    context.clip()
    context.setFillColor(card.header.cgColor)
    context.fill(CGRect(x: rect.minX, y: rect.maxY - 92, width: width, height: 92))
    context.restoreGState()

    // Text lines.
    context.setFillColor(color(0xD4D4DC).cgColor)
    let lineWidths: [CGFloat] = [250, 210, 240, 150]
    for (index, lineWidth) in lineWidths.enumerated() {
        let y = rect.maxY - 150 - CGFloat(index) * 52
        let line = CGRect(x: rect.minX + 40, y: y, width: lineWidth, height: 22)
        context.addPath(CGPath(roundedRect: line, cornerWidth: 11, cornerHeight: 11, transform: nil))
        context.fillPath()
    }
    context.restoreGState()
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift <output.png>\n".utf8))
    exit(64)
}

let pixels = Int(size)
let context = CGContext(
    data: nil,
    width: pixels,
    height: pixels,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

drawBackground(in: context)
// Back to front, fanned like the history strip.
let cards = [
    Card(center: CGPoint(x: 600, y: 520), angle: -14, header: color(0x34C759)),
    Card(center: CGPoint(x: 512, y: 500), angle: -2, header: color(0x0A84FF)),
    Card(center: CGPoint(x: 430, y: 480), angle: 10, header: color(0xFF9F0A)),
]
for card in cards {
    drawCard(card, in: context)
}

let image = context.makeImage()!
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
