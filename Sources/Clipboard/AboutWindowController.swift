import AppKit
import ClipboardCore
import SwiftUI

struct AboutView: View {
    let versionText: String

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(Config.appName)
                .font(.title2.bold())
            Text(versionText)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("By \(Config.authorName)")
                .padding(.top, 8)
            Link(Config.repositoryURL.absoluteString, destination: Config.repositoryURL)
        }
        .padding(24)
        .frame(width: 340)
    }
}

/// Not AppKit's standard About panel: in this app it would neither close with ⌘W or Esc nor hide the app once closed.
@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private let window: ClosableWindow

    override init() {
        window = ClosableWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.delegate = self
        window.title = "About \(Config.appName)"
        window.isReleasedWhenClosed = false
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        window.contentViewController = NSHostingController(
            rootView: AboutView(versionText: AboutInfo.versionText(shortVersion: shortVersion))
        )
    }

    func show() {
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// With no window left the app would stay active and unseen: the next ⇧⌘V has to see the user's app in front.
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }
}
