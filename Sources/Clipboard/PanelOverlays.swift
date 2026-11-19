import ClipboardCore
import SwiftUI

struct PanelOverlayView: View {
    let store: HistoryStore
    @Bindable var state: PanelState
    let overlay: PanelOverlay

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture {
                    state.overlay = nil
                }
            content
                .padding(16)
                .frame(width: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var content: some View {
        switch overlay {
        case .tagPicker(let itemID):
            TagPickerOverlay(store: store, state: state, itemID: itemID)
        case .newTag:
            TextPromptOverlay(title: "New Tag", state: state) {
                state.submitPrompt(in: store)
            }
        case .renameTag:
            TextPromptOverlay(title: "Rename Tag", state: state) {
                state.submitPrompt(in: store)
            }
        case .deleteTag(let tagID):
            ConfirmDeleteOverlay(
                tagName: store.tags.first { $0.id == tagID }?.name ?? "",
                onConfirm: { state.confirmDelete(in: store) },
                onCancel: { state.overlay = nil }
            )
        }
    }
}

struct TagPickerOverlay: View {
    let store: HistoryStore
    @Bindable var state: PanelState
    let itemID: UUID

    var body: some View {
        let options = state.pickerOptions(for: itemID, in: store)
        VStack(alignment: .leading, spacing: 6) {
            Text("Tag")
                .font(.headline)
            // A ScrollView always takes the whole height: with few tags the card would be far taller than its rows
            // and cover the search field. It is only used when the rows do not fit.
            ViewThatFits(in: .vertical) {
                rows(options)
                ScrollView {
                    rows(options)
                }
            }
            .frame(maxHeight: 180)
        }
    }

    private func rows(_ options: [TagPickerOption]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                row(option)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(
                            index == state.pickerIndex
                                ? Color.accentColor.opacity(0.3)
                                : Color.clear
                        )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.apply(option, to: itemID, in: store)
                    }
            }
        }
    }

    @ViewBuilder
    private func row(_ option: TagPickerOption) -> some View {
        switch option {
        case .tag(let tagID):
            if let tag = store.tags.first(where: { $0.id == tagID }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(TagPalette.color(tag.colorIndex))
                        .frame(width: 8, height: 8)
                    Text(tag.name)
                }
            }
        case .newTag:
            Text("New Tag…")
        case .removeTag:
            Text("Remove Tag")
        }
    }
}

struct TextPromptOverlay: View {
    let title: String
    @Bindable var state: PanelState
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        let canSubmit = !state.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            TextField("Name", text: $state.promptText)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    if canSubmit {
                        onSubmit()
                    }
                }
            HStack {
                Spacer()
                Button("Cancel") {
                    state.overlay = nil
                }
                Button("OK", action: onSubmit)
                    .disabled(!canSubmit)
            }
        }
        .onAppear {
            focused = true
        }
    }
}

struct ConfirmDeleteOverlay: View {
    let tagName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delete the tag “\(tagName)”?")
                .font(.headline)
            Text("Its items go back to the history as just copied.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Delete", role: .destructive, action: onConfirm)
            }
        }
    }
}
