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

struct HistoryView: View {
    let store: HistoryStore
    @Bindable var state: PanelState
    let onPick: (ClipItem) -> Void
    let onOpenSettings: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = state.results(in: store)
        let selectedIndex = state.selectedIndex(in: results)
        VStack(spacing: 12) {
            // One row, centred: the search field keeps its width and the tabs take what they need.
            HStack(spacing: 12) {
                // Drawn here: taller and rounder than the system's bordered field, like the search of System Settings.
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $state.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
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
                .frame(width: 280, height: 30)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .overlay {
                    if searchFocused {
                        SearchFocusRing()
                            .fill(Color(nsColor: .keyboardFocusIndicatorColor), style: FillStyle(eoFill: true))
                    }
                }
                TabBarView(store: store, state: state)
                settingsButton
            }

            if results.isEmpty {
                Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cards(results, selectedIndex: selectedIndex)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if let overlay = state.overlay {
                PanelOverlayView(store: store, state: state, overlay: overlay)
            }
        }
        .onChange(of: state.overlay) { _, newValue in
            // AppKit draws the search field's focus ring above the overlay, so the field gives focus up meanwhile.
            searchFocused = newValue == nil
        }
        .onChange(of: state.query) {
            state.selectedID = nil
        }
        .onChange(of: state.scope) {
            state.selectedID = nil
        }
        .onAppear {
            searchFocused = true
        }
        .onChange(of: state.focusRequest) {
            searchFocused = true
        }
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings…")
        .accessibilityLabel("Settings")
    }

    private var emptyMessage: String {
        if !state.query.isEmpty {
            return "No results"
        }
        if case .tag = state.effectiveScope(in: store) {
            return "This tag has no items"
        }
        return "The history is empty"
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
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(results) { item in
                        ClipCardView(
                            item: item,
                            image: ThumbnailCache.image(for: item, store: store),
                            isSelected: item.id == selectedCardID,
                            tagColor: tagColor(for: item)
                        )
                        .id(item.id)
                        .onTapGesture(count: 2) {
                            onPick(item)
                        }
                        .onTapGesture {
                            state.selectedID = item.id
                        }
                        .contextMenu {
                            Menu("Tag") {
                                ForEach(store.tags) { tag in
                                    Button(tag.name) {
                                        store.setTag(itemID: item.id, tagID: tag.id)
                                    }
                                }
                                if !store.tags.isEmpty {
                                    Divider()
                                }
                                Button("New Tag…") {
                                    state.apply(.newTag, to: item.id, in: store)
                                }
                            }
                            .disabled(item.isConcealed)
                            Button("Remove Tag") {
                                store.setTag(itemID: item.id, tagID: nil)
                            }
                            .disabled(item.isConcealed || item.tagID == nil)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            // The card shown as selected, not `selectedID`: nil (after reopening, a tab switch or a search) and a
            // removed or expired item fall back to the first card, which must then be scrolled into view too.
            .onChange(of: selectedCardID) { _, newID in
                withAnimation {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            // The panel keeps its scroll offset while hidden; on every show the selected card must be on screen
            // even when the selection did not change.
            .onChange(of: state.focusRequest) {
                proxy.scrollTo(selectedCardID, anchor: .center)
            }
        }
    }
}
