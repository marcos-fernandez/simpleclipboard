import ClipboardCore
import Observation
import SwiftUI

/// What the settings window shows. `AppDelegate` owns the values and refreshes them.
@MainActor
@Observable
final class SettingsState {
    var opensAtLogin = false
    var pickAction = PickAction.pasteDirectly
    var isAccessibilityGranted = false
}

@MainActor
struct SettingsActions {
    let setOpensAtLogin: @MainActor (Bool) -> Void
    let setPickAction: @MainActor (PickAction) -> Void
    let openAccessibilitySettings: @MainActor () -> Void
}

struct SettingsView: View {
    let state: SettingsState
    let actions: SettingsActions

    private static let radioSpacing: CGFloat = 8

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Open at Login",
                    isOn: Binding(get: { state.opensAtLogin }, set: actions.setOpensAtLogin)
                )
            }
            Section("Paste Items") {
                VStack(alignment: .leading, spacing: 10) {
                    pickOption(
                        .pasteDirectly,
                        title: "Paste Directly",
                        caption: "The item is pasted into the app you are using."
                    )
                    if state.pickAction == .pasteDirectly, !state.isAccessibilityGranted {
                        HStack(spacing: Self.radioSpacing) {
                            // As wide as the radio button, so the notice lines up with the option's text.
                            Image(systemName: "circle")
                                .hidden()
                            Text("Accessibility permission not granted")
                                .font(.callout)
                            Button("Open System Settings…", action: actions.openAccessibilitySettings)
                                .controlSize(.small)
                        }
                    }
                    pickOption(
                        .copyToClipboard,
                        title: "Copy to Clipboard",
                        caption: "The item goes to the clipboard and you paste it manually."
                    )
                }
            }
        }
        .formStyle(.grouped)
        // The window's background shows through (see `SettingsWindowController`).
        .scrollContentBackground(.hidden)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A radio button with its explanation underneath. Drawn here: in a grouped form the system's radio group puts
    /// the buttons on the trailing edge and takes no second line.
    private func pickOption(_ option: PickAction, title: String, caption: String) -> some View {
        let isSelected = state.pickAction == option
        let symbol = isSelected
            ? "circle.inset.filled"
            : "circle"
        let symbolColor = isSelected
            ? Color.accentColor
            : Color.secondary
        let traits: AccessibilityTraits = isSelected
            ? .isSelected
            : []
        return Button {
            actions.setPickAction(option)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Self.radioSpacing) {
                Image(systemName: symbol)
                    .foregroundStyle(symbolColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            // The whole row is the target, not only the drawn parts.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
    }
}
