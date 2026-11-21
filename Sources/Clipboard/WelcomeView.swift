import ClipboardCore
import Observation
import SwiftUI

/// What a new install is asked at its first launch.
@MainActor
@Observable
final class WelcomeState {
    var opensAtLogin = true
    /// Copying is what the welcome starts on: it needs no permission, where pasting brings the system's request for
    /// the Accessibility one.
    var pickAction = PickAction.copyToClipboard
}

/// What the welcome says and asks, shown inside its alert under the title.
struct WelcomeView: View {
    @Bindable var state: WelcomeState

    @Environment(\.colorScheme) private var colorScheme

    private static let boxCornerRadius: CGFloat = 8
    private static let boxInset: CGFloat = 12
    /// Between a heading and what it heads.
    private static let headingSpacing: CGFloat = 8
    /// Between the options of a section that are controls of their own.
    private static let optionSpacing: CGFloat = 16
    /// Between the sections.
    private static let sectionSpacing: CGFloat = 24
    /// Wider than an alert is on its own: room for the longer explanation of the options on one line.
    private static let width: CGFloat = 390

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            VStack(alignment: .leading, spacing: Self.optionSpacing) {
                Text("Welcome to \(Config.appName) 👋")
                    .font(.title)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Press ⇧⌘V anywhere to open the history.")
            }
            VStack(alignment: .leading, spacing: Self.headingSpacing) {
                // Asked, where the settings name the section "Paste Items": here it is a question to answer.
                Text("How do you want to paste items?")
                    .font(.headline)
                // Word for word and in the order of the settings: it is the same choice.
                VStack(alignment: .leading, spacing: Self.optionSpacing) {
                    option(
                        .pasteDirectly,
                        title: "Paste Directly",
                        caption: "The item is pasted into the app you are using."
                    )
                    option(
                        .copyToClipboard,
                        title: "Copy to Clipboard",
                        caption: "The item goes to the clipboard and you paste it manually."
                    )
                }
                .modifier(box)
            }
            // A switch at the end of its row, in a box of its own, as in the settings.
            HStack {
                Text("Open at Login")
                Spacer()
                Toggle("Open at Login", isOn: $state.opensAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .modifier(box)
        }
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Darker than the alert around it, to set a choice apart: the reverse of the settings, whose boxes are lighter
    /// than their page.
    private var box: Box {
        Box(
            color: Color.black.opacity(
                colorScheme == .dark
                    ? 0.25
                    : 0.06
            )
        )
    }

    private struct Box: ViewModifier {
        let color: Color

        func body(content: Content) -> some View {
            content
                .padding(WelcomeView.boxInset)
                .background(color, in: RoundedRectangle(cornerRadius: WelcomeView.boxCornerRadius))
        }
    }

    /// The view at its own size, as an alert takes what goes under its text.
    @MainActor
    static func accessoryView(state: WelcomeState) -> NSView {
        let view = NSHostingView(rootView: WelcomeView(state: state))
        view.frame.size = view.fittingSize
        return view
    }

    private func option(_ option: PickAction, title: String, caption: String) -> some View {
        PickOptionRow(title: title, caption: caption, isSelected: state.pickAction == option) {
            state.pickAction = option
        }
    }
}
