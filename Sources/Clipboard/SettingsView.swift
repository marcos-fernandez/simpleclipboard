import AppKit
import ClipboardCore
import Observation
import SwiftUI

/// The panes of the settings window, in the order of the sidebar: alphabetical. Only the ones with something in them:
/// a pane is added here together with its content.
enum SettingsPane: CaseIterable {
    case about
    case general
    case privacy

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .privacy:
            return "hand.raised"
        case .about:
            return "info.circle"
        }
    }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .privacy:
            return "Privacy"
        case .about:
            return "About"
        }
    }

    /// The title of the window while this pane is on show. The pane, as in any settings window, after the app's
    /// name: the app has no Dock icon and no place in the app switcher, so in Mission Control the title is all that
    /// says whose window it is.
    var windowTitle: String {
        "\(Config.appName) — \(title)"
    }
}

/// The lists of apps of the Privacy pane, in the order it shows them. An app shows in one of them only.
typealias PrivacyList = PrivacyLists.Kind

extension PrivacyLists.Kind {
    var caption: String {
        switch self {
        case .ignored:
            return "What you copy from these apps is not kept in the history."
        case .secured:
            return "What you copy from these apps is kept hidden and never leaves this Mac."
        }
    }

    var title: String {
        switch self {
        case .ignored:
            return "Ignored Apps"
        case .secured:
            return "Secured Apps"
        }
    }
}

/// An app of a list of the Privacy pane, as the list shows it.
struct AppRow: Identifiable {
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
    var apps: [PrivacyList: [AppRow]] = [:]
    /// General and not the first row of the sidebar: About is first only by its name.
    var pane = SettingsPane.general
    /// The app selected in each list of the Privacy pane, by bundle identifier.
    var selectedAppID: [PrivacyList: String] = [:]
    var opensAtLogin = false
    var pickAction = PickAction.pasteDirectly
    var securedLifetime = Config.concealedLifetime
    var isAccessibilityGranted = false
    /// Whether the menu-bar item is on show, not the saved setting.
    var showsMenuBarIcon = true
    /// False when ⇧⌘V could not be registered: the icon then stays whatever the setting.
    var canHideMenuBarIcon = true

    /// The pane `offset` rows away in the sidebar, stopping at its ends.
    func movePane(by offset: Int) {
        let panes = SettingsPane.allCases
        let index = (panes.firstIndex(of: pane) ?? 0) + offset
        pane = panes[min(max(0, index), panes.count - 1)]
    }
}

@MainActor
struct SettingsActions {
    let addApps: @MainActor (PrivacyList) -> Void
    let openAccessibilitySettings: @MainActor () -> Void
    let removeApp: @MainActor (String, PrivacyList) -> Void
    let resetAllSettings: @MainActor () -> Void
    let resetPrivacy: @MainActor () -> Void
    let setOpensAtLogin: @MainActor (Bool) -> Void
    let setPickAction: @MainActor (PickAction) -> Void
    let setSecuredLifetime: @MainActor (TimeInterval) -> Void
    let setShowsMenuBarIcon: @MainActor (Bool) -> Void
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
    @Bindable var state: SettingsState
    let actions: SettingsActions
    /// Called when another pane comes on show, by the sidebar or by the keyboard.
    let onPaneChange: (SettingsPane) -> Void

    /// Whether the window is the one in use: the system's sidebars grey their selection when it is not.
    @Environment(\.controlActiveState) private var controlActiveState

    private static let aboutIconSize: CGFloat = 96
    /// Between the version, the people and the link.
    private static let aboutSectionSpacing: CGFloat = 14
    private static let aboutWordSpacing: CGFloat = 4
    /// The bundle's version, which does not change while the app runs.
    private static let versionText = AboutInfo.versionText(
        shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    )
    /// Lines the header up with the boxes of the form.
    private static let headerInset: CGFloat = 20
    /// Room for four apps: a list scrolls past that, so the window keeps its height however many there are.
    private static let appListHeight: CGFloat = 115
    /// Between the options of a section that are controls of their own, as the two ways of pasting.
    private static let optionSpacing: CGFloat = 16
    private static let paneWidth: CGFloat = 490
    /// Between the sections of a pane.
    private static let sectionSpacing: CGFloat = 24
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
        case .about:
            about
        }
    }

    private var about: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Self.aboutIconSize, height: Self.aboutIconSize)
                // The name under it already says what it is.
                .accessibilityHidden(true)
            Text(Config.appName)
                .font(.title2)
                .fontWeight(.semibold)
            // Selectable, to be pasted into a bug report.
            Text(Self.versionText)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: Self.aboutWordSpacing) {
                Text("Made by")
                    .foregroundStyle(.secondary)
                Link(Config.author.name, destination: Config.author.profileURL)
            }
            .padding(.top, Self.aboutSectionSpacing)
            Text("Contributors")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, Self.aboutSectionSpacing)
            ForEach(Config.contributors, id: \.name) { contributor in
                Link(contributor.name, destination: contributor.profileURL)
            }
            // Not the address itself: it carries the name of one of them.
            Link("View on GitHub", destination: Config.repositoryURL)
                .padding(.top, Self.aboutSectionSpacing)
        }
        .frame(maxWidth: .infinity)
        .padding(Self.headerInset)
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            ForEach(PrivacyList.allCases, id: \.self) { list in
                VStack(alignment: .leading, spacing: Self.optionSpacing) {
                    appList(list)
                    if list == .secured {
                        securedLifetimePicker
                    }
                }
            }
            Button("Reset to Defaults…", action: actions.resetPrivacy)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(Self.headerInset)
    }

    private func appList(_ list: PrivacyList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(list.title)
                .font(.headline)
            Text(list.caption)
                .font(.callout)
                .foregroundStyle(.secondary)
            List(state.apps[list] ?? [], selection: $state.selectedAppID[list]) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: Self.appListHeight)
            .onDeleteCommand {
                removeSelectedApp(from: list)
            }
            HStack(spacing: 12) {
                Button {
                    actions.addApps(list)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add to \(list.title)…")
                Button {
                    removeSelectedApp(from: list)
                } label: {
                    Image(systemName: "minus")
                }
                .accessibilityLabel("Remove from \(list.title)")
                .disabled(state.selectedAppID[list] == nil)
            }
            .buttonStyle(.borderless)
        }
    }

    private var securedLifetimePicker: some View {
        Picker(
            "Keep For",
            selection: Binding(get: { state.securedLifetime }, set: { actions.setSecuredLifetime($0) })
        ) {
            ForEach(ConcealedLifetime.choices, id: \.self) { lifetime in
                Text(ConcealedLifetime.title(of: lifetime))
                    .tag(lifetime)
            }
        }
        .fixedSize()
    }

    private func removeSelectedApp(from list: PrivacyList) {
        guard let bundleID = state.selectedAppID[list] else {
            return
        }
        state.selectedAppID[list] = nil
        actions.removeApp(bundleID, list)
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
                // A grouped form draws the second text of the label under the first, in the secondary style.
                Toggle(isOn: Binding(get: { state.showsMenuBarIcon }, set: { actions.setShowsMenuBarIcon($0) })) {
                    Text("Show in Menu Bar")
                    Text(
                        state.canHideMenuBarIcon
                            ? "When it is off, the menu opens from the wrench next to the search field of the history."
                            : "⇧⌘V could not be set up, and nothing else would open the app: the icon stays."
                    )
                }
                .disabled(!state.canHideMenuBarIcon)
            }
            Section("Paste Items") {
                VStack(alignment: .leading, spacing: Self.optionSpacing) {
                    // The notice belongs to the first option: closer to it than the next option is.
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
                    }
                    pickOption(
                        .copyToClipboard,
                        title: "Copy to Clipboard",
                        caption: "The item goes to the clipboard and you paste it manually."
                    )
                }
            }
            // A section of its own: the button stands apart from the settings it resets.
            Section {
                Button("Reset All Settings…", action: actions.resetAllSettings)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
