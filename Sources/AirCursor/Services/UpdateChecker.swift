import Foundation
import AirCursorCore

/// Asks GitHub for the latest AirCursor release. These are AirCursor's only network requests:
/// one anonymous GET of public release info, at most once a day (or when the user clicks
/// "Check Now"), and, only when the user clicks "Install & Relaunch", downloading that
/// release's archive and signature. No identifiers, cookies, cache or usage data are sent
/// or stored. GitHub's API requires a User-Agent, which carries only "AirCursor/<version>".
enum UpdateChecker {
    static let repository = "m-afham/AirCursor"
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    /// Always the newest build: the release workflow attaches a stable AirCursor.zip.
    static let downloadURL = URL(string: "https://github.com/\(repository)/releases/latest/download/AirCursor.zip")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    enum CheckError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): "GitHub answered with status \(code)."
            }
        }
    }

    /// Testing only: a local release JSON file used instead of GitHub
    /// (`open AirCursor.app --env AIRCURSOR_UPDATE_TEST_RELEASE=/path/release.json`).
    /// Its assets may be file URLs; signatures are still verified with the real key.
    static let testRelease: URL? = ProcessInfo.processInfo.environment["AIRCURSOR_UPDATE_TEST_RELEASE"]
        .map { URL(fileURLWithPath: $0) }

    /// No cookies, cache or credentials: every request is anonymous.
    static func session(timeout: TimeInterval = 15) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = 600
        config.httpAdditionalHeaders = ["User-Agent": "AirCursor/\(currentVersion)"]
        return URLSession(configuration: config)
    }

    static func fetchLatestRelease() async throws -> ReleaseInfo {
        if let testRelease {
            return try JSONDecoder().decode(ReleaseInfo.self, from: Data(contentsOf: testRelease))
        }
        let session = session()
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CheckError.badResponse(status) }
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }
}
