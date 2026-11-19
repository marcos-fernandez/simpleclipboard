import Foundation

/// A release version such as `1.2.0` or `v1.2.0`, compared numerically component by component: missing components
/// count as 0, so `1.0` and `1.0.0` are the same version.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    /// nil unless every component is plain digits: `1.2.0-beta`, `+1` or an empty component are not versions.
    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v")
            ? string.dropFirst()
            : Substring(string)
        var components: [Int] = []
        for part in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part) else {
                return nil
            }
            components.append(value)
        }
        self.components = components
    }

    /// Rebuilt from the parsed numbers, so text from the network never reaches the menu as it came.
    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count
                ? lhs.components[index]
                : 0
            let right = index < rhs.components.count
                ? rhs.components[index]
                : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case available(AppVersion)
    case upToDate
    /// Offline, rate-limited, an unexpected answer: says nothing about whether there is an update.
    case failed

    /// The update to show after this check, given the one shown before: a failed check changes nothing.
    public func availableUpdate(replacing shown: AppVersion?) -> AppVersion? {
        switch self {
        case .available(let version):
            return version
        case .upToDate:
            return nil
        case .failed:
            return shown
        }
    }
}

/// Asks GitHub for the latest release and compares it with the running version. The only network request the app
/// makes: a plain GET, without cookies or cache, that sends nothing about the user.
public enum UpdateCheck {
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Config.updateCheckTimeout
        configuration.timeoutIntervalForResource = Config.updateCheckTimeout
        return URLSession(configuration: configuration)
    }

    /// Whether to check now, given when a check last got an answer (nil: never, or only failures since launch).
    public static func isDue(lastAnswer: Date?, now: Date) -> Bool {
        guard let lastAnswer else {
            return true
        }
        return now.timeIntervalSince(lastAnswer) >= Config.updateCheckInterval
    }

    /// `fetch` is `URLSession.data(from:)` on `Config.latestReleaseAPIURL`; injected so tests never touch the network.
    public static func check(
        currentVersion: String?,
        fetch: @Sendable () async throws -> (Data, URLResponse)
    ) async -> UpdateCheckResult {
        guard let current = currentVersion.flatMap(AppVersion.init),
              case let (data, response)? = try? await fetch(),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = latestVersion(fromReleaseJSON: data) else {
            return .failed
        }
        return latest > current
            ? .available(latest)
            : .upToDate
    }

    /// The `tag_name` of a GitHub release (`GET /repos/{owner}/{repo}/releases/latest`).
    static func latestVersion(fromReleaseJSON data: Data) -> AppVersion? {
        struct Release: Decodable {
            let tag_name: String
        }
        return (try? JSONDecoder().decode(Release.self, from: data))
            .flatMap { AppVersion($0.tag_name) }
    }
}
