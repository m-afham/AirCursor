import AppKit
import Security
import AirCursorCore

/// Installs a verified update in place: download → check signature → unzip → check the
/// app → swap it in → relaunch. Nothing is installed unless the archive was signed by the
/// AirCursor release key. Any failure leaves the current app untouched.
enum UpdateInstaller {
    /// Public half of the release-signing key (private half: UPDATE_SIGNING_KEY secret).
    /// Changing it means every installed copy stops accepting updates from the old key.
    static let publicKey = "sRg0k9RiLLO5mvIT9kOcp4hRKe24yWlQKGmjkfg5h9k="

    static let justUpdatedKey = "AirCursor.justUpdatedTo"

    enum InstallError: LocalizedError {
        case notInstallable, tooLarge, badSignature, unzipFailed, appMissing
        case wrongApp, wrongVersion, invalidCodeSignature, cannotReplace(String)

        var errorDescription: String? {
            switch self {
            case .notInstallable: "This release can’t be installed automatically."
            case .tooLarge: "The download is unexpectedly large."
            case .badSignature: "The download’s signature doesn’t match. It wasn’t installed."
            case .unzipFailed: "The download couldn’t be unpacked."
            case .appMissing: "The download doesn’t contain AirCursor."
            case .wrongApp: "The download isn’t AirCursor."
            case .wrongVersion: "The download’s version doesn’t match the release."
            case .invalidCodeSignature: "The downloaded app’s code signature is invalid."
            case .cannotReplace(let reason): "AirCursor couldn’t replace itself: \(reason)"
            }
        }
    }

    static var appURL: URL { Bundle.main.bundleURL }

    /// Ad-hoc signed copies (1.0.6 and earlier, and unsigned local builds) have a new identity
    /// every build, so macOS drops their permissions on update. Certificate-signed releases don't.
    static let isAdHocSigned: Bool = {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return true }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0 || dict[kSecCodeInfoCertificates as String] == nil
    }()

    /// In-place install needs a writable app location. A copy run straight from Downloads
    /// (App Translocation) or from a read-only volume falls back to manual download.
    static var canReplaceSelf: Bool {
        let fm = FileManager.default
        return !appURL.path.contains("/AppTranslocation/")
            && fm.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
            && fm.isWritableFile(atPath: appURL.path)
    }

    static func canInstall(_ update: AvailableUpdate) -> Bool {
        update.release.archive != nil && update.release.archiveSignature != nil && canReplaceSelf
    }

    /// Downloads, verifies and swaps in the update. Returns the installed app's URL;
    /// the caller then relaunches.
    static func install(_ update: AvailableUpdate, progress: @escaping @Sendable (String) -> Void) async throws -> URL {
        guard let archive = update.release.archive, let signatureAsset = update.release.archiveSignature,
              canReplaceSelf else { throw InstallError.notInstallable }
        guard archive.size <= UpdateSignature.maxArchiveBytes else { throw InstallError.tooLarge }

        // A scratch folder on the same volume as the app, so the final swap is a rename.
        let fm = FileManager.default
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                              appropriateFor: appURL, create: true)
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: work) } }

        progress("Downloading…")
        let zipURL = work.appendingPathComponent(archive.name)
        try await fetch(archive.url, to: zipURL)
        let signatureURL = work.appendingPathComponent(signatureAsset.name)
        try await fetch(signatureAsset.url, to: signatureURL)

        progress("Verifying…")
        let size = (try? fm.attributesOfItem(atPath: zipURL.path)[.size] as? Int) ?? .max
        guard size <= UpdateSignature.maxArchiveBytes else { throw InstallError.tooLarge }
        let zipData = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        let signatureText = (try? String(contentsOf: signatureURL, encoding: .utf8)) ?? ""
        guard UpdateSignature.isValid(signatureText: signatureText, for: zipData, publicKeyBase64: publicKey) else {
            throw InstallError.badSignature
        }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        try await run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpacked.path])
        let newApp = unpacked.appendingPathComponent("AirCursor.app")
        guard fm.fileExists(atPath: newApp.path) else { throw InstallError.appMissing }
        try check(newApp, expected: update.version)

        progress("Installing…")
        do {
            _ = try fm.replaceItemAt(appURL, withItemAt: newApp, backupItemName: nil, options: [])
        } catch {
            throw InstallError.cannotReplace(error.localizedDescription)
        }
        succeeded = true
        try? fm.removeItem(at: work)
        return appURL
    }

    /// Quits and reopens AirCursor once this process has exited.
    @MainActor
    static func relaunch(_ app: URL, version: String) {
        UserDefaults.standard.set(version, forKey: justUpdatedKey)
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Paths and the PID are passed as arguments, never interpolated into the script.
        waiter.arguments = ["-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#,
                            "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        do {
            try waiter.run()
        } catch {
            // Couldn't arrange the relaunch: the new version is installed, so just say so.
            Diagnostics.log.error("Relaunch helper failed: \(error.localizedDescription, privacy: .public)")
            UserDefaults.standard.removeObject(forKey: justUpdatedKey)
            return
        }
        NSApp.terminate(nil)
    }

    // MARK: Steps

    private static func fetch(_ url: URL, to destination: URL) async throws {
        if url.isFileURL, UpdateChecker.testRelease != nil {
            try FileManager.default.copyItem(at: url, to: destination)
            return
        }
        guard url.scheme == "https" else { throw InstallError.notInstallable }
        let session = UpdateChecker.session(timeout: 60)
        defer { session.finishTasksAndInvalidate() }
        let (temp, response) = try await session.download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temp)
            throw UpdateChecker.CheckError.badResponse(status)
        }
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// The unpacked app must be AirCursor, the advertised version, and correctly signed.
    private static func check(_ app: URL, expected: AppVersion) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw InstallError.wrongApp }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let version, let parsed = AppVersion(version), parsed == expected else { throw InstallError.wrongVersion }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw InstallError.invalidCodeSignature
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw InstallError.invalidCodeSignature
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw InstallError.unzipFailed }
        }.value
    }
}
