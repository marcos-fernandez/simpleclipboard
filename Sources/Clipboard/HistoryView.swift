import ClipboardCore
import SwiftUI

/// The focus ring of the search field: the band between a capsule and a smaller one inside it, to be filled with
/// the even-odd rule. Filled and not stroked: the stroke of a capsule is drawn with a mark at each end.
private struct SearchFocusRing: Shape {
    private static let lineWidth: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        let inner = rect.insetBy(dx: Self.lineWidth, dy: Self.lineWidth)
        var path = Path(roundedRect: rect, cornerRadius: rect.height / 2)
        path.addRoundedRect(in: inner, cornerSize: CGSize(width: inner.height / 2, height: inner.height / 2))
        return path
    }
}

/// Holds the AppKit view under the wrench, which AppKit needs to open a menu from. Owned by `PanelController` and
/// not by the view: this toolchain has no SwiftUI macros, so no `@State`.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
}

/// An empty AppKit view, put behind the wrench so its frame is the wrench's.
private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct HistoryView: View {
    let store: HistoryStore
    @Bindable var state: PanelState
    let onDelete: (ClipItem) -> Void
    let onPick: (ClipItem) -> Void
    /// Puts the keyboard back in the search field, after its text, once an overlay that took it closes.
    let onRestoreSearchFocus: () -> Void
    /// Filled with the view behind the wrench, for `onShowMenu` to open the menu from.
    let menuAnchor: MenuAnchor
    /// Opens the menu of the menu-bar item from the wrench.
    let onShowMenu: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = state.results(in: store)
        let selectedIndex = state.selectedIndex(in: results)
        VStack(spacing: PanelMetrics.stripSpacing) {
            // One row, centred: the search field keeps its width and the tabs take what they need.
            HStack(spacing: PanelMetrics.searchRowSpacing) {
                if state.showsMenuButton {
                    menuButton
                }
                // Drawn here: taller and rounder than the system's bordered field, like the search of System Settings.
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $state.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if state.query.isEmpty && !searchFocused {
                        // The keyboard is on the cards: how to bring it here.
                        Text("⌘F")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if !state.query.isEmpty {
                        Button {
                            state.query = ""
                            searchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 10)
                .frame(width: 280, height: PanelMetrics.searchRowHeight)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .overlay {
                    if searchFocused {
                        SearchFocusRing()
                            .fill(Color(nsColor: .keyboardFocusIndicatorColor), style: FillStyle(eoFill: true))
                    }
                }
                TabBarView(store: store, state: state)
            }
            // Clear at both ends, so the field and the tabs stay in the middle with the share button at the end.
            .padding(.horizontal, PanelMetrics.shareButtonSize + PanelMetrics.searchRowSpacing)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                shareButton(results, selectedIndex: selectedIndex)
            }

            if results.isEmpty {
                Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cards(results, selectedIndex: selectedIndex)
            }
        }
        .padding(PanelMetrics.stripPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if let overlay = state.overlay {
                PanelOverlayView(store: store, state: state, overlay: overlay)
            }
        }
        .onChange(of: state.overlay) { oldValue, newValue in
            // AppKit draws the search field's focus ring above the overlay, so the field gives the keyboard up
            // meanwhile, and has it back afterwards if it had it. Through the panel and not by `searchFocused`,
            // which selects the whole text: the next key would replace the search.
            if oldValue == nil {
                state.hadSearchFocusBeforeOverlay = searchFocused
            }
            if newValue != nil {
                searchFocused = false
            } else if state.hadSearchFocusBeforeOverlay {
                onRestoreSearchFocus()
            }
        }
        // Where the keyboard goes is the panel's to decide (`PanelController.show`, `focusSearchField`); this only
        // tells it where it is.
        .onChange(of: searchFocused) { _, isFocused in
            state.isSearchFocused = isFocused
        }
        .onChange(of: state.query) {
            startFromTheFirstCard()
        }
        .onChange(of: state.scope) {
            startFromTheFirstCard()
        }
    }

    /// Opens the menu of the menu-bar item while that item is hidden. Round and as tall as the search field, with the
    /// same background, so the two read as one row of controls.
    private var menuButton: some View {
        let symbolColor = state.isUpdateAvailable
            ? Color(nsColor: .systemBlue)
            : Color.secondary
        let label = state.isUpdateAvailable
            ? "\(Config.appName) Menu, update available"
            : "\(Config.appName) Menu"
        return Button(action: onShowMenu) {
            Image(systemName: "wrench.adjustable")
                .foregroundStyle(symbolColor)
                .frame(width: PanelMetrics.searchRowHeight, height: PanelMetrics.searchRowHeight)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: menuAnchor))
        .help(label)
        .accessibilityLabel(label)
    }

    /// Another search or tab is another list: nothing selected, and the strip back at its first card.
    private func startFromTheFirstCard() {
        state.selectedID = nil
        state.showFirst(0, of: state.results(in: store))
    }

    /// Shares the selected card.
    private func shareButton(_ results: [ClipItem], selectedIndex: Int) -> some View {
        let selected = results.indices.contains(selectedIndex)
            ? results[selectedIndex]
            : nil
        let canShare = selected.map { CardShare.canShare($0, store: store) } ?? false
        return ShareButton(isEnabled: canShare) {
            selected.map { CardShare.items(for: $0, store: store) } ?? []
        }
        .frame(width: PanelMetrics.shareButtonSize, height: PanelMetrics.shareButtonSize)
    }

    private var emptyMessage: String {
        if state.hasSearch {
            return "No results"
        }
        if case .tag = state.effectiveScope(in: store) {
            return "This tag has no items."
        }
        return "The history is empty."
    }

    private func tagColor(for item: ClipItem) -> Color? {
        guard let tagID = item.tagID, let tag = store.tags.first(where: { $0.id == tagID }) else {
            return nil
        }
        return TagPalette.color(tag.colorIndex)
    }

    private func cards(_ results: [ClipItem], selectedIndex: Int) -> some View {
        // By id, so no indexed copy of the whole list is built on every body pass.
        let selectedCardID = results[selectedIndex].id
        // The cards in view, from the first one, show the shortcut that picks them (see `CardShortcuts`).
        let leadingIndex = state.leadingIndex(in: results)
        let shortcutIDs = leadingIndex.map { results.dropFirst($0).prefix(state.cardShortcutCount).map(\.id) } ?? []
        let cardWidth = state.cardWidth
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: PanelMetrics.cardSpacing) {
                ForEach(results) { item in
                    ClipCardView(
                        appColor: AppIcons.color(bundleID: item.sourceAppBundleID),
                        item: item,
                        image: ThumbnailCache.image(for: item, store: store),
                        isSelected: item.id == selectedCardID,
                        tagColor: tagColor(for: item),
                        shortcut: shortcutIDs.firstIndex(of: item.id).flatMap(CardShortcuts.label(position:)),
                        width: cardWidth
                    )
                    .id(item.id)
                    .onTapGesture(count: 2) {
                        onPick(item)
                    }
                    .onTapGesture {
                        state.selectedID = item.id
                    }
                    .overlay {
                        AppKitContextMenu { card in
                            CardMenu.menu(
                                card: card,
                                item: item,
                                tags: store.tags,
                                onDelete: { onDelete(item) },
                                onNewTag: { state.apply(.newTag, to: item.id, in: store) },
                                onSetTag: { store.setTag(itemID: item.id, tagID: $0) },
                                shareItems: CardShare.canShare(item, store: store)
                                    ? { CardShare.items(for: item, store: store) }
                                    : nil
                            )
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        // Margins of the scroll and not padding of the row: a scroll that only goes as far as a card needs keeps
        // them, where it would leave the card against the edge with its border cut.
        .contentMargins(.horizontal, PanelMetrics.rowInset, for: .scrollContent)
        // The strip always stops on whole cards, by hand too: the shortcuts count from the first card in view, and
        // a card cut at the edge would show one for something the user does not see whole.
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $state.leadingCardID, anchor: .leading)
        // The card shown as selected, not `selectedID`: nil (after reopening, a tab switch or a search) and a
        // removed or expired item fall back to the first card, which must then be scrolled into view too.
        .onChange(of: selectedCardID) {
            let leading = StripLayout.leadingCard(
                current: leadingIndex ?? selectedIndex, selected: selectedIndex, cardCount: state.cardCount
            )
            withAnimation {
                state.showFirst(leading, of: results)
            }
        }
        // The first card in view is gone from the list and the strip does not say where it is now: the card that
        // took its place becomes the first, so the cards in view have their shortcuts again.
        .onChange(of: leadingIndex) { oldIndex, newIndex in
            if newIndex == nil, let oldIndex {
                state.showFirst(oldIndex, of: results)
            }
        }
        // The panel keeps its scroll offset while hidden; every show starts from the first card, the selected one.
        .onChange(of: state.showRequest) {
            state.showFirst(0, of: results)
        }
    }
}
