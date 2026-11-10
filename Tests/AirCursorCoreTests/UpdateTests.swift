import CryptoKit
import XCTest
@testable import AirCursorCore

final class UpdateTests: XCTestCase {
    private let page = URL(string: "https://github.com/m-afham/AirCursor/releases/tag/v1.0.5")!

    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> ReleaseInfo {
        ReleaseInfo(tagName: tag, htmlURL: page, draft: draft, prerelease: prerelease)
    }

    func testParsesVersionsAndTags() {
        XCTAssertEqual(AppVersion("v1.0.4")?.description, "1.0.4")
        XCTAssertEqual(AppVersion("1.2")?.description, "1.2.0")
        XCTAssertEqual(AppVersion(" 2.0.1-beta.3 ")?.description, "2.0.1")
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1.-2"))
    }

    func testComparesNumericallyNotAlphabetically() throws {
        let v = { (s: String) in AppVersion(s)! }
        XCTAssertLessThan(v("1.0.9"), v("1.0.10"))
        XCTAssertLessThan(v("1.9"), v("1.10"))
        XCTAssertLessThan(v("1.0.4"), v("2.0.0"))
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertFalse(v("1.2.0") < v("1.2"))
    }

    func testOffersOnlyNewerFinalReleases() {
        XCTAssertEqual(UpdatePolicy.update(current: "1.0.4", release: release("v1.0.5"), skippedVersion: nil)?.version.description, "1.0.5")
        XCTAssertNil(UpdatePolicy.update(current: "1.0.4", release: release("v1.0.4"), skippedVersion: nil))
        XCTAssertNil(UpdatePolicy.update(current: "1.1.0", release: release("v1.0.9"), skippedVersion: nil))
        XCTAssertNil(UpdatePolicy.update(current: "1.0.4", release: release("v1.0.5", draft: true), skippedVersion: nil))
        XCTAssertNil(UpdatePolicy.update(current: "1.0.4", release: release("v1.0.5", prerelease: true), skippedVersion: nil))
        XCTAssertNil(UpdatePolicy.update(current: "dev", release: release("v1.0.5"), skippedVersion: nil))
        XCTAssertNil(UpdatePolicy.update(current: "1.0.4", release: release("nightly"), skippedVersion: nil))
    }

    func testSkippedVersionIsQuietUntilANewerOneOrAManualCheck() {
        XCTAssertNil(UpdatePolicy.update(current: "1.0.4", release: release("v1.0.5"), skippedVersion: "1.0.5"))
        XCTAssertNotNil(UpdatePolicy.update(current: "1.0.4", release: release("v1.0.5"), skippedVersion: "1.0.5", includeSkipped: true))
        XCTAssertNotNil(UpdatePolicy.update(current: "1.0.4", release: release("v1.0.6"), skippedVersion: "1.0.5"))
    }

    func testCheckIsDueOncePerInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdatePolicy.isCheckDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-UpdatePolicy.checkInterval), now: now))
        XCTAssertTrue(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(3600), now: now), "a clock set back must not block checks")
    }

    func testDecodesGitHubLatestReleaseResponse() throws {
        let json = """
        {"url":"https://api.github.com/repos/m-afham/AirCursor/releases/1","tag_name":"v1.0.5",
         "name":"AirCursor 1.0.5","body":"## What's Changed\\n* Fix things","draft":false,"prerelease":false,
         "html_url":"https://github.com/m-afham/AirCursor/releases/tag/v1.0.5","assets":[]}
        """
        let info = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.tagName, "v1.0.5")
        XCTAssertEqual(info.name, "AirCursor 1.0.5")
        XCTAssertEqual(info.htmlURL, page)
        XCTAssertEqual(info.version?.description, "1.0.5")
        XCTAssertFalse(info.draft)
    }

    func testReleaseNotesBecomePlainLines() {
        let body = """
        ## What's Changed
        * Give slow-starting AirPods time to stream motion (#5) by @m-afham in https://github.com/m-afham/AirCursor/pull/7
        * Add update alerts by @dependabot[bot] in https://github.com/m-afham/AirCursor/pull/8

        ## New Contributors
        - Better tilt thresholds

        **Full Changelog**: https://github.com/m-afham/AirCursor/compare/v1.0.4...v1.0.5
        """
        XCTAssertEqual(ReleaseNotes.summary(from: body), [
            "Give slow-starting AirPods time to stream motion (#5)",
            "Add update alerts",
            "Better tilt thresholds",
        ])
        XCTAssertEqual(ReleaseNotes.summary(from: body, maxLines: 1).count, 1)
        XCTAssertEqual(ReleaseNotes.summary(from: nil), [])
    }

    func testFindsVersionedArchiveAndSignature() throws {
        let json = """
        {"tag_name":"v1.0.5","html_url":"https://github.com/m-afham/AirCursor/releases/tag/v1.0.5","assets":[
          {"name":"AirCursor.zip","browser_download_url":"https://example.com/AirCursor.zip","size":10},
          {"name":"AirCursor-1.0.5.zip","browser_download_url":"https://example.com/AirCursor-1.0.5.zip","size":10},
          {"name":"AirCursor-1.0.5.zip.sig","browser_download_url":"https://example.com/AirCursor-1.0.5.zip.sig","size":89}]}
        """
        let info = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.archive?.name, "AirCursor-1.0.5.zip")
        XCTAssertEqual(info.archiveSignature?.name, "AirCursor-1.0.5.zip.sig")
        XCTAssertEqual(info.archive?.size, 10)

        let unsigned = ReleaseInfo(tagName: "v1.0.4", htmlURL: page, assets: [
            ReleaseAsset(name: "AirCursor-1.0.4.zip", url: page, size: 1),
        ])
        XCTAssertNotNil(unsigned.archive)
        XCTAssertNil(unsigned.archiveSignature, "older releases have no signature, so they can't auto-install")
    }

    func testSignatureVerifiesOnlyTheSignedArchiveWithTheRightKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let archive = Data("AirCursor.app bytes".utf8)
        let signature = try key.signature(for: archive).base64EncodedString() + "\n"

        XCTAssertTrue(UpdateSignature.isValid(signatureText: signature, for: archive, publicKeyBase64: publicKey))

        var tampered = archive
        tampered[0] ^= 0x01
        XCTAssertFalse(UpdateSignature.isValid(signatureText: signature, for: tampered, publicKeyBase64: publicKey))

        let otherKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        XCTAssertFalse(UpdateSignature.isValid(signatureText: signature, for: archive, publicKeyBase64: otherKey))

        XCTAssertFalse(UpdateSignature.isValid(signatureText: "not base64!", for: archive, publicKeyBase64: publicKey))
        XCTAssertFalse(UpdateSignature.isValid(signatureText: "", for: archive, publicKeyBase64: publicKey))
        XCTAssertFalse(UpdateSignature.isValid(signatureText: signature, for: archive, publicKeyBase64: ""))
    }

    func testOldSettingsKeepUpdateChecksOn() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"version":3,"showHUD":false}"#.utf8))
        XCTAssertTrue(old.checkForUpdates)
        XCTAssertNil(old.skippedUpdateVersion)
        XCTAssertFalse(old.showHUD)
    }
}
