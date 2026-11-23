import Foundation
import Testing
@testable import ClipboardCore

struct UpdateInstallerTests {
    // MARK: what to download and how to restart

    @Test func theDiskImageURLIsBuiltFromTheVersion() throws {
        // The name that release.yml publishes; built here, so nothing from the API but the version is used.
        let version = try #require(AppVersion("v1.10.0"))
        #expect(UpdateInstaller.diskImageURL(for: version).absoluteString
            == "https://github.com/marcos-fernandez/simpleclipboard/releases/download/v1.10.0/SimpleClipboard-1.10.0-universal.dmg")
    }

    @Test func theRestartPassesThePathAsAnArgumentNotInTheScript() {
        // A path with quotes or a semicolon must not become part of the shell script.
        let app = URL(fileURLWithPath: "/Applications/Simple \"Clip\"; rm.app")
        let arguments = UpdateInstaller.restartArguments(pid: 42, app: app)
        #expect(arguments.first == "-c")
        #expect(!arguments[1].contains(app.path))
        #expect(Array(arguments.suffix(2)) == ["42", app.path])
    }
}
