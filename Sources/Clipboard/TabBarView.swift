import ClipboardCore
import SwiftUI

/// "History" plus one tab per tag, in creation order.
struct TabBarView: View {
    let store: HistoryStore
    @Bindable var state: PanelState

    var body: some View {
        // As wide as its tabs while they fit in the row, so the row can be centred; scrolled once they do not.
        ViewThatFits(in: .horizontal) {
            tabs
            ScrollView(.horizontal, showsIndicators: false) {
                tabs
            }
        }
        .frame(height: 26)
    }

    private var tabs: some View {
        let active = state.effectiveScope(in: store)
        return HStack(spacing: 6) {
            tab(title: "History", color: nil, scope: .history, active: active)
            ForEach(store.tags) { tag in
                tab(title: tag.name, color: TagPalette.color(tag.colorIndex), scope: .tag(tag.id), active: active)
                    .contextMenu {
                        tabMenu(for: tag)
                    }
            }
        }
        .padding(.horizontal, 4)
    }

    private func tab(title: String, color: Color?, scope: HistoryStore.Scope, active: HistoryStore.Scope) -> some View {
        Button {
            state.scope = scope
            state.selectedID = nil
        } label: {
            HStack(spacing: 5) {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    scope == active
                        ? Color.accentColor.opacity(0.25)
                        : Color.clear
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabMenu(for tag: Tag) -> some View {
        Button("Rename…") {
            state.startRename(tag)
        }
        Menu("Color") {
            ForEach(TagPalette.colors.indices, id: \.self) { index in
                Button(TagPalette.names[index]) {
                    store.recolorTag(id: tag.id, colorIndex: index)
                }
            }
        }
        Divider()
        Button("Delete Tag…", role: .destructive) {
            state.overlay = .deleteTag(tagID: tag.id)
        }
    }
}
