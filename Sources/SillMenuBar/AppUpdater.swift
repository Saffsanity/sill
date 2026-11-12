import AppKit
import Foundation
import Observation
import Security
import StreamProtocol

/// Update Now in Sill.app (docs/one-click-update-plan.md §5): where Sill runs (the facts
/// UpdateInstallPolicy decides from), the steps run through UpdateInstaller, the launch of the new copy,
/// the quit, the wait at launch for a Sill that is quitting, and the clean-up after a start.
///
/// It passes UpdateInstaller only `Trust.release` and `Endpoints.github`, and reads no default, no
/// variable and no argument: a test feed or a test version given to the update check
/// (`-SillUpdateFeed`, `-SillUpdateVersion`) makes Update Now unavailable instead. With no update key
/// compiled in (UpdateManifest.releaseKeys, empty until Noah makes the key) it is not available at all,
/// and Settings and the menu show what they showed before it.
///
/// Main actor. The network steps run in Tasks, the file steps in detached Tasks; each answer carries
/// the attempt it belongs to, and an answer for an attempt that was cancelled or replaced is dropped.
/// The quit starts from a run-loop Timer, never a Task (AppDelegate's modal-loop rule).
@MainActor @Observable
final class AppUpdater {
    typealias Policy = UpdateInstallPolicy

    private(set) var state = Policy.State()
    /// Why Update Now cannot run here, at the last look.
    private(set) var refusal: Policy.Refusal?
    /// Where the old copy is when it could not be put back (the person's way back).
    private(set) var keptAt: String?
    /// Update Now exists in this build: Sill.app itself, in a .app bundle, with an update key compiled in.
    let available: Bool

    /// Wired by AppModel: the release the check offers; whether the check runs on a test feed or a test
    /// version; the names of the connected devices.
    @ObservationIgnored var offer: () -> UpdatePolicy.Offer? = { nil }
    @ObservationIgnored var checkerUsesTestValues: () -> Bool = { false }
    @ObservationIgnored var devices: () -> [String] = { [] }

    @ObservationIgnored private let installer: UpdateInstaller
    @ObservationIgnored private let bundle: URL
    /// This bundle's own version (its signed Info.plist, read at launch), never a test version.
    @ObservationIgnored private let runningVersion: SillVersion?
    @ObservationIgnored private var runningCodeCache: UpdateInstaller.RunningCode?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var cancel: UpdateInstaller.Cancel?
    @ObservationIgnored private var staging: URL?
    @ObservationIgnored private var prepared: (release: Policy.Release, manifest: UpdateManifest)?
    @ObservationIgnored private var zip: URL?
    @ObservationIgnored private var unpacked: URL?
    @ObservationIgnored private var checked: Policy.Checked?
    @ObservationIgnored private var watch: Timer?
    @ObservationIgnored private var shownProgress: (Int64, Date) = (0, .distantPast)
    @ObservationIgnored private var loggedRefusal: Policy.Refusal?

    init(bundled: Bool) {
        let trust = Policy.Trust.release
        bundle = Bundle.main.bundleURL
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        runningVersion = version.flatMap(Policy.strictVersion)
        available = bundled && !trust.updateKeys.isEmpty && bundle.pathExtension == "app" && runningVersion != nil
        installer = UpdateInstaller(trust: trust, endpoints: .github, userAgent: "Sill/\(version ?? "unknown")")
    }

    /// The running code's facts, read once (Security.framework: a few milliseconds).
    private var runningCode: UpdateInstaller.RunningCode {
        if let c = runningCodeCache { return c }
        let c = UpdateInstaller.runningCode(trust: installer.trust)
        runningCodeCache = c
        return c
    }

    // MARK: What Settings and the menu show

    /// Update Now shows for the offer: this build has it, and the release is signed for it (its manifest
    /// listed), or an update of it has begun. A release Noah has not signed yet shows as before: Open
    /// Release Page… alone.
    private var shown: Bool {
        guard available, let offer = offer() else { return false }
        if case .idle = state.phase { return offer.signed }
        return true
    }

    var pane: Policy.Pane {
        Policy.pane(state, offered: offer()?.version, running: runningVersion, available: shown, refusal: refusal, keptAt: keptAt)
    }

    var menu: MenuBuilder.UpdateMenuState {
        MenuBuilder.UpdateMenuState(phase: state.phase, available: shown, refusal: refusal)
    }

    /// Looks again at where Sill runs: Settings › General calls it while it shows, and Update Now first.
    /// Nothing while no release is offered or an update is under way.
    func refresh() {
        guard shown, !state.phase.busy else { return }
        let installed = UpdateInstaller.runningIsInstalled(bundle).0
        let s = UpdateInstaller.situation(bundle: bundle, runningIsRelease: runningCode.isRelease, testFeed: checkerUsesTestValues(),
                                          runningIsInstalled: installed, neededBytes: Policy.neededBytes(assetBytes: 8 << 20))
        let r = Policy.refusal(s)
        if r != refusal { refusal = r }
        if let r, r != loggedRefusal {
            loggedRefusal = r
            print("Update Now unavailable: \(Policy.words(r))")
        }
    }

    // MARK: The person's buttons (SwiftUI Button actions)

    func updateNow() {
        guard shown, !state.phase.busy else { return }
        refresh()
        guard refusal == nil else { return }
        attempt += 1
        keptAt = nil
        send(.updateNow(devices: devices()))
    }

    func confirm() {
        send(.confirm)
    }

    func cancelUpdate() {
        cancel?.cancel()
        send(.cancel)
    }

    // MARK: Steps

    private func send(_ event: Policy.Event) {
        let (next, effects) = Policy.next(state, event)
        if next != state { state = next }
        for effect in effects { perform(effect) }
    }

    /// An answer for `run`, dropped when it belongs to an attempt since cancelled or replaced.
    private func deliver(_ run: Int, _ event: Policy.Event) {
        guard run == attempt else { return }
        send(event)
    }

    private func perform(_ effect: Policy.Effect) {
        let run = attempt
        switch effect {
        case .fetch: fetch(run)
        case .download: startDownload(run)
        case .unpack: startUnpack(run)
        case .check: startCheck(run)
        case .install: startInstall(run)
        case .launch: launchNewCopy(run)
        case .quit: quitForUpdate()
        case .cleanUp: cleanUp()
        }
    }

    private func fetch(_ run: Int) {
        guard let offer = offer(), let running = runningVersion else { deliver(run, .fetched(.releaseNotNewer)); return }
        let token = UpdateInstaller.Cancel()
        cancel = token
        switch UpdateInstaller.makeStaging(for: bundle) {
        case .failure(let f):
            log(f)
            deliver(run, .fetched(f))
            return
        case .success(let dir):
            staging = dir
        }
        print("Update: getting Sill \(offer.version) (\(offer.tag)) from GitHub.")
        let installer = self.installer
        Task { [weak self] in
            let result = await installer.prepare(offeredTag: offer.tag, running: running, cancel: token)
            guard let self else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.deliver(run, .fetched(f))
            case .success(let p):
                self.prepared = p
                print("Update: Sill \(p.release.version)’s manifest is signed with the update key \(p.manifest.keyID): \(p.manifest.size) bytes, SHA-256 \(p.manifest.sha256).")
                self.deliver(run, .fetched(nil))
            }
        }
    }

    private func startDownload(_ run: Int) {
        guard let prepared, let staging, let token = cancel else { deliver(run, .downloaded(.cancelled)); return }
        print("Update: downloading Sill \(prepared.release.version) (\(Policy.megabytes(prepared.manifest.size)) MB) from github.com.")
        let installer = self.installer
        Task { [weak self] in
            let result = await installer.download(prepared.release, manifest: prepared.manifest, into: staging,
                                                  progress: { received, total in
                                                      Task { @MainActor [weak self] in self?.progress(run, received, total) }
                                                  }, cancel: token)
            guard let self else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.deliver(run, .downloaded(f))
            case .success(let file):
                self.zip = file
                self.deliver(run, .downloaded(nil))
            }
        }
    }

    /// The download's progress, at most ten times a second and one percent at a time.
    private func progress(_ run: Int, _ received: Int64, _ total: Int64) {
        guard run == attempt, case .downloading = state.phase else { return }
        let now = Date()
        guard received == total || (received - shownProgress.0) * 100 >= total || now.timeIntervalSince(shownProgress.1) >= 0.1 else { return }
        shownProgress = (received, now)
        send(.progress(received: received, total: total))
    }

    private func startUnpack(_ run: Int) {
        guard let prepared, let staging, let zip, let token = cancel else { deliver(run, .unpacked(.cancelled)); return }
        let installer = self.installer
        let manifest = prepared.manifest
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                installer.unpack(zip, manifest: manifest, into: staging, cancel: token)
            }.value
            guard let self else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.deliver(run, .unpacked(f))
            case .success(let app):
                self.unpacked = app
                self.deliver(run, .unpacked(nil))
            }
        }
    }

    private func startCheck(_ run: Int) {
        guard let prepared, let unpacked, let running = runningVersion else { deliver(run, .checked(.cancelled, devices: [])); return }
        let installer = self.installer
        let manifest = prepared.manifest
        let requirement = runningCode.requirement
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                installer.check(unpacked, manifest: manifest, running: running, runningRequirement: requirement)
            }.value
            guard let self else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.deliver(run, .checked(f, devices: []))
            case .success(let c):
                self.checked = c
                print("Update: Sill \(c.version) (\(c.build)) checked: signed by Developer ID \(installer.trust.teamID ?? "-") as \(installer.trust.identifier), notarized, \(c.version) newer than \(running), the code the manifest names.")
                self.deliver(run, .checked(nil, devices: self.devices()))
            }
        }
    }

    private func startInstall(_ run: Int) {
        guard let prepared, let unpacked, let checked, let running = runningVersion else { deliver(run, .installed(.cancelled)); return }
        let (isInstalled, cdhash) = UpdateInstaller.runningIsInstalled(bundle)
        guard isInstalled, let cdhash else { deliver(run, .installed(.changedSinceStart)); return }
        let installer = self.installer
        let bundle = self.bundle
        let manifest = prepared.manifest
        let requirement = runningCode.requirement
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                installer.install(staged: unpacked, installed: bundle, runningCDHash: cdhash, expected: checked,
                                  manifest: manifest, running: running, runningRequirement: requirement)
            }.value
            guard let self else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                if !f.cleanUp { self.keptAt = unpacked.path }
                self.deliver(run, .installed(f))
            case .success:
                print("Update: replaced \(bundle.path) with Sill \(checked.version); Sill \(running) is kept at \(unpacked.path) until \(checked.version) has started.")
                self.deliver(run, .installed(nil))
            }
        }
    }

    /// The new copy as a new instance, beside this one (it waits for this one to quit before it starts
    /// anything: `waitForOtherSill`); this one quits once it has finished launching and its running code
    /// is the code that was checked. Anything else: it is stopped and the old copy put back.
    private func launchNewCopy(_ run: Int) {
        guard let checked else { didNotStart(run, "nothing was checked"); return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        config.addsToRecentItems = false
        config.promptsUserIfNeeded = false
        config.allowsRunningApplicationSubstitution = false
        print("Update: starting Sill \(checked.version) from \(bundle.path).")
        let started = Date()
        NSWorkspace.shared.openApplication(at: bundle, configuration: config) { app, error in
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in self?.opened(run, app, message, since: started) }
        }
    }

    private func opened(_ run: Int, _ app: NSRunningApplication?, _ error: String?, since started: Date) {
        guard run == attempt, case .restarting = state.phase, let checked else {
            app?.forceTerminate()
            return
        }
        guard let app else { didNotStart(run, error ?? "macOS didn’t start it"); return }
        let requirement = installer.launchRequirement(checked)
        let deadline = started.addingTimeInterval(Policy.launchWait)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                if app.isTerminated {
                    timer.invalidate()
                    self.didNotStart(run, "it quit as it started")
                } else if app.isFinishedLaunching {
                    timer.invalidate()
                    guard UpdateInstaller.process(app.processIdentifier, satisfies: requirement) else {
                        app.forceTerminate()
                        self.didNotStart(run, "the copy that started isn’t the one Sill checked")
                        return
                    }
                    print("Update: Sill \(checked.version) started (pid \(app.processIdentifier)) and is waiting for this Sill to quit; quitting.")
                    self.deliver(run, .launched(nil))
                } else if Date() >= deadline {
                    timer.invalidate()
                    app.forceTerminate()
                    self.didNotStart(run, "it didn’t finish starting within \(Int(Policy.launchWait)) seconds")
                }
            }
        }
        watch = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The new copy didn't come up: the old one back where it was (the new one goes with the staging
    /// folder), and why.
    private func didNotStart(_ run: Int, _ why: String) {
        var putBack = false
        if let unpacked { putBack = installer.putBack(staged: unpacked, installed: bundle) }
        if !putBack, let unpacked { keptAt = unpacked.path }
        let f = Policy.Failure.didNotStart(why, putBack: putBack)
        log(f)
        deliver(run, .launched(f))
    }

    /// Quits through the ordinary quit path (the streamed window home, the virtual display gone), from a
    /// run-loop Timer: NSApp.terminate can answer .terminateLater.
    private func quitForUpdate() {
        let timer = Timer(timeInterval: 0.2, repeats: false) { _ in NSApp.terminate(nil) }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cleanUp() {
        watch?.invalidate()
        watch = nil
        cancel = nil
        if let staging {
            DispatchQueue.global(qos: .utility).async { UpdateInstaller.remove(staging) }
        }
        staging = nil
        prepared = nil
        zip = nil
        unpacked = nil
        checked = nil
        shownProgress = (0, .distantPast)
    }

    private func log(_ f: Policy.Failure) {
        if f == .cancelled { print("Update: cancelled."); return }
        print("Update failed: \(Policy.logText(f)).")
        if !f.cleanUp, let unpacked { print("Update: Sill’s previous copy is kept at \(unpacked.path); to put it back, quit Sill and move it to \(bundle.deletingLastPathComponent().path).") }
    }

    // MARK: Launch and start

    /// Once this Sill's host has started: what earlier updates left in the temporary folder goes, the
    /// copy an update replaced among it (kept until now so it could be put back).
    func cleanUpAfterStart() {
        guard available else { return }
        let bundle = self.bundle
        DispatchQueue.global(qos: .utility).async {
            let removed = UpdateInstaller.cleanUpStaging(for: bundle)
            if !removed.isEmpty {
                print("Update: removed \(removed.count) folder\(removed.count == 1 ? "" : "s") an earlier update left (\(removed.joined(separator: ", "))).")
            }
        }
    }

    /// At launch: when another Sill of this account is running (the one that launched this copy after an
    /// update, which quits once this one has finished launching), this one starts nothing until it has
    /// quit, at most `Policy.launchWait`, then quits itself. True when it waits (`start` comes later).
    /// From applicationDidFinishLaunching; the Timer is a run-loop one (it may call NSApp.terminate).
    static func waitForOtherSill(then start: @escaping @MainActor () -> Void) -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != own && !$0.isTerminated }
        guard !others.isEmpty else { return false }
        let pids = others.map { String($0.processIdentifier) }.joined(separator: ", ")
        print("Another Sill is running (pid \(pids)); waiting for it to quit before starting.")
        let deadline = Date().addingTimeInterval(Policy.launchWait)
        let timer = Timer(timeInterval: 0.2, repeats: true) { timer in
            MainActor.assumeIsolated {
                if others.allSatisfy({ $0.isTerminated }) {
                    timer.invalidate()
                    print("The other Sill quit; starting.")
                    start()
                } else if Date() >= deadline {
                    timer.invalidate()
                    print("Another Sill is still running after \(Int(Policy.launchWait)) s (pid \(pids)); this one quits.")
                    NSApp.terminate(nil)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return true
    }
}
