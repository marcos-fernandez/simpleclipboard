import Foundation

/// Installs a release over the running app: its disk image is downloaded only when the user chooses the update in
/// the menu.
public enum UpdateInstaller {
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
}
