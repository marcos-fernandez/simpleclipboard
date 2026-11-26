import AppKit
import ClipboardCore
import SwiftUI

struct ClipCardView: View {
    /// The colour of the icon of the app the card was copied from, when it has one: for the header of a card
    /// without a tag.
    let appColor: Color?
    let density: PanelDensity
    /// Of the text of the card.
    let font: CardFont
    let item: ClipItem
    let image: NSImage?
    let isSelected: Bool
    let tagColor: Color?
    /// The shortcut that picks this card, shown at its foot; nil beyond the cards that have one.
    let shortcut: String?
    /// Set by the strip so that a whole number of cards fills the screen.
    let width: CGFloat

    @Environment(\.colorScheme) private var colorScheme

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
                .frame(height: density.cardHeaderHeight)
                // The colour of its tag says more about a card than the one of its app, which is there for the
                // cards without a tag; the grey is for an app whose icon has no colour.
                .background(
                    (tagColor ?? appColor).map { AnyShapeStyle($0.opacity(PanelMetrics.cardHeaderTint)) }
                        ?? AnyShapeStyle(HierarchicalShapeStyle.quaternary)
                )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(PanelMetrics.cardPadding)
            footer
        }
        .frame(width: width, height: density.cardHeight)
        // Black or white with the appearance of the system, and not the grey of a window's background: the cards
        // stand out from the strip, and what they hold is read on the paper it would be read on.
        .background(
            colorScheme == .dark
                ? Color.black
                : Color.white,
            in: RoundedRectangle(cornerRadius: PanelMetrics.cardCornerRadius)
        )
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
            // Not on a card whose header is in the colour of its tag: without the icon of the app it is told apart
            // from the others at once. By the colour and not by the tag of the item, so the two never disagree.
            if tagColor == nil {
                Image(nsImage: AppIcons.icon(bundleID: item.sourceAppBundleID))
                    .resizable()
                    .frame(width: density.cardIconSize, height: density.cardIconSize)
            }
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
                .font(font.font)
                .lineLimit(PanelMetrics.textLineLimit(density: density, font: font))
        }
    }

    private func subtitle(at date: Date) -> String {
        if let expiresAt = item.expiresAt {
            let minutes = max(1, Int((expiresAt.timeIntervalSince(date) / 60).rounded(.up)))
            return "expires in \(minutes) min"
        }
        return Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: date)
    }
}
