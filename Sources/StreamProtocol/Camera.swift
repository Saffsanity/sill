import Foundation

// The device's camera as a camera on the Mac (kind 46, docs/camera-plan.md §5: the Mac's word on whether
// it wants frames rides kind 16, a frame's capture time and keyframe flag ride the message header). A
// kind 46 payload's first byte says what follows:
//
//   type 1, device → host: JSON `CameraFormat`, the device's offer of its camera, its pause and why,
//           or the format of an epoch whose frames follow;
//   type 2, device → host: binary `CameraFrame`, one HEVC access unit of that epoch;
//   type 3, host → device: JSON `CameraDemand`, the picture the Mac wants: its size, rate and bitrate
//           ceiling, and a keyframe.
//
// A reader drops a message past its type's cap whole (`CameraMessage.parse`) and skips a type it does
// not know. A writer refuses rather than truncates (`serialized()` is nil past a cap or a bound).
//
// Who sends what:
// • A device sends types 1 and 2 only to a host whose window list says `camera` 1 or more
//   (`WindowList.camera`), and frames only while its connection's kind 16 says `inUse`
//   (`HostSettingsState.camera`, `CameraState`): nothing captures before an app on the Mac uses the
//   camera.
// • A host sends type 3 only to a device whose hello says `camera` 1 or more (`Hello.camera`).
// • Whether the Mac wants this device's frames, and why not, is kind 16's `CameraState`, never type 3,
//   which carries only the stream's settings.
// • A frame's capture time is its message header's `timestamp`, the device's wall clock at capture in
//   seconds since 1970, as kinds 1 and 43 carry the Mac's; a device converts from the capture's host time
//   by an elapsed time alone (the privacy manifest's reason 35F9.1). Its keyframe flag is the header's
//   `isKeyframe`.
//
// Rules for later changes, on top of HostSettings.swift's:
// • `CameraFormat`, `CameraDemand` and kind 16's `CameraState` (HostSettings.swift, beside the other
//   structs of kind 16, which several checks compile alone) are JSON: every field optional but `state`,
//   strings never enums, never renamed or retyped. A reader takes an unknown `pause` as `unavailable`, an unknown
//   `position` as `front` and an unknown `state` as `off`.
// • The frame's layout is fixed once a public build carries it: a change is a new type byte.
// • Generation 1 (`CameraCodec.generation`) is HEVC Main, 8-bit 4:2:0, each side even and 16 to 1920,
//   1 to 30 fps, the layouts here. A later generation (H.264, 60 fps) says 2 in the hello and the list
//   and goes only to a peer that says 2.
//
// Pure: Foundation only, so it is checked on its own with swiftc (`camera-wire`, `compatibility`).

/// Generation 1's codec, positions and bounds.
public enum CameraCodec {
    /// What `Hello.camera` and `WindowList.camera` say for this layout.
    public static let generation = 1
    /// The one codec of generation 1: HEVC Main, 8-bit 4:2:0, no B-frames.
    public static let hevc = "hevc"
    /// `CameraFormat.position`'s values; any other reads as front.
    public static let positionFront = "front"
    public static let positionBack = "back"
    /// Each side of a picture, in pixels; even.
    public static let sides = 16...1920
    /// Frames a second.
    public static let rates = 1...30
    /// An epoch's number on the wire (UInt16).
    public static let epochs = 0...65_535
    /// `CameraFormat.parameterSets`, encoded (`ParameterSets.encoded()`): the epoch's VPS, SPS and PPS.
    public static let maxParameterSetBytes = 1024
    /// A bitrate in a format or a demand, in bits per second.
    public static let bitrates = 0...100_000_000

    /// A side of generation 1: even, 16 to 1920.
    public static func validSide(_ v: Int) -> Bool { sides.contains(v) && v % 2 == 0 }

    /// The camera a position names: the back one only for "back".
    public static func position(_ raw: String?) -> String { raw == positionBack ? positionBack : positionFront }

    /// Parameter sets as an epoch must carry them: `ParameterSets.encoded()` of three to sixteen sets (the
    /// VPS, SPS and PPS at least), none empty, with a NAL length of 1, 2 or 4 bytes, the whole at most
    /// `maxParameterSetBytes`.
    public static func validParameterSets(_ d: Data) -> Bool {
        guard d.count <= maxParameterSetBytes, let p = ParameterSets(encoded: d) else { return false }
        return [1, 2, 4].contains(p.nalUnitHeaderLength) && (3...16).contains(p.sets.count) && p.sets.allSatisfy { !$0.isEmpty }
            && p.encoded() == d
    }
}

/// Device → host (kind 46, type 1). Without `codec`: the device's offer of its camera (`claim` when its
/// person just turned Share Camera on), its pause and why (`pause`), or its stop (`stop`, Share Camera
/// off). With `codec`: the format of the epoch whose frames follow, sent before its first frame. JSON;
/// every field optional, so `{}` decodes and a later device's keys are skipped.
public struct CameraFormat: Codable, Hashable, Sendable {
    /// True: Share Camera went off; this device's offer ends (#193's).
    public var stop: Bool?
    /// `front` or `back` (#193's); any other value reads as `front`.
    public var position: String?
    /// True: the person just turned Share Camera on, so this device becomes the Mac's camera even if
    /// another device is. Never on a session's start, a reconnect or a move.
    public var claim: Bool?
    /// The offer stands but no frames come now, and why: one of `pauses`. Nil: not paused.
    public var pause: String?
    /// `hevc`: an epoch's format (#193's name). Generation 1 knows no other.
    public var codec: String?
    /// The frames' size as they stand upright, each side even and 16 to 1920 (#193's).
    public var width: Int?
    public var height: Int?
    /// 1 to 30 (#193's).
    public var fps: Int?
    /// 0 to 65,535; a new one for any change of size, rate or parameter sets (#193's).
    public var epoch: Int?
    /// The epoch's VPS, SPS and PPS, `ParameterSets.encoded()` (base64 in the JSON), at most 1,024 bytes.
    public var parameterSets: Data?
    /// The device encoder's target, bits per second; logged only.
    public var bitrate: Int?

    /// `pause`'s values: no demand yet, Sill in the background (Picture in Picture too), the iPad's
    /// multitasking, another app or a call holding the camera, Sill's own pairing scanner, the device too
    /// warm, camera access refused, no usable camera.
    public static let waiting = "waiting"
    public static let background = "background"
    public static let multitasking = "multitasking"
    public static let busy = "busy"
    public static let scanner = "scanner"
    public static let thermal = "thermal"
    public static let denied = "denied"
    public static let unavailable = "unavailable"
    public static let pauses = [waiting, background, multitasking, busy, scanner, thermal, denied, unavailable]

    public init(stop: Bool? = nil, position: String? = nil, claim: Bool? = nil, pause: String? = nil,
                codec: String? = nil, width: Int? = nil, height: Int? = nil, fps: Int? = nil, epoch: Int? = nil,
                parameterSets: Data? = nil, bitrate: Int? = nil) {
        self.stop = stop; self.position = position; self.claim = claim; self.pause = pause
        self.codec = codec; self.width = width; self.height = height; self.fps = fps; self.epoch = epoch
        self.parameterSets = parameterSets; self.bitrate = bitrate
    }

    /// An epoch's format, whose frames follow; else an offer, a pause or a stop.
    public var isEpoch: Bool { codec != nil }

    /// The pause as this build reads it: nil when not paused, one of `pauses`, an unknown reason as
    /// `unavailable`.
    public var knownPause: String? {
        guard let pause else { return nil }
        return Self.pauses.contains(pause) ? pause : Self.unavailable
    }

    /// Every field inside generation 1's bounds, and an epoch's format whole: `hevc`, its size, rate, epoch
    /// and parameter sets all there. A type 1 that is not is dropped whole (`CameraMessage.parse`).
    public var isValid: Bool {
        if let width, !CameraCodec.validSide(width) { return false }
        if let height, !CameraCodec.validSide(height) { return false }
        if let fps, !CameraCodec.rates.contains(fps) { return false }
        if let epoch, !CameraCodec.epochs.contains(epoch) { return false }
        if let parameterSets, !CameraCodec.validParameterSets(parameterSets) { return false }
        if let bitrate, !CameraCodec.bitrates.contains(bitrate) { return false }
        guard let codec else { return true }
        return codec == CameraCodec.hevc && width != nil && height != nil && fps != nil && epoch != nil && parameterSets != nil
    }
}

/// Device → host (kind 46, type 2): one HEVC access unit of an epoch, as the stream's own kind 1 carries
/// one: NAL units, each after its 4-byte big-endian length (VideoToolbox's output as it is). Binary, big
/// endian like the header:
///
///     type 2 · epoch UInt16 · seq UInt32 · data
///
/// The capture time and the keyframe flag are the message header's (`timestamp`, `isKeyframe`): #193's
/// per-frame width and height are gone (they are the epoch's), and so is its flags byte.
public struct CameraFrame: Hashable, Sendable {
    /// The epoch whose format came before it, 0 to 65,535.
    public var epoch: Int
    /// Its number in the epoch, from 0; a gap is a frame the device dropped.
    public var seq: UInt32
    /// 1 to `maxDataBytes` bytes.
    public var data: Data

    /// Before the data: the type, the epoch and seq.
    public static let headerBytes = 7
    /// The largest access unit a frame carries: a keyframe of 1920×1080 at generation 1's bitrates is far
    /// under it, and the device's encoder holds its keyframes to its data-rate limits.
    public static let maxDataBytes = 262_144

    public init(epoch: Int, seq: UInt32, data: Data) {
        self.epoch = epoch; self.seq = seq; self.data = data
    }

    /// The payload, its type byte first; nil for no data, more than `maxDataBytes` or an epoch outside
    /// 0 to 65,535: a frame is refused, never cut.
    public func serialized() -> Data? {
        guard !data.isEmpty, data.count <= Self.maxDataBytes, CameraCodec.epochs.contains(epoch) else { return nil }
        var d = Data(capacity: Self.headerBytes + data.count)
        d.append(CameraMessage.typeFrame)
        d.appendBigEndian(UInt16(epoch))
        d.appendBigEndian(seq)
        d.append(data)
        return d
    }
}

/// Host → device (kind 46, type 3): the picture the Mac wants of the device that holds its camera, sent
/// when it changes, and with `keyframe` to ask for one. Whether frames are wanted at all is kind 16's
/// (`CameraState`). JSON; every field optional.
public struct CameraDemand: Codable, Hashable, Sendable {
    /// What the app on the Mac chose: the device keeps its picture upright inside it (a phone held upright
    /// sends a tall picture, which the Mac pillarboxes).
    public var width: Int?
    public var height: Int?
    public var fps: Int?
    /// Make the next frame a keyframe: a frame that did not decode, an app that started, a pause's end.
    public var keyframe: Bool?
    /// The Mac's ceiling for the device's encoder, bits per second (lower away from home).
    public var maxBitrate: Int?
    /// Rises with every demand; the device's console line names it.
    public var token: Int?

    public init(width: Int? = nil, height: Int? = nil, fps: Int? = nil, keyframe: Bool? = nil,
                maxBitrate: Int? = nil, token: Int? = nil) {
        self.width = width; self.height = height; self.fps = fps; self.keyframe = keyframe
        self.maxBitrate = maxBitrate; self.token = token
    }

    /// Every field inside generation 1's bounds; a demand that is not is dropped whole.
    public var isValid: Bool {
        if let width, !CameraCodec.validSide(width) { return false }
        if let height, !CameraCodec.validSide(height) { return false }
        if let fps, !CameraCodec.rates.contains(fps) { return false }
        if let maxBitrate, !CameraCodec.bitrates.contains(maxBitrate) { return false }
        if let token, token < 0 { return false }
        return true
    }
}

/// A kind 46 payload, of any of its three types.
public enum CameraMessage: Hashable, Sendable {
    case format(CameraFormat)
    case frame(CameraFrame)
    case demand(CameraDemand)

    public static let typeFormat: UInt8 = 1
    public static let typeFrame: UInt8 = 2
    public static let typeDemand: UInt8 = 3
    /// The largest payload of each type a reader takes, its type byte included (a format with its
    /// parameter sets is under 2 KB, a demand under 200 bytes), all under the 1 MiB a device may send.
    /// Part of the compatibility floor once a public build reads kind 46: a peer drops a message past them
    /// whole, so a later one keeps within them.
    public static let maxFormatPayload = 4096
    public static let maxFramePayload = CameraFrame.headerBytes + CameraFrame.maxDataBytes
    public static let maxDemandPayload = 4096

    /// The payload, its type byte first; nil for a value outside its bounds or past its type's cap: a
    /// message is refused, never cut.
    public func serialized() -> Data? {
        switch self {
        case .format(let f):
            guard f.isValid else { return nil }
            var d = Data([Self.typeFormat])
            d.append(Wire.encode(f))
            return d.count <= Self.maxFormatPayload ? d : nil
        case .frame(let f):
            return f.serialized()
        case .demand(let r):
            guard r.isValid else { return nil }
            var d = Data([Self.typeDemand])
            d.append(Wire.encode(r))
            return d.count <= Self.maxDemandPayload ? d : nil
        }
    }

    /// Nil for an empty payload, a type this build does not know, one past its type's cap, JSON that does
    /// not decode or is outside generation 1's bounds (`isValid`), and a frame cut short or without data.
    /// Never traps, whatever the input.
    public static func parse(_ payload: Data) -> CameraMessage? {
        guard let type = payload.first else { return nil }
        switch type {
        case typeFormat:
            guard payload.count <= maxFormatPayload,
                  let f = Wire.decode(CameraFormat.self, from: Data(payload.dropFirst())), f.isValid else { return nil }
            return .format(f)
        case typeFrame:
            guard payload.count <= maxFramePayload, payload.count > CameraFrame.headerBytes else { return nil }
            let d = Data(payload)   // indices from 0
            let epoch = Int(d.readBigEndian(UInt16.self, at: 1))
            let seq = d.readBigEndian(UInt32.self, at: 3)
            return .frame(CameraFrame(epoch: epoch, seq: seq, data: d.subdata(in: CameraFrame.headerBytes..<d.count)))
        case typeDemand:
            guard payload.count <= maxDemandPayload,
                  let r = Wire.decode(CameraDemand.self, from: Data(payload.dropFirst())), r.isValid else { return nil }
            return .demand(r)
        default:
            return nil
        }
    }

    /// The whole kind 46 message of a type 2 frame: the header's time stamp is the capture time (the
    /// device's wall clock, seconds since 1970) and its keyframe flag the frame's. Nil as `serialized()`.
    public static func frameMessage(_ frame: CameraFrame, captured: Double, keyframe: Bool) -> StreamMessage? {
        guard let payload = frame.serialized() else { return nil }
        return StreamMessage(kind: .camera, timestamp: captured, isKeyframe: keyframe, payload: payload)
    }

    /// The whole kind 46 message of a type 1 or 3, stamped `now`. Nil as `serialized()`.
    public static func message(_ m: CameraMessage, now: Double) -> StreamMessage? {
        guard let payload = m.serialized() else { return nil }
        if case .frame = m { return nil }   // a frame carries its capture time: `frameMessage`
        return StreamMessage(kind: .camera, timestamp: now, isKeyframe: false, payload: payload)
    }
}
