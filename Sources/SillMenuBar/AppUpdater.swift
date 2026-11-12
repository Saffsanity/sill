import AppKit
import Foundation
import Observation
import Security
import StreamProtocol

/// Update Now and Automatically update Sill in Sill.app (docs/one-click-update-plan.md §5 and §15): where
/// Sill runs (the facts UpdateInstallPolicy decides from), the steps run through UpdateInstaller, the
/// launch of the new copy, the watcher that puts the old copy back if the new one doesn't run, the quit,
/// the wait at launch for a Sill that is quitting, and the clean-up after a start. One state machine for
/// both: the automatic update is the same steps and checks, begun by UpdateAutoPolicy after a daily check
/// instead of by a click, and installed only at a moment with no device connected, never over one.
///
/// It passes UpdateInstaller only `Trust.release` and `Endpoints.github`, and reads no default, no
/// variable and no argument: a test feed or a test version given to the update check makes Update Now
/// unavailable instead. With no update key compiled in (UpdateManifest.releaseKeys, empty until Noah
/// makes the key) it is not available at all, and Settings and the menu show what they showed before it.
///
/// Main actor. The network steps run in Tasks, the file steps (and the look at where Sill runs) in
/// detached Tasks; each answer carries the attempt it belongs to, and an answer for an attempt since
/// cancelled or replaced is dropped before it touches anything. The quit starts from a run-loop Timer,
/// never a Task (AppDelegate's modal-loop rule); so do the automatic update's looks for a quiet moment.
@MainActor @Observable
final class AppUpdater {
    typealias Policy = UpdateInstallPolicy
    typealias Auto = UpdateAutoPolicy

    private(set) var state = Policy.State()
    /// Why Update Now cannot run here, at the last look.
    private(set) var refusal: Policy.Refusal?
    /// Where the old copy is when it could not be put back (the person's way back).
    private(set) var keptAt: String?
    /// Update Now exists in this build: Sill.app itself, in a .app bundle, with an update key compiled in.
    let available: Bool
    /// Sill.app itself, in a .app bundle, with a version: it answers an update's watcher whatever its own
    /// key list says (a later Sill without Update Now must still tell the watcher it runs, or it is put back).
    @ObservationIgnored private let isApp: Bool
    /// What the automatic update remembers, its switch among it (AutoUpdateStore's, mirrored for Settings):
    /// the cooling-off's first sights among it (UpdateAutoPolicy.Memory.seen), across launches.
    private(set) var memory: Auto.Memory

    /// Wired by AppModel: the release the check offers; whether the check runs on a test feed or a test
    /// version; the connected devices; whether the daily check is on; whether a pairing window is open;
    /// and the host's hold on new sessions (StreamCoordinator.holdNewSessions: how many are connected).
    @ObservationIgnored var offer: () -> UpdatePolicy.Offer? = { nil }
    @ObservationIgnored var checkerUsesTestValues: () -> Bool = { false }
    @ObservationIgnored var devices: () -> [Policy.Device] = { [] }
    @ObservationIgnored var checkOn: () -> Bool = { false }
    @ObservationIgnored var pairing: () -> Bool = { false }
    @ObservationIgnored var hold: (Bool) -> Int = { _ in 0 }
    /// The check's latest release, newer or not (UpdateChecker.latest): Update Now's choice beside a nightly.
    @ObservationIgnored var latestRelease: () -> UpdatePolicy.Offer? = { nil }
    /// The newest nightly the last look found (plan §16), while "Use nightly builds" is on.
    private(set) var nightlyOffer: UpdatePolicy.Offer?

    @ObservationIgnored private let installer: UpdateInstaller
    /// The nightly channel's (Endpoints.nightly, the nightly key alone; plan §16).
    @ObservationIgnored private let nightlyInstaller: UpdateInstaller
    /// This bundle's build (CFBundleVersion) and whether it is a nightly (`SillChannel` in its signed Info.plist).
    @ObservationIgnored private let runningBuild: Int?
    @ObservationIgnored private let runningIsNightly: Bool
    @ObservationIgnored private var lookingAtNightly = false
    @ObservationIgnored private let store: AutoUpdateStore
    @ObservationIgnored private let bundle: URL
    /// This bundle's own version (its signed Info.plist, read at launch), never a test version.
    @ObservationIgnored private let runningVersion: SillVersion?
    @ObservationIgnored private var runningCodeCache: UpdateInstaller.RunningCode?
    /// The release the update under way is for: it goes on with it whatever a later check says.
    @ObservationIgnored private var target: UpdatePolicy.Offer?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var cancel: UpdateInstaller.Cancel?
    @ObservationIgnored private var staging: URL?
    @ObservationIgnored private var prepared: (release: Policy.Release, manifest: UpdateManifest)?
    @ObservationIgnored private var zip: URL?
    @ObservationIgnored private var unpacked: URL?
    @ObservationIgnored private var checked: Policy.Checked?
    /// The running code's cdhash, which the copy put aside by the swap must still show to be put back.
    @ObservationIgnored private var oldCDHash: String?
    /// The new Sill's process once it finished launching (the watcher's).
    @ObservationIgnored private var newPID: pid_t?
    @ObservationIgnored private var watch: Timer?
    @ObservationIgnored private var shownProgress: (Int64, Date) = (0, .distantPast)
    @ObservationIgnored private var loggedRefusal: Policy.Refusal?
    @ObservationIgnored private var refreshing = false
    /// What waits for the look in flight (a click while Settings' once-a-second look runs).
    @ObservationIgnored private var afterRefresh: [(Policy.Refusal?) -> Void] = []
    /// The automatic update's wait for a quiet moment: since when the copy waits, since when no device
    /// was seen, the Timer that looks, GitHub asked again, and the host's hold on new sessions.
    @ObservationIgnored private var waitingSince: Date?
    @ObservationIgnored private var quietSince = Date()
    @ObservationIgnored private var quietTimer: Timer?
    @ObservationIgnored private var asking = false
    @ObservationIgnored private var holding = false
    @ObservationIgnored private var loggedAutomatic: String?
    /// The person quit Sill while an install step ran (AppDelegate): the new copy is not started then.
    @ObservationIgnored private var quitting = false
    /// The notes an earlier Sill left were read (`afterHostUp`, off the main actor), or there are none to read
    /// (the host didn't start): the automatic update waits for that, so what they say (a put-back) is known
    /// before it begins anything.
    @ObservationIgnored private var notesSettled = false
    @ObservationIgnored private var considerWhenSettled = false

    init(bundled: Bool, accessGroup: String?) {
        let trust = Policy.Trust.release
        bundle = Bundle.main.bundleURL
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        runningVersion = version.flatMap(Policy.strictVersion)
        isApp = bundled && bundle.pathExtension == "app" && runningVersion != nil
        let available = isApp && !trust.updateKeys.isEmpty
        self.available = available
        installer = UpdateInstaller(trust: trust, endpoints: .github, userAgent: "Sill/\(version ?? "unknown")")
        nightlyInstaller = UpdateInstaller(trust: trust, endpoints: .nightly, userAgent: "Sill/\(version ?? "unknown")")
        runningBuild = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { UpdateManifest.isDigits($0, 1...9) ? Int($0) : nil }
        runningIsNightly = Bundle.main.object(forInfoDictionaryKey: "SillChannel") as? String == UpdateManifest.nightlyTag
        // Read only where the switch can be: a build without an update key reads no keychain item.
        store = AutoUpdateStore(accessGroup: available ? accessGroup : nil)
        memory = store.memory
    }

    /// The running code's facts, read once (Security.framework: a few milliseconds).
    private var runningCode: UpdateInstaller.RunningCode {
        if let c = runningCodeCache { return c }
        let c = UpdateInstaller.runningCode(trust: installer.trust)
        runningCodeCache = c
        return c
    }

    // MARK: What Settings and the menu show

    private var idle: Bool { if case .idle = state.phase { return true }; return false }
    /// An update may begin: none is under way, asked about or waiting.
    private var mayBegin: Bool {
        switch state.phase {
        case .idle, .failed: return true
        default: return false
        }
    }

    /// The automatic update may begin: as `mayBegin`, but never after a failure that left Sill's old copy out
    /// of place (its way back shown in Settings stays the person's, as Try Again does: dimmed).
    private var mayBeginAutomatic: Bool {
        if case .failed(let f) = state.phase, !f.cleanUp { return false }
        return mayBegin && keptAt == nil
    }

    /// The release Update Now's part of the pane is about: the check's offer while nothing runs, when it is
    /// signed for Update Now (a release Noah has not signed yet shows as before: Open Release Page… alone),
    /// else the release of the update under way.
    private var paneOffer: UpdatePolicy.Offer? {
        guard available else { return nil }
        if idle { return chosen.flatMap { $0.signed ? $0 : nil } }
        return target
    }

    /// The end of `offer`'s cooling-off from what this Sill remembers (a release's, or a nightly's while nightlies wait).
    private func waitUntil(_ offer: UpdatePolicy.Offer) -> Date? {
        guard let build = offer.build else { return Auto.waitUntil(memory, tag: offer.tag) }
        return Auto.nightlyCoolingOff > 0 ? Auto.waitUntil(memory, tag: Auto.key(offer.version, build: build), wait: Auto.nightlyCoolingOff) : nil
    }

    /// "Use nightly builds" in effect: on, and a nightly key compiled in.
    private var nightliesOn: Bool { memory.nightly && !installer.trust.nightlyKeys.isEmpty }

    /// What Update Now offers: UpdateInstallPolicy.chooseOffer over the check's latest release and the last
    /// look's nightly.
    private var chosen: UpdatePolicy.Offer? {
        guard let running = runningVersion else { return nil }
        return Policy.chooseOffer(release: latestRelease(), nightly: nightliesOn ? nightlyOffer : nil, running: running,
                                  runningBuild: runningBuild)
    }

    /// Update Now's own choice where it isn't the check's offer (a nightly): the menu names it.
    var offered: UpdatePolicy.Offer? {
        guard available, let c = chosen, c.signed, c != offer() else { return nil }
        return c
    }

    private func installerFor(_ offer: UpdatePolicy.Offer) -> UpdateInstaller {
        offer.build != nil ? nightlyInstaller : installer
    }

    /// The installer of the channel a prepared release came from (each reads and downloads its own channel).
    private func installerFor(_ release: Policy.Release) -> UpdateInstaller {
        release.channel == .nightly ? nightlyInstaller : installer
    }

    /// Update Now shows: this build has it, and there is a release for it.
    private var shown: Bool { paneOffer != nil }

    var pane: Policy.Pane {
        let o = paneOffer
        let now = Date()
        let automatic = Auto.pane(memory, offered: o?.version, offeredTag: o?.tag, running: runningVersion,
                                  waitUntil: o.flatMap(waitUntil), now: now,
                                  offeredBuild: o?.build, runningBuild: runningIsNightly ? runningBuild : nil)
        return Policy.pane(state, offered: o?.version, running: runningVersion, available: available, refusal: refusal,
                           keptAt: keptAt, automatic: automatic, offeredBuild: o?.build, ownLine: idle && o != nil && o != offer())
    }

    var menu: MenuBuilder.UpdateMenuState {
        MenuBuilder.UpdateMenuState(phase: state.phase, available: shown, refusal: refusal)
    }

    /// Settings › General's "Automatically update Sill".
    var automaticSwitch: Auto.Switch {
        Auto.switchState(available: available, canKeep: store.canKeep, checkOn: checkOn(), refusal: refusal, on: memory.on,
                         unreadable: store.unreadable)
    }

    /// Settings › General's "Use nightly builds" (plan §16).
    var nightlySwitch: Auto.Switch {
        Auto.nightlySwitch(available: available, keyCompiled: !installer.trust.nightlyKeys.isEmpty, canKeep: store.canKeep, on: memory.nightly,
                           runningNightly: runningIsNightly ? runningVersion.flatMap { v in runningBuild.map { (v, $0) } } : nil,
                           unreadable: store.unreadable)
    }

    /// Looks again at where Sill runs, off the main actor (review 3, N2: the look takes 10 to 70 ms):
    /// Settings › General calls it while it shows, the menu as it opens, and every begin. Nothing while
    /// neither a signed release is offered nor the switch is on, or while an update is under way.
    func refresh(then: ((Policy.Refusal?) -> Void)? = nil) {
        guard available, shown || memory.on, !state.phase.busy else { then?(refusal); return }
        if let then { afterRefresh.append(then) }
        guard !refreshing else { return }
        refreshing = true
        let inputs = lookInputs()
        Task { [weak self] in
            let r = await Task.detached(priority: .utility) { Self.refusal(inputs) }.value
            guard let self else { return }
            self.refreshing = false
            if r != self.refusal { self.refusal = r }
            if let r, r != self.loggedRefusal {
                self.loggedRefusal = r
                print("Update Now unavailable: \(Policy.words(r))")
            }
            let waiting = self.afterRefresh
            self.afterRefresh = []
            for then in waiting { then(r) }
        }
    }

    /// What the look at where Sill runs needs, taken on the main actor.
    struct LookInputs: Sendable {
        let bundle: URL
        let executable: String
        let runningIsRelease: Bool
        let testFeed: Bool
        let requirement: String
        let bundleID: String?
    }

    private func lookInputs() -> LookInputs {
        LookInputs(bundle: bundle, executable: installer.trust.executable, runningIsRelease: runningCode.isRelease,
                   testFeed: checkerUsesTestValues(), requirement: installer.trust.signer, bundleID: Bundle.main.bundleIdentifier)
    }

    /// The first refusal that holds now (UpdateInstallPolicy.refusal over UpdateInstaller.situation),
    /// counting every other genuine Sill of this account by its bundle identifier wherever it runs from: the
    /// new copy, once started, waits for every one of them to quit (review 3, N7: only a process that
    /// satisfies Sill's requirement counts; anything can claim the identifier).
    nonisolated static func refusal(_ i: LookInputs) -> Policy.Refusal? {
        let installed = UpdateInstaller.runningIsInstalled(i.bundle).0
        var s = UpdateInstaller.situation(bundle: i.bundle, executable: i.executable, runningIsRelease: i.runningIsRelease,
                                          testFeed: i.testFeed, runningIsInstalled: installed,
                                          neededBytes: Policy.neededBytes(assetBytes: 8 << 20))
        let own = ProcessInfo.processInfo.processIdentifier
        let others = i.bundleID.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).filter { $0.processIdentifier != own && !$0.isTerminated }
                .map(\.processIdentifier)
        } ?? []
        s.otherInstances = max(s.otherInstances, UpdateInstaller.genuine(others, requirement: i.requirement).count)
        return Policy.refusal(s)
    }

    // MARK: The person's buttons (SwiftUI Button actions)

    /// Update Now, and Install Now on a copy the automatic update checked.
    func updateNow() {
        guard shown, !state.phase.busy else { return }
        if case .waiting = state.phase {
            refresh { [weak self] r in
                guard let self, r == nil, case .waiting = self.state.phase else { return }
                self.stopWaiting()
                self.send(.updateNow(devices: self.devices()))
            }
            return
        }
        guard let offer = chosen, offer.signed else { return }
        refresh { [weak self] r in
            guard let self, r == nil, self.mayBegin, let current = self.chosen, current == offer else { return }
            self.attempt += 1
            self.keptAt = nil
            self.target = offer
            self.send(.updateNow(devices: self.devices()))
        }
    }

    func confirm() {
        send(.confirm)
    }

    /// Cancel retires the attempt (whatever it had in flight answers into nothing), but only in a phase
    /// that takes it: a Cancel that arrives once installing has begun (a click on a button the next
    /// frame removes, an assistive technology's late action) changes nothing, so the install's and the
    /// launch's answers still land.
    func cancelUpdate() {
        guard Policy.next(state, .cancel).0 != state else { return }
        cancel?.cancel()
        attempt += 1
        send(.cancel)
    }

    /// Settings › General's switch, the only code that changes it (AutoUpdateStore). On only where it can
    /// act; off at any time, which also drops an automatic update that hasn't begun installing.
    func setAutomaticUpdate(_ on: Bool) {
        guard available, on != memory.on else { return }
        if on, !automaticSwitch.enabled { return }
        // Turning it on is the one write that may replace an item Sill couldn't read (A3: it starts afresh).
        remember(replacingUnreadable: on) { Auto.switched($0, on: on) }
        if memory.on == on {
            print("Automatically update Sill: \(on ? "on" : "off").")
        } else {
            print("Automatically update Sill couldn’t be turned on: Sill’s keychain item couldn’t be written (\(store.problem ?? "no keychain group")).")
        }
        loggedAutomatic = nil
        if memory.on {
            considerAutomatic()
        } else if state.mode == .automatic {
            cancelUpdate()
        }
    }

    /// Settings › General's "Use nightly builds", the only code that changes it (AutoUpdateStore). Off drops a
    /// nightly the automatic update hasn't begun installing, and never goes back to a release (plan §16.3).
    func setNightly(_ on: Bool) {
        guard available, !installer.trust.nightlyKeys.isEmpty, on != memory.nightly else { return }
        if on, !nightlySwitch.enabled { return }
        // Turning it on may replace an item Sill couldn't read, as the automatic switch does (A3: it starts afresh).
        remember(replacingUnreadable: on) { Auto.switchedNightly($0, on: on) }
        print(memory.nightly == on ? "Use nightly builds: \(on ? "on" : "off")."
              : "Use nightly builds couldn’t be turned on: Sill’s keychain item couldn’t be written (\(store.problem ?? "no keychain group")).")
        if memory.nightly {
            lookAtNightly { [weak self] in self?.considerAutomatic() }
        } else {
            nightlyOffer = nil
            if target?.build != nil, state.mode == .automatic { cancelUpdate() }
        }
    }

    /// After every check GitHub answered (AppModel), and at launch (`atLaunch`, with the offer the last check stored):
    /// the nightly looked at first while the switch is on; at launch only while Check for updates automatically is
    /// on too, so Sill asks GitHub nothing by itself with it off (privacy.html; the footnote's "each time Sill opens").
    func checkAnswered(atLaunch: Bool = false) {
        if nightliesOn, !atLaunch || checkOn() { lookAtNightly { [weak self] in self?.considerAutomatic() } } else { considerAutomatic() }
    }

    /// The nightly pre-release (Endpoints.nightly): its listing and its manifest, verified with the nightly key, and
    /// the build that manifest names as the offer (UpdateInstaller.nightlyOffer: GitHub's title is never read).
    private func lookAtNightly(then: @escaping () -> Void) {
        guard available, nightliesOn, !lookingAtNightly else { then(); return }
        lookingAtNightly = true
        let nightlyInstaller = self.nightlyInstaller
        Task { [weak self] in
            let result = await nightlyInstaller.nightlyOffer(cancel: UpdateInstaller.Cancel())
            guard let self else { return }
            self.lookingAtNightly = false
            switch result {
            case .success(let o):
                if o != self.nightlyOffer { self.nightlyOffer = o }
            case .failure(let f):
                print("Update: the nightly build couldn’t be read (\(Policy.logText(f))).")
            }
            then()
        }
    }

    // MARK: The automatic update

    /// After every check that answered, and when the switch is turned on: begins the automatic update when
    /// UpdateAutoPolicy says so, with where Sill runs looked at afresh first.
    func considerAutomatic() {
        guard notesSettled else { considerWhenSettled = true; return }
        guard available, memory.on, let offer = chosen, mayBeginAutomatic else { return }
        refresh { [weak self] r in
            guard let self, self.mayBeginAutomatic, let current = self.chosen, current == offer else { return }
            let now = Date()
            switch Auto.start(self.memory, checkOn: self.checkOn(), available: self.available, refusal: r, offered: offer.version,
                              offeredTag: offer.tag, signed: offer.signed, running: self.runningVersion, idle: self.mayBeginAutomatic,
                              waitUntil: self.waitUntil(offer), now: now,
                              offeredBuild: offer.build, runningBuild: self.runningBuild) {
            case .no(let why):
                if why != self.loggedAutomatic {
                    self.loggedAutomatic = why
                    print("Automatic update: not now: \(why).")
                }
            case .go:
                // No attempt is counted yet: only once the release's manifest verified and Sill goes on to download
                // it (`fetch`; the second security pass's A3: an offer nobody verified counts nothing).
                self.loggedAutomatic = nil
                self.attempt += 1
                self.keptAt = nil
                self.target = offer
                print("Automatic update: \(Policy.name(version: offer.version, build: offer.build)) is out; reading its signed manifest on GitHub.")
                self.send(.automatic)
            }
        }
    }

    /// The host's devices changed (AppModel, from its status): any device restarts the quiet wait.
    func devicesChanged(_ count: Int) {
        if count > 0 { quietSince = Date() }
    }

    /// Every change of what the automatic update remembers, kept small (UpdateAutoPolicy.bounded, A3).
    private func remember(replacingUnreadable: Bool = false, _ change: (Auto.Memory) -> Auto.Memory) {
        let (running, runningBuild) = (runningVersion, self.runningBuild)
        store.update({ Auto.bounded(change($0), running: running, runningBuild: runningBuild) },
                     replacingUnreadable: replacingUnreadable)
        if store.memory != memory { memory = store.memory }
    }

    private func startWaiting() {
        let now = Date()
        waitingSince = now
        quietSince = now
        quietTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookForQuiet() }
        }
        quietTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        if let target {
            print("Update: Sill \(target.version) is checked and waits to be installed once no device has been connected for \(Auto.quietMinutes) minutes.")
        }
    }

    private func stopWaiting() {
        quietTimer?.invalidate()
        quietTimer = nil
        waitingSince = nil
    }

    /// Every 30 s while a checked copy waits (a run-loop Timer): a day without a quiet moment drops it;
    /// otherwise, once no device has been connected for `quietFor` and no pairing window is open, GitHub is
    /// asked again (the release must still be the latest, its manifest the one checked, and no stop beside
    /// it), then `installWhenQuiet`.
    private func lookForQuiet() {
        guard case .waiting = state.phase, state.mode == .automatic, !asking, let target, let prepared,
              let running = runningVersion else { return }
        let now = Date()
        guard memory.on, checkOn() else {
            print("Automatic update: \(memory.on ? "the daily check is off" : "the switch is off"); Sill \(target.version) isn’t installed by itself.")
            cancelUpdate()
            return
        }
        if let since = waitingSince, Auto.waitedTooLong(since: since, now: now) {
            print("Automatic update: no moment without a device in \(Int(Auto.maxWait / 3600)) hours; Sill \(target.version) waits for a later check.")
            remember { Auto.forgive($0, target.version, build: target.build) }
            cancelUpdate()
            return
        }
        if !devices().isEmpty { quietSince = now; return }
        guard Auto.quiet(devices: 0, quietSince: quietSince, pairing: pairing(), now: now) else { return }
        asking = true
        let run = attempt
        let token = UpdateInstaller.Cancel()
        cancel = token
        let installer = installerFor(target)
        let runningBuild = self.runningBuild
        Task { [weak self] in
            let result = await installer.prepare(offeredTag: target.tag, running: running, cancel: token,
                                                 offeredVersion: target.build != nil ? target.version : nil, offeredBuild: target.build,
                                                 runningBuild: runningBuild)
            guard let self else { return }
            self.asking = false
            guard run == self.attempt, case .waiting = self.state.phase else { return }
            switch result {
            case .failure(let f) where f.transient:
                print("Automatic update: GitHub didn’t answer before the install (\(Policy.logText(f))); asking again at the next look.")
            case .failure(let f):
                self.log(f)
                self.send(.quiet(f))
            case .success(let p) where p.release.tag != prepared.release.tag || p.manifest != prepared.manifest:
                let f = Policy.Failure.releaseChanged(tag: p.release.tag)
                self.log(f)
                self.send(.quiet(f))
            case .success:
                self.installWhenQuiet()
            }
        }
    }

    /// The last look and the hold in one step on the host's queue (StreamServer.holdNewSessions): no device
    /// connected, and none can be until Sill has restarted (each one that tries is told so and reconnects by
    /// itself); then the install (review 3, the automatic update's point 3).
    private func installWhenQuiet() {
        guard devices().isEmpty, !pairing(), let target else { quietSince = Date(); return }
        let connected = hold(true)
        guard connected == 0, devices().isEmpty, !pairing() else {
            _ = hold(false)
            quietSince = Date()
            print("Automatic update: a device connected at the last moment; waiting again.")
            return
        }
        holding = true
        print("Automatic update: no device connected for \(Auto.quietMinutes) minutes; new sessions are held while Sill \(target.version) is installed.")
        send(.quiet(nil))
    }

    /// Install Now on a waiting copy (the second security pass's G1): GitHub asked again first, as `lookForQuiet`
    /// does before the automatic install (the release still the latest, its manifest the one checked, no stop
    /// beside it); then the install, or the question for the devices connected at the click.
    private func lookAgain(_ run: Int) {
        guard let target, let prepared, let running = runningVersion else { send(.lookedAgain(.cancelled)); return }
        let token = UpdateInstaller.Cancel()
        cancel = token
        let installer = installerFor(target)
        let runningBuild = self.runningBuild
        Task { [weak self] in
            let result = await installer.prepare(offeredTag: target.tag, running: running, cancel: token,
                                                 offeredVersion: target.build != nil ? target.version : nil, offeredBuild: target.build,
                                                 runningBuild: runningBuild)
            guard let self, run == self.attempt, case .lookingAgain = self.state.phase else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.send(.lookedAgain(f))
            case .success(let p) where p.release.tag != prepared.release.tag || p.manifest != prepared.manifest:
                let f = Policy.Failure.releaseChanged(tag: p.release.tag)
                self.log(f)
                self.send(.lookedAgain(f))
            case .success:
                self.send(.lookedAgain(nil))
            }
        }
    }

    private func releaseHold() {
        guard holding else { return }
        holding = false
        _ = hold(false)
        print("Update: new sessions are no longer held.")
    }

    // MARK: Steps

    private func send(_ event: Policy.Event) {
        let before = state
        let (next, effects) = Policy.next(state, event)
        if next != state { state = next }
        if next.phase != before.phase {
            if case .failed(let f) = next.phase {
                if case .stopped(let tag) = f { remember { Auto.stopped($0, tag) } }
                if next.mode == .automatic, let t = target { remember { Auto.failed($0, t.version, why: Policy.logText(f), build: t.build) } }
            }
            if case .waiting = next.phase { startWaiting() } else { stopWaiting() }
            switch next.phase {
            case .installing, .restarting: break
            default: releaseHold()
            }
        }
        if idle { target = nil }
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: Policy.Effect) {
        let run = attempt
        switch effect {
        case .fetch: fetch(run)
        case .lookAgain: lookAgain(run)
        case .download: startDownload(run)
        case .unpack: startUnpack(run)
        case .check: startCheck(run)
        case .install: startInstall(run)
        case .launch:
            // Quit while the install step ran (AppDelegate): the new copy is in place, checked twice, and starts the
            // next time Sill is opened; Sill doesn't start it against the quit.
            if quitting {
                print("Update: Sill \(checked.map { "\($0.version)" } ?? "") is installed and starts the next time Sill opens (Sill is quitting).")
                return
            }
            launchNewCopy(run)
        case .quit: quitForUpdate()
        case .cleanUp: cleanUp()
        }
    }

    private func fetch(_ run: Int) {
        guard let target, let running = runningVersion else { send(.fetched(.releaseNotNewer)); return }
        let token = UpdateInstaller.Cancel()
        cancel = token
        switch UpdateInstaller.makeStaging(for: bundle) {
        case .failure(let f):
            log(f)
            send(.fetched(f))
            return
        case .success(let dir):
            staging = dir
        }
        print("Update: getting \(Policy.name(version: target.version, build: target.build)) (\(target.tag)) from GitHub.")
        let installer = installerFor(target)
        let runningBuild = self.runningBuild
        let nightly = target.build != nil
        Task { [weak self] in
            let result = await installer.prepare(offeredTag: target.tag, running: running, cancel: token,
                                                 offeredVersion: nightly ? target.version : nil, offeredBuild: target.build,
                                                 runningBuild: runningBuild)
            guard let self, run == self.attempt else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.send(.fetched(f))
            case .success(let p):
                self.prepared = p
                let nightly = p.release.channel == .nightly
                if nightly {
                    print("Update: \(Policy.name(version: p.release.version, build: p.release.build))’s manifest is signed with Sill’s nightly key \(p.manifest.keyID) at \(UpdateManifest.dateText(p.manifest.signedAt)): \(p.manifest.size) bytes, SHA-256 \(p.manifest.sha256), commit \(p.manifest.commit ?? "-").")
                } else {
                    print("Update: Sill \(p.release.version)’s release is signed with Sill’s update key \(p.manifest.keyID) at \(UpdateManifest.dateText(p.manifest.signedAt)): \(p.manifest.size) bytes, SHA-256 \(p.manifest.sha256).")
                }
                guard self.state.mode == .automatic else { self.send(.fetched(nil)); return }
                // The cooling-off counts from this Sill's first read of this verified manifest, kept across launches
                // (the second security pass's A1): the signed line is whoever holds the key's to write. It counts on
                // GitHub's clock too, from the release's publication when that is later (the third pass's CL1 and
                // AU1). A nightly waits only while `Auto.nightlyCoolingOff` says so (none today), and only then is
                // its sight kept (by its key, "0.6.2 (1471)").
                let now = Date()
                let wait = nightly ? Auto.nightlyCoolingOff : Auto.coolingOff
                let sightTag = nightly ? Auto.key(p.release.version, build: p.release.build) : p.release.tag
                if wait > 0 {
                    self.remember { Auto.sighted($0, tag: sightTag, sha256: p.manifest.sha256, signedAt: p.manifest.signedAt, now: now,
                                                 github: p.release.answeredAt, published: nightly ? nil : p.release.publishedAt) }
                }
                let sight = Auto.sighting(self.memory, tag: sightTag, sha256: p.manifest.sha256)
                let first = sight?.first ?? now
                let github = Auto.GitHubClock(firstSeen: sight?.firstGitHub ?? p.release.answeredAt, now: p.release.answeredAt,
                                              published: nightly ? nil : (sight?.published ?? p.release.publishedAt))
                switch Auto.dates(signedAt: p.manifest.signedAt, firstSeen: first, now: now, nightly: nightly, wait: wait, github: github) {
                case .go:
                    // An attempt counts from here: a verified release Sill goes on to download (A3).
                    self.remember { Auto.began($0, p.release.version, now: now, build: p.release.build) }
                    self.send(.fetched(nil))
                case .waitUntil(let until):
                    let name = Policy.name(version: p.release.version, build: p.release.build)
                    let words = nightly ? Auto.nightlyCoolingOffWords : Auto.coolingOffWords
                    print("Automatic update: \(name) waits \(until.map { "until \(UpdateManifest.dateText($0))" } ?? "for an answer from GitHub with a date") to install by itself, \(words) (first found \(UpdateManifest.dateText(first)) by this Mac’s clock, \(sight?.firstGitHub.map(UpdateManifest.dateText) ?? "no date") by GitHub’s; Update Now can install it now).")
                    self.send(.postponed)
                case .refuse(let why):
                    // Never counted (the second pass's N9: a Mac whose clock is wrong would otherwise run out of tries).
                    let f = Policy.Failure.notAutomatic(why)
                    self.log(f)
                    self.send(.fetched(f))
                }
            }
        }
    }

    private func startDownload(_ run: Int) {
        guard let prepared, let staging, let token = cancel else { send(.downloaded(.cancelled)); return }
        print("Update: downloading \(Policy.name(version: prepared.release.version, build: prepared.release.build)) (\(Policy.megabytes(prepared.manifest.size)) MB) from github.com.")
        let installer = installerFor(prepared.release)
        // Each piece's count, on the main actor (the reference taken weakly here, held only by its hop).
        let report: @Sendable (Int64, Int64) -> Void = { [weak self] received, total in
            Task { @MainActor [self] in self?.progress(run, received, total) }
        }
        Task { [weak self] in
            let result = await installer.download(prepared.release, manifest: prepared.manifest, into: staging,
                                                  progress: report, cancel: token)
            guard let self, run == self.attempt else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.send(.downloaded(f))
            case .success(let file):
                self.zip = file
                self.send(.downloaded(nil))
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
        guard let prepared, let staging, let zip, let token = cancel else { send(.unpacked(.cancelled)); return }
        let installer = installerFor(prepared.release)
        let manifest = prepared.manifest
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                installer.unpack(zip, manifest: manifest, into: staging, cancel: token)
            }.value
            guard let self, run == self.attempt else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.send(.unpacked(f))
            case .success(let app):
                self.unpacked = app
                self.send(.unpacked(nil))
            }
        }
    }

    private func startCheck(_ run: Int) {
        guard let prepared, let unpacked, let running = runningVersion else { send(.checked(.cancelled, devices: [])); return }
        let installer = installerFor(prepared.release)
        let manifest = prepared.manifest
        let requirement = runningCode.requirement
        let runningBuild = self.runningBuild
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                installer.check(unpacked, manifest: manifest, running: running, runningRequirement: requirement,
                                runningBuild: runningBuild)
            }.value
            guard let self, run == self.attempt else { return }
            switch result {
            case .failure(let f):
                self.log(f)
                self.send(.checked(f, devices: []))
            case .success(let c):
                self.checked = c
                // The floor rises only now, on an app that passed both checks (the second security pass's A2: a
                // manifest alone, for a made-up version, would stop every later release installing by itself).
                if let build = prepared.release.build, prepared.release.channel == .nightly {
                    self.remember { Auto.signedNightly($0, c.version, build: build) }
                } else {
                    self.remember { Auto.signedRelease($0, c.version) }
                }
                let signedWith = manifest.channel == .nightly ? "the nightly signed with Sill’s nightly key" : "the release signed with Sill’s update key"
                print("Update: Sill \(c.version) (\(c.build)) checked both ways: Apple’s signature for Developer ID \(installer.trust.teamID ?? "-") as \(installer.trust.identifier) and its notarization, and every slice the code \(signedWith) \(manifest.keyID) names; newer than \(running).")
                self.send(.checked(nil, devices: self.devices()))
            }
        }
    }

    private func startInstall(_ run: Int) {
        guard let prepared, let unpacked, let checked, let running = runningVersion else { send(.installed(.cancelled)); return }
        // Update Now: new sessions held from here to the restart (a device that tries is told Sill is restarting
        // and reconnects by itself), and in the same step the last look: one connected since the person's
        // answer is asked about first, never cut off (review 3, point 3; the automatic update held them
        // before its own last look, `installWhenQuiet`).
        if state.mode == .manual {
            let connected = hold(true)
            holding = true
            let now = devices()
            if connected > state.consented.count || !Set(now.map(\.key)).isSubset(of: Set(state.consented)) {
                print("Update: a device connected since the question; asking again.")
                send(.devicesJoined(now))
                return
            }
        }
        let installer = installerFor(prepared.release)
        let bundle = self.bundle
        let manifest = prepared.manifest
        let requirement = runningCode.requirement
        let inputs = lookInputs()
        let note = Self.leftoverNote
        let runningBuild = self.runningBuild
        Task { [weak self] in
            // Off the main actor: where Sill runs, looked at once more right before the swap (another account
            // or copy may have started Sill since the click), the copy at the path, then the install (which
            // checks the staged copy once more right before its swap: review 3, F5).
            let (result, oldCDHash, oldCopyWaits) = await Task.detached(priority: .userInitiated) { () -> (Result<Void, Policy.Failure>, String?, Bool) in
                if let r = Self.refusal(inputs) { return (.failure(.unavailable(r)), nil, false) }
                let (isInstalled, cdhash) = UpdateInstaller.runningIsInstalled(bundle)
                guard isInstalled, let cdhash else { return (.failure(.changedSinceStart), nil, false) }
                let r = installer.install(staged: unpacked, installed: bundle, runningCDHash: cdhash, expected: checked,
                                          manifest: manifest, running: running, runningRequirement: requirement, leftoverNote: note,
                                          runningBuild: runningBuild)
                // Not put back: whether what waits in staging is still the old copy, whole (the way back).
                if case .failure(let f) = r, !f.cleanUp { return (r, cdhash, installer.isTheOldCopy(unpacked, old: cdhash)) }
                return (r, cdhash, false)
            }.value
            guard let self, run == self.attempt else { return }
            self.oldCDHash = oldCDHash
            switch result {
            case .failure(let f):
                if case .unavailable(let r) = f { self.refusal = r }
                if oldCopyWaits { self.keep(unpacked) }
                self.log(f)
                self.send(.installed(f))
            case .success:
                print("Update: replaced \(bundle.path) with Sill \(checked.version); Sill \(running) is kept at \(unpacked.path) until \(checked.version) has run for \(Int(Policy.provedAfter)) s.")
                self.send(.installed(nil))
            }
        }
    }

    /// The new copy as a new instance, beside this one (it waits for this one to quit before it starts
    /// anything: `waitForOtherSill`); this one quits once it has finished launching and its running code
    /// is the code that was checked, leaving the watcher behind. Anything else: it is stopped and the old
    /// copy put back.
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
        NSWorkspace.shared.openApplication(at: bundle, configuration: config) { [weak self] app, error in
            let message = error?.localizedDescription
            Task { @MainActor [self] in self?.opened(run, app, message, since: started) }
        }
    }

    private func opened(_ run: Int, _ app: NSRunningApplication?, _ error: String?, since started: Date) {
        let own = ProcessInfo.processInfo.processIdentifier
        guard run == attempt, case .restarting = state.phase, let checked else {
            // Never this Sill itself (review 3, N3: forceTerminate on the current app ends it at once).
            if let app, app.processIdentifier != own { app.forceTerminate() }
            return
        }
        guard let app else { didNotStart(run, error ?? "macOS didn’t start it"); return }
        guard app.processIdentifier != own else { didNotStart(run, "macOS handed back this Sill instead of starting the new one"); return }
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
                    self.newPID = app.processIdentifier
                    if run == self.attempt { self.send(.launched(nil)) }
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

    /// The new copy didn't come up: the old one back where it was if it is still the old one, whole (the
    /// new one goes with the staging folder), and why. When it is the old one but the exchange failed, it
    /// is kept as the way back; when it is not, it is never offered (the checked new copy stays in place,
    /// and Settings says to download Sill again).
    private func didNotStart(_ run: Int, _ why: String) {
        guard run == attempt else { return }
        var back = UpdateInstaller.PutBack.notTheOldCopy
        if let unpacked, let oldCDHash { back = installer.putBack(staged: unpacked, installed: bundle, old: oldCDHash) }
        if back == .failed, let unpacked { keep(unpacked) }
        let f = Policy.Failure.didNotStart(why, putBack: back == .done)
        log(f)
        send(.launched(f))
    }

    /// The old copy could not be put back but is whole: its folder is set aside (renamed out of every
    /// clean-up's reach, with a note), and Settings and the log say where it is.
    private func keep(_ copy: URL) {
        let folder = UpdateInstaller.setAside(copy.deletingLastPathComponent())
        keptAt = folder.appendingPathComponent(copy.lastPathComponent).path
        staging = nil
    }

    /// Quits through the ordinary quit path (the streamed window home, the virtual display gone), from a
    /// run-loop Timer: NSApp.terminate can answer .terminateLater. The watcher first: it puts this copy
    /// back by itself if the new one doesn't run (review 3, the automatic update's point 6).
    private func quitForUpdate() {
        startWatcher()
        let timer = Timer(timeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startWatcher() {
        guard let pid = newPID, let unpacked, let oldCDHash, let checked, let running = runningVersion else { return }
        let token = UUID().uuidString
        // The version and the build: a nightly can have this Sill's version (only the new Sill may answer the watcher).
        UpdateInstaller.writeNote(Self.pendingNote, lines: [token, "\(checked.version) (\(checked.build))", state.mode == .automatic ? "automatic" : "manual",
                                                            target?.build != nil ? UpdateManifest.nightlyTag : "release"])
        let w = UpdateInstaller.Watch(pid: pid, installed: bundle, executable: installer.trust.executable, oldCopy: unpacked, oldCDHash: oldCDHash,
                                      requirement: installer.trust.signer, startedNote: Self.startedNote(token), token: token,
                                      restoredNote: Self.restoredNote, seconds: Int(Policy.watchWait))
        if UpdateInstaller.startWatcher(w) {
            print("Update: if Sill \(checked.version) hasn’t run for \(Int(Policy.provedAfter)) s within \(Int(Policy.watchWait)) s, a watcher puts Sill \(running) back and starts it.")
        } else {
            print("Update: the watcher couldn’t start; Sill \(running) stays at \(unpacked.path) until \(checked.version) has started.")
        }
    }

    private func cleanUp() {
        watch?.invalidate()
        watch = nil
        cancel = nil
        stopWaiting()
        if let staging, keptAt == nil {
            DispatchQueue.global(qos: .utility).async { UpdateInstaller.remove(staging) }
        }
        staging = nil
        prepared = nil
        zip = nil
        unpacked = nil
        checked = nil
        oldCDHash = nil
        newPID = nil
        shownProgress = (0, .distantPast)
    }

    private func log(_ f: Policy.Failure) {
        if f == .cancelled { print("Update: cancelled."); return }
        print("Update failed: \(Policy.logText(f)).")
        if let keptAt {
            print("Update: Sill’s previous copy is kept at \(keptAt), where macOS may empty the folder after a few days; to put it back, quit Sill and move it to \(bundle.deletingLastPathComponent().path).")
        } else if !f.cleanUp {
            print("Update: what waits in the temporary folder is no longer Sill’s previous copy whole, so it is not offered as the way back; download Sill again.")
        }
    }

    // MARK: Launch and start

    /// Once this Sill's host is up. The launch an update made (the pending note names this version): once it
    /// has run `Policy.provedAfter`, the note the watcher waits for, then the clean-up of the copy it replaced.
    /// The launch the watcher made after it put this copy back: what happened, in Settings and the log.
    /// Otherwise: what earlier updates left goes at once. The notes are read off the main actor, and only as
    /// regular files (UpdateInstaller.readSmallFile; the second security pass's W2).
    func afterHostUp() {
        guard isApp else { settleNotes(); return }
        Task { [weak self] in
            let notes = await Task.detached(priority: .utility) {
                (UpdateInstaller.readNote(Self.pendingNote), UpdateInstaller.readNote(Self.restoredNote))
            }.value
            self?.afterHostUp(pending: notes.0, restored: notes.1)
        }
    }

    private func afterHostUp(pending: [String]?, restored: [String]?) {
        defer { settleNotes() }
        if let restored {
            try? FileManager.default.removeItem(at: Self.restoredNote)
            try? FileManager.default.removeItem(at: Self.pendingNote)
            // The watcher couldn't put the old copy back (it failed its last check) and left this new one at Sill's
            // path, not started (the third security pass's W3): this Sill is that copy, opened since.
            if restored.count > 2, restored[2] == "kept", let p = pending, p.count >= 3, restored.first == p[0], p[1] == runningKey {
                let why = restored[1]
                print("Update: Sill \(runningKey ?? "") didn’t start the first time (\(why)), and the copy it replaced failed the watcher’s last check, so the watcher left this one in place, not started.")
                state = Policy.State(phase: .failed(.keptUnstarted(why)), mode: p[2] == "automatic" ? .automatic : .manual)
                cleanUpAfterStart()
                return
            }
            if let p = pending, p.count >= 3, restored.first == p[0], let (failed, failedBuild) = Auto.parseKey(p[1]), let running = runningVersion,
               Policy.isNewer(failed, build: failedBuild, than: running, runningBuild: runningBuild, byBuild: true) {
                let why = restored.count > 1 ? restored[1] : "it didn’t run"
                let automatic = p[2] == "automatic"
                let nightly = p.count > 3 && p[3] == UpdateManifest.nightlyTag
                print("Update: \(Policy.name(version: failed, build: nightly ? failedBuild : nil)) didn’t run properly (\(why)), so Sill’s watcher put \(running) back and started it.")
                if automatic { remember { Auto.failed($0, failed, why: "it didn’t run: \(why)", build: nightly ? failedBuild : nil) } }
                let tag = nightly ? UpdateManifest.nightlyTag : "v\(failed)"
                target = UpdatePolicy.Offer(version: failed, tag: tag, url: URL(string: "https://github.com/Saffsanity/sill/releases/tag/\(tag)")!,
                                            signed: true, build: nightly ? failedBuild : nil)
                state = Policy.State(phase: .failed(.didNotStart(why, putBack: true)), mode: automatic ? .automatic : .manual)
            }
            cleanUpAfterStart()
            return
        }
        guard let p = pending, p.count >= 3, Policy.isToken(p[0]), p[1] == runningKey else {
            if pending != nil { try? FileManager.default.removeItem(at: Self.pendingNote) }
            cleanUpAfterStart()
            return
        }
        let token = p[0], automatic = p[2] == "automatic"
        let proved = Timer(timeInterval: Policy.provedAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.proved(token: token, automatic: automatic) }
        }
        RunLoop.main.add(proved, forMode: .common)
    }

    /// The host didn't start (AppModel): no note is read, and the automatic update needn't wait for them.
    func hostDidNotStart() {
        settleNotes()
    }

    private func settleNotes() {
        notesSettled = true
        if considerWhenSettled {
            considerWhenSettled = false
            considerAutomatic()
        }
    }

    /// This launch, the update, has run long enough: the watcher's note (it ends), then the clean-up a few
    /// seconds later (the watcher looks once a second).
    private func proved(token: String, automatic: Bool) {
        guard Policy.isToken(token) else { return }
        UpdateInstaller.writeNote(Self.startedNote(token), lines: [token])
        try? FileManager.default.removeItem(at: Self.pendingNote)
        if automatic, available, let v = runningVersion { remember { Auto.updated($0, to: v, at: Date(), build: runningIsNightly ? runningBuild : nil) } }
        print("Update: Sill \(runningVersion.map { "\($0)" } ?? "") has run for \(Int(Policy.provedAfter)) s; the copy it replaced goes.")
        let later = Timer(timeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                try? FileManager.default.removeItem(at: Self.startedNote(token))
                self?.cleanUpAfterStart()
            }
        }
        RunLoop.main.add(later, forMode: .common)
    }

    /// Quitting before `proved`: a quit asked for (not a crash) is no failure of the update, so the watcher
    /// is told the same. From AppDelegate's quit.
    func willQuit() {
        guard isApp, let p = UpdateInstaller.readNote(Self.pendingNote), p.count >= 3, p[1] == runningKey else { return }
        proved(token: p[0], automatic: p[2] == "automatic")
    }

    /// This Sill as the pending note names the new one: "0.6.2 (1471)", its version and build (a nightly can have
    /// the old Sill's version, so the build tells the new Sill from the old: only the new one answers the watcher).
    private var runningKey: String? {
        guard let v = runningVersion, let b = runningBuild else { return nil }
        return "\(v) (\(b))"
    }

    /// The update's install step runs (AppDelegate's quit waits for it: review 3, F5).
    var installing: Bool { if case .installing = state.phase { return true }; return false }

    /// The person quits while the install step runs (AppDelegate, before it waits for the step): the new copy
    /// is then left in place, unstarted (the second pass's N9).
    func quitRequested() {
        quitting = true
    }

    /// What earlier updates left in the temporary folder goes, the copy an update replaced among it (kept
    /// until now so it could be put back). Never while an update is under way (its own folder is spared),
    /// and never a folder marked as holding a copy that could not be put back.
    func cleanUpAfterStart() {
        guard isApp, mayBegin, keptAt == nil else { return }
        let bundle = self.bundle
        let note = Self.leftoverNote
        DispatchQueue.global(qos: .utility).async {
            let removed = [UpdateInstaller.removeLeftover(noted: note, for: bundle)].compactMap { $0 }
                + UpdateInstaller.cleanUpStaging(for: bundle)
            if !removed.isEmpty {
                print("Update: removed \(removed.count) folder\(removed.count == 1 ? "" : "s") an earlier update left (\(removed.joined(separator: ", "))).")
            }
        }
    }

    /// Sill's own folder in this user's Caches, where one Sill leaves notes for the next.
    nonisolated private static var notes: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("me.saffer.sill.mac", isDirectory: true)
    }

    /// The folder that holds the copy an update replaced, for the next Sill (it can't find it by listing).
    nonisolated static var leftoverNote: URL { notes.appendingPathComponent("Update Now leftover.txt") }
    /// The update's token, the new version and the mode, for the new Sill.
    nonisolated static var pendingNote: URL { notes.appendingPathComponent("Update Now pending.txt") }
    /// The new Sill's word to the watcher that it ran long enough: a regular file whose name carries the token
    /// (`Policy.isToken`), which the watcher looks for without opening (W2).
    nonisolated static func startedNote(_ token: String) -> URL { notes.appendingPathComponent("Update Now started \(token).txt") }
    /// The watcher's word that it put the old copy back (the token, then why).
    nonisolated static var restoredNote: URL { notes.appendingPathComponent("Update Now restored.txt") }

    /// At launch: when another genuine Sill of this account is running (the one that launched this copy
    /// after an update, which quits once this one has finished launching), this one starts nothing until it
    /// has quit, at most `Policy.launchWait`, then quits itself. True when it waits (`start` comes later).
    /// Only a process that satisfies Sill's requirement counts (review 3, N7: anything can claim the bundle
    /// identifier). From applicationDidFinishLaunching; the Timer is a run-loop one (it may call NSApp.terminate).
    static func waitForOtherSill(then start: @escaping @MainActor () -> Void) -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != own && !$0.isTerminated }
        let genuine = Set(UpdateInstaller.genuine(candidates.map(\.processIdentifier), requirement: Policy.Trust.release.signer))
        let others = candidates.filter { genuine.contains($0.processIdentifier) }
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
