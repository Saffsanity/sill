import Foundation

// The device's microphone as a microphone on the Mac (kind 48, docs/microphone-plan.md §4; the 2026-11-18
// overview's §1). Device → host only. A kind 48 payload's first byte says what follows:
//
//   type 1: JSON `MicrophoneFormat`, kind 43's AudioFormat keys with the microphone's own `claim` and
//           `pause`. Without `codec`: the device's offer of its microphone (its Share Microphone is on), its
//           claim when its person just turned the switch on, and its pause and why. With `codec`: the
//           format of the epoch whose packets follow too, sent before the epoch's first packet.
//   type 2: binary `AudioPackets`, kind 43's layout byte for byte (the epoch, the first packet's seq, the
//           segment flag, 1 to 255 AAC-ELD packets of 10 ms): ten packets a message, the 100 ms one capture
//           buffer holds. The message header's time stamp is the capture time of the first packet's first
//           decoded sample, on the device's wall clock (seconds since 1970, as kinds 1 and 43 carry the
//           Mac's); a device converts from the capture's host time by an elapsed time alone (the privacy
//           manifest's reason 35F9.1). The Mac never needs the offset between the two clocks: its playout's
//           floor does without it (AudioPlayout, rule 1).
//   type 3: the single byte 3: the device's Share Microphone went off, and its offer ends.
//
// A reader drops a message past its type's cap whole and skips a type it does not know; a writer refuses
// rather than cuts (`serialized()` is nil for a format outside generation 1's bounds or past the cap).
//
// Who sends what:
// • A device sends kind 48 only to a host whose window list says `microphone` 1 or more
//   (`WindowList.microphone`), and packets only while its connection's kind 16 says `inUse`
//   (`HostSettingsState.microphone`, `MicrophoneState`): nothing records before an app on the Mac uses
//   Sill Microphone. Whether the Mac wants this device's sound, and why not, is kind 16's alone.
// • A host sends no microphone kind ever.
//
// Rules for later changes, on top of HostSettings.swift's:
// • `MicrophoneFormat` is JSON: every field optional, strings never enums, never renamed or retyped. Its
//   keys are AudioFormat's (Audio.swift) with the same meanings, plus `claim` and `pause`; a reader takes an
//   unknown `pause` as `unavailable`.
// • The packets' layout is kind 43's, fixed: a change is a new type byte.
// • Generation 1 (`MicrophoneCodec.generation`): AAC-ELD, 48 kHz, mono, 480 or 512 frames a packet, the
//   layouts here. A new codec is a new string in kind 16's `codecs`, which a device picks from
//   (`MicrophoneCodec.choose`); a new layout a new type, or generation 2 in the window list.
//
// Pure: Foundation only, so it is checked on its own with swiftc (`microphone`, `compatibility`).

/// Generation 1's codec and bounds.
public enum MicrophoneCodec {
    /// What `WindowList.microphone` says for this layout.
    public static let generation = 1
    /// AAC-ELD, kind 43's codec, the other way.
    public static let aacELD = AudioCodec.aacELD
    /// What a host takes, best first: kind 16's `codecs` while it takes this device's microphone.
    public static let hostTakes = [aacELD]
    /// What a device makes, best first.
    public static let deviceMakes = [aacELD]
    /// What a device's encoder makes: 48 kHz mono, 480 frames a packet (10 ms), at 64 kbps.
    public static let sampleRate = 48_000
    public static let channels = 1
    public static let framesPerPacket = 480
    public static let bitrate = 64_000
    /// Packets one message carries: one capture buffer's 100 ms.
    public static let packetsPerMessage = 10
    /// A format's packet sizes (AAC-ELD's two), priming, cookie and bitrate, as generation 1 bounds them.
    public static let packetSizes = [480, 512]
    public static let primings = 0...2048
    public static let cookieBytes = 1...256
    public static let bitrates = 8_000...320_000
    public static let epochs = 0...65_535

    /// The codec a device sends: the first of the Mac's list (best first, kind 16's `codecs`) that the
    /// device makes. Nil for no list (an older Mac, a state without one) or nothing in common: no kind 48.
    public static func choose(taken: [String]?, makes: [String] = deviceMakes) -> String? {
        guard let taken else { return nil }
        return taken.first { makes.contains($0) }
    }
}

/// Device → host (kind 48, type 1): the device's offer of its microphone, and with `codec` the format of the
/// epoch whose packets follow. The JSON is kind 43's AudioFormat (its keys, names and meanings: `codec`
/// "aac-eld", `sampleRate` 48000, `channels` 1, `framesPerPacket`, `primingFrames`, `bitrate`, `epoch` and
/// `cookie`; `source` and `app` unused) with two keys of its own beside them, so `{}` decodes and a later
/// device's keys are skipped. Every type 1 says the offer stands.
public struct MicrophoneFormat: Codable, Hashable, Sendable {
    /// Kind 43's keys. With `codec`: an epoch's format, whole (`isValid`).
    public var format: AudioFormat
    /// True: the person just turned Share Microphone on, so this device becomes Sill Microphone's even if
    /// another device is. Never on a session's start, a reconnect or a move.
    public var claim: Bool?
    /// The offer stands but no sound comes now, and why: one of `pauses`. Nil: not paused.
    public var pause: String?

    /// `pause`'s values: Sill left the screen (Picture in Picture too), a call or another app holds the
    /// microphone, no microphone can be used now.
    public static let background = "background"
    public static let busy = "busy"
    public static let unavailable = "unavailable"
    public static let pauses = [background, busy, unavailable]

    public init(format: AudioFormat = AudioFormat(), claim: Bool? = nil, pause: String? = nil) {
        self.format = format; self.claim = claim; self.pause = pause
    }

    /// The format of an epoch generation 1 makes: AAC-ELD, 48 kHz mono, 480 frames a packet, 64 kbps.
    public static func epoch(_ epoch: Int, primingFrames: Int, cookie: Data, bitrate: Int = MicrophoneCodec.bitrate,
                             framesPerPacket: Int = MicrophoneCodec.framesPerPacket) -> MicrophoneFormat {
        MicrophoneFormat(format: AudioFormat(codec: MicrophoneCodec.aacELD, sampleRate: MicrophoneCodec.sampleRate,
                                             channels: MicrophoneCodec.channels, framesPerPacket: framesPerPacket,
                                             primingFrames: primingFrames, bitrate: bitrate, epoch: epoch, cookie: cookie))
    }

    /// An epoch's format, whose packets follow; else an offer alone.
    public var isEpoch: Bool { format.codec != nil }

    /// The pause as this build reads it: nil when not paused, one of `pauses`, an unknown reason as
    /// `unavailable`.
    public var knownPause: String? {
        guard let pause else { return nil }
        return Self.pauses.contains(pause) ? pause : Self.unavailable
    }

    /// Every field inside generation 1's bounds, and an epoch's format whole: AAC-ELD at 48 kHz, one
    /// channel, a packet size AAC-ELD has, its priming, epoch and cookie all there. A type 1 that is not is
    /// dropped whole (`MicrophoneMessage.parse`).
    public var isValid: Bool {
        let f = format
        if let v = f.sampleRate, v != MicrophoneCodec.sampleRate { return false }
        if let v = f.channels, v != MicrophoneCodec.channels { return false }
        if let v = f.framesPerPacket, !MicrophoneCodec.packetSizes.contains(v) { return false }
        if let v = f.primingFrames, !MicrophoneCodec.primings.contains(v) { return false }
        if let v = f.bitrate, !MicrophoneCodec.bitrates.contains(v) { return false }
        if let v = f.epoch, !MicrophoneCodec.epochs.contains(v) { return false }
        if let v = f.cookie, !MicrophoneCodec.cookieBytes.contains(v.count) { return false }
        guard let codec = f.codec else { return true }
        return codec == MicrophoneCodec.aacELD && f.sampleRate != nil && f.channels != nil && f.framesPerPacket != nil
            && f.primingFrames != nil && f.epoch != nil && f.cookie != nil
    }

    private enum Keys: String, CodingKey { case claim, pause }

    /// Kind 43's keys from the same JSON object, then the microphone's own.
    public init(from decoder: Decoder) throws {
        format = try AudioFormat(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        claim = try c.decodeIfPresent(Bool.self, forKey: .claim)
        pause = try c.decodeIfPresent(String.self, forKey: .pause)
    }

    /// One JSON object: kind 43's keys and the microphone's own side by side.
    public func encode(to encoder: Encoder) throws {
        try format.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(claim, forKey: .claim)
        try c.encodeIfPresent(pause, forKey: .pause)
    }
}

/// A kind 48 payload, of any of its three types.
public enum MicrophoneMessage: Hashable, Sendable {
    case format(MicrophoneFormat)
    case packets(AudioPackets)
    /// Share Microphone went off on the device.
    case end

    public static let typeFormat: UInt8 = 1
    public static let typePackets: UInt8 = 2
    public static let typeEnd: UInt8 = 3
    /// The largest payload of each type a reader takes, its type byte included: kind 43's caps (a format is
    /// under 1 KB, ten packets at 64 kbps under 1 KB too). Part of the compatibility floor once a public
    /// build reads kind 48: a Mac drops a message past them whole, so a later device keeps within them.
    public static let maxFormatPayload = AudioMessage.maxFormatPayload
    public static let maxPacketsPayload = AudioMessage.maxPacketsPayload

    /// The payload, its type byte first; nil for a format outside generation 1's bounds, packets the
    /// layout cannot carry whole (none, more than 255, one over 65,535 bytes) and anything past its type's
    /// cap: a message is refused, never cut.
    public func serialized() -> Data? {
        switch self {
        case .format(let f):
            guard f.isValid else { return nil }
            var d = Data([Self.typeFormat])
            d.append(Wire.encode(f))
            return d.count > 1 && d.count <= Self.maxFormatPayload ? d : nil
        case .packets(let p):
            guard (1...AudioPackets.maxCount).contains(p.packets.count),
                  p.packets.allSatisfy({ $0.count <= AudioPackets.maxPacketBytes }) else { return nil }
            let d = p.serialized()
            return d.count <= Self.maxPacketsPayload ? d : nil
        case .end:
            return Data([Self.typeEnd])
        }
    }

    /// Nil for an empty payload, a type this build does not know, one past its type's cap, a format whose
    /// JSON does not decode or is outside generation 1's bounds (`MicrophoneFormat.isValid`), packets as
    /// kind 43's reader refuses them (`AudioMessage.parse`: a header cut short, a count of 0, a length past
    /// the end, bytes left over), and an end with anything after its byte. Never traps, whatever the input.
    public static func parse(_ payload: Data) -> MicrophoneMessage? {
        guard let type = payload.first else { return nil }
        switch type {
        case typeFormat:
            guard payload.count <= maxFormatPayload,
                  let f = Wire.decode(MicrophoneFormat.self, from: Data(payload.dropFirst())), f.isValid else { return nil }
            return .format(f)
        case typePackets:
            guard payload.count <= maxPacketsPayload, case .packets(let p)? = AudioMessage.parse(payload) else { return nil }
            return .packets(p)
        case typeEnd:
            return payload.count == 1 ? .end : nil
        default:
            return nil
        }
    }

    /// The whole kind 48 message of a type 1 or 3, stamped `now`. Nil as `serialized()`, and for packets,
    /// which carry their capture time (`packetsMessage`).
    public static func message(_ m: MicrophoneMessage, now: Double) -> StreamMessage? {
        if case .packets = m { return nil }
        guard let payload = m.serialized() else { return nil }
        return StreamMessage(kind: .microphone, timestamp: now, isKeyframe: false, payload: payload)
    }

    /// The whole kind 48 message of a type 2: its header's time stamp is `captured`, the device's wall clock
    /// at the first packet's first decoded sample. Nil as `serialized()`.
    public static func packetsMessage(_ p: AudioPackets, captured: Double) -> StreamMessage? {
        guard captured.isFinite, let payload = MicrophoneMessage.packets(p).serialized() else { return nil }
        return StreamMessage(kind: .microphone, timestamp: captured, isKeyframe: false, payload: payload)
    }
}
