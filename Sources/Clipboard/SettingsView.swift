import AppKit
import ClipboardCore
import Observation
import SwiftUI

/// The panes of the settings window, in the order of the sidebar. Only the ones with something in them: a pane is
/// added here together with its content.
enum SettingsPane: CaseIterable {
    case general
    case privacy

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .privacy:
            return "hand.raised"
        }
    }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .privacy:
            return "Privacy"
        }
    }

    /// The title of the window while this pane is on show. The pane, as in any settings window, after the app's
    /// name: the app has no Dock icon and no place in the app switcher, so in Mission Control the title is all that
    /// says whose window it is.
    var windowTitle: String {
        "\(Config.appName) — \(title)"
    }
}

/// An app of the "Never Copy From" list, as the list shows it.
struct IgnoredAppRow: Identifiable {
    /// The bundle identifier.
    let id: String
    let icon: NSImage
    let name: String

    /// An app that is not installed has no name or icon to show: its identifier and the icon of any app.
    init(bundleID: String) {
        id = bundleID
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            icon = NSWorkspace.shared.icon(for: .application)
            name = bundleID
            return
        }
        icon = NSWorkspace.shared.icon(forFile: url.path)
        name = FileManager.default.displayName(atPath: url.path)
    }
}

/// What the settings window shows. `AppDelegate` owns the values and refreshes them; the pane on show is the
/// window's own.
@MainActor
@Observable
final class SettingsState {
    var ignoredApps: [IgnoredAppRow] = []
    var pane = SettingsPane.general
    /// The app selected in the "Never Copy From" list, by bundle identifier.
    var selectedIgnoredAppID: String?
    var opensAtLogin = false
    var pickAction = PickAction.pasteDirectly
    var isAccessibilityGranted = false

    /// The pane `offset` rows away in the sidebar, stopping at its ends.
    func movePane(by offset: Int) {
        let panes = SettingsPane.allCases
        let index = (panes.firstIndex(of: pane) ?? 0) + offset
        pane = panes[min(max(0, index), panes.count - 1)]
    }
}

@MainActor
struct SettingsActions {
    let addIgnoredApps: @MainActor () -> Void
    let openAccessibilitySettings: @MainActor () -> Void
    let removeIgnoredApp: @MainActor (String) -> Void
    let setOpensAtLogin: @MainActor (Bool) -> Void
    let setPickAction: @MainActor (PickAction) -> Void
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
    /// Called when another pane comes on show, by the sidebar or by the keyboard.
    let onPaneChange: (SettingsPane) -> Void

    /// Whether the window is the one in use: the system's sidebars grey their selection when it is not.
    @Environment(\.controlActiveState) private var controlActiveState

    /// Lines the header up with the boxes of the form.
    private static let headerInset: CGFloat = 20
    /// Room for six apps: the list scrolls past that, so the window keeps its height however many there are.
    private static let ignoredAppsHeight: CGFloat = 170
    private static let paneWidth: CGFloat = 490
    /// The same for every row, so the names line up whatever the width of each symbol.
    private static let sidebarIconWidth: CGFloat = 22
    private static let sidebarInset: CGFloat = 10
    /// Inside a row, on each side of its symbol and name.
    private static let sidebarRowInset: CGFloat = 8
    private static let sidebarRowSpacing: CGFloat = 2
    private static let sidebarTopInset: CGFloat = 20

    var body: some View {
        // Not a NavigationSplitView: its divider can be dragged and its sidebar collapsed whatever widths it is given,
        // and a collapsed sidebar leaves no sign of the other panes.
        HStack(spacing: 0) {
            sidebar
            Divider()
                .ignoresSafeArea()
            selectedPane
        }
        // The window takes this height: the sidebar alone fills whatever it is given and would set none.
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: state.pane) { _, pane in
            onPaneChange(pane)
        }
    }

    /// Drawn here and not a List: as wide as its longest name, whatever the language, where a List cuts the name to
    /// the width it is given.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Self.sidebarRowSpacing) {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                sidebarRow(pane)
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
    private var selectedPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.pane.title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, Self.headerInset)
                .accessibilityAddTraits(.isHeader)
            // Every pane is laid out at its tallest, unseen, under the selected one: the window is as tall as the
            // tallest pane can get and keeps that height whatever the pane and whatever it shows, as the sidebar is
            // as wide as its longest name. A window that changes size with a setting moves what the user is on.
            ZStack(alignment: .topLeading) {
                ForEach(SettingsPane.allCases, id: \.self) { pane in
                    // Hidden and not transparent: a transparent control still takes the keyboard focus, and would
                    // be switched or typed into unseen.
                    content(of: pane, atItsTallest: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                }
                content(of: state.pane, atItsTallest: false)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Self.paneWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `atItsTallest`: with everything the pane can show, for the copy that only gives the window its height.
    @ViewBuilder
    private func content(of pane: SettingsPane, atItsTallest: Bool) -> some View {
        switch pane {
        case .general:
            general(showsAccessibilityNotice: atItsTallest || isAccessibilityNoticeDue)
        case .privacy:
            privacy
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Never Copy From")
                .font(.headline)
            Text("What you copy from these apps is not kept in the history.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List(
                state.ignoredApps,
                selection: Binding(get: { state.selectedIgnoredAppID }, set: { state.selectedIgnoredAppID = $0 })
            ) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: Self.ignoredAppsHeight)
            .onDeleteCommand(perform: removeSelectedIgnoredApp)
            HStack(spacing: 12) {
                Button(action: actions.addIgnoredApps) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Apps…")
                Button(action: removeSelectedIgnoredApp) {
                    Image(systemName: "minus")
                }
                .accessibilityLabel("Remove App")
                .disabled(state.selectedIgnoredAppID == nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(Self.headerInset)
    }

    private func removeSelectedIgnoredApp() {
        guard let bundleID = state.selectedIgnoredAppID else {
            return
        }
        state.selectedIgnoredAppID = nil
        actions.removeIgnoredApp(bundleID)
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        let isSelected = state.pane == pane
        // As the system's sidebars: the selection colour only while the window is the one in use, with the text
        // colour the system pairs with it (white is not readable on every accent colour).
        let isEmphasized = isSelected && controlActiveState == .key
        let selectedBackground = isEmphasized
            ? Color(nsColor: .selectedContentBackgroundColor)
            : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        let background = isSelected
            ? selectedBackground
            : Color.clear
        let foreground = isEmphasized
            ? Color(nsColor: .alternateSelectedControlTextColor)
            : Color.primary
        let traits: AccessibilityTraits = isSelected
            ? .isSelected
            : []
        return Button {
            state.pane = pane
        } label: {
            HStack(spacing: 6) {
                Image(systemName: pane.symbolName)
                    .frame(width: Self.sidebarIconWidth)
                Text(pane.title)
            }
            // Every row as wide as the widest one.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.sidebarRowInset)
            .padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
    }

    /// "Paste Directly" is chosen and cannot work yet.
    private var isAccessibilityNoticeDue: Bool {
        state.pickAction == .pasteDirectly && !state.isAccessibilityGranted
    }

    private func general(showsAccessibilityNotice: Bool) -> some View {
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
                    if showsAccessibilityNotice {
                        HStack(spacing: PickOptionRow.spacing) {
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

    private func pickOption(_ option: PickAction, title: String, caption: String) -> some View {
        PickOptionRow(title: title, caption: caption, isSelected: state.pickAction == option) {
            actions.setPickAction(option)
        }
    }
}
