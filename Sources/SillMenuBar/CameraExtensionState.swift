import Foundation

/// Sill Camera in Sill.app (docs/camera-plan.md §6.5, §7, §10, §11): what Sill asks macOS for (to activate the camera
/// extension, to replace an older one, to remove it) and what macOS answers, as one reducer; and what Settings ›
/// Streaming's "Camera and Microphone (beta)" section says from that, from Sill's feed into Sill Camera (CameraSink) and
/// from the app that uses it: a line, a button and a log line for each state. Pure: Foundation only, checked with swiftc
/// (Tests/checks/camera-app). CameraExtensionManager carries it out with OSSystemExtensionRequest, or with a TEST ONLY
/// dry run in the bare SillMenuBar binary.
///
/// - Off (the default) asks nothing of macOS: no request, no prompt, no extension.
/// - On asks macOS to activate Sill Camera (an administrator allows it once in System Settings), at once and at every
///   launch while it stays on, as Apple expects: an active extension answers at once, an older one in its place is
///   replaced by this Sill's (macOS asks only when the versions differ), one waiting for approval waits on.
/// - Only Sill.app's own code asks for real, and only from the Applications folder with Sill Camera inside and the
///   install entitlement in its signature; any other Sill.app says why without asking (`refusal`). The bare binary's
///   dry run says what it would ask.
/// - Off again leaves Sill Camera installed and unused (§18 Q19: removing it asks an administrator each time, and an
///   app keeps the camera it was set to): Sill stops feeding it, so it shows its own words. Remove Sill Camera… takes
///   it away, the switch going off with it.
/// - Once Sill's feed reaches Sill Camera, it works, whatever this launch's request says (`shown`).
enum CameraExtensionPolicy {
    /// Sill Camera's bundle identifier, the name of its folder in Contents/Library/SystemExtensions.
    static let identifier = "me.saffer.sill.mac.camera"
    /// SystemExtensions' error domain (OSSystemExtensionErrorDomain).
    static let errorDomain = "OSSystemExtensionErrorDomain"

    // MARK: What Sill knows of itself, read once at launch

    struct Facts: Equatable {
        /// Sill.app's own code: its requests are real. The bare binary's are a dry run.
        var real: Bool
        /// Running from /Applications, the only place macOS activates an extension from.
        var inApplications: Bool
        /// Sill Camera inside this Sill (Scripts/make-app.sh with SILL_CAMERA_EXTENSION=1).
        var extensionInside: Bool
        /// com.apple.developer.system-extension.install in its signature (a profile with the capability).
        var entitled: Bool
        /// The build of Sill Camera this Mac's Sill last activated (remembered across launches); nil when none is.
        var installedBuild: String?
        /// This Sill's Sill Camera build.
        var build: String
    }

    /// Why a real Sill.app asks nothing, which it says instead: no Sill Camera it may install, or not in the
    /// Applications folder. Nil when it asks (always for the dry run, which asks nobody).
    static func refusal(_ f: Facts) -> CameraExtensionState? {
        guard f.real else { return nil }
        if !f.extensionInside || !f.entitled { return .unsupportedBuild }
        if !f.inApplications { return .needsApplications }
        return nil
    }

    // MARK: The request, and what came back

    /// An error macOS answered with: its domain and code.
    struct Failure: Equatable {
        var domain: String
        var code: Int
        static func systemExtension(_ code: Int) -> Failure { Failure(domain: CameraExtensionPolicy.errorDomain, code: code) }
        var isSystemExtension: Bool { domain == CameraExtensionPolicy.errorDomain }
    }

    /// What this launch asked of macOS and the last answer.
    enum Request: Equatable {
        /// Nothing asked this launch.
        case none
        /// An activation asked, no answer yet.
        case activating(Activating)
        /// macOS waits for an administrator to allow it in System Settings (the request stays pending while Sill runs).
        case needsApproval
        case activated
        /// Active once this Mac restarts.
        case rebootNeeded
        case failed(Failure)
        case removing
        case removed
        case removeFailed(Failure)
    }

    /// What an activation does, by what this Mac's Sill last activated: a first install, a start of the one installed,
    /// or an update of an older (or other) build to this Sill's.
    enum Activating: Equatable { case install, start, update }

    struct Model: Equatable {
        var facts: Facts
        var switchOn = false
        var request: Request = .none
        /// The person turned Sill Camera off in System Settings (macOS 15.1 and later say so).
        var disabledInSettings = false
        init(facts: Facts) { self.facts = facts }
    }

    enum Event: Equatable {
        /// Use iPhone and iPad cameras, at launch and as the person turns it.
        case switchChanged(Bool)
        /// Try Again, after a failure.
        case tryAgain
        /// Remove Sill Camera… (the switch goes off with it).
        case remove
        /// macOS's answers to an activation.
        case replacing(from: String, to: String)
        case needsApproval
        case completed
        case completesAfterReboot
        case failed(Failure)
        /// macOS's answers to a removal.
        case removeCompleted
        case removeFailed(Failure)
        /// macOS 15.1 and later: the person turned Sill Camera on or off in System Settings.
        case enabledInSettings(Bool)
    }

    enum Effect: Equatable {
        /// Submit an activation request (OSSystemExtensionRequest.activationRequest).
        case activate
        /// Submit a deactivation request.
        case deactivate
        /// Remember the build now installed (nil: none).
        case remember(String?)
        case line(String)
    }

    static func handle(_ event: Event, _ m: inout Model) -> [Effect] {
        switch event {
        case .switchChanged(let on):
            guard on != m.switchOn else { return [] }
            m.switchOn = on
            if on { return ask(&m) }
            // Nothing to cancel: an activation that waits for approval stays pending until Sill quits, and an approval
            // given meanwhile still installs Sill Camera (`completed` remembers it); a removal under way goes on.
            switch m.request {
            case .removing, .removed, .removeFailed: break
            default: m.request = .none
            }
            return [.line("Camera extension: Use iPhone and iPad cameras off; Sill Camera \(m.facts.installedBuild == nil ? "is not installed" : "stays installed, unused").")]
        case .tryAgain:
            guard m.switchOn else { return [] }
            return ask(&m)
        case .remove:
            m.switchOn = false
            m.request = .removing
            return [.deactivate, .line("Camera extension: removal requested\(m.facts.real ? "" : " (dry run: nothing asked of macOS)").")]
        case .replacing(let from, let to):
            guard case .activating = m.request else { return [] }
            m.request = .activating(.update)
            return [.line("Camera extension: replacing build \(from) with \(to).")]
        case .needsApproval:
            guard case .activating = m.request else { return [] }
            m.request = .needsApproval
            return [.line("Camera extension: waits for approval in System Settings.")]
        case .completed:
            // Remembered whatever the switch says now: an approval given after it went off still installed it.
            m.request = m.switchOn ? .activated : .none
            m.disabledInSettings = false
            m.facts.installedBuild = m.facts.build
            return [.remember(m.facts.build), .line("Camera extension: activated (build \(m.facts.build)).")]
        case .completesAfterReboot:
            m.request = m.switchOn ? .rebootNeeded : .none
            m.facts.installedBuild = m.facts.build
            return [.remember(m.facts.build), .line("Camera extension: activated once this Mac restarts (build \(m.facts.build)).")]
        case .failed(let f):
            // A newer request took the place of an earlier one: its own answer follows.
            if f == .systemExtension(12) { return [] }
            if m.switchOn { m.request = .failed(f) }
            return [.line("Camera extension: failed: \(reason(f)).")]
        case .removeCompleted:
            m.request = .removed
            m.facts.installedBuild = nil
            return [.remember(nil), .line("Camera extension: removed.")]
        case .removeFailed(let f):
            // Not there to remove: as good as removed (an install this Mac's Sill no longer remembers right).
            if f == .systemExtension(4) {
                m.request = .removed
                m.facts.installedBuild = nil
                return [.remember(nil), .line("Camera extension: removed (it was not installed).")]
            }
            m.request = .removeFailed(f)
            return [.line("Camera extension: removal failed: \(reason(f)).")]
        case .enabledInSettings(let on):
            guard m.disabledInSettings == on else { return [] }
            m.disabledInSettings = !on
            return [.line("Camera extension: turned \(on ? "on" : "off") in System Settings.")]
        }
    }

    /// The switch went on, or Try Again: an activation, unless a real Sill.app may not ask (it says why instead).
    private static func ask(_ m: inout Model) -> [Effect] {
        if let r = refusal(m.facts) {
            m.request = .none
            return [.line("Camera extension: not asked: \(words(r, macOS: 15).line ?? "\(r)")")]
        }
        let kind: Activating = m.facts.installedBuild == nil ? .install : (m.facts.installedBuild == m.facts.build ? .start : .update)
        m.request = .activating(kind)
        return [.activate, .line("Camera extension: activation requested\(m.facts.real ? "" : " (dry run: nothing asked of macOS)").")]
    }

    /// An error in a few words, for the section's failure line and the log.
    static func reason(_ f: Failure) -> String {
        guard f.isSystemExtension else { return "error \(f.code) (\(f.domain))" }
        switch f.code {
        case 1: return "macOS gave no reason"
        case 2: return "this build of Sill isn’t allowed to install it"
        case 3: return "Sill isn’t in the Applications folder"
        case 4: return "this build of Sill has no Sill Camera inside"
        case 5: return "its bundle has no identifier"
        case 6: return "another copy of it is in the way"
        case 7: return "macOS doesn’t know its kind of extension"
        case 8: return "its signature isn’t valid"
        case 9: return "macOS couldn’t validate it"
        case 10: return "this Mac’s administrator doesn’t allow it"
        case 11: return "the request was cancelled"
        case 12: return "a newer request took its place"
        case 13: return "an administrator has to allow it"
        default: return "error \(f.code)"
        }
    }

    // MARK: What the section shows

    /// Sill's feed into Sill Camera (CameraSink), as the section needs it.
    enum Sink: Equatable {
        /// Not looking: the switch is off.
        case stopped
        /// Looking for Sill Camera's device, which is not there yet.
        case looking
        /// Its sink stream runs: Sill Camera takes Sill's frames.
        case feeding
        /// The device is there but its sink would not start (Sill Camera refused Sill's feed, or another error).
        case refused
        /// macOS denied Sill access to cameras, which starting the sink may need (docs/camera-plan.md §17, V2).
        case cameraDenied
    }

    /// An app on this Mac using Sill Camera with a device's camera: the app (nil when Sill Camera cannot tell) and the
    /// device's name.
    struct Use: Equatable {
        var app: String?
        var device: String
    }

    static func shown(_ m: Model, sink: Sink, use: Use?) -> CameraExtensionState {
        guard m.switchOn else {
            switch m.request {
            case .removing: return .removing
            case .removed: return .removed
            case .removeFailed(let f): return .removeFailed(reason(f))
            default: return .off(installed: m.facts.installedBuild != nil)
            }
        }
        // Sill's feed reaches Sill Camera: it works, whatever this launch's request says.
        if sink == .feeding { return use.map { .inUse(app: $0.app, device: $0.device) } ?? .ready }
        if sink == .cameraDenied { return .cameraDenied }
        if m.disabledInSettings { return .disabledInSettings }
        if let r = refusal(m.facts) { return r }
        switch m.request {
        case .none, .activating(.start): return .starting
        case .activating(.install): return .installing
        case .activating(.update): return .updating
        case .needsApproval: return .awaitingApproval
        case .activated: return sink == .refused ? .notFed : .starting
        case .rebootNeeded: return .needsRestart
        case .failed(let f):
            guard f.isSystemExtension else { return .failed(reason(f)) }
            switch f.code {
            case 2, 4: return .unsupportedBuild
            case 3: return .needsApplications
            case 10: return .forbidden
            default: return .failed(reason(f))
            }
        case .removing: return .removing
        case .removed: return .removed
        case .removeFailed(let f): return .removeFailed(reason(f))
        }
    }

    // MARK: The words

    enum Copy {
        static let header = "Camera and Microphone (beta)"
        static let toggle = "Use iPhone and iPad cameras"
        static let footnote = "Apps on this Mac, such as FaceTime and Zoom, can choose “Sill Camera” to use the camera of a connected iPhone or iPad that has Share Camera on. Its camera turns on only while an app here uses it. Sill installs Sill Camera once, and an administrator allows it in System Settings."
        static let openSettings = "Open System Settings…"
        static let tryAgain = "Try Again"
        static let remove = "Remove Sill Camera…"
        /// The card's camera row: "Camera: FaceTime" over "iPad’s camera".
        static func cardTitle(app: String?) -> String { "Camera: \(app.flatMap { $0.isEmpty ? nil : $0 } ?? "In Use")" }
        static func cardDetail(device: String) -> String { "\(device)’s camera" }
    }

    /// Where Open System Settings… goes: Login Items & Extensions (macOS 15 and later: the approval and the switch
    /// for Sill Camera), Privacy & Security (macOS 14's approval), or Privacy & Security › Camera.
    enum Pane: Equatable { case loginItems, privacySecurity, camera }

    enum Button: Equatable {
        case openSettings(Pane)
        case tryAgain
    }

    struct Words: Equatable {
        /// The status line under the switch; nil when the switch and its footnote say it all.
        var line: String?
        /// Drawn as a problem (orange, with its sign).
        var attention: Bool
        var button: Button?
        /// Remove Sill Camera… beside it.
        var remove: Bool
    }

    /// `macOS`: the running macOS's major version (14 asks for approval in Privacy & Security, 15 and later in Login
    /// Items & Extensions).
    static func words(_ s: CameraExtensionState, macOS: Int) -> Words {
        let loginItems = macOS >= 15
        switch s {
        case .off(let installed):
            return installed
                ? Words(line: "Sill Camera stays installed while this is off, and apps still list it.", attention: false, button: nil, remove: true)
                : Words(line: nil, attention: false, button: nil, remove: false)
        case .installing:
            return Words(line: "Installing Sill Camera…", attention: false, button: nil, remove: false)
        case .starting:
            return Words(line: "Starting Sill Camera…", attention: false, button: nil, remove: false)
        case .updating:
            return Words(line: "Updating Sill Camera to this version of Sill…", attention: false, button: nil, remove: false)
        case .awaitingApproval:
            return Words(line: loginItems
                         ? "Waiting for approval: in System Settings › General › Login Items & Extensions, click ⓘ beside Camera Extensions and turn on Sill Camera."
                         : "Waiting for approval: in System Settings › Privacy & Security, click Allow for Sill.",
                         attention: true, button: .openSettings(loginItems ? .loginItems : .privacySecurity), remove: false)
        case .needsApplications:
            return Words(line: "Move Sill to the Applications folder, open it from there, and turn this on again.", attention: true, button: nil, remove: false)
        case .disabledInSettings:
            return Words(line: "Sill Camera is turned off in System Settings › General › Login Items & Extensions.",
                         attention: true, button: .openSettings(.loginItems), remove: true)
        case .forbidden:
            return Words(line: "This Mac’s administrator doesn’t allow camera extensions from other developers.", attention: true, button: nil, remove: false)
        case .unsupportedBuild:
            return Words(line: "This build of Sill can’t install Sill Camera.", attention: true, button: nil, remove: false)
        case .needsRestart:
            return Words(line: "Restart this Mac to finish installing Sill Camera.", attention: true, button: nil, remove: false)
        case .cameraDenied:
            return Words(line: "Sill isn’t allowed to use cameras, which it needs to pass a device’s camera to apps here. In System Settings › Privacy & Security › Camera, turn on Sill.",
                         attention: true, button: .openSettings(.camera), remove: true)
        case .notFed:
            return Words(line: "Sill Camera is installed but didn’t take Sill’s pictures. Turn this off and on to try again.", attention: true, button: nil, remove: true)
        case .ready:
            return Words(line: "Ready. Apps on this Mac can choose “Sill Camera”.", attention: false, button: nil, remove: true)
        case .inUse(let app, let device):
            return Words(line: "In use by \(app.flatMap { $0.isEmpty ? nil : $0 } ?? "an app"), with \(device)’s camera.", attention: false, button: nil, remove: true)
        case .failed(let reason):
            return Words(line: "Couldn’t install Sill Camera: \(reason).", attention: true, button: .tryAgain, remove: false)
        case .removing:
            return Words(line: "Removing Sill Camera…", attention: false, button: nil, remove: false)
        case .removed:
            return Words(line: "Sill Camera was removed.", attention: false, button: nil, remove: false)
        case .removeFailed(let reason):
            return Words(line: "Couldn’t remove Sill Camera: \(reason).", attention: true, button: nil, remove: true)
        }
    }

    // MARK: TEST ONLY: the dry run's answers

    /// The bare binary's `-SillCameraDryRun '<s> <answer>[; …]'`: what macOS would answer, s seconds after the dry run's
    /// request (activation or removal), one of `approval`, `complete`, `reboot`, `replace:A>B`, `fail:N`, `disabled`,
    /// `enabled`, `removed` and `removefail:N`. Nil when a step does not read (the whole is refused), or there are more
    /// than 16. Without it the dry run answers an activation as macOS answers a build with no Sill Camera inside (code
    /// 4) and a removal as one with nothing to remove (code 4 again: removed).
    static func dryRunScript(_ raw: String) -> [(at: Double, event: Event)]? {
        var steps: [(at: Double, event: Event)] = []
        for part in raw.split(separator: ";") {
            let words = part.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard words.count == 2, let at = Double(words[0]), at.isFinite, at >= 0, at <= 600 else { return nil }
            let w = words[1]
            let event: Event
            if w == "approval" { event = .needsApproval }
            else if w == "complete" { event = .completed }
            else if w == "reboot" { event = .completesAfterReboot }
            else if w == "disabled" { event = .enabledInSettings(false) }
            else if w == "enabled" { event = .enabledInSettings(true) }
            else if w == "removed" { event = .removeCompleted }
            else if w.hasPrefix("fail:"), let n = Int(w.dropFirst(5)), (1...99).contains(n) { event = .failed(.systemExtension(n)) }
            else if w.hasPrefix("removefail:"), let n = Int(w.dropFirst(11)), (1...99).contains(n) { event = .removeFailed(.systemExtension(n)) }
            else if w.hasPrefix("replace:") {
                let builds = w.dropFirst(8).split(separator: ">", omittingEmptySubsequences: false).map(String.init)
                guard builds.count == 2, !builds[0].isEmpty, !builds[1].isEmpty, builds.allSatisfy({ $0.count <= 16 }) else { return nil }
                event = .replacing(from: builds[0], to: builds[1])
            } else { return nil }
            steps.append((at, event))
        }
        guard !steps.isEmpty, steps.count <= 16 else { return nil }
        return steps.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
    }
}

/// What Settings › Streaming's camera section says (CameraExtensionPolicy.shown, .words).
enum CameraExtensionState: Equatable {
    /// The switch is off: nothing asked. `installed`: Sill Camera stays installed from an earlier activation here.
    case off(installed: Bool)
    case installing
    case starting
    /// An older Sill Camera is being replaced by this Sill's.
    case updating
    case awaitingApproval
    case needsApplications
    case disabledInSettings
    case forbidden
    case unsupportedBuild
    case needsRestart
    case cameraDenied
    /// Installed and active, but Sill's feed did not start.
    case notFed
    case ready
    case inUse(app: String?, device: String)
    case failed(String)
    case removing
    case removed
    case removeFailed(String)
}
