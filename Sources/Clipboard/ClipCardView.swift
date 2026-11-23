import AppKit
import ClipboardCore
import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let image: NSImage?
    let isSelected: Bool
    let tagColor: Color?
    /// The shortcut that picks this card, shown at its foot; nil beyond the cards that have one.
    let shortcut: String?
    /// Set by the strip so that a whole number of cards fills the screen.
    let width: CGFloat

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    /// Text can be up to 2 MiB; the few lines a card shows hold far fewer characters, so only this much is laid out.
    private static let previewLength = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, PanelMetrics.cardPadding)
                .frame(height: PanelMetrics.cardHeaderHeight)
                .background(
                    tagColor.map { AnyShapeStyle($0.opacity(0.45)) }
                        ?? AnyShapeStyle(HierarchicalShapeStyle.quaternary)
                )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(PanelMetrics.cardPadding)
            footer
        }
        .frame(width: width, height: PanelMetrics.cardHeight)
        .background(.background, in: RoundedRectangle(cornerRadius: PanelMetrics.cardCornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.cardCornerRadius)
                .stroke(
                    isSelected
                        ? Color.accentColor
                        : Color.clear,
                    lineWidth: PanelMetrics.cardSelectionStroke
                )
        )
    }

    /// A row of its own, so the shortcuts never cover what the card holds. Kept on the cards with nothing to show
    /// too: every card gives its content the same room.
    private var footer: some View {
        HStack {
            if let shortcut {
                Text(shortcut)
            }
            Spacer()
            // ⌘⌫ deletes the selected card (see `PanelController.handle`), so only that one says it.
            if isSelected {
                Text("⌘⌫")
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, PanelMetrics.cardPadding)
        .frame(height: PanelMetrics.cardFooterHeight)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: PanelMetrics.cardIconSize, height: PanelMetrics.cardIconSize)
            Text(item.sourceAppName ?? "Unknown")
                .font(.callout.bold())
                .lineLimit(1)
            Spacer()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(subtitle(at: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // Whole and on one line: a long app name is what gives way.
                    .lineLimit(1)
                    .fixedSize()
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
            Text(String((item.text ?? "").prefix(Self.previewLength)))
                .font(.system(size: PanelMetrics.textFontSize))
                .lineLimit(PanelMetrics.textLineLimit)
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
