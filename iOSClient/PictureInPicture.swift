import AVFoundation
import AVKit
import UIKit

// MARK: - One window's Picture in Picture

/// Picture in Picture for one window's session (issue #291, docs/picture-in-picture-plan.md): AVKit's
/// controller on the session's display layer (`HEVCDisplayView.sampleBufferLayer`), its two delegates, and
/// what their events do. PictureInPicturePolicy decides; this carries it out and tells the client
/// (`StreamClient.pictureInPictureChanged`): the frozen picture, the sound, what runs as in the foreground,
/// the keyframe asks. One per StreamClient, as each Sill window has its own session and layer; no AVKit
/// object exists until the window's picture is first offered, so with the switch off (the default) nothing
/// of this runs.
///
/// Sill never starts Picture in Picture itself in a Release build: iOS does, as the person leaves Sill
/// (`canStartPictureInPictureAutomaticallyFromInline`, while PictureInPictureHub says the picture is
/// offered); App Review rejects an app that starts it on its way to the background. It stops it (the
/// session's end, the window back in front, the device's lock, ten minutes paused), which is allowed.
/// Main thread, as AVKit calls its delegates.
final class PictureInPicture: NSObject {
    private weak var client: StreamClient?
    /// AVKit's controller, made the first time this window's picture is offered, kept while the switch is
    /// on (its content source holds this object, the playback delegate, weakly: the client holds it).
    private var controller: AVPictureInPictureController?
    /// The window's Picture in Picture over time (PictureInPicturePolicy.Lifecycle).
    private(set) var lifecycle = PictureInPicturePolicy.Lifecycle()
    var state: PictureInPicturePolicy.State { lifecycle.state }
    /// Offered now (PictureInPictureHub): iOS may take the picture into Picture in Picture as Sill leaves.
    private(set) var offered = false
    /// Holding the app's audio session active (`holdSession`).
    private var holdsSession = false
    /// The next look at a pause's end (Lifecycle.Effects.lookAt).
    private var look: DispatchWorkItem?
    /// Whether AVKit reads the window as paused, for its own threads (`pictureInPictureControllerIsPlaybackPaused`).
    private let pausedLock = NSLock()
    private var pausedForAVKit = false
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private var possibleObservation: NSKeyValueObservation?
    #endif

    init(client: StreamClient) {
        self.client = client
        super.init()
        let center = NotificationCenter.default
        // The device locked: iOS says protected data is about to go (with a passcode, about ten seconds after
        // the lock). Nobody is watching: Picture in Picture stops, and Sill is in the background as before.
        observers.append(center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            self?.end(.deviceLocked, why: "the device locked")
        })
        // This window's scene in front again (the window's return button, or Sill opened any other way): the
        // picture belongs in Sill again. The scene's notification, so another Sill window's coming forward
        // stops nothing here.
        observers.append(center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let scene = note.object as? UIScene, scene === self.client?.displayView.window?.windowScene else { return }
            self.end(.backInFront, why: "its window is in front again")
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        look?.cancel()
        if holdsSession { _ = AudioOutput.holdSessionForPictureInPicture(false) }
    }

    // MARK: Support

    /// iOS has Picture in Picture on this device: what decides whether a controller is made.
    static let systemSupports = AVPictureInPictureController.isPictureInPictureSupported()

    /// iOS has Picture in Picture on this device: the Settings panel's switch shows, and a session can
    /// qualify. DEBUG `-SillPiPSupported 1|0` says otherwise for one run (the harness's photos of the switch,
    /// on a simulator that may say no); AVKit's own answer still decides whether a controller is made.
    static var supported: Bool {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "SillPiPSupported") { return raw == "1" }
        #endif
        return systemSupports
    }

    // MARK: Offered

    /// Offered or not: PictureInPictureHub's decision (PictureInPicturePolicy.offered). Main thread.
    func setOffered(_ on: Bool) {
        guard on != offered else { return }
        offered = on
        if on, controller == nil { makeController() }
        controller?.canStartPictureInPictureAutomaticallyFromInline = on
        holdSession(on || state.active)
        #if DEBUG
        print("pip: " + (on ? "offered: iOS may take this window's picture into Picture in Picture as Sill leaves"
                            : "not offered") + (controller.map { " (possible \($0.isPictureInPicturePossible))" } ?? ""))
        if on { scheduleDebugStart() }
        #endif
        forgetIfUnused()
    }

    /// AVKit's controller on this window's display layer: no skipping, no scrubbing (a live picture), the
    /// `.playback` category it needs (AudioOutput, mixing with other audio as every engine does).
    private func makeController() {
        guard Self.systemSupports, let client else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: client.displayView.sampleBufferLayer,
                                                               playbackDelegate: self)
        let made = AVPictureInPictureController(contentSource: source)
        made.delegate = self
        made.requiresLinearPlayback = true
        AudioOutput.preparePictureInPictureCategory()
        #if DEBUG
        possibleObservation = made.observe(\.isPictureInPicturePossible, options: [.new]) { c, _ in
            let possible = c.isPictureInPicturePossible
            DispatchQueue.main.async { print("pip: possible \(possible)") }
        }
        print("pip: controller made on the display layer")
        #endif
        controller = made
    }

    /// The switch off, nothing showing and nothing offered: AVKit's controller goes (the next offer makes one
    /// again), and with it its hold on the layer.
    private func forgetIfUnused() {
        guard controller != nil, !offered, !state.active, !StreamClient.pictureInPictureOn else { return }
        #if DEBUG
        possibleObservation = nil
        print("pip: controller let go (the switch is off)")
        #endif
        controller = nil
    }

    // MARK: Endings

    /// One of Sill's endings (PictureInPicturePolicy.Ending): stops Picture in Picture when the rule says.
    /// Main thread.
    func end(_ ending: PictureInPicturePolicy.Ending, why: String) {
        event(why) { $0.ending(ending) }
    }

    /// Runs one event through the lifecycle, tells the client when the state changed, and carries out what
    /// the rule asks.
    private func event(_ why: String, _ change: (inout PictureInPicturePolicy.Lifecycle) -> PictureInPicturePolicy.Lifecycle.Effects) {
        let old = lifecycle.state
        let effects = change(&lifecycle)
        if lifecycle.state != old { stateChanged(from: old, why: why) }
        if !PictureInPicturePolicy.frozen(lifecycle.state) { look?.cancel(); look = nil }
        if let at = effects.lookAt { lookAgain(at: at) }
        if effects.invalidate { controller?.invalidatePlaybackState() }
        if effects.stop {
            #if DEBUG
            print("pip: stopping: \(why)")
            #endif
            controller?.stopPictureInPicture()
        }
    }

    private func stateChanged(from old: PictureInPicturePolicy.State, why: String) {
        let now = lifecycle.state
        pausedLock.withLock { pausedForAVKit = now.paused }
        #if DEBUG
        print("pip: \(now.active ? (now.paused ? "paused" : "playing") : "off") (\(why))")
        #endif
        holdSession(offered || now.active)
        client?.pictureInPictureChanged(from: old, to: now)
        forgetIfUnused()
    }

    /// A pause's end, looked at when it is due (PictureInPicturePolicy.pauseEnds).
    private func lookAgain(at: Double) {
        look?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.event("paused for \(Int(PictureInPicturePolicy.pausedLimit / 60)) minutes") {
                $0.tick(now: ProcessInfo.processInfo.systemUptime)
            }
        }
        look = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, at - ProcessInfo.processInfo.systemUptime), execute: work)
    }

    // MARK: The audio session

    /// Holds the app's audio session active (`.playback`, mixing) while this window's picture is offered or
    /// shows, so iOS finds a playback session when it decides; a device only, unless DEBUG `-SillPiPSession
    /// active` (the simulator's sound never opens an output: AudioOutput). DEBUG `-SillPiPSession inactive`
    /// never holds it, for the comparison (the plan's P3).
    private func holdSession(_ want: Bool) {
        let want = want && Self.holdsAudioSession
        guard want != holdsSession else { return }
        holdsSession = AudioOutput.holdSessionForPictureInPicture(want)
        #if DEBUG
        print("pip: audio session \(holdsSession ? "held active (playback, mixing with other audio)" : "let go")")
        #endif
    }

    private static var holdsAudioSession: Bool {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "SillPiPSession") {
        case "active"?: return true
        case "inactive"?: return false
        default: break
        }
        #endif
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    // MARK: DEBUG stand-ins for what a test cannot do

    #if DEBUG
    private var debugStartScheduled = false
    private var debugAfterStartScheduled = false

    /// `-SillPiPStartAt <s>`: s seconds after this window's picture is first offered, Picture in Picture
    /// starts as iOS's automatic start would as Sill leaves (startPictureInPicture, with Sill in front: a
    /// stand-in for leaving, which a test cannot do). Once a launch; never in a Release build.
    private func scheduleDebugStart() {
        guard !debugStartScheduled else { return }
        let at = UserDefaults.standard.double(forKey: "SillPiPStartAt")
        guard at > 0 else { return }
        debugStartScheduled = true
        print("pip: -SillPiPStartAt: Picture in Picture starts in \(at) s")
        DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
            guard let controller = self?.controller else { print("pip: -SillPiPStartAt: no controller"); return }
            print("pip: -SillPiPStartAt: starting (possible \(controller.isPictureInPicturePossible))")
            controller.startPictureInPicture()
        }
    }

    /// `-SillPiPPauseAt <s>[,<s>…]`: at each of these seconds after Picture in Picture first started, its
    /// window's pause or play button as the person would press it (the playback delegate's setPlaying, the
    /// other way from what it is). `-SillPiPLockAt <s>`: s seconds after it first started, the device's lock
    /// as iOS says it. Once a launch.
    private func scheduleDebugAfterStart() {
        guard !debugAfterStartScheduled else { return }
        debugAfterStartScheduled = true
        let defaults = UserDefaults.standard
        let pauses = (defaults.string(forKey: "SillPiPPauseAt") ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 > 0 }
        for t in pauses {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self, let controller = self.controller else { return }
                let playing = self.state.paused
                print("pip: -SillPiPPauseAt: the window's \(playing ? "play" : "pause") button at \(t) s")
                self.pictureInPictureController(controller, setPlaying: playing)
            }
        }
        let lockAt = defaults.double(forKey: "SillPiPLockAt")
        if lockAt > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + lockAt) { [weak self] in
                print("pip: -SillPiPLockAt: the device locks at \(lockAt) s")
                self?.end(.deviceLocked, why: "the device locked (-SillPiPLockAt)")
            }
        }
    }
    #endif
}

// MARK: - AVKit's delegates

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        event("iOS starts Picture in Picture") { $0.willStart() }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        #if DEBUG
        print("pip: started")
        scheduleDebugAfterStart()
        #endif
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        #if DEBUG
        print("pip: failed to start: \((error as NSError).domain) \((error as NSError).code) \(error.localizedDescription)")
        #endif
        event("it failed to start") { $0.ended() }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        #if DEBUG
        print("pip: stopping (AVKit)")
        #endif
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        event("it stopped") { $0.ended() }
    }

    /// The window's return button: iOS brings Sill forward. The picture is Sill's own layer, still in the
    /// stream screen, so the interface is there as it was.
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        #if DEBUG
        print("pip: the window's return button: Sill's interface restored")
        #endif
        completionHandler(true)
    }
}

extension PictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    /// The window's play and pause button (PictureInPicturePolicy.Lifecycle.setPlaying): a pause freezes the
    /// picture and the sound, a play lets the live picture back.
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let apply = { [weak self] in
            guard let self else { return }
            self.event(playing ? "the window's play button" : "the window's pause button") { $0.setPlaying(playing, now: now) }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    /// Live: a range of infinite duration (the header: kCMTimeInfinity "to indicate live content"). Its start
    /// is not documented: zero, not negative infinity, which cost a lot of CPU from iOS 16.1 (Apple Developer
    /// Forums 724632).
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        pausedLock.withLock { pausedForAVKit }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        #if DEBUG
        print("pip: the window shows the picture at \(newRenderSize.width)×\(newRenderSize.height) px")
        #endif
    }

    /// Nothing to skip in a live picture (`requiresLinearPlayback` hides the buttons); the completion is owed
    /// whatever, or the window stays in a seeking state for good (the header).
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    /// The sound goes on while the window is tucked against the screen's edge, as the picture does.
    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }
}

// MARK: - Which window offers it

/// Which of Sill's windows offers Picture in Picture (PictureInPicturePolicy.chosen: the one used last among
/// those in front, and while none is in front the last choice), and so each window's offer: one per process,
/// as DeviceIdleTimer is. Each window's WindowSessionObserver says which session it shows and in which
/// UIWindow, both weak, so a window that closed leaves nothing; every look lists them afresh. It looks when a
/// scene comes, goes or changes its activation, when a session connects, ends, changes its source, gets its
/// picture or a cover over it, when the switch changes, and when the person uses a window that is not the
/// chosen one. Main thread.
final class PictureInPictureHub {
    static let shared = PictureInPictureHub()

    private struct Entry {
        weak var client: StreamClient?
        weak var window: UIWindow?
        let id: Int
        /// When its window's scene last came to the front (systemUptime); nil while it is not there.
        var frontSince: Double?
    }
    private var entries: [Entry] = []
    private var nextID = 1
    /// The window whose session offers Picture in Picture (its entry's id), kept while Sill is away.
    private var chosen: Int?
    private var observers: [NSObjectProtocol] = []

    private init() {
        for name in [UIScene.willConnectNotification, UIScene.didDisconnectNotification, UIScene.didActivateNotification,
                     UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.willEnterForegroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // A scene's activation state reads its new value once its notification has gone out.
                DispatchQueue.main.async { self?.update() }
            })
        }
    }

    /// A session's screen moved into `window` (nil: out of every window, and so offered nowhere).
    func session(_ client: StreamClient, window: UIWindow?) {
        let kept = entries.first { $0.client === client }
        entries.removeAll { $0.client == nil || $0.client === client }
        if let window {
            let id: Int
            if let kept { id = kept.id } else { id = nextID; nextID += 1 }
            entries.append(Entry(client: client, window: window, id: id, frontSince: kept?.window === window ? kept?.frontSince : nil))
        } else {
            client.pictureInPicture.setOffered(false)
        }
        update()
    }

    /// The person used `client`'s window (input to the Mac, one of the stream screen's controls): with
    /// several windows the choice may move to it. Cheap when it is the chosen one already, or the only one.
    func used(_ client: StreamClient) {
        guard entries.count > 1, let entry = entries.first(where: { $0.client === client }), entry.id != chosen else { return }
        update()
    }

    /// Lists the windows afresh, chooses, and tells each session whether it is offered.
    func update() {
        let now = ProcessInfo.processInfo.systemUptime
        entries.removeAll { $0.client == nil || $0.window == nil }
        var windows: [PictureInPicturePolicy.Window] = []
        var sessions: [Int: PictureInPicturePolicy.Session] = [:]
        for i in entries.indices {
            guard let client = entries[i].client, let window = entries[i].window else { continue }
            let front = window.windowScene?.activationState == .foregroundActive
            if !front { entries[i].frontSince = nil } else if entries[i].frontSince == nil { entries[i].frontSince = now }
            let session = client.pictureInPictureSession
            sessions[entries[i].id] = session
            let used = DeviceIdlePolicy.lastUse(.init(input: client.lastPersonInputAt, control: client.lastActionAt,
                                                      session: client.personSessionAt, front: entries[i].frontSince))
            windows.append(PictureInPicturePolicy.Window(id: entries[i].id, foregroundActive: front,
                                                         qualifies: PictureInPicturePolicy.qualifies(session), lastUsedAt: used))
        }
        #if DEBUG
        let was = chosen
        #endif
        chosen = PictureInPicturePolicy.chosen(windows, previous: chosen)
        #if DEBUG
        if chosen != was, entries.count > 1 {
            print("pip: window \(chosen.map(String.init) ?? "none") of \(entries.count) offers Picture in Picture")
        }
        #endif
        for entry in entries {
            guard let client = entry.client, let session = sessions[entry.id] else { continue }
            client.pictureInPicture.setOffered(PictureInPicturePolicy.offered(session, chosen: entry.id == chosen))
        }
    }
}
