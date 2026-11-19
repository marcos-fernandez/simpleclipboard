import ClipboardCore
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore
    @Bindable var state: PanelState
    let onPick: (ClipItem) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = state.results(in: store)
        let selectedIndex = state.selectedIndex(in: results)
        VStack(spacing: 12) {
            TabBarView(store: store, state: state)

            TextField("Search history", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
                .focused($searchFocused)

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
            if newValue == nil {
                searchFocused = true
            }
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
            .onChange(of: state.selectedID) { _, newID in
                guard let newID else {
                    return
                }
                withAnimation {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }
}
