import AppKit
import Observation
import SillHostCore

/// Owns the host for the app: the settings, the coordinator, and the small models the menu and
/// the windows bind to. Works out what the status item says (`presentation`) whenever any of it
/// changes, and holds the App Nap guard. Main actor.
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

    /// Wired by the app delegate: the status item's glyph and tooltip, and the two windows.
    @ObservationIgnored var onPresentation: ((StatusPresentation) -> Void)?
    @ObservationIgnored var showSettings: ((SettingsTab?) -> Void)?
    @ObservationIgnored var showLog: (() -> Void)?

    @ObservationIgnored private var loggedStatus: String?
    @ObservationIgnored private var napActivity: NSObjectProtocol?

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
                let c = try StreamCoordinator(config: settings.config, synthetic: synthetic, appKitLoop: true)
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
        holdAppNapOff(while: (coordinator?.status.snapshot.devices.count ?? 0) > 0)
    }

    /// App Nap would coalesce this windowless app's timers once it is in the background, among
    /// them the 30 ms link keepalive ticks that keep a device's Wi-Fi out of power save, and the
    /// 2026-09-22 stutter would be back. So while a device is connected Sill holds a
    /// latency-critical activity. It still lets the Mac sleep when idle: keeping it awake while
    /// streaming (.userInitiated) is a product call left for Noah.
    private func holdAppNapOff(while connected: Bool) {
        if connected, napActivity == nil {
            napActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                                reason: "Sill is serving a connected device")
        } else if !connected, let activity = napActivity {
            ProcessInfo.processInfo.endActivity(activity)
            napActivity = nil
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
