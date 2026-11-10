import AppKit
import AirCursorCore

/// Tracks whether a newer AirCursor release exists and decides when to announce it.
/// Automatic checks run shortly after launch and then at most once a day, only while
/// "Check for updates automatically" is on. A new version is announced (the update
/// window opens) once; after that it stays as a banner in the menu until installed.
@MainActor
final class UpdateController: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case failed(String)
    }

    enum InstallPhase: Equatable {
        case idle
        case working(String)
        case failed(String)
    }

    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var status: Status = .idle
    @Published private(set) var installPhase: InstallPhase = .idle

    var canInstallAutomatically: Bool {
        guard let available else { return false }
        return UpdateInstaller.canInstall(available)
    }

    /// Settings access, provided by AppController.
    var settings: () -> AppSettings = { AppSettings() }
    var updateSettings: (_ change: (inout AppSettings) -> Void) -> Void = { _ in }
    /// Opens the update window. Returns false when now isn't a good moment (e.g. during setup).
    var announce: () -> Bool = { false }

    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var pendingAnnouncement = false

    private static let lastCheckKey = "AirCursor.lastUpdateCheck"
    private static let announcedKey = "AirCursor.announcedUpdate"

    private var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastCheckKey) }
    }

    var currentVersion: String { UpdateChecker.currentVersion }

    func start() {
        // Give launch, permissions and motion a head start, then check hourly whether
        // a day has passed (a long-lived timer alone would drift across sleep).
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    func checkIfDue() {
        if UpdateChecker.testRelease != nil { return check(manual: true) }
        guard settings().checkForUpdates,
              UpdatePolicy.isCheckDue(lastCheck: lastCheck, now: Date()) else { return }
        check(manual: false)
    }

    /// Downloads, verifies and installs the available update, then relaunches.
    func install() {
        guard let update = available, installPhase == .idle || isFailed else { return }
        installPhase = .working("Downloading…")
        Diagnostics.log.notice("Installing update \(update.version.description, privacy: .public)")
        Task { [weak self] in
            do {
                let app = try await UpdateInstaller.install(update) { message in
                    Task { @MainActor in self?.installPhase = .working(message) }
                }
                self?.installPhase = .working("Restarting…")
                Diagnostics.log.notice("Update \(update.version.description, privacy: .public) installed; relaunching")
                UpdateInstaller.relaunch(app, version: update.version.description)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Diagnostics.log.error("Update install failed: \(message, privacy: .public)")
                self?.installPhase = .failed(message)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = installPhase { return true }
        return false
    }

    /// `manual`: the user clicked "Check for updates", so show a skipped version too
    /// and always open the window when there's something new.
    func check(manual: Bool) {
        guard status != .checking else { return }
        status = .checking
        task = Task { [weak self] in
            do {
                let release = try await UpdateChecker.fetchLatestRelease()
                self?.finish(with: release, manual: manual)
            } catch {
                self?.fail(error)
            }
        }
    }

    private func finish(with release: ReleaseInfo, manual: Bool) {
        lastCheck = Date()
        let s = settings()
        available = UpdatePolicy.update(current: currentVersion, release: release,
                                        skippedVersion: s.skippedUpdateVersion, includeSkipped: manual)
        status = .upToDate(Date())
        guard let available else {
            Diagnostics.log.notice("Update check: \(self.currentVersion, privacy: .public) is current (latest \(release.tagName, privacy: .public))")
            return
        }
        let version = available.version.description
        Diagnostics.log.notice("Update available: \(version, privacy: .public) (installed \(self.currentVersion, privacy: .public))")
        let alreadyAnnounced = UserDefaults.standard.string(forKey: Self.announcedKey) == version
        pendingAnnouncement = manual || !alreadyAnnounced
        announceIfPending()
        if UpdateChecker.testRelease != nil, ProcessInfo.processInfo.environment["AIRCURSOR_UPDATE_TEST_INSTALL"] == "1" {
            install()
        }
    }

    /// Opens the update window for a newly found version once it's a good moment
    /// (AppController retries this while setup is in progress).
    func announceIfPending() {
        guard pendingAnnouncement, let version = available?.version.description, announce() else { return }
        pendingAnnouncement = false
        UserDefaults.standard.set(version, forKey: Self.announcedKey)
    }

    private func fail(_ error: Error) {
        // Offline or rate-limited: stay quiet and retry at the next hourly tick.
        status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        Diagnostics.log.notice("Update check failed: \(error.localizedDescription, privacy: .public)")
    }

    func download() {
        NSWorkspace.shared.open(UpdateChecker.downloadURL)
    }

    func openReleaseNotes() {
        guard let url = available?.release.htmlURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Don't announce this version again (a newer one will still be announced).
    func skip() {
        guard let version = available?.version.description else { return }
        updateSettings { $0.skippedUpdateVersion = version }
        available = nil
        pendingAnnouncement = false
    }
}
