import Foundation
import StreamProtocol

/// The device's rules for Share Camera (docs/camera-plan.md §6.1, §6.2, with §0's settlement): when the row
/// shows, when the device offers its camera and when it captures, the pause it says and why, the format and
/// bitrate it sends, the heat's steps, its keyframes, the chip, every word, and the send budget that keeps
/// the camera from queuing in front of input (`CameraPacing`). Pure: Foundation and StreamProtocol's types,
/// checked with swiftc (Tests/checks/camera). StreamClient+Camera, CameraCapture and CameraEncoder (the
/// next step) read it; nothing here touches AVFoundation, VideoToolbox or the network.
enum CameraPolicy {
    // MARK: The row

    /// What the device's Settings show for Share Camera with this Mac: nothing (the CLI, a host before the
    /// camera without a version: an older SillHost), "Update Sill on ‹Mac›" (a Sill.app from before the
    /// camera: a list with a `hostVersion` and no `camera`), the switch disabled with the Mac's words (the
    /// list says 0: its Use iPhone and iPad cameras off or Sill Camera not ready), or the switch.
    enum Row: Equatable { case hidden, updateMac, disabled, enabled }

    /// `locked`: the Mac's list says it is locked (LockPolicy leaves `camera` out then): hidden, the header
    /// says why.
    static func row(hostCamera: Int?, hostVersion: String?, locked: Bool) -> Row {
        if locked { return .hidden }
        guard let camera = hostCamera else { return hostVersion == nil ? .hidden : .updateMac }
        return camera >= CameraCodec.generation ? .enabled : .disabled
    }

    // MARK: Offering and capturing

    /// The iOS side's pressure (AVCaptureDevice.SystemPressureState.Level), in order.
    enum Pressure: Int, Comparable, CaseIterable {
        case nominal, fair, serious, critical, shutdown
        static func < (a: Pressure, b: Pressure) -> Bool { a.rawValue < b.rawValue }
    }

    /// What iOS says of the camera, besides the person's switch.
    struct Device: Equatable {
        /// Camera access refused (AVAuthorizationStatus .denied or .restricted).
        var denied = false
        /// A camera at the position chosen exists.
        var hasCamera = true
        /// Sill's scene is active with this session's window in front: never in the background or Picture in
        /// Picture, where iOS stops the camera.
        var front = true
        /// The iPad shares its screen with another app (Split View, Slide Over, Stage Manager without an
        /// external display), where iPadOS stops the camera.
        var multitasking = false
        /// Another app or a call has the camera (the session's interruption).
        var busy = false
        /// Sill's own pairing scanner shows.
        var scanner = false
        var pressure: Pressure = .nominal
    }

    /// The device offers its camera (type 1 without a pause, or with one) while the person's switch is on
    /// (turned on since Sill launched), the Mac's list says `camera` 1 or more, the session is connected, and
    /// iOS has not refused the camera: a refusal is said once as a pause and offers nothing more.
    static func offers(switchOn: Bool, hostCamera: Int?, connected: Bool) -> Bool {
        switchOn && connected && (hostCamera ?? 0) >= CameraCodec.generation
    }

    /// The capture session runs only while all hold: it offers, kind 16's camera says `inUse`, and nothing
    /// pauses it (`pause` is nil).
    static func captures(offering: Bool, state: CameraState?, device: Device) -> Bool {
        offering && state?.wanted == true && pause(state: state, device: device) == nil
    }

    /// Why the camera does not run although the device offers it, in this order: iOS refused it, there is no
    /// camera, it is too warm to run at all, Sill is not in front, the iPad shares its screen, Sill's scanner
    /// shows, another app has the camera; else `waiting` while the Mac wants nothing. Nil while it runs.
    static func pause(state: CameraState?, device d: Device) -> String? {
        if d.denied { return CameraFormat.denied }
        if !d.hasCamera { return CameraFormat.unavailable }
        if d.pressure == .shutdown { return CameraFormat.thermal }
        if !d.front { return CameraFormat.background }
        if d.multitasking { return CameraFormat.multitasking }
        if d.scanner { return CameraFormat.scanner }
        if d.busy { return CameraFormat.busy }
        if state?.wanted != true { return CameraFormat.waiting }
        return nil
    }

    /// Each second the camera captures counts as the person's use (DeviceIdlePolicy): a call keeps a phone
    /// awake.
    static func countsAsUse(capturing: Bool) -> Bool { capturing }

    // MARK: The format, the heat, the bitrate

    /// What the device sends: the demand's size if its camera has a format at that size and rate (`supports`),
    /// else 1280×720; upright, so a phone held upright sends 720×1280 inside a 1280×720 demand (the Mac
    /// pillarboxes); the demand's rate, at most 30; away from home at most 1280×720; the heat's caps on top.
    static func format(demand: CameraDemand?, upright: Bool, away: Bool, pressure: Pressure,
                       supports: (Int, Int, Int) -> Bool) -> (width: Int, height: Int, fps: Int) {
        var w = demand?.width ?? 1280, h = demand?.height ?? 720
        var fps = min(demand?.fps ?? 30, CameraCodec.rates.upperBound)
        if w < h { swap(&w, &h) }                                  // the camera's own landscape terms
        if !supports(w, h, fps) { (w, h) = (1280, 720) }
        let capped = away || pressure >= .critical
        if capped, w * h > 1280 * 720 { (w, h) = (1280, 720) }
        fps = min(fps, maxRate(pressure))
        return upright ? (h, w, fps) : (w, h, fps)
    }

    /// The rate the heat allows: 20 fps from `.serious`, 15 from `.critical`.
    static func maxRate(_ p: Pressure) -> Int {
        switch p {
        case .nominal, .fair: return 30
        case .serious: return 20
        case .critical, .shutdown: return 15
        }
    }

    /// How long the pressure must have fallen before the format steps back up.
    static let thermalRecovery: Double = 30

    /// The encoder's target: 2.5 Mbit/s for 1280×720 at 30 fps at home, 1.2 away; 4 for 1920×1080 at home;
    /// by area and rate between, at least 300 kbit/s; never over the demand's ceiling.
    static func bitrate(width: Int, height: Int, fps: Int, away: Bool, ceiling: Int?) -> Int {
        let pixels = Double(width * height) * Double(max(1, fps)) / 30
        let small = Double(1280 * 720), large = Double(1920 * 1080)
        var rate = pixels <= small ? 2_500_000 * pixels / small : 2_500_000 + 1_500_000 * min(1, (pixels - small) / (large - small))
        if away { rate = min(rate, 1_200_000) }
        if let ceiling, ceiling > 0 { rate = min(rate, Double(ceiling)) }
        return max(300_000, Int(rate.rounded()))
    }

    /// The bitrate as the link allows: a third down after each second with a pacing drop, a tenth back up
    /// every 5 s without one, never above the target nor under a fifth of it (300 kbit/s at least).
    struct BitrateStep: Equatable {
        private(set) var target: Int
        private(set) var current: Int
        private var quietSince: Double

        init(target: Int, at now: Double) { self.target = target; current = target; quietSince = now }

        static let upEvery: Double = 5

        /// A new target (a new demand or format): taken at once, the steps start again.
        mutating func retarget(_ t: Int, at now: Double) { target = t; current = t; quietSince = now }

        /// One second closed: whether a frame was dropped in it.
        mutating func second(dropped: Bool, at now: Double) {
            let floor = max(300_000, target / 5)
            if dropped {
                current = max(floor, current * 2 / 3)
                quietSince = now
            } else if now - quietSince >= Self.upEvery {
                current = min(target, current + max(1, target / 10))
                quietSince = now
            }
        }
    }

    // MARK: Keyframes

    /// The encoder's next frame is a keyframe: at a new epoch, at a demand's `keyframe` (at most one a second),
    /// after a pacing drop; never otherwise (an infinite GOP, as the Mac's stream).
    static func keyframe(newEpoch: Bool, demanded: Bool, lastDemandedAt: Double?, droppedSince: Bool, at now: Double) -> Bool {
        if newEpoch || droppedSince { return true }
        guard demanded else { return false }
        return now - (lastDemandedAt ?? -.infinity) >= 1
    }

    // MARK: The chip

    /// The indicator (App Review 2.5.14: a clear sign whenever the camera runs): "Camera" and who uses it while
    /// frames go, "Camera Paused" while the Mac wants it and it pauses, nothing otherwise. In Full Screen, the
    /// camera symbol alone.
    enum Chip: Equatable {
        case none
        case on(app: String?)
        case paused
    }

    static func chip(offering: Bool, state: CameraState?, capturing: Bool) -> Chip {
        guard offering, state?.wanted == true else { return .none }
        return capturing ? .on(app: state?.app) : .paused
    }

    // MARK: The words

    enum Copy {
        static let row = "Share Camera"
        static let beta = "Beta"
        static let position = "Camera"
        static let front = "Front"
        static let back = "Back"
        static let openSettings = "Open Settings"
        static let chipTitle = "Camera"
        static let chipPaused = "Camera Paused"
        static let chipStop = "Stop"
        static let chipStopLabel = "Stop sharing the camera"
        static let chipFullScreenLabel = "Camera on"
        static let chipPausedLabel = "Camera paused."

        /// The chip's second line: "FaceTime on Mac mini", or "On" when the app is not known.
        static func chipDetail(app: String?, mac: String) -> String { app.map { "\($0) on \(mac)" } ?? "On" }

        /// VoiceOver's words for the chip while the camera runs.
        static func chipLabel(app: String?, mac: String) -> String {
            app.map { "Camera on. \($0) on \(mac) is using it." } ?? "Camera on. An app on \(mac) is using it."
        }

        /// The footnote under the row: the Mac's word (kind 16's camera), the pause, or what the switch does.
        static func footnote(row: Row, switchOn: Bool, state: CameraState?, pause: String?, mac: String, device: String) -> String {
            switch row {
            case .hidden: return ""
            case .updateMac: return "Update Sill on \(mac) to share this \(device)’s camera with it."
            case .disabled, .enabled: break
            }
            // The Mac's words by its literal state: a state this build does not know never captures (`wanted`), and
            // its words are the switch's own below.
            if row == .disabled || state?.state == CameraState.off {
                return "Turn on Use iPhone and iPad cameras in Sill’s Settings on \(mac) to share this \(device)’s camera with it."
            }
            if state?.state == CameraState.notReady {
                return "Sill Camera isn’t ready on \(mac). In Sill’s Settings there, Streaming shows what it needs."
            }
            if state?.state == CameraState.unpaired { return "Pair this \(device) with \(mac) to share its camera." }
            guard switchOn else {
                return "Lets apps on \(mac), such as FaceTime or Zoom, use this \(device)’s camera as “Sill Camera”. "
                    + "The camera turns on only while one of them uses it, and Sill shows when it’s on."
            }
            switch pause {
            case CameraFormat.denied?: return "Sill isn’t allowed to use the camera. Open Settings and turn on Camera for Sill."
            case CameraFormat.unavailable?: return "This \(device) has no camera Sill can use."
            case CameraFormat.thermal?: return "The camera is paused while this \(device) cools down."
            case CameraFormat.multitasking?: return "The camera pauses while another app shares the screen with Sill."
            case CameraFormat.busy?: return "Another app is using the camera. Sill’s comes back when it’s done."
            default: break
            }
            switch state?.state {
            case CameraState.another?:
                let holder = state?.holder.flatMap { $0.isEmpty ? nil : $0 } ?? "Another device"
                return "\(holder) is \(mac)’s camera now. Turn Share Camera off and on to use this \(device) instead."
            case CameraState.inUse?:
                return state?.app.map { "\($0) on \(mac) is using this \(device)’s camera." } ?? "An app on \(mac) is using this \(device)’s camera."
            default:
                return "Apps on \(mac) can choose “Sill Camera”. The camera turns on only while one of them uses it."
            }
        }

        /// The settings button beside a refusal's footnote.
        static func showsOpenSettings(pause: String?) -> Bool { pause == CameraFormat.denied }
    }
}

/// The device's send budget for the camera (docs/camera-plan.md §6.2): its frames share the session's TCP
/// connection with input, so they never queue in front of it. A captured picture goes to the encoder only
/// while no hand-over fence or hold stands (SessionLink) and the bytes the connection has not taken yet (sent,
/// `.contentProcessed` not yet called; the camera's and everyone's) are within the budget: the larger of 16 KB
/// and 40 ms of what the connection took over the last second. Otherwise the picture is skipped before it is
/// encoded (latency beats quality: drop before queuing), so the encoder never makes a frame that a later one
/// needs and is then lost, and no keyframe is forced. So input waits behind at most the budget and the one
/// frame then crossing. An encoded frame is dropped only when a fence went up between its encoding and its
/// sending (a move): the move's new epoch then starts with a keyframe.
///
/// (The plan's first draft dropped encoded frames and forced a keyframe after each drop. Its model, in
/// Tests/checks/camera, showed a 2.5 Mbit/s camera on a 5 Mbit/s link dropping every frame after each keyframe:
/// a keyframe is five frames' bytes, over the budget for its own drain, each drop forced another keyframe, and
/// the stream fell to its lowest bitrate. Skipping before the encoder has no such cycle.)
struct CameraPacing: Equatable {
    static let minimumBudget = 16_384
    static let budgetSeconds = 0.040

    /// The budget for what the connection took in the last second.
    static func budget(takenLastSecond: Int) -> Int {
        max(minimumBudget, Int(Double(takenLastSecond) * budgetSeconds))
    }

    /// Pictures skipped before the encoder, and encoded frames dropped at a fence (ClientStats' `cameraDropped`
    /// is their sum).
    private(set) var skipped = 0
    private(set) var dropped = 0
    /// A frame was dropped and no keyframe has gone since: only a keyframe may go now.
    private(set) var needsKeyframe = false

    /// Whether a captured picture goes to the encoder. `fenced`: a hand-over's fence or hold stands;
    /// `unsent`: bytes handed to the connection and not taken yet; `takenLastSecond`: what it took in the last
    /// second.
    mutating func encodes(fenced: Bool, unsent: Int, takenLastSecond: Int) -> Bool {
        if fenced || unsent > Self.budget(takenLastSecond: takenLastSecond) { skipped += 1; return false }
        return true
    }

    /// Whether an encoded frame goes now: always, but while a fence or hold stands (a move began since it was
    /// encoded), and never a frame that needs a dropped one before a keyframe.
    mutating func sends(keyframe: Bool, fenced: Bool) -> Bool {
        if fenced || (needsKeyframe && !keyframe) { dropped += 1; needsKeyframe = true; return false }
        if keyframe { needsKeyframe = false }
        return true
    }
}
