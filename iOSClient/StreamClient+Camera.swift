import AVFoundation
import CoreMedia
import Foundation
import UIKit
import StreamProtocol

/// What the views read of Share Camera now (StreamClient's `cameraLook`): whether this device offers its camera to
/// this session's Mac, whether the camera runs for it, and why not while the Mac wants it (CameraPolicy's pause).
struct CameraLook: Equatable {
    var offering = false
    var capturing = false
    var pause: String?
}

/// The camera's state for this session, main thread (StreamClient's `cameraSession`).
struct CameraSessionState {
    /// What this device last said of its offer on this connection (CameraPolicy.offerStep).
    var offer = CameraPolicy.Offer()
    /// The Mac's last type 3 (its size, rate and bitrate ceiling).
    var demand: CameraDemand?
    /// What iOS says of the camera besides the switch (CameraPolicy.Device).
    var device = CameraPolicy.Device()
    /// The pressure the format follows: up at once, back down a step every `CameraPolicy.thermalRecovery`.
    var pressure = CameraPolicy.Pressure.nominal
    var pressureNow = CameraPolicy.Pressure.nominal
    var pressureStep: DispatchWorkItem?
    /// The capture asked for, and the stop that waits a moment (a move, the Mac changing its mind).
    var request: CameraCapture.Request?
    var stopWork: DispatchWorkItem?
    /// Camera access asked once this launch.
    var askedAccess = false
    /// The last second the camera ran for the Mac (DeviceIdlePolicy.Uses.camera; systemUptime).
    var lastUseAt: Double?
    /// The stream's last second, for ClientStats: nil before the camera ran this session.
    var second: CameraStream.Second?
    /// DEBUG: the harness set what the camera looks like (MockCatalog.seedCamera); nothing decides it then.
    var mocked = false
}

// Share Camera, this device's side (kind 46; docs/camera-plan.md §6.1, §8, §9, with §0's settlement and the
// overview's decision 4). CameraPolicy has the rules, CameraStream the stream's, CameraCapture the camera, CameraEncoder
// the encoder; this keeps the session's state and carries them out.
//
// - The switch (`shareCameraKey`, the Settings panel's This iPad group, a beta) starts off at every launch: the camera
//   runs only after the person turned it on since Sill launched; it stays on through reconnects and moves.
// - The offer (kind 46 type 1 without a codec): while the switch is on and the Mac's list says `camera` 1 or more,
//   on each connection, again when the Mac's camera comes back from its switch, Sill Camera's readiness, a lock or
//   pairing (it must be said again within 10 s: CameraHostPolicy.grace), with its pause when it changes; `claim` once
//   after the person turned the switch on; `stop` when the person turns it off.
// - The camera runs only while CameraPolicy.captures says so: kind 16's `camera` says `inUse` (an app on the Mac uses
//   Sill Camera and this device is it), Sill is in front, and nothing pauses it. Its format follows the Mac's type 3
//   (CameraPolicy.format, upright: the capture turns the pictures as the device turns), its bitrate CameraPolicy's.
//   iOS's interruptions (another app, multitasking, the background) leave the session to resume by itself.
// - Each second the camera runs counts as the person's use (DeviceIdlePolicy.Uses.camera); ClientStats carry its
//   frames, rate, drops and pause.
//
// Everything here is main thread; DeviceCamera runs the stream on its own queue.
extension StreamClient {
    /// This device's switch, Share Camera (#193's key): off until turned on, and off again at every launch
    /// (`resetShareCameraAtLaunch`). The device's own, never sent; read at each decision.
    static let shareCameraKey = "Sill.shareCamera"
    static var shareCameraOn: Bool { UserDefaults.standard.bool(forKey: shareCameraKey) }

    /// Which camera (Camera: Front | Back under the switch): front unless chosen; remembered.
    static let cameraPositionKey = "Sill.cameraPosition"
    static var cameraPosition: String { CameraCodec.position(UserDefaults.standard.string(forKey: cameraPositionKey)) }

    /// As Sill launches (SillApp): the switch off, so the camera never runs before the person turned it on in this
    /// launch (the overview's decision 4). A launch argument's value (the harness's `-Sill.shareCamera 1`) is in
    /// another domain and stays.
    static func resetShareCameraAtLaunch() {
        UserDefaults.standard.removeObject(forKey: shareCameraKey)
    }

    /// Sill's scene coming and going, and the pairing scanner, change what the camera may do. From init.
    func observeCameraActivation() {
        let center = NotificationCenter.default
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification,
                     UIApplication.willResignActiveNotification, CodeScanner.liveChanged] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // A scene's activation state reads its new value once its notification has gone out.
                DispatchQueue.main.async { self?.updateCamera(why: "Sill's scene or the scanner") }
            }
        }
    }

    // MARK: From the Mac and the person

    /// Each window list's `camera`.
    func hostCameraChanged(_ value: Int?) {
        guard hostCamera != value else { return }
        hostCamera = value
        updateCamera(why: "the Mac's list says camera \(value.map(String.init) ?? "nothing")")
    }

    /// Kind 16's `camera` for this connection. Back from a refusal (the Mac's switch, Sill Camera's readiness,
    /// pairing), the offer is said again.
    func cameraStateChanged(_ state: CameraState?) {
        // The harness's mock answers a pick with its own state, which says nothing of the camera it set.
        guard cameraState != state, !cameraSession.mocked else { return }
        if CameraPolicy.offersAgain(from: cameraState, to: state) { cameraSession.offer.offered = false }
        cameraState = state
        updateCamera(why: "the Mac says \(state.map { $0.state + ($0.app.map { " (\($0))" } ?? "") } ?? "nothing")")
    }

    /// A type 3: the Mac's size, rate and bitrate ceiling, and its keyframe ask.
    func receiveCameraDemand(_ d: CameraDemand) {
        var shape = d
        shape.keyframe = nil
        shape.token = nil
        if d.keyframe == true { cameraPipeline?.keyframeAsked() }
        #if DEBUG
        print("camera: the Mac asks \(d.width ?? 0)x\(d.height ?? 0) at \(d.fps ?? 0) fps, at most \(d.maxBitrate ?? 0) bit/s\(d.keyframe == true ? ", a keyframe" : "") (token \(d.token ?? 0))")
        #endif
        guard cameraSession.demand != shape else { return }
        cameraSession.demand = shape
        updateCamera(why: "the Mac's demand")
    }

    /// The Settings row's switch moved.
    func cameraSwitchChanged() {
        if Self.shareCameraOn {
            cameraSession.offer.claimOwed = true
            cameraSession.offer.offered = false
        }
        updateCamera(why: "the switch \(Self.shareCameraOn ? "on" : "off")")
    }

    /// Camera: Front | Back.
    func cameraPositionChanged() { updateCamera(why: "the \(Self.cameraPosition) camera chosen") }

    /// The chip's Stop: Share Camera off (CameraPolicy's Q14: Stop turns it off).
    func stopSharingCamera() {
        UserDefaults.standard.set(false, forKey: Self.shareCameraKey)
        cameraSwitchChanged()
    }

    /// A move handed the session to its new connection (`finishMove`): the Mac knows the new one afresh, so the offer
    /// goes again on it (no claim) and the camera waits for its kind 16; the capture stays warm meanwhile.
    func cameraMoved() {
        cameraSession.offer.offered = false
        cameraSession.demand = nil
        cameraState = nil
        updateCamera(why: "a move")
    }

    /// The session ended: the camera stops at once, nothing of the session is kept.
    func resetCamera() {
        hostCamera = nil
        cameraState = nil
        cameraSession.stopWork?.cancel()
        cameraSession.pressureStep?.cancel()
        let kept = (cameraSession.askedAccess, cameraSession.lastUseAt)
        cameraSession = CameraSessionState()
        cameraSession.askedAccess = kept.0
        cameraSession.lastUseAt = kept.1
        cameraPipeline?.run(nil, plan: nil)
        cameraLook = CameraLook()
    }

    // MARK: The decision

    /// The one place the camera's state is decided: what iOS says now, the offer, and the capture.
    func updateCamera(why: String) {
        guard !cameraSession.mocked else { return }
        var s = cameraSession
        let switchOn = Self.shareCameraOn
        let position = Self.cameraPosition
        // What iOS says.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        s.device.denied = status == .denied || status == .restricted
        s.device.hasCamera = Self.cameraSourceIsPattern || CameraCapture.camera(at: position) != nil
        s.device.front = sceneInFront && !shownOnlyInPictureInPicture
        s.device.scanner = CodeScanner.live > 0
        s.device.pressure = s.pressure
        if !s.device.front { s.device.busy = false; s.device.multitasking = false }   // iOS says again once Sill is back
        // The offer (CameraPolicy.offerStep): said when new on this connection or changed, `claim` once after the switch
        // went on, `stop` when the person turned the switch off while the Mac takes the camera.
        let offering = CameraPolicy.offers(switchOn: switchOn, hostCamera: hostCamera, connected: connected) && !CameraPolicy.refuses(cameraState)
        let pause = CameraPolicy.pause(state: cameraState, device: s.device)
        if offering, switchOn, status == .notDetermined, !s.askedAccess {
            s.askedAccess = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.updateCamera(why: "camera access \(granted ? "allowed" : "refused")") }
            }
        }
        let hostTakes = connected && (hostCamera ?? 0) >= CameraCodec.generation
        if let said = CameraPolicy.offerStep(&s.offer, offering: offering, switchOn: switchOn, hostTakes: hostTakes, pause: pause, position: position) {
            if let m = CameraMessage.message(.format(said), now: Date().timeIntervalSince1970) { sendCameraControl(m.serialized()) }
            #if DEBUG
            print(said.stop == true ? "camera: stopped sharing"
                  : "camera: offered (\(position)\(said.claim == true ? ", claiming it" : "")\(pause.map { ", paused: \($0)" } ?? ""))")
            #endif
        }
        // The capture runs through iOS's own interruptions and the worst pressure (CameraPolicy.sessionRuns), so iOS
        // says when they end; its pictures go to the Mac exactly while nothing pauses it (`captures`).
        let runs = CameraPolicy.sessionRuns(offering: offering, state: cameraState, device: s.device)
        let capturing = CameraPolicy.captures(offering: offering, state: cameraState, device: s.device)
        if runs {
            s.stopWork?.cancel()
            s.stopWork = nil
            let away = remoteRoute != nil
            let device = Self.cameraSourceIsPattern ? nil : CameraCapture.camera(at: position)
            let f = CameraPolicy.format(demand: s.demand, upright: false, away: away, pressure: s.pressure) { w, h, fps in
                Self.cameraSourceIsPattern || CameraCapture.supports(device, width: w, height: h, fps: fps)
            }
            let request = CameraCapture.Request(position: position, width: f.width, height: f.height, fps: f.fps)
            let bitrate = CameraPolicy.bitrate(width: f.width, height: f.height, fps: f.fps, away: away, ceiling: s.demand?.maxBitrate)
            let pipeline = cameraPipeline ?? makeCameraPipeline()
            #if DEBUG
            if s.request != request { print("camera: capturing \(f.width)x\(f.height) at \(f.fps) fps, \(bitrate) bit/s (\(position), \(why))") }
            #endif
            s.request = request
            pipeline.run(request, plan: capturing ? CameraStream.Plan(fps: f.fps, bitrate: bitrate, position: position) : nil)
        } else if s.request != nil, s.stopWork == nil {
            // The stream stops at once; the camera a moment later, unless it is wanted again meanwhile.
            cameraPipeline?.run(s.request, plan: nil)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.cameraSession.stopWork = nil
                self.cameraSession.request = nil
                self.cameraPipeline?.run(nil, plan: nil)
                #if DEBUG
                print("camera: off")
                #endif
            }
            s.stopWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.cameraStopDelay, execute: work)
        }
        cameraSession = s
        let look = CameraLook(offering: offering, capturing: capturing, pause: offering ? pause : nil)
        if look != cameraLook { cameraLook = look }
        if capturing { DeviceIdleTimer.shared.used() }
    }

    /// How long the camera stays on after it is no longer wanted: a move or a quick change of the Mac's mind finds it
    /// still running; the green dot goes within it.
    static let cameraStopDelay = 0.5

    /// DEBUG `-SillCameraSource pattern`: CameraPattern's moving pattern instead of the camera (the simulator has
    /// none). Never in a Release build.
    static var cameraSourceIsPattern: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "SillCameraSource") == "pattern"
        #else
        return false
        #endif
    }

    /// The stream's runner, made the first time the camera runs, with this session's way out.
    private func makeCameraPipeline() -> DeviceCamera {
        let p = DeviceCamera(pattern: Self.cameraSourceIsPattern)
        p.sendControl = { [weak self] data in self?.sendCameraControl(data) }
        p.sendFrame = { [weak self] data in self?.sendCameraFrame(data) ?? false }
        p.uplink = { [weak self] in self?.cameraUplink ?? SessionLink.Uplink(fenced: true, unsent: 0, takenLastSecond: 0) }
        p.onEvent = { [weak self] event in DispatchQueue.main.async { self?.cameraEvent(event) } }
        p.onSecond = { [weak self] second in DispatchQueue.main.async { self?.cameraSecond(second) } }
        cameraPipeline = p
        return p
    }

    /// What the camera says: iOS's interruptions and their end, its pressure, a missing camera.
    private func cameraEvent(_ event: CameraCapture.Event) {
        switch event {
        case .running:
            return
        case .interrupted(let why):
            switch why {
            case .multitasking?: cameraSession.device.multitasking = true
            case .busy?: cameraSession.device.busy = true
            case .pressure?: pressureChanged(.shutdown)
            case .background?, nil: break      // the scene's own state says it
            }
        case .interruptionEnded:
            cameraSession.device.multitasking = false
            cameraSession.device.busy = false
        case .failed(let code):
            #if DEBUG
            print("camera: the capture failed (\(code)); it starts again when it can")
            #endif
            _ = code
            return
        case .pressure(let p):
            pressureChanged(p)
        case .noCamera:
            break          // `updateCamera` finds no camera at that position, and says so
        }
        #if DEBUG
        print("camera: \(event)")
        #endif
        updateCamera(why: "the camera: \(event)")
    }

    /// The system's pressure: a rise is taken at once, a fall a step at a time, `thermalRecovery` apart.
    private func pressureChanged(_ p: CameraPolicy.Pressure) {
        cameraSession.pressureNow = p
        cameraSession.pressureStep?.cancel()
        cameraSession.pressureStep = nil
        if p >= cameraSession.pressure {
            cameraSession.pressure = p
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let s = self.cameraSession
            guard s.pressureNow < s.pressure, let lower = CameraPolicy.Pressure(rawValue: s.pressure.rawValue - 1) else { return }
            self.cameraSession.pressure = max(lower, s.pressureNow)
            self.updateCamera(why: "the pressure fell")
            self.pressureChanged(s.pressureNow)
        }
        cameraSession.pressureStep = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CameraPolicy.thermalRecovery, execute: work)
    }

    /// A second of the stream: its numbers for ClientStats, and the person's use while it ran (DeviceIdlePolicy).
    private func cameraSecond(_ second: CameraStream.Second) {
        guard connected else { return }
        cameraSession.second = second
        if second.frames > 0 {
            cameraSession.lastUseAt = ProcessInfo.processInfo.systemUptime
            DeviceIdleTimer.shared.used()
        }
    }

    /// ClientStats' camera fields for the second just closed: nil before the camera ran this session.
    func cameraStatsFields(_ stats: inout ClientStats) {
        guard let s = cameraSession.second else { return }
        stats.cameraFps = s.frames
        stats.cameraKbps = s.kbps
        stats.cameraDropped = s.skipped + s.dropped
        stats.cameraPause = cameraLook.offering && cameraState?.wanted == true ? cameraLook.pause : nil
    }

    /// When the camera last ran for the Mac (DeviceIdlePolicy.Uses.camera).
    var lastCameraUseAt: Double? { cameraSession.lastUseAt }
}

/// The device's camera stream on its queue `sill.camera.media` (docs/camera-plan.md §9): the source's pictures
/// (CameraCapture, or DEBUG's PatternSource) through CameraStream into CameraEncoder (the device's own encoder; in the
/// simulator VideoToolbox's software one, never the Mac's hardware encoder), and what comes back out to the Mac: an
/// epoch's format through SessionLink.send, its frames through SessionLink.sendCamera. Its seconds and the camera's
/// events go to the main thread. Nothing here touches the views.
final class DeviceCamera {
    let queue = DispatchQueue(label: "sill.camera.media", qos: .userInitiated)
    var sendControl: ((Data) -> Void)?
    var sendFrame: ((Data) -> Bool)?
    var uplink: (() -> SessionLink.Uplink)?
    var onEvent: ((CameraCapture.Event) -> Void)?
    var onSecond: ((CameraStream.Second) -> Void)?

    private var stream = CameraStream()
    private let source: CameraSource
    private var encoder: CameraEncoder?
    private var serial = 0
    private var timer: DispatchSourceTimer?
    private var running = false
    private var encoderFailedSaid = false
    /// The encoder CameraStream asked for, made again at most once a second while VideoToolbox gives none.
    private var wanted: (encoder: CameraStream.Encoder, bitrate: Int)?
    private var retryAt = 0.0
    /// In the simulator VideoToolbox runs on the Mac: its software encoder only.
    private static let software: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    init(pattern: Bool) {
        if pattern {
            source = PatternSource(queue: queue)
        } else {
            source = CameraCapture(outputQueue: queue)
        }
        source.onPicture = { [weak self] image, pts in self?.picture(image, pts: pts) }
        source.onEvent = { [weak self] event in self?.onEvent?(event) }
    }

    /// From the main thread: the camera runs at `request` (nil: off), and its pictures go to the Mac with `plan` (nil:
    /// none go, the camera kept warm).
    func run(_ request: CameraCapture.Request?, plan: CameraStream.Plan?) {
        if let request { source.start(request) } else { source.stop() }
        queue.async { [self] in
            apply(stream.run(plan, at: Self.now), image: nil)
            let wants = plan != nil
            guard wants != running else { return }
            running = wants
            if wants {
                let t = DispatchSource.makeTimerSource(queue: queue)
                t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(50))
                t.setEventHandler { [weak self] in self?.closeSecond() }
                t.resume()
                timer = t
            } else {
                timer?.cancel()
                timer = nil
                closeSecond()
            }
        }
    }

    /// The Mac asked for a keyframe.
    func keyframeAsked() { queue.async { [self] in stream.keyframeAsked(at: Self.now) } }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// A picture, on `queue`.
    private func picture(_ image: CVPixelBuffer, pts: CMTime) {
        let u = uplink?() ?? SessionLink.Uplink(fenced: true, unsent: 0, takenLastSecond: 0)
        let acts = stream.picture(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image),
                                  uplink: CameraStream.Uplink(fenced: u.fenced, unsent: u.unsent, takenLastSecond: u.takenLastSecond), at: Self.now)
        apply(acts, image: (image, pts))
    }

    private func apply(_ actions: [CameraStream.Action], image: (CVPixelBuffer, CMTime)?) {
        for action in actions {
            switch action {
            case .encoder(let e, let bitrate):
                encoder = nil
                serial = e.serial
                wanted = (e, bitrate)
                retryAt = 0
                makeEncoder()
            case .noEncoder:
                encoder = nil
                wanted = nil
            case .encode(let keyframe):
                if encoder == nil, Self.now >= retryAt { makeEncoder() }
                guard let (pixels, pts) = image, let encoder else { stream.encodeFailed(serial: serial); continue }
                let serial = self.serial
                let status = encoder.encode(pixels, pts: pts, keyframe: keyframe) { [weak self] status, output in
                    guard let self else { return }
                    self.queue.async { self.encoded(serial: serial, status: status, output: output) }
                }
                if status != noErr { stream.encodeFailed(serial: serial) }
            case .format(let f):
                if let m = CameraMessage.message(.format(f), now: Date().timeIntervalSince1970) { sendControl?(m.serialized()) }
            case .frame(let f, let keyframe):
                guard let m = CameraMessage.frameMessage(f, captured: captured, keyframe: keyframe) else { continue }
                if sendFrame?(m.serialized()) != true { stream.notSent() }
            case .bitrate(let b):
                encoder?.setBitrate(b)
            }
        }
    }

    /// The encoder CameraStream asked for (`wanted`), its bitrate the steps' now; when VideoToolbox gives none, said once
    /// and tried again a second later, each picture meanwhile counted as one the encoder did not give back.
    private func makeEncoder() {
        guard let (e, bitrate) = wanted else { return }
        retryAt = Self.now + 1
        switch CameraEncoder.make(width: e.width, height: e.height, fps: e.fps, bitrate: stream.step?.current ?? bitrate, software: Self.software) {
        case .success(let made):
            encoder = made
            encoderFailedSaid = false
        case .failure(let why):
            if !encoderFailedSaid {
                encoderFailedSaid = true
                print("camera: no encoder for \(e.width)x\(e.height) at \(e.fps) fps (\(why)); trying again each second")
            }
        }
    }

    /// The capture time of the frame being sent (the device's wall clock, converted from the host clock by an elapsed
    /// time alone: the privacy manifest's reason 35F9.1).
    private var captured = 0.0

    private func encoded(serial: Int, status: OSStatus, output: CameraEncoder.Output?) {
        guard let output else { stream.encodeFailed(serial: serial); return }
        let hostNow = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        captured = Date().timeIntervalSince1970 - max(0, hostNow - output.pts.seconds)
        let fenced = uplink?().fenced ?? true
        apply(stream.encoded(serial: serial, data: output.data, keyframe: output.keyframe, parameterSets: output.parameterSets,
                             fenced: fenced, at: Self.now), image: nil)
    }

    private func closeSecond() {
        let (second, acts) = stream.closeSecond(at: Self.now)
        apply(acts, image: nil)
        onSecond?(second)
    }
}
