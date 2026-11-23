import Foundation
import Security

/// Why an update was not installed. In every case the installed app is left as it was.
public enum UpdateInstallError: Error, Equatable, Sendable {
    /// The app or its folder cannot be written by this user, such as a standard user's /Applications.
    case cannotReplace
    /// Offline, or GitHub did not answer 200 (a release whose disk image is still being uploaded answers 404).
    case download
    case mount
    /// The disk image has no SimpleClipboard.app at its top.
    case missingApp
    /// Not signed like the running app: a local build asking for a release, or an image that is not a release.
    case signature
    /// Not the version that was offered, such as an older release signed alike.
    case wrongVersion
}

/// Installs a release over the running app: its disk image is downloaded only when the user chooses the update in
/// the menu.
public enum UpdateInstaller {
    /// The designated requirement of the running app, as text: what a downloaded app must satisfy to replace it.
    /// For a release, its signing certificate; for an ad-hoc build, its own code hash, which no release matches.
    public static func runningAppRequirement() throws -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess,
              let code,
              let staticCode = staticCode(of: code) else {
            throw UpdateInstallError.signature
        }
        return try requirementText(of: staticCode)
    }

    static func designatedRequirement(of app: URL) throws -> String {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateInstallError.signature
        }
        return try requirementText(of: staticCode)
    }

    /// Downloads the disk image of `version`, checks the app in it and puts it in place of `installedApp`. The app
    /// is replaced in one rename, from a copy on the same volume, so it is never left half written; the running
    /// process keeps the old one until it quits.
    /// `requirement`: as `runningAppRequirement()`. `download`: `URLSession.download(from:)`, injected so tests never
    /// touch the network.
    public static func install(
        version: AppVersion,
        over installedApp: URL,
        requirement: String,
        download: @Sendable (URL) async throws -> (URL, URLResponse)
    ) async throws {
        let fileManager = FileManager.default
        // Before downloading: nothing is fetched that could not be installed.
        guard fileManager.isWritableFile(atPath: installedApp.deletingLastPathComponent().path),
              fileManager.isWritableFile(atPath: installedApp.path) else {
            throw UpdateInstallError.cannotReplace
        }
        let work: URL
        do {
            work = try fileManager.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: installedApp,
                create: true
            )
        } catch {
            throw UpdateInstallError.cannotReplace
        }
        defer {
            try? fileManager.removeItem(at: work)
        }

        let image = work.appendingPathComponent("update.dmg")
        do {
            let (file, response) = try await download(diskImageURL(for: version))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                try? fileManager.removeItem(at: file)
                throw UpdateInstallError.download
            }
            try fileManager.moveItem(at: file, to: image)
        } catch {
            throw UpdateInstallError.download
        }

        let mountPoint = work.appendingPathComponent("mount", isDirectory: true)
        guard await run("/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", "-noautoopen", "-quiet",
                        "-mountpoint", mountPoint.path, image.path) else {
            throw UpdateInstallError.mount
        }
        let copy = work.appendingPathComponent("\(Config.appName).app", isDirectory: true)
        let mountedApp = mountPoint.appendingPathComponent("\(Config.appName).app", isDirectory: true)
        let hasApp = fileManager.fileExists(atPath: mountedApp.path)
        // ditto keeps the signature as it is. Copied out so the image can be detached before anything else.
        let copied = hasApp
            ? await run("/usr/bin/ditto", mountedApp.path, copy.path)
            : false
        _ = await run("/usr/bin/hdiutil", "detach", "-force", "-quiet", mountPoint.path)
        guard hasApp else {
            throw UpdateInstallError.missingApp
        }
        guard copied else {
            throw UpdateInstallError.mount
        }

        try checkSignature(of: copy, requirement: requirement)
        guard bundleVersion(of: copy) == version else {
            throw UpdateInstallError.wrongVersion
        }
        do {
            _ = try fileManager.replaceItemAt(installedApp, withItemAt: copy)
        } catch {
            throw UpdateInstallError.cannotReplace
        }
    }

    /// The disk image that release.yml publishes for `version`. Built here, never taken from the API's answer: only
    /// the version comes from the network, and it is rebuilt from its numbers.
    public static func diskImageURL(for version: AppVersion) -> URL {
        Config.releaseDownloadBaseURL
            .appendingPathComponent("v\(version)")
            .appendingPathComponent("\(Config.appName)-\(version)-universal.dmg")
    }

    /// The arguments of `/bin/sh` that open `app` once the process `pid` has quit: the new version cannot start while
    /// the old one still runs, as macOS would only bring the old one forward. The pid and the path are passed as
    /// arguments, not written into the script, so no path can change what it runs.
    public static func restartArguments(pid: Int32, app: URL) -> [String] {
        [
            "-c",
            #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open "$2""#,
            "sh",
            String(pid),
            app.path,
        ]
    }

    private static func staticCode(of code: SecCode) -> SecStaticCode? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess else {
            return nil
        }
        return staticCode
    }

    private static func requirementText(of staticCode: SecStaticCode) throws -> String {
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
              let text else {
            throw UpdateInstallError.signature
        }
        return text as String
    }

    /// Every architecture and nested code, strictly: a universal app whose Intel half was changed must not pass.
    private static func checkSignature(of app: URL, requirement text: String) throws {
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw UpdateInstallError.signature
        }
    }

    private static func bundleVersion(of app: URL) -> AppVersion? {
        (Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init)
    }

    /// Runs `tool` with `arguments`, never through a shell; true when it exits with 0.
    private static func run(_ tool: String, _ arguments: String...) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            // Waited for on its handler, not with waitUntilExit, which would hold a thread of the concurrency pool.
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
    }
}
