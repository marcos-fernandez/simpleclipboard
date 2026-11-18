import AppKit
import ClipboardCore
import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let image: NSImage?
    let isSelected: Bool
    let tagColor: Color?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(8)
                .background(
                    tagColor.map { AnyShapeStyle($0.opacity(0.45)) }
                        ?? AnyShapeStyle(HierarchicalShapeStyle.quaternary)
                )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
        }
        .frame(width: 220, height: 220)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected
                        ? Color.accentColor
                        : Color.clear,
                    lineWidth: 3
                )
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(item.sourceAppName ?? "Unknown")
                .font(.caption.bold())
                .lineLimit(1)
            Spacer()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(subtitle(at: context.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.isConcealed {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title)
                Text("••••••••")
                    .font(.title3.monospaced())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.secondary)
        } else if item.kind == .image {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text(item.text ?? "")
                .font(.system(size: 12))
                .lineLimit(11)
        }
    }

    private func subtitle(at date: Date) -> String {
        if let expiresAt = item.expiresAt {
            let minutes = max(1, Int((expiresAt.timeIntervalSince(date) / 60).rounded(.up)))
            return "expires in \(minutes) min"
        }
        return Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: date)
    }

    /// Icons by bundle ID: body runs for every visible card on every change, and the NSWorkspace lookup is slow.
    /// Apps that are not found are cached with the fallback too, so they are not looked up again.
    @MainActor private static var iconCache: [String: NSImage] = [:]
    @MainActor private static let fallbackIcon = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        ?? NSImage()

    private var appIcon: NSImage {
        guard let bundleID = item.sourceAppBundleID else {
            return Self.fallbackIcon
        }
        if let cached = Self.iconCache[bundleID] {
            return cached
        }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? Self.fallbackIcon
        Self.iconCache[bundleID] = icon
        return icon
    }
}
