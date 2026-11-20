import ClipboardCore
import Observation
import SwiftUI

/// The panes of the settings window, in the order of the sidebar.
enum SettingsSection: CaseIterable {
    case general
    case keyboardShortcuts
    case privacy

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .keyboardShortcuts:
            return "keyboard"
        case .privacy:
            return "hand.raised"
        }
    }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .keyboardShortcuts:
            return "Keyboard Shortcuts"
        case .privacy:
            return "Privacy"
        }
    }
}

/// What the settings window shows. `AppDelegate` owns the values and refreshes them; the pane on show is the
/// window's own.
@MainActor
@Observable
final class SettingsState {
    var section = SettingsSection.general
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

/// The system's sidebar material, which SwiftUI only gives to a List.
private struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SettingsView: View {
    let state: SettingsState
    let actions: SettingsActions

    private static let radioSpacing: CGFloat = 8
    /// Lines the header up with the boxes of the form.
    private static let headerInset: CGFloat = 20
    private static let paneSize = CGSize(width: 490, height: 420)
    /// The same for every row, so the names line up whatever the width of each symbol.
    private static let sidebarIconWidth: CGFloat = 22
    private static let sidebarInset: CGFloat = 10
    private static let sidebarRowSpacing: CGFloat = 2
    private static let sidebarTopInset: CGFloat = 20

    var body: some View {
        // Not a NavigationSplitView: its divider can be dragged and its sidebar collapsed whatever widths it is given,
        // and the sidebar is the only way to change pane.
        HStack(spacing: 0) {
            sidebar
            Divider()
                .ignoresSafeArea()
            pane
        }
        .frame(height: Self.paneSize.height)
    }

    /// Drawn here and not a List: as wide as its longest name, whatever the language, where a List cuts the name to
    /// the width it is given.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Self.sidebarRowSpacing) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                sidebarRow(section)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, Self.sidebarInset)
        // Some air under the title bar: the rows already start below it and the window's buttons.
        .padding(.top, Self.sidebarTopInset)
        .frame(maxHeight: .infinity, alignment: .top)
        // Up to the top edge, under the title bar.
        .background(SidebarBackground().ignoresSafeArea())
    }

    /// The name of the pane on show and, under it, its content.
    private var pane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.section.title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, Self.headerInset)
                .accessibilityAddTraits(.isHeader)
            switch state.section {
            case .general:
                general
            case .keyboardShortcuts, .privacy:
                Text("Nothing here yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: Self.paneSize.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        let isSelected = state.section == section
        let background = isSelected
            ? Color.accentColor
            : Color.clear
        let foreground = isSelected
            ? Color.white
            : Color.primary
        let traits: AccessibilityTraits = isSelected
            ? .isSelected
            : []
        return Button {
            state.section = section
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.symbolName)
                    .frame(width: Self.sidebarIconWidth)
                Text(section.title)
            }
            // Every row as wide as the widest one.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
    }

    private var general: some View {
        Form {
            Section {
                Toggle(
                    "Open at Login",
                    // Called in a closure, not passed as a value: Swift 6.3 (the one that builds the releases) crashes
                    // converting a @MainActor function to the plain one a Binding takes.
                    isOn: Binding(get: { state.opensAtLogin }, set: { actions.setOpensAtLogin($0) })
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
