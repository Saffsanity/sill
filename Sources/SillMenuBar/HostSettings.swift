import Foundation
import Observation
import SillHostCore

/// The app's settings: the host's knobs (`config`) and a few facts the UI remembers, all in
/// UserDefaults (the bundle's domain, me.saffer.sill.mac; the bare SillMenuBar binary's is
/// "SillMenuBar"). Main actor, like everything that shows or changes them.
///
/// One path to the host: the menu, the Settings panes, the debug hooks and connected devices (through
/// the coordinator's `onDeviceSettingsChange`, which the model points here) all assign `config`.
/// Its didSet saves what changed and calls `onChange`, which the model points at
/// `StreamCoordinator.setTarget`, synchronously, so the host's target and `config` never disagree
/// between two main-actor turns. No sliders anywhere: one change is one apply and at most one
/// restart.
///
/// Defaults are registered from `HostConfig.app`: the CLI's (`HostConfig.standard`) with the virtual
/// display and Send Audio on (Noah, 2026-10-27), so a fresh install streams like the CLI with
/// `--virtual-display --audio`. A Mac with no screen's display (`headlessDisplay`) is on in both.
/// Registered, never written: a key a change saved always wins over them (`virtualDisplay` 0 stays
/// off whatever the default), and launch arguments override for one run without being saved
/// (`-maxFPS 60`, `-virtualDisplay 0`), because a save writes only the keys a change touched. Launch
/// at login is not stored here: SMAppService is its source of truth (LoginItem.swift).
///
/// Remote Access, its port and the internet switch are the Mac's alone: they come from here (the
/// menu, the Remote Access pane, -SillSetAfter), never from a device. The trust list, the keys and
/// Require pairing never live here: any process of the same user can write these defaults
/// (KeychainIdentityStore; docs/home-pairing-plan.md §6.5). `config.requirePairing` only carries
/// the stored value to the host (AppModel.setRequirePairing), and `save(changedFrom:)` never writes it.
///
/// Away from home (docs/remote-bundle-plan.md §5): the away quality is saved under its own keys,
/// `awayBitrate` and `awayCaptureScale`, never over `bitrate` and `captureScale`; a device away sets
/// it, and so does Settings › Streaming's "Away from home" section. Until the first change the keys do
/// not exist (`defaults read … awayBitrate` says so), which is how Low · Standard reads.
///
/// `updateCheck` (automatic update checks) is here too, outside HostConfig: it moves no listener and
/// no pipeline. What the checks found is UpdateChecker's own (updateLastCheck, updateETag,
/// updateLatestTag, updateLatestURL, in the same defaults). So is `showPairingWindowToScreenSharing`
/// (Settings › Devices, issue #108): only the pairing window reads it, never the host, and it lives
/// here rather than beside Require pairing because it lets no device in (PairingWindowSharing).
@MainActor @Observable
final class HostSettings {
    enum Key {
        static let maxFPS = "maxFPS", captureScale = "captureScale", bitrate = "bitrate"
        static let awayBitrate = "awayBitrate", awayCaptureScale = "awayCaptureScale"
        static let prioritizeSpeed = "prioritizeSpeed", virtualDisplay = "virtualDisplay", directWireless = "directWireless"
        static let remoteAccess = "remoteAccess", remotePort = "remotePort", internetAccess = "internetAccess"
        static let remoteAddressName = "remoteAddressName", remoteDevicesSeen = "remoteDevicesSeen"
        static let settingsTab = "settingsTab", permissionsOnboardingDismissed = "permissionsOnboardingDismissed"
        static let askedScreenRecording = "askedScreenRecording", askedAccessibility = "askedAccessibility"
        static let logShowsStats = "logShowsStats"
        static let updateCheck = "updateCheck"
        static let shareClipboard = "shareClipboard"
        static let sendAudio = "sendAudio"
        static let offConsoleView = "offConsoleView"
        static let lockAfterSession = "lockAfterSession"
        static let lockSleepsDisplay = "lockSleepsDisplay"
        static let lockOnlyAfterAway = "lockOnlyAfterAway"
        static let headlessDisplay = "headlessDisplay"
        static let virtualDesktop = "virtualDesktop"
        static let virtualDesktopSize = "virtualDesktopSize", virtualDesktopHz = "virtualDesktopHz"
        static let virtualDesktopDevices = "virtualDesktopDevices"
        static let showPairingWindowToScreenSharing = "showPairingWindowToScreenSharing"
    }

    var config: HostConfig {
        didSet {
            guard config != oldValue else { return }
            save(changedFrom: oldValue)
            onChange?()
        }
    }
    /// Called after `config` changed and was saved, on the main actor, before the assignment returns.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    /// The Settings tab shown last, reopened next time.
    var settingsTab: SettingsTab { didSet { defaults.set(settingsTab.rawValue, forKey: Key.settingsTab) } }
    /// The user closed the onboarding Settings window while a permission was still missing: later
    /// launches (a login item, say) only mark the status item. Cleared once both are allowed.
    var permissionsOnboardingDismissed: Bool { didSet { defaults.set(permissionsOnboardingDismissed, forKey: Key.permissionsOnboardingDismissed) } }
    /// The system's permission alerts appear once per app; after that, Allow… opens System Settings.
    var askedScreenRecording: Bool { didSet { defaults.set(askedScreenRecording, forKey: Key.askedScreenRecording) } }
    var askedAccessibility: Bool { didSet { defaults.set(askedAccessibility, forKey: Key.askedAccessibility) } }
    /// The Log window shows the once-a-second stats and client lines.
    var logShowsStats: Bool { didSet { defaults.set(logShowsStats, forKey: Key.logShowsStats) } }

    /// The devices this Mac knows, as the Virtual Desktop's budget counts them (part B: VirtualDesktopBudget.Device, each
    /// device that connected and said its screen, by its name, the newest kept), for Settings › Displays' Custom…: what may
    /// be typed (the largest budget among them, VirtualDesktopBudget.ceiling) and which get a size as it is and which
    /// scaled. Saved as JSON under `virtualDesktopDevices`; empty on a Mac that has seen none (the largest current iPad's
    /// budget is then the ceiling). Forgotten with Sill's settings.
    private(set) var knownDevices: [VirtualDesktopBudget.Device] = []

    /// Keeps `devices` (the host's connected ones that said their screen) among the known: by name, the newest screen and
    /// rate kept, at most 24 (the oldest dropped). Saved only when something changed.
    func rememberDevices(_ devices: [VirtualDesktopBudget.Device]) {
        guard !devices.isEmpty else { return }
        var next = knownDevices
        for d in devices {
            next.removeAll { $0.name == d.name }
            next.append(d)
        }
        if next.count > 24 { next.removeFirst(next.count - 24) }
        guard next != knownDevices else { return }
        knownDevices = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Key.virtualDesktopDevices) }
    }

    /// The router's dynamic DNS name for the internet switch ("home.example.net", or with ":port"
    /// when the router forwards another outside port); "" for none. Not in HostConfig: it changes
    /// no listener, only the addresses devices learn (`RemoteAccess.setAddressName`).
    var remoteAddressName: String {
        didSet {
            guard remoteAddressName != oldValue else { return }
            defaults.set(remoteAddressName, forKey: Key.remoteAddressName)
            onAddressNameChange?()
        }
    }
    @ObservationIgnored var onAddressNameChange: (@MainActor () -> Void)?
    /// "Check for updates automatically" (Settings › General): once a day, GitHub's releases feed
    /// (UpdateChecker). On by default; `-updateCheck 0` turns it off for one run without saving.
    var updateCheck: Bool {
        didSet {
            guard updateCheck != oldValue else { return }
            defaults.set(updateCheck, forKey: Key.updateCheck)
            print("Update check: automatic checks \(updateCheck ? "on" : "off").")
            onUpdateCheckChange?()
        }
    }
    @ObservationIgnored var onUpdateCheckChange: (@MainActor () -> Void)?

    /// "Show the pairing window to screen sharing" (Settings › Devices; issue #108): Screen Sharing,
    /// Apple Remote Desktop and VNC apps show the pairing window, its QR code and its code, so a Mac
    /// used through them can pair (PairingWindowSharing). Off by default; a window already open
    /// follows a change at once (the app delegate's hook). `-showPairingWindowToScreenSharing 1`
    /// turns it on for one run without saving.
    var showPairingWindowToScreenSharing: Bool {
        didSet {
            guard showPairingWindowToScreenSharing != oldValue else { return }
            defaults.set(showPairingWindowToScreenSharing, forKey: Key.showPairingWindowToScreenSharing)
            print(PairingWindowSharing.line(on: showPairingWindowToScreenSharing))
            onPairingWindowSharingChange?()
        }
    }
    @ObservationIgnored var onPairingWindowSharingChange: (@MainActor () -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = HostConfig.app
        defaults.register(defaults: [
            Key.maxFPS: base.maxFPS,
            Key.captureScale: Double(base.captureScale),
            Key.bitrate: base.bitrate,
            Key.awayBitrate: base.awayBitrate,
            Key.awayCaptureScale: Double(base.awayCaptureScale),
            Key.prioritizeSpeed: base.prioritizeSpeed,
            // On, unlike the CLI (Noah, 2026-10-27): an install that never set the key streams a picked
            // window from the virtual display; one whose user or device turned it off keeps it off.
            Key.virtualDisplay: base.virtualDisplay,
            // Off, like the CLI: an existing install has no key, so it stops asking for AWDL.
            Key.directWireless: base.directWireless,
            // Off, and the internet switch too: only the Mac's own user widens exposure.
            Key.remoteAccess: base.remoteAccess,
            Key.remotePort: base.remotePort,
            Key.internetAccess: base.internetAccess,
            Key.remoteAddressName: "",
            Key.updateCheck: true,
            // On, like the CLI: each device has its own switch.
            Key.shareClipboard: base.shareClipboard,
            // On, unlike the CLI (Noah, 2026-10-27: "Send Audio should be on by default"); a saved key
            // wins. The Mac keeps playing its own sound too.
            Key.sendAudio: base.sendAudio,
            // Off, like the CLI: a Mac off console shows nothing of this session unless its user says so here.
            Key.offConsoleView: base.offConsoleView,
            // Off, like the CLI: a Mac locks by itself after a device leaves only once its user says so here.
            Key.lockAfterSession: base.lockAfterSession,
            // Under it (shown while it is on): its display off with the lock, and every session counting (the plan's
            // open decisions 6 and 5), as the CLI.
            Key.lockSleepsDisplay: base.lockSleepsDisplay,
            Key.lockOnlyAfterAway: base.lockOnlyAfterAway,
            // On, like the CLI (Noah on #61: a Mac with no screen gets a display of its own); a saved key wins, so a
            // Mac whose user turned it off in Settings › Virtual Display (#380's stops, a #333 monitor) keeps it off.
            Key.headlessDisplay: base.headlessDisplay,
            // Off, like the CLI (Noah, 2026-11-11: the Virtual Desktop off by default); a saved key wins.
            Key.virtualDesktop: base.virtualDesktop,
            // Its size and rate the device's (Noah, 2026-11-18), as the CLI's; a saved choice wins.
            Key.virtualDesktopSize: base.virtualDesktopSize,
            Key.virtualDesktopHz: base.virtualDesktopHz,
            // Off: whoever can see this Mac's screen remotely could read a code (PairingWindowSharing).
            Key.showPairingWindowToScreenSharing: false,
        ])
        config = HostConfig(maxFPS: defaults.integer(forKey: Key.maxFPS),
                            captureScale: CGFloat(defaults.double(forKey: Key.captureScale)),
                            bitrate: defaults.integer(forKey: Key.bitrate),
                            awayBitrate: defaults.integer(forKey: Key.awayBitrate),
                            awayCaptureScale: CGFloat(defaults.double(forKey: Key.awayCaptureScale)),
                            prioritizeSpeed: defaults.bool(forKey: Key.prioritizeSpeed),
                            virtualDisplay: defaults.bool(forKey: Key.virtualDisplay),
                            directWireless: defaults.bool(forKey: Key.directWireless),
                            remoteAccess: defaults.bool(forKey: Key.remoteAccess),
                            remotePort: defaults.integer(forKey: Key.remotePort),
                            internetAccess: defaults.bool(forKey: Key.internetAccess),
                            // Never a default or a launch argument: it lives with the trust list
                            // (the identity store), from which AppModel reads it at launch, before
                            // the host starts, and to which the Devices pane saves it.
                            requirePairing: base.requirePairing,
                            shareClipboard: defaults.bool(forKey: Key.shareClipboard),
                            sendAudio: defaults.bool(forKey: Key.sendAudio),
                            offConsoleView: defaults.bool(forKey: Key.offConsoleView),
                            lockAfterSession: defaults.bool(forKey: Key.lockAfterSession),
                            lockSleepsDisplay: defaults.bool(forKey: Key.lockSleepsDisplay),
                            lockOnlyAfterAway: defaults.bool(forKey: Key.lockOnlyAfterAway),
                            headlessDisplay: defaults.bool(forKey: Key.headlessDisplay),
                            virtualDesktop: defaults.bool(forKey: Key.virtualDesktop),
                            virtualDesktopSize: defaults.string(forKey: Key.virtualDesktopSize) ?? base.virtualDesktopSize,
                            virtualDesktopHz: defaults.integer(forKey: Key.virtualDesktopHz)).validated()
        remoteAddressName = defaults.string(forKey: Key.remoteAddressName) ?? ""
        updateCheck = defaults.bool(forKey: Key.updateCheck)
        showPairingWindowToScreenSharing = defaults.bool(forKey: Key.showPairingWindowToScreenSharing)
        settingsTab = defaults.string(forKey: Key.settingsTab).flatMap(SettingsTab.init(rawValue:)) ?? .general
        permissionsOnboardingDismissed = defaults.bool(forKey: Key.permissionsOnboardingDismissed)
        askedScreenRecording = defaults.bool(forKey: Key.askedScreenRecording)
        askedAccessibility = defaults.bool(forKey: Key.askedAccessibility)
        logShowsStats = defaults.bool(forKey: Key.logShowsStats)
        // Saved by a later Sill for Mac in a form this one cannot read: none known, as on a Mac that has seen no device.
        knownDevices = defaults.data(forKey: Key.virtualDesktopDevices)
            .flatMap { try? JSONDecoder().decode([VirtualDesktopBudget.Device].self, from: $0) } ?? []
    }

    /// Writes only the keys that changed, so a launch-argument override of another key is not
    /// made permanent by an unrelated change.
    private func save(changedFrom old: HostConfig) {
        if config.maxFPS != old.maxFPS { defaults.set(config.maxFPS, forKey: Key.maxFPS) }
        if config.captureScale != old.captureScale { defaults.set(Double(config.captureScale), forKey: Key.captureScale) }
        if config.bitrate != old.bitrate { defaults.set(config.bitrate, forKey: Key.bitrate) }
        if config.awayBitrate != old.awayBitrate { defaults.set(config.awayBitrate, forKey: Key.awayBitrate) }
        if config.awayCaptureScale != old.awayCaptureScale { defaults.set(Double(config.awayCaptureScale), forKey: Key.awayCaptureScale) }
        if config.prioritizeSpeed != old.prioritizeSpeed { defaults.set(config.prioritizeSpeed, forKey: Key.prioritizeSpeed) }
        if config.virtualDisplay != old.virtualDisplay { defaults.set(config.virtualDisplay, forKey: Key.virtualDisplay) }
        if config.directWireless != old.directWireless { defaults.set(config.directWireless, forKey: Key.directWireless) }
        if config.remoteAccess != old.remoteAccess { defaults.set(config.remoteAccess, forKey: Key.remoteAccess) }
        if config.remotePort != old.remotePort { defaults.set(config.remotePort, forKey: Key.remotePort) }
        if config.internetAccess != old.internetAccess { defaults.set(config.internetAccess, forKey: Key.internetAccess) }
        if config.shareClipboard != old.shareClipboard { defaults.set(config.shareClipboard, forKey: Key.shareClipboard) }
        if config.sendAudio != old.sendAudio { defaults.set(config.sendAudio, forKey: Key.sendAudio) }
        if config.offConsoleView != old.offConsoleView { defaults.set(config.offConsoleView, forKey: Key.offConsoleView) }
        if config.lockAfterSession != old.lockAfterSession { defaults.set(config.lockAfterSession, forKey: Key.lockAfterSession) }
        if config.lockSleepsDisplay != old.lockSleepsDisplay { defaults.set(config.lockSleepsDisplay, forKey: Key.lockSleepsDisplay) }
        if config.lockOnlyAfterAway != old.lockOnlyAfterAway { defaults.set(config.lockOnlyAfterAway, forKey: Key.lockOnlyAfterAway) }
        if config.headlessDisplay != old.headlessDisplay { defaults.set(config.headlessDisplay, forKey: Key.headlessDisplay) }
        if config.virtualDesktop != old.virtualDesktop { defaults.set(config.virtualDesktop, forKey: Key.virtualDesktop) }
        if config.virtualDesktopSize != old.virtualDesktopSize { defaults.set(config.virtualDesktopSize, forKey: Key.virtualDesktopSize) }
        if config.virtualDesktopHz != old.virtualDesktopHz { defaults.set(config.virtualDesktopHz, forKey: Key.virtualDesktopHz) }
    }

    // MARK: Remote devices seen (display only)

    /// When each paired device last connected from away and how, by its key prefix: the Remote
    /// Access pane's "last connected", kept across launches. Display only, never trust.
    func remoteDevicesSeen() -> [String: (at: Date, route: String)] {
        guard let raw = defaults.dictionary(forKey: Key.remoteDevicesSeen) else { return [:] }
        var out: [String: (at: Date, route: String)] = [:]
        for (prefix, value) in raw {
            guard let entry = value as? [String: Any], let at = entry["at"] as? Double, let route = entry["route"] as? String else { continue }
            out[prefix] = (Date(timeIntervalSince1970: at), route)
        }
        return out
    }

    /// Saves one device's record, at most once a minute per device (a device that reconnects every
    /// few seconds must not write defaults every few seconds), and keeps only `keep` (the paired
    /// devices' prefixes).
    func rememberRemoteDevice(_ prefix: String, at: Date, route: String, keep: Set<String>) {
        var raw = defaults.dictionary(forKey: Key.remoteDevicesSeen) ?? [:]
        if let entry = raw[prefix] as? [String: Any], let last = entry["at"] as? Double,
           at.timeIntervalSince1970 - last < 60, entry["route"] as? String == route { return }
        raw[prefix] = ["at": at.timeIntervalSince1970, "route": route]
        raw = raw.filter { keep.contains($0.key) }
        defaults.set(raw, forKey: Key.remoteDevicesSeen)
    }

    /// Drops the record of a device that was removed.
    func forgetRemoteDevice(_ prefix: String) {
        guard var raw = defaults.dictionary(forKey: Key.remoteDevicesSeen), raw[prefix] != nil else { return }
        raw[prefix] = nil
        defaults.set(raw, forKey: Key.remoteDevicesSeen)
    }
}
