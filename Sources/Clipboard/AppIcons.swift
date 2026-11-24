import AppKit
import ClipboardCore
import SwiftUI

/// The icon of an app and the colour of that icon, by bundle identifier. Looked up once and kept: the body of a card
/// runs on every change, and both the lookup and reading the pixels of an icon are slow. Apps that are not found are
/// kept too, with the fallback, so they are not looked up again.
@MainActor
enum AppIcons {
    private static var cache: [String: (icon: NSImage, color: Color?)] = [:]
    private static let fallbackIcon = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    /// The side, in pixels, of the copy of an icon whose pixels are read: its colour does not need more.
    private static let sampleSize = 32

    static func icon(bundleID: String?) -> NSImage {
        entry(bundleID: bundleID)?.icon ?? fallbackIcon
    }

    /// The colour of the app's icon, nil for an app that is not found or whose icon has no colour of its own.
    static func color(bundleID: String?) -> Color? {
        entry(bundleID: bundleID)?.color
    }

    private static func entry(bundleID: String?) -> (icon: NSImage, color: Color?)? {
        guard let bundleID else {
            return nil
        }
        if let cached = cache[bundleID] {
            return cached
        }
        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        let entry = (icon: found ?? fallbackIcon, color: found.flatMap(color(of:)))
        cache[bundleID] = entry
        return entry
    }

    private static func color(of icon: NSImage) -> Color? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: sampleSize,
            pixelsHigh: sampleSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: sampleSize * 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap), let data = bitmap.bitmapData else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        NSGraphicsContext.restoreGraphicsState()
        let pixels = Array(UnsafeBufferPointer(start: data, count: sampleSize * sampleSize * 4))
        return IconColor.color(ofPremultipliedRGBA: pixels).map {
            Color(red: $0.red, green: $0.green, blue: $0.blue)
        }
    }
}
