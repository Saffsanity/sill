import AppKit
import Observation
import Security
import SystemExtensions

/// Sill Camera's installation (docs/camera-plan.md §7, step 8): carries out CameraExtensionPolicy, which decides, with
/// `CameraExtensionSystem`, the seam that asks macOS. Main actor; the section in Settings › Streaming observes it.
///
/// Only Sill.app's own code, from /Applications, with Sill Camera inside and the install entitlement in its signature,
/// asks macOS for real (`SystemCameraExtension`, OSSystemExtensionRequest). Every other Sill.app says why instead, and
/// the bare SillMenuBar binary (previews, gates) has the TEST ONLY dry run, which says what it would ask and plays the
/// answers `-SillCameraDryRun` scripts. Nothing is asked while the switch is off, nor while the model is being made:
/// the previews render from a model that never started.
@MainActor @Observable
final class CameraExtensionManager {
    /// The policy's state (the request, the switch, Sill Camera turned off in System Settings).
    private(set) var model: CameraExtensionPolicy.Model
    @ObservationIgnored private let system: CameraExtensionSystem
    @ObservationIgnored private let defaults: UserDefaults
    /// Where the build of Sill Camera this Mac's Sill last activated is remembered (`defaults read me.saffer.sill.mac`).
    static let installedKey = "cameraExtensionBuild"

    init(facts: CameraExtensionPolicy.Facts, system: CameraExtensionSystem, defaults: UserDefaults) {
        model = CameraExtensionPolicy.Model(facts: facts)
        self.system = system
        self.defaults = defaults
        system.answer = { [weak self] event in self?.handle(event) }
    }

    /// The switch at launch (once the host is up) and as the person turns it.
    func switchChanged(_ on: Bool) { handle(.switchChanged(on)) }
    func tryAgain() { handle(.tryAgain) }
    /// Remove Sill Camera…: the model's caller turns the switch off first, so nothing feeds it while it goes.
    func remove() { handle(.remove) }

    private func handle(_ event: CameraExtensionPolicy.Event) {
        for effect in CameraExtensionPolicy.handle(event, &model) {
            switch effect {
            case .activate: system.activate()
            case .deactivate: system.deactivate()
            case .remember(let build):
                if let build { defaults.set(build, forKey: Self.installedKey) } else { defaults.removeObject(forKey: Self.installedKey) }
            case .line(let line): print(line)
            }
        }
    }

    // MARK: What this Sill is

    /// Read once at launch: real only for Sill.app's own code (`AppModel.bundled`); the folder it runs from, Sill Camera
    /// inside it, the install entitlement in its own signature (nil in every build whose profile lacks the System
    /// Extension capability, and in every development build), and what was installed before.
    static func facts(real: Bool, defaults: UserDefaults) -> CameraExtensionPolicy.Facts {
        let bundle = Bundle.main.bundleURL
        let inside = bundle.appendingPathComponent("Contents/Library/SystemExtensions/\(CameraExtensionPolicy.identifier).systemextension")
        let extensionInside = FileManager.default.fileExists(atPath: inside.path)
        let build = Bundle(url: inside)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        return CameraExtensionPolicy.Facts(real: real, inApplications: bundle.path.hasPrefix("/Applications/"),
                                           extensionInside: extensionInside, entitled: installEntitlement(),
                                           installedBuild: defaults.string(forKey: installedKey), build: build)
    }

    /// Whether this process's own signature holds com.apple.developer.system-extension.install (true). Reads only this
    /// process's entitlements.
    static func installEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.system-extension.install" as CFString, nil) else { return false }
        return (value as? Bool) == true
    }

    /// The running macOS's major version, for the approval's words.
    static var macOS: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// Open System Settings… (the person's click): the pane the words name.
    static func open(_ pane: CameraExtensionPolicy.Pane) {
        let id: String
        switch pane {
        case .loginItems: id = "com.apple.LoginItems-Settings.extension"
        case .privacySecurity: id = "com.apple.settings.PrivacySecurity.extension"
        case .camera: id = "com.apple.preference.security?Privacy_Camera"
        }
        if let url = URL(string: "x-apple.systempreferences:\(id)") { NSWorkspace.shared.open(url) }
    }
}

/// What asks macOS (OSSystemExtensionRequest), or the TEST ONLY dry run. Main actor; `answer` carries macOS's answers.
@MainActor
protocol CameraExtensionSystem: AnyObject {
    var answer: ((CameraExtensionPolicy.Event) -> Void)? { get set }
    func activate()
    func deactivate()
}

/// The real requests: Sill Camera's activation (and its replacement, approval and failures) and removal, with the
/// delegate answering on the main queue; on macOS 15.1 and later also System Settings' own switch for Sill Camera
/// (OSSystemExtensionsWorkspace). Never a modal of Sill's own: macOS shows its alert ("“Sill” would like to use a new
/// camera extension"). Made only for Sill.app's own code (AppModel), and asked only when the policy says it may.
@MainActor
final class SystemCameraExtension: NSObject, CameraExtensionSystem, OSSystemExtensionRequestDelegate {
    var answer: ((CameraExtensionPolicy.Event) -> Void)?
    /// The removals in flight, by request (a request holds its delegate weakly; macOS holds the request while it runs).
    private var removing: Set<ObjectIdentifier> = []
    private var watching = false

    func activate() {
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: CameraExtensionPolicy.identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        watchSettings()
    }

    func deactivate() {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: CameraExtensionPolicy.identifier, queue: .main)
        request.delegate = self
        removing.insert(ObjectIdentifier(request))
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// macOS 15.1 and later: System Settings' switch for Sill Camera, as the person turns it.
    private func watchSettings() {
        guard !watching else { return }
        watching = true
        if #available(macOS 15.1, *) {
            do { try OSSystemExtensionsWorkspace.shared.addObserver(self) }
            catch { print("Camera extension: System Settings’ switch for it can’t be followed (\(error.localizedDescription)).") }
        }
    }

    // The delegate's queue is the main queue (the requests above), and Sill.app always runs NSApplication, so its
    // callbacks are on the main actor (AppDelegate's rule for app code).

    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // macOS asks only when the builds differ: the one inside this Sill is the one its feed speaks to.
        let from = existing.bundleVersion, to = ext.bundleVersion
        MainActor.assumeIsolated { answer?(.replacing(from: from, to: to)) }
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        MainActor.assumeIsolated { answer?(.needsApproval) }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let id = ObjectIdentifier(request)
        MainActor.assumeIsolated {
            if removing.remove(id) != nil { answer?(.removeCompleted); return }
            answer?(result == .willCompleteAfterReboot ? .completesAfterReboot : .completed)
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let id = ObjectIdentifier(request)
        let e = error as NSError
        let failure = CameraExtensionPolicy.Failure(domain: e.domain, code: e.code)
        MainActor.assumeIsolated {
            if removing.remove(id) != nil { answer?(.removeFailed(failure)); return }
            answer?(.failed(failure))
        }
    }
}

@available(macOS 15.1, *)
extension SystemCameraExtension: OSSystemExtensionsWorkspaceObserver {
    // On whatever queue macOS calls these: hopped to the main queue.
    nonisolated func systemExtensionWillBecomeEnabled(_ info: OSSystemExtensionInfo) {
        guard info.bundleIdentifier == CameraExtensionPolicy.identifier else { return }
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.answer?(.enabledInSettings(true)) } }
    }

    nonisolated func systemExtensionWillBecomeDisabled(_ info: OSSystemExtensionInfo) {
        guard info.bundleIdentifier == CameraExtensionPolicy.identifier else { return }
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.answer?(.enabledInSettings(false)) } }
    }

    nonisolated func systemExtensionWillBecomeInactive(_ info: OSSystemExtensionInfo) {}
}

/// TEST ONLY: the bare SillMenuBar binary's stand-in for OSSystemExtensionRequest, which never asks macOS anything. It
/// prints what it would ask and plays the answers of `-SillCameraDryRun` (CameraExtensionPolicy.dryRunScript), counted
/// from each request; without a script, the answers macOS gives a build with no Sill Camera inside.
final class DryRunCameraExtension: CameraExtensionSystem {
    var answer: ((CameraExtensionPolicy.Event) -> Void)?
    private let script: [(at: Double, event: CameraExtensionPolicy.Event)]?

    init(script: [(at: Double, event: CameraExtensionPolicy.Event)]?) { self.script = script }

    func activate() {
        print("Camera extension (dry run): would ask macOS to activate Sill Camera (\(CameraExtensionPolicy.identifier)).")
        play(script ?? [(0.2, .failed(.systemExtension(4)))], removal: false)
    }

    func deactivate() {
        print("Camera extension (dry run): would ask macOS to remove Sill Camera (\(CameraExtensionPolicy.identifier)).")
        play(script ?? [(0.2, .removeFailed(.systemExtension(4)))], removal: true)
    }

    /// The script's steps after `at` seconds each, on run-loop Timers (AppDelegate's modal-loop rule): an activation
    /// plays the activation's answers, a removal the removal's.
    private func play(_ steps: [(at: Double, event: CameraExtensionPolicy.Event)], removal: Bool) {
        for (at, event) in steps {
            let isRemoval: Bool
            switch event {
            case .removeCompleted, .removeFailed: isRemoval = true
            default: isRemoval = false
            }
            guard isRemoval == removal else { continue }
            let timer = Timer(timeInterval: at, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    print("Camera extension (dry run): macOS would answer \(event).")
                    self?.answer?(event)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
