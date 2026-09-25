import AppKit
import Observation
import SillHostCore
import StreamProtocol

/// Owns the host for the app: the settings, the coordinator, remote access and the small models
/// the menu and the windows bind to. Works out what the status item says (`presentation`)
/// whenever any of it changes, and holds the App Nap and sleep guard. Main actor.
@MainActor @Observable
final class AppModel {
    let settings: HostSettings
    let permissions: PermissionsModel
    let loginItem = LoginItemModel()
    /// `--synthetic`: the Desktop streams a test pattern and the host stays off Bonjour, exactly
    /// as with the CLI's flag. No onboarding in this mode.
    let synthetic = CommandLine.arguments.contains("--synthetic")
    private(set) var coordinator: StreamCoordinator?
    /// The coordinator could not be created (the listener refused its parameters). Shown in the
    /// menu; the app keeps running so the user can read it and quit.
    private(set) var startupError: String?
    /// What the status item, its card and the menu show.
    private(set) var presentation: StatusPresentation
    /// The Settings tab on screen, nil while Settings is closed: the panes that poll run only
    /// while theirs is visible.
    var visibleSettingsTab: SettingsTab?

    /// Wired by the app delegate: the status item's glyph and tooltip, and the windows.
    @ObservationIgnored var onPresentation: ((StatusPresentation) -> Void)?
    @ObservationIgnored var showSettings: ((SettingsTab?) -> Void)?
    @ObservationIgnored var showLog: (() -> Void)?
    /// Shows the pairing window with this offer (or brings it forward with the same code).
    @ObservationIgnored var showPairing: ((RemoteAccess.PairingOffer) -> Void)?

    @ObservationIgnored private var loggedStatus: String?
    @ObservationIgnored private var napActivity: NSObjectProtocol?
    @ObservationIgnored private var napHold = NapHold.none

    init() {
        let settings = HostSettings()
        self.settings = settings
        permissions = PermissionsModel(settings: settings)
        presentation = StatusText.present(snapshot: HostStatusSnapshot(),
                                          permissions: PermissionState(screenRecording: true, accessibility: true),
                                          startupError: nil, hasCoordinator: false)
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unbundled" }

    /// Starts the host: the same coordinator as the CLI, under the AppKit loop that is already
    /// running, asking for no permission at launch. Never exits on an error.
    func start() {
        observePresentation()
        Task { @MainActor in
            do {
                // The identity before the coordinator: its TXT tag goes into the first Bonjour
                // registration. A keychain failure leaves remote access unavailable, not the app.
                let remote = makeRemoteAccess()
                let c = try StreamCoordinator(config: settings.config, synthetic: synthetic, appKitLoop: true, remote: remote)
                c.keepRunningOnListenerFailure()
                coordinator = c
                // One path from the controls to the host, synchronous: the host's target equals
                // settings.config at every main-actor turn, so a device's change and a menu click
                // never undo each other.
                settings.onChange = { [settings, weak c] in c?.setTarget(settings.config) }
                // A device's change goes through HostSettings like a menu click: saved (only the keys
                // it changed) and shown live in Settings and the menu. Laid over settings.config, never
                // over the host's value. No validated(): the host accepted only menu values, and
                // validating here would rewrite unrelated hand-set keys (which save(changedFrom:)
                // would then write).
                c.onDeviceSettingsChange = { [settings] change in
                    settings.config = settings.config.applying(change)
                    return settings.config
                }
                // Not in HostConfig (it moves no listener): handed over on its own.
                remote.setAddressName(settings.remoteAddressName)
                settings.onAddressNameChange = { [settings, weak remote] in remote?.setAddressName(settings.remoteAddressName) }
                await c.start(preselect: nil, promptForPermissions: false)
                Stats.shared.startPrinting()
                print("Sill \(Self.version) (\(Self.build)) running from \(Bundle.main.bundlePath); log file \(HostLog.shared.fileURL?.path ?? "none")")
                onboardIfNeeded()
            } catch {
                startupError = "\(error)"
                print("Sill couldn’t start: \(error)")
            }
        }
    }

    // MARK: Remote access

    /// The Mac's identity and trust list: the login keychain in Sill.app. A test never touches
    /// that keychain: `--synthetic` keeps them in SILL_TEST_REMOTE_DIR (a 0700 directory) or in
    /// memory, and so does the bare SillMenuBar binary, whose ad hoc signature changes with every
    /// build (each rebuild would face a keychain prompt for items the last one made).
    private func makeRemoteAccess() -> RemoteAccess {
        var store: IdentityStore = KeychainIdentityStore()
        let bundled = Bundle.main.bundleURL.pathExtension == "app"
        if synthetic || !bundled {
            store = MemoryIdentityStore()
            if synthetic, let dir = ProcessInfo.processInfo.environment["SILL_TEST_REMOTE_DIR"], !dir.isEmpty {
                do { store = try FileIdentityStore(directory: URL(fileURLWithPath: dir)) }
                catch { print("SILL_TEST_REMOTE_DIR=\(dir) ignored: \(error)") }
            }
        }
        let remote = RemoteAccess(store: store)
        if let problem = remote.identityProblem { print("Remote access unavailable: \(problem)") }
        remote.restoreSeen(settings.remoteDevicesSeen())
        remote.onSeen = { [weak self, weak remote] prefix, at, route in
            let keep = Set(remote?.pairedPrefixes ?? [])
            self?.settings.rememberRemoteDevice(prefix, at: at, route: route, keep: keep)
        }
        remote.onPairingOffer = { [weak self] offer in self?.pairingOffered(offer) }
        return remote
    }

    /// The host's remote access, once the coordinator is up.
    var remote: RemoteAccess? { coordinator?.remote }

    /// Pair iPhone or iPad… (the menu, the pane, -SillPairAfter): opens a pairing window, or
    /// brings the open one forward with its code.
    func pairDevice() {
        remote?.openPairing(requestedBy: nil)
    }

    /// The pairing window was closed, or its Cancel clicked: the code dies with it.
    func cancelPairing() {
        remote?.cancelPairing()
    }

    /// Remove in the pane (and -SillUnpairAfter). Nil when done; otherwise why the device is still
    /// paired (the keychain could not be written), and its "last connected" stays too.
    @discardableResult
    func removeDevice(_ id: String) -> String? {
        let prefix = coordinator?.status.snapshot.remote?.paired.first { $0.id == id }?.keyPrefix
        if let problem = remote?.remove(fingerprint: id) { return problem }
        if let prefix { settings.forgetRemoteDevice(prefix) }
        return nil
    }

    func renameDevice(_ id: String, to name: String) {
        remote?.rename(fingerprint: id, to: name)
    }

    /// The pairing window's Turn On Remote Access: the Mac user's click. A pairing never turns it
    /// on by itself.
    func turnOnRemoteAccess() {
        settings.config.remoteAccess = true
    }

    /// An offer from the host: the window shows it. TEST ONLY: with the file store (--synthetic
    /// and SILL_TEST_REMOTE_DIR) the link and the code are also left in its directory, mode 0600,
    /// for a test client to read. Never printed: the print shadow copies stdout into Sill.log.
    private func pairingOffered(_ offer: RemoteAccess.PairingOffer) {
        if let dir = remote?.testDirectory {
            try? FileIdentityStore.writePrivate(Data(offer.url.utf8), to: dir.appendingPathComponent("pairing.url"))
            try? FileIdentityStore.writePrivate(Data(offer.code.utf8), to: dir.appendingPathComponent("pairing.code"))
        }
        showPairing?(offer)
    }

    // MARK: Status

    /// Recomputes the presentation now and again after anything it read changes: the host's
    /// snapshot, the coordinator appearing, the permissions, a startup error. Observation fires
    /// once, before the change lands, so each change hops to the next main-actor turn, re-reads
    /// the permissions (a revoked one shows with the status change it causes) and re-arms.
    private func observePresentation() {
        let next = withObservationTracking {
            StatusText.present(snapshot: coordinator?.status.snapshot ?? HostStatusSnapshot(),
                               permissions: PermissionState(screenRecording: permissions.screenRecording,
                                                            accessibility: permissions.accessibility),
                               startupError: startupError, hasCoordinator: coordinator != nil)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.permissions.refresh()
                self?.observePresentation()
            }
        }
        publish(next)
    }

    private func publish(_ next: StatusPresentation) {
        if next != presentation || loggedStatus == nil {
            presentation = next
            onPresentation?(next)
        }
        // One line per change of header or explanation; tests grep for "Status:".
        let line = next.subtitle.map { "\(next.header) — \($0)" } ?? next.header
        if line != loggedStatus {
            loggedStatus = line
            print("Status: \(line)")
        }
        let snapshot = coordinator?.status.snapshot
        holdAppNapOff(devices: snapshot?.devices.count ?? 0, remote: snapshot?.remoteDeviceCount ?? 0)
    }

    private enum NapHold { case none, connected, remote }

    /// App Nap would coalesce this windowless app's timers once it is in the background, among
    /// them the 30 ms link keepalive ticks that keep a device's Wi-Fi out of power save, and the
    /// 2026-09-22 stutter would be back. So while a device is connected Sill holds a
    /// latency-critical activity, which still lets the Mac sleep when idle: a device at home can
    /// wake it (Bonjour Sleep Proxy) or walk over. A device connected from away cannot, so while
    /// one is, the activity is `.userInitiated`, which also keeps the Mac from idle sleep (the
    /// display may still sleep; docs/remote-access-plan.md §6.5). Switching ends one activity and
    /// begins the other.
    private func holdAppNapOff(devices: Int, remote: Int) {
        let want: NapHold = remote > 0 ? .remote : (devices > 0 ? .connected : .none)
        guard want != napHold else { return }
        if let activity = napActivity {
            ProcessInfo.processInfo.endActivity(activity)
            napActivity = nil
        }
        napHold = want
        switch want {
        case .remote:
            napActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                                reason: "Sill is serving a device connected from away")
        case .connected:
            napActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                                reason: "Sill is serving a connected device")
        case .none:
            break
        }
    }

    /// First launch, or any launch until the user closes Settings on it: when a permission is
    /// missing, Settings opens on Permissions. The test pattern needs none.
    private func onboardIfNeeded() {
        permissions.refresh()
        guard !synthetic, !permissions.allGranted, !settings.permissionsOnboardingDismissed else { return }
        showSettings?(.permissions)
    }
}
