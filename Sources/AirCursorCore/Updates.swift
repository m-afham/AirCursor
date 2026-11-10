import CryptoKit
import Foundation

/// A dotted release version such as "1.0.4" or tag "v1.2". Pre-release suffixes
/// ("-beta.1", "+build") are ignored, so "1.1.0-beta" compares equal to "1.1.0".
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) { s = String(s[..<cut]) }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let n = Int(part), n >= 0 else { return nil }
            numbers.append(n)
        }
        // Trailing zeros don't matter: 1.2 == 1.2.0.
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        components = numbers
    }

    public var description: String {
        var parts = components
        while parts.count < 3 { parts.append(0) }
        return parts.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for i in 0..<max(lhs.components.count, rhs.components.count) {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// A file attached to a GitHub release.
public struct ReleaseAsset: Decodable, Equatable, Sendable {
    public var name: String
    public var url: URL
    public var size: Int

    enum CodingKeys: String, CodingKey { case name, url = "browser_download_url", size }

    public init(name: String, url: URL, size: Int) {
        self.name = name
        self.url = url
        self.size = size
    }
}

/// The parts of GitHub's "latest release" response that AirCursor uses.
public struct ReleaseInfo: Decodable, Equatable, Sendable {
    public var tagName: String
    public var name: String?
    public var body: String?
    public var htmlURL: URL
    public var draft: Bool
    public var prerelease: Bool
    public var assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body, htmlURL = "html_url", draft, prerelease, assets
    }

    public init(tagName: String, name: String? = nil, body: String? = nil,
                htmlURL: URL, draft: Bool = false, prerelease: Bool = false, assets: [ReleaseAsset] = []) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    /// The version as the release workflow writes it in file names ("v1.0.5" → "1.0.5").
    public var fileVersion: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// The versioned app archive and its signature, e.g. AirCursor-1.0.5.zip(.sig).
    /// Versioned names, not AirCursor.zip, so a newer release can't swap in mid-install.
    public var archive: ReleaseAsset? { assets.first { $0.name == "AirCursor-\(fileVersion).zip" } }
    public var archiveSignature: ReleaseAsset? { assets.first { $0.name == "AirCursor-\(fileVersion).zip.sig" } }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try c.decode(String.self, forKey: .tagName)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try c.decode(URL.self, forKey: .htmlURL)
        draft = (try? c.decodeIfPresent(Bool.self, forKey: .draft)) ?? false
        prerelease = (try? c.decodeIfPresent(Bool.self, forKey: .prerelease)) ?? false
        assets = (try? c.decodeIfPresent([ReleaseAsset].self, forKey: .assets)) ?? []
    }

    public var version: AppVersion? { AppVersion(tagName) }
}

/// A newer release the user hasn't dismissed.
public struct AvailableUpdate: Equatable, Sendable {
    public var version: AppVersion
    public var release: ReleaseInfo

    public static func == (lhs: AvailableUpdate, rhs: AvailableUpdate) -> Bool {
        lhs.version == rhs.version && lhs.release == rhs.release
    }
}

/// Ed25519 signatures on release archives. The release workflow signs each
/// AirCursor-x.y.z.zip with a private key kept only in the repository's secrets; the app
/// holds the public key and installs nothing whose signature doesn't verify.
public enum UpdateSignature {
    /// Archives larger than this are refused before they're read into memory.
    public static let maxArchiveBytes = 200 * 1024 * 1024

    /// `signatureText` is the .sig file: the 64-byte signature, base64-encoded.
    public static func isValid(signatureText: String, for data: Data, publicKeyBase64: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              signature.count == 64 else { return false }
        return key.isValidSignature(signature, for: data)
    }
}

/// Turns GitHub's generated release notes into short plain lines for the update window:
/// drops headings and the "Full Changelog" link, and the "by @user in <url>" suffixes.
public enum ReleaseNotes {
    public static func summary(from body: String?, maxLines: Int = 8) -> [String] {
        guard let body else { return [] }
        var lines: [String] = []
        for raw in body.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("**Full Changelog**")
                || line.hasPrefix("<!--") { continue }
            for bullet in ["* ", "- ", "+ "] where line.hasPrefix(bullet) {
                line.removeFirst(bullet.count)
            }
            if let r = line.range(of: #"\s+by @[A-Za-z0-9-]+(\[bot\])?\s+in\s+\S+$"#, options: .regularExpression) {
                line.removeSubrange(r)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { lines.append(line) }
            if lines.count == maxLines { break }
        }
        return lines
    }
}

public enum UpdatePolicy {
    /// Automatic checks run at most this often.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    public static func isCheckDue(lastCheck: Date?, now: Date, interval: TimeInterval = checkInterval) -> Bool {
        guard let lastCheck else { return true }
        // A clock moved backwards shouldn't block checks forever.
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// The update to offer, if `release` is newer than `current`. Drafts and pre-releases
    /// are never offered. A version the user chose to skip is offered only when
    /// `includeSkipped` is true (a manual "Check for updates").
    public static func update(current: String, release: ReleaseInfo,
                              skippedVersion: String?, includeSkipped: Bool = false) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let latest = release.version, let installed = AppVersion(current),
              latest > installed else { return nil }
        if !includeSkipped, let skippedVersion, let skipped = AppVersion(skippedVersion), skipped == latest {
            return nil
        }
        return AvailableUpdate(version: latest, release: release)
    }
}
