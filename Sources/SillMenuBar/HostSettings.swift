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
/// Defaults are registered from `HostConfig.standard`, so a fresh install streams exactly like the
/// CLI, and launch arguments override for one run without being saved (`-maxFPS 60`), because a
/// save writes only the keys a change touched. Launch at login is not stored here: SMAppService
/// is its source of truth (LoginItem.swift).
@MainActor @Observable
final class HostSettings {
    enum Key {
        static let maxFPS = "maxFPS", captureScale = "captureScale", bitrate = "bitrate"
        static let prioritizeSpeed = "prioritizeSpeed", virtualDisplay = "virtualDisplay", directWireless = "directWireless"
        static let settingsTab = "settingsTab", permissionsOnboardingDismissed = "permissionsOnboardingDismissed"
        static let askedScreenRecording = "askedScreenRecording", askedAccessibility = "askedAccessibility"
        static let logShowsStats = "logShowsStats"
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

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let standard = HostConfig.standard
        defaults.register(defaults: [
            Key.maxFPS: standard.maxFPS,
            Key.captureScale: Double(standard.captureScale),
            Key.bitrate: standard.bitrate,
            Key.prioritizeSpeed: standard.prioritizeSpeed,
            Key.virtualDisplay: standard.virtualDisplay,
            // Off, like the CLI: an existing install has no key, so it stops asking for AWDL.
            Key.directWireless: standard.directWireless,
        ])
        config = HostConfig(maxFPS: defaults.integer(forKey: Key.maxFPS),
                            captureScale: CGFloat(defaults.double(forKey: Key.captureScale)),
                            bitrate: defaults.integer(forKey: Key.bitrate),
                            prioritizeSpeed: defaults.bool(forKey: Key.prioritizeSpeed),
                            virtualDisplay: defaults.bool(forKey: Key.virtualDisplay),
                            directWireless: defaults.bool(forKey: Key.directWireless),
                            // Remote access comes to the app with its keychain identity (a later
                            // step); until then the app runs the standard values, never saved.
                            remoteAccess: standard.remoteAccess, remotePort: standard.remotePort,
                            internetAccess: standard.internetAccess).validated()
        settingsTab = defaults.string(forKey: Key.settingsTab).flatMap(SettingsTab.init(rawValue:)) ?? .general
        permissionsOnboardingDismissed = defaults.bool(forKey: Key.permissionsOnboardingDismissed)
        askedScreenRecording = defaults.bool(forKey: Key.askedScreenRecording)
        askedAccessibility = defaults.bool(forKey: Key.askedAccessibility)
        logShowsStats = defaults.bool(forKey: Key.logShowsStats)
    }

    /// Writes only the keys that changed, so a launch-argument override of another key is not
    /// made permanent by an unrelated change.
    private func save(changedFrom old: HostConfig) {
        if config.maxFPS != old.maxFPS { defaults.set(config.maxFPS, forKey: Key.maxFPS) }
        if config.captureScale != old.captureScale { defaults.set(Double(config.captureScale), forKey: Key.captureScale) }
        if config.bitrate != old.bitrate { defaults.set(config.bitrate, forKey: Key.bitrate) }
        if config.prioritizeSpeed != old.prioritizeSpeed { defaults.set(config.prioritizeSpeed, forKey: Key.prioritizeSpeed) }
        if config.virtualDisplay != old.virtualDisplay { defaults.set(config.virtualDisplay, forKey: Key.virtualDisplay) }
        if config.directWireless != old.directWireless { defaults.set(config.directWireless, forKey: Key.directWireless) }
    }
}
