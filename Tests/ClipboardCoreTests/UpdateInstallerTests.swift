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

/// Runs the whole install on disk images built here, with apps signed ad hoc: the designated requirement of an
/// ad-hoc signature is its code hash, so only the very app it was read from satisfies it.
struct UpdateInstallerInstallTests {
    let root: URL
    let installed: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpdateInstallerTests-\(UUID().uuidString)", isDirectory: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        installed = try Self.makeApp(version: "1.0.0", in: applications)
    }

    @Test func aSignedImageOfTheExpectedVersionReplacesTheApp() async throws {
        let new = try Self.makeApp(version: "1.2.0", in: folder("new"))
        let image = try Self.makeDiskImage(containing: new, in: root)
        try await UpdateInstaller.install(
            version: try Self.version("1.2.0"),
            over: installed,
            requirement: try UpdateInstaller.designatedRequirement(of: new),
            download: Self.served(image)
        )
        #expect(try Self.bundleVersion(of: installed) == "1.2.0")
    }

    @Test func anAppSignedOtherwiseIsNotInstalled() async throws {
        // A local build asking to install a release: the signatures differ.
        let new = try Self.makeApp(version: "1.2.0", in: folder("new"))
        let other = try Self.makeApp(version: "1.2.0", in: folder("other"), marker: "other")
        let image = try Self.makeDiskImage(containing: new, in: root)
        await #expect(throws: UpdateInstallError.signature) {
            try await UpdateInstaller.install(
                version: try Self.version("1.2.0"),
                over: installed,
                requirement: try UpdateInstaller.designatedRequirement(of: other),
                download: Self.served(image)
            )
        }
        #expect(try Self.bundleVersion(of: installed) == "1.0.0")
    }

    @Test func anotherVersionThanTheOneOfferedIsNotInstalled() async throws {
        // An older release, signed alike, served in place of the new one.
        let older = try Self.makeApp(version: "1.1.0", in: folder("older"))
        let image = try Self.makeDiskImage(containing: older, in: root)
        await #expect(throws: UpdateInstallError.wrongVersion) {
            try await UpdateInstaller.install(
                version: try Self.version("1.2.0"),
                over: installed,
                requirement: try UpdateInstaller.designatedRequirement(of: older),
                download: Self.served(image)
            )
        }
        #expect(try Self.bundleVersion(of: installed) == "1.0.0")
    }

    @Test func aMissingAssetIsADownloadFailure() async throws {
        // The release exists while its disk image is still being uploaded: GitHub answers 404.
        let new = try Self.makeApp(version: "1.2.0", in: folder("new"))
        let image = try Self.makeDiskImage(containing: new, in: root)
        await #expect(throws: UpdateInstallError.download) {
            try await UpdateInstaller.install(
                version: try Self.version("1.2.0"),
                over: installed,
                requirement: try UpdateInstaller.designatedRequirement(of: new),
                download: Self.served(image, status: 404)
            )
        }
        #expect(try Self.bundleVersion(of: installed) == "1.0.0")
    }

    @Test func anImageWithoutTheAppIsRefused() async throws {
        let empty = try folder("empty")
        let image = root.appendingPathComponent("empty.dmg")
        try Self.run("/usr/bin/hdiutil", "create", "-quiet", "-srcfolder", empty.path, "-format", "UDZO", image.path)
        await #expect(throws: UpdateInstallError.missingApp) {
            try await UpdateInstaller.install(
                version: try Self.version("1.2.0"),
                over: installed,
                requirement: try UpdateInstaller.designatedRequirement(of: installed),
                download: Self.served(image)
            )
        }
        #expect(try Self.bundleVersion(of: installed) == "1.0.0")
    }

    @Test func aFolderThatCannotBeWrittenFailsBeforeDownloading() async throws {
        // A standard user with the app in /Applications: nothing is downloaded that could not be installed.
        let applications = installed.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: applications.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path)
        }
        let downloaded = Flag()
        await #expect(throws: UpdateInstallError.cannotReplace) {
            try await UpdateInstaller.install(
                version: try Self.version("1.2.0"),
                over: installed,
                requirement: try UpdateInstaller.designatedRequirement(of: installed),
                download: { _ in
                    downloaded.set()
                    throw URLError(.cancelled)
                }
            )
        }
        #expect(!downloaded.isSet)
    }

    // MARK: fixtures

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool {
            lock.withLock { value }
        }

        func set() {
            lock.withLock { value = true }
        }
    }

    func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func version(_ text: String) throws -> AppVersion {
        try #require(AppVersion(text))
    }

    /// A SimpleClipboard.app whose executable is a copy of /usr/bin/true, signed ad hoc. `marker` changes its
    /// Info.plist, and so its code hash, without changing its version.
    static func makeApp(version: String, in folder: URL, marker: String = "") throws -> URL {
        let app = folder.appendingPathComponent("\(Config.appName).app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"),
            to: macOS.appendingPathComponent(Config.appName)
        )
        let info: [String: String] = [
            "CFBundleIdentifier": Config.bundleID,
            "CFBundleExecutable": Config.appName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "TestMarker": marker,
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try run("/usr/bin/codesign", "--force", "--sign", "-", app.path)
        return app
    }

    static func makeDiskImage(containing app: URL, in folder: URL) throws -> URL {
        let image = folder.appendingPathComponent("\(UUID().uuidString).dmg")
        try run(
            "/usr/bin/hdiutil", "create", "-quiet",
            "-srcfolder", app.deletingLastPathComponent().path,
            "-format", "UDZO",
            image.path
        )
        return image
    }

    /// What `URLSession.download(from:)` gives: a file of its own, which the installer moves.
    static func served(_ file: URL, status: Int = 200) -> @Sendable (URL) async throws -> (URL, URLResponse) {
        { url in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: file, to: copy)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (copy, response)
        }
    }

    static func bundleVersion(of app: URL) throws -> String? {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return plist?["CFBundleShortVersionString"] as? String
    }

    static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "\(tool) \(arguments.joined(separator: " "))")
    }
}
