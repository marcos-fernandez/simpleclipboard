import ClipboardCore
import SwiftUI

/// The measures the overlays share, in points.
private enum OverlayMetrics {
    static let cornerRadius: CGFloat = 12
    /// Between the dot of a tag and what follows it.
    static let dotSpacing: CGFloat = 8
    static let inset: CGFloat = 20
    /// Of the strip the overlays are drawn over (see `HistoryView`).
    static let panelCornerRadius: CGFloat = 16
    static let pickerRowCornerRadius: CGFloat = 6
    static let pickerRowInset: CGFloat = 8
    /// The rows of the tag picker: what is shown of them at most, each one, and between two.
    static let pickerMaxHeight: CGFloat = 180
    static let pickerRowHeight: CGFloat = 28
    static let pickerRowSpacing: CGFloat = 2
    /// Between the options of a section that are controls of their own, as in the settings.
    static let optionSpacing: CGFloat = 16
    /// Between the sections of an overlay: its title, its content, its buttons.
    static let sectionSpacing: CGFloat = 24
    /// Between a title and the line that explains it.
    static let titleSpacing: CGFloat = 8
    static let width: CGFloat = 320
}

/// The colour in the overlay that names a tag.
enum PromptColor {
    /// Chosen there, from the row of dots: for a tag that does not exist yet.
    case chosen
    /// Shown before the name: the one the tag has. Its row of dots is in the menu of its tab.
    case shown(Color?)
}

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
                .padding(OverlayMetrics.inset)
                .frame(width: OverlayMetrics.width)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OverlayMetrics.cornerRadius))
        }
        .clipShape(RoundedRectangle(cornerRadius: OverlayMetrics.panelCornerRadius))
    }

    @ViewBuilder
    private var content: some View {
        switch overlay {
        case .tagPicker(let itemID):
            TagPickerOverlay(store: store, state: state, itemID: itemID)
        case .newTag:
            TextPromptOverlay(
                title: "New Tag",
                color: .chosen,
                confirmTitle: "Create",
                state: state
            ) {
                state.submitPrompt(in: store)
            }
        case .renameTag(let tagID):
            // Worded as the question of deleting one is: the name it has is in the title, the field is for the new.
            TextPromptOverlay(
                title: "Rename the tag “\(store.tags.first { $0.id == tagID }?.name ?? "")”?",
                color: .shown(color(ofTag: tagID)),
                confirmTitle: "Rename",
                state: state
            ) {
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

    private func color(ofTag tagID: UUID) -> Color? {
        store.tags.first { $0.id == tagID }.map { TagPalette.color($0.colorIndex) }
    }
}

/// What every overlay starts with: what it does. Text alone: a dot of colour before it, in the corner of the
/// overlay, read as one of the buttons of a window.
private struct OverlayTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct TagPickerOverlay: View {
    let store: HistoryStore
    @Bindable var state: PanelState
    let itemID: UUID

    var body: some View {
        let options = state.pickerOptions(for: itemID, in: store)
        VStack(alignment: .leading, spacing: OverlayMetrics.optionSpacing) {
            OverlayTitle(title: "Tag")
            // As tall as its rows, up to a point: left to take what it is offered, the overlay would be far taller
            // than a few tags need and cover the search field.
            ScrollView {
                rows(options)
            }
            .frame(height: min(Self.height(ofRows: options.count), OverlayMetrics.pickerMaxHeight))
        }
    }

    private static func height(ofRows count: Int) -> CGFloat {
        CGFloat(count) * OverlayMetrics.pickerRowHeight + CGFloat(max(0, count - 1)) * OverlayMetrics.pickerRowSpacing
    }

    private func rows(_ options: [TagPickerOption]) -> some View {
        VStack(alignment: .leading, spacing: OverlayMetrics.pickerRowSpacing) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                row(option)
                    .padding(.horizontal, OverlayMetrics.pickerRowInset)
                    .frame(maxWidth: .infinity, minHeight: OverlayMetrics.pickerRowHeight, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: OverlayMetrics.pickerRowCornerRadius).fill(
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
                HStack(spacing: OverlayMetrics.dotSpacing) {
                    TagDot(color: TagPalette.color(tag.colorIndex), size: TagDot.dialogSize)
                    // One line, as its tab: the height of the list is worked out from rows of one.
                    Text(tag.name)
                        .lineLimit(1)
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
    let color: PromptColor
    /// What the main button says: what it does, not "OK".
    let confirmTitle: String
    @Bindable var state: PanelState
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        let canSubmit = !state.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: OverlayMetrics.sectionSpacing) {
            OverlayTitle(title: title)
            VStack(alignment: .leading, spacing: OverlayMetrics.optionSpacing) {
                // The dot before the name, as the tab of the tag has it. Not for a new tag: its colour is the one
                // ringed in the row below.
                HStack(spacing: OverlayMetrics.dotSpacing) {
                    if case .shown(let shown?) = color {
                        TagDot(color: shown, size: TagDot.dialogSize)
                    }
                    TextField("Name", text: $state.promptText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focused)
                        .onSubmit {
                            if canSubmit {
                                onSubmit()
                            }
                        }
                }
                if case .chosen = color {
                    TagColorRow(selected: state.newTagColorIndex, inset: 0) { index in
                        state.newTagColorIndex = index
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    state.overlay = nil
                }
                Button(confirmTitle, action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
            .controlSize(.large)
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
        VStack(alignment: .leading, spacing: OverlayMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: OverlayMetrics.titleSpacing) {
                OverlayTitle(title: "Delete the tag “\(tagName)”?")
                Text("The items with this tag are not deleted. They will go back to the history.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Delete", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .controlSize(.large)
        }
    }
}
