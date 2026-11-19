import Foundation
import StreamProtocol

/// The device's camera stream (docs/camera-plan.md §6.1 points 4 to 8, §6.2, with §0's settlement): what
/// becomes of each picture the camera gives and each frame the encoder makes, as one reducer. DeviceCamera
/// (StreamClient+Camera) runs it on its queue `sill.camera.media` and carries out what comes back: an
/// encoder made or let go, a picture encoded (a keyframe or not) or skipped, an epoch's format (kind 46 type
/// 1, through SessionLink.send, kept in order across a move's fence) and its frames (type 2, through
/// SessionLink.sendCamera, never kept), the encoder's bitrate. Pure: Foundation and StreamProtocol's types,
/// checked with swiftc (Tests/checks/camera-stream).
///
/// - Encoders and epochs: an encoder is made at the first picture after the camera started, its rate or
///   camera changed, or a picture came at another size (the device turned: the camera's pictures are
///   upright). Each opens a new epoch (0 to 65,535, then round again), and so does a keyframe whose
///   parameter sets differ from its epoch's. The Mac decodes an epoch only after its format, so the format
///   goes right before the epoch's first frame, with that keyframe's parameter sets; nothing an older
///   encoder still gives back ever goes.
/// - Keyframes: an epoch's first frame, the Mac's ask (at most one a second: CameraPolicy.keyframe), after a
///   frame the encoder did not give back, and after an encoded frame was dropped, whose successors may need
///   it: nothing but a keyframe goes then (`awaitingKeyframe`); never otherwise.
/// - The send budget (CameraPacing): a picture is skipped before the encoder while a fence or hold stands or
///   the connection holds more than the budget; an encoded frame is dropped at a fence that went up since it
///   was encoded, and when it is past CameraFrame.maxDataBytes (the bitrate then steps down at once).
/// - The bitrate (CameraPolicy.BitrateStep): the target CameraPolicy.bitrate gives, a third down after a
///   second with a skip or a drop, a tenth back up every 5 s without one.
struct CameraStream: Equatable {
    /// What the glue asks for while the camera runs: the rate, the target bitrate, the camera.
    struct Plan: Equatable {
        var fps: Int
        var bitrate: Int
        var position: String
    }

    /// The uplink as SessionLink reads it now (CameraPacing's inputs).
    struct Uplink: Equatable {
        var fenced: Bool
        var unsent: Int
        var takenLastSecond: Int
    }

    /// An encoder: its serial (what its frames come back with), the pictures' size and the rate.
    struct Encoder: Equatable {
        var serial: Int
        var width: Int
        var height: Int
        var fps: Int
    }

    enum Action: Equatable {
        /// Make this encoder at this bitrate; the one before goes, with what it still holds.
        case encoder(Encoder, bitrate: Int)
        /// No encoder: the camera stopped.
        case noEncoder
        /// Encode the picture just given, a keyframe or not.
        case encode(keyframe: Bool)
        /// The epoch's format (type 1), right before its first frame.
        case format(CameraFormat)
        /// A frame (type 2), with its keyframe flag (the header's).
        case frame(CameraFrame, keyframe: Bool)
        /// The encoder's bitrate now.
        case bitrate(Int)
    }

    /// One second of the stream, for ClientStats (`cameraFps`, `cameraKbps`, `cameraDropped`).
    struct Second: Equatable {
        var frames = 0
        var bytes = 0
        var skipped = 0
        var dropped = 0
        var kbps: Int { bytes * 8 / 1000 }
    }

    private(set) var plan: Plan?
    private(set) var encoder: Encoder?
    /// The epoch the current encoder's frames go out as, and the one the next takes.
    private(set) var epoch = -1
    private var nextEpoch = 0
    private var nextSerial = 1
    /// The next frame's number in the epoch.
    private(set) var seq: UInt32 = 0
    /// The epoch's format went, with these parameter sets (`ParameterSets.encoded()`).
    private(set) var announced: Data?
    private(set) var pacing = CameraPacing()
    private(set) var step: CameraPolicy.BitrateStep?
    /// The next picture is encoded as a keyframe.
    private(set) var keyframeOwed = true
    /// An encoded frame was dropped: only a keyframe may go until one has.
    private(set) var awaitingKeyframe = false
    private var lastAskAt: Double?
    private var second = Second()
    /// The rate or the camera changed: the next picture makes a new encoder.
    private var encoderStale = false

    init() {}

    /// The camera runs with `plan`, or stops (nil). A new rate or camera makes a new encoder at the next picture;
    /// a new target bitrate is taken at once.
    mutating func run(_ next: Plan?, at now: Double) -> [Action] {
        let was = plan
        plan = next
        guard let next else {
            step = nil
            guard encoder != nil else { return [] }
            encoder = nil
            return [.noEncoder]
        }
        if let was, was.fps != next.fps || was.position != next.position { encoderStale = true }
        if var s = step {
            guard s.target != next.bitrate else { return [] }
            s.retarget(next.bitrate, at: now)
            step = s
            return encoder == nil ? [] : [.bitrate(s.current)]
        }
        step = CameraPolicy.BitrateStep(target: next.bitrate, at: now)
        return []
    }

    /// A picture of `width`×`height` from the camera: encoded (and first a new encoder, at a new size, rate or
    /// camera), or skipped by the send budget. Nothing while the camera is stopped, nor for a picture whose sides
    /// generation 1 does not take.
    mutating func picture(width: Int, height: Int, uplink: Uplink, at now: Double) -> [Action] {
        // A picture outside generation 1's sides (each even, 16 to 1920) could never be announced: never encoded.
        guard let plan, let step, CameraCodec.validSide(width), CameraCodec.validSide(height) else { return [] }
        var out: [Action] = []
        if encoderStale || encoder.map({ $0.width != width || $0.height != height }) ?? true {
            let e = Encoder(serial: nextSerial, width: width, height: height, fps: plan.fps)
            nextSerial += 1
            encoder = e
            encoderStale = false
            openEpoch()
            out.append(.encoder(e, bitrate: step.current))
        }
        guard pacing.encodes(fenced: uplink.fenced, unsent: uplink.unsent, takenLastSecond: uplink.takenLastSecond) else {
            second.skipped += 1
            return out
        }
        out.append(.encode(keyframe: keyframeOwed))
        keyframeOwed = false
        return out
    }

    /// A frame from the encoder of `serial`: the epoch's format first when it opens the epoch, then the frame.
    /// Dropped when an older encoder gave it, when it is past the frame's cap, when it opens an epoch without
    /// being a keyframe with parameter sets, or at a fence (CameraPacing.sends).
    mutating func encoded(serial: Int, data: Data, keyframe: Bool, parameterSets: ParameterSets?, fenced: Bool, at now: Double) -> [Action] {
        guard let e = encoder, e.serial == serial, let plan else { return [] }
        // A keyframe with other parameter sets than its epoch's opens an epoch of its own, which it starts.
        if keyframe, let ps = parameterSets?.encoded(), let was = announced, ps != was { openEpoch(owingKeyframe: false) }
        let number = seq
        seq &+= 1
        guard !data.isEmpty else {
            dropped()
            return []
        }
        guard data.count <= CameraFrame.maxDataBytes else {
            dropped()
            guard var s = step else { return [] }
            let before = s.current
            s.second(dropped: true, at: now)
            step = s
            return s.current != before ? [.bitrate(s.current)] : []
        }
        guard pacing.sends(keyframe: keyframe, fenced: fenced), keyframe || !awaitingKeyframe else {
            dropped()
            return []
        }
        var out: [Action] = []
        if announced == nil {
            guard keyframe, let ps = parameterSets?.encoded(), CameraCodec.validParameterSets(ps) else {
                dropped()
                return []
            }
            out.append(.format(CameraFormat(position: CameraCodec.position(plan.position), codec: CameraCodec.hevc,
                                            width: e.width, height: e.height, fps: e.fps, epoch: epoch,
                                            parameterSets: ps, bitrate: step?.current)))
            announced = ps
        }
        if keyframe { awaitingKeyframe = false }
        second.frames += 1
        second.bytes += CameraFrame.headerBytes + data.count
        out.append(.frame(CameraFrame(epoch: epoch, seq: number, data: data), keyframe: keyframe))
        return out
    }

    /// An encoded frame did not go: a later one may need it, so nothing but a keyframe goes until one has, and
    /// the next picture is one.
    private mutating func dropped() {
        second.dropped += 1
        keyframeOwed = true
        awaitingKeyframe = true
    }

    /// The link refused a frame `encoded` let go (SessionLink.sendCamera: a fence or a hold went up in between, or the
    /// connection went): as a frame dropped here.
    mutating func notSent() {
        guard encoder != nil else { return }
        dropped()
    }

    /// The encoder of `serial` gave nothing back for a picture (dropped or failed): as a frame dropped here,
    /// nothing but a keyframe goes until one has, and the next picture is one.
    mutating func encodeFailed(serial: Int) {
        guard encoder?.serial == serial else { return }
        dropped()
    }

    /// The Mac asked for a keyframe (type 3's `keyframe`): the next picture is one, at most once a second.
    mutating func keyframeAsked(at now: Double) {
        guard CameraPolicy.keyframe(newEpoch: false, demanded: true, lastDemandedAt: lastAskAt, droppedSince: false, at: now) else { return }
        lastAskAt = now
        keyframeOwed = true
    }

    /// A second closed: its numbers, and the bitrate's step (down after a skip or a drop in it, back up after
    /// 5 s without one).
    mutating func closeSecond(at now: Double) -> (Second, [Action]) {
        let s = second
        second = Second()
        guard var st = step else { return (s, []) }
        let before = st.current
        st.second(dropped: s.skipped + s.dropped > 0, at: now)
        step = st
        return (s, st.current != before && encoder != nil ? [.bitrate(st.current)] : [])
    }

    /// A new epoch for the frames from here: its number, its frames from 0, its format still to go, and a keyframe
    /// owed unless the frame that opens it is one.
    private mutating func openEpoch(owingKeyframe: Bool = true) {
        epoch = nextEpoch
        nextEpoch = (nextEpoch + 1) % (CameraCodec.epochs.upperBound + 1)
        seq = 0
        announced = nil
        if owingKeyframe { keyframeOwed = true }
    }
}
