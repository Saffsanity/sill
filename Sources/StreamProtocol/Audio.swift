import Foundation

// The Mac's sound on the device (kind 29, docs/audio-plan.md §3). A kind 29 payload's first byte
// says what follows: type 1, how to decode what follows (JSON `AudioFormat`); type 2, codec packets
// of one epoch (binary `AudioPackets`). A reader skips a type it does not know.
//
// Who gets it: a host sends kind 29 only to a device whose hello (kind 23, `Hello.audio`) lists a
// codec it makes (`AudioCodec.choose`), and only while Send Audio is on (`StreamSettings.sendAudio`).
// A device from before 2026-09-27 lists none, so it is never sent one; it would skip it anyway (an
// unknown kind reads as `.unknown`).
//
// Rules for later changes, on top of HostSettings.swift's:
// • `AudioFormat` is JSON: every field optional, strings not enums, never renamed or retyped.
// • The packets' layout is fixed: a change is a new type byte, never a changed type 2.
// • A new codec is a new `codec` string, listed in the hello by the devices that play it. A host picks
//   the first of a device's list that it can make.
//
// Pure: Foundation only, so it is checked on its own with swiftc (`compatibility`, `protocol`).

/// The codecs by name, as the hello and the format carry them, and the host's pick.
public enum AudioCodec {
    /// AAC-ELD (AudioToolbox's kAudioFormatMPEG4AAC_ELD): 48 kHz stereo, 480 or 512 frames a packet
    /// (10 or 10.7 ms), 128 kbps. The only codec in this step.
    public static let aacELD = "aac-eld"
    /// What this host makes, best first.
    public static let hostMakes = [aacELD]
    /// What a device that plays the Mac's sound lists in its hello, best first.
    public static let devicePlays = [aacELD]

    /// The codec a host sends a device: the first of the device's list (best first) that the host
    /// makes. Nil for no list (a device that plays no sound, every device before 2026-09-27) and for
    /// a list with nothing the host makes: that device gets no kind 29.
    public static func choose(offered: [String]?, makes: [String] = hostMakes) -> String? {
        guard let offered else { return nil }
        return offered.first { makes.contains($0) }
    }
}

/// Host → device (kind 29, type 1): how to decode what follows. Sent to each device before its first
/// packet of an epoch, and so again for every new epoch (a new encoder: another app, Send Audio
/// coming on, the capture starting again). JSON; every field optional (HostSettings.swift's rules), so
/// `{}` decodes and a reader of a later host skips the keys it does not know.
public struct AudioFormat: Codable, Hashable, Sendable {
    /// `AudioCodec.aacELD` in this step. A device that does not play it ignores the sound.
    public var codec: String?
    /// 48000.
    public var sampleRate: Int?
    /// 2.
    public var channels: Int?
    /// 480 or 512: the frames each packet decodes to.
    public var framesPerPacket: Int?
    /// 240 or 256: the decoded frames a new segment starts with that are the codec's own, before its
    /// first captured frame (the device drops them).
    public var primingFrames: Int?
    /// The encoder's target in bits per second, 128000 (display only).
    public var bitrate: Int?
    /// The epoch of the packets this format belongs to (`AudioPackets.epoch`: 0 to 65535, wrapping).
    public var epoch: Int?
    /// The codec's magic cookie (AAC-ELD: its AudioSpecificConfig), which the device's decoder needs.
    /// Base64 in the JSON.
    public var cookie: Data?
    /// What the sound is of, display only: "app" (then `app` names it), "desktop" or "test". A string,
    /// never an enum.
    public var source: String?
    /// "Safari": the app whose sound this is (SafeText.label, at most 64 characters).
    public var app: String?

    /// `source`'s values.
    public static let sourceApp = "app"
    public static let sourceDesktop = "desktop"
    public static let sourceTest = "test"

    public init(codec: String? = nil, sampleRate: Int? = nil, channels: Int? = nil, framesPerPacket: Int? = nil,
                primingFrames: Int? = nil, bitrate: Int? = nil, epoch: Int? = nil, cookie: Data? = nil,
                source: String? = nil, app: String? = nil) {
        self.codec = codec; self.sampleRate = sampleRate; self.channels = channels
        self.framesPerPacket = framesPerPacket; self.primingFrames = primingFrames; self.bitrate = bitrate
        self.epoch = epoch; self.cookie = cookie; self.source = source; self.app = app
    }
}

/// Host → device (kind 29, type 2): one or more codec packets of one epoch, back to back. The
/// message header's time stamp is the host's wall clock (seconds since 1970, as the video's) of the
/// first decoded sample of its first packet; the packets after it follow `framesPerPacket /
/// sampleRate` apart. Binary, big endian like the header:
///
///     type 2 · epoch UInt16 · seq UInt32 · flags UInt8 · count UInt8 · count × (length UInt16 · bytes)
///
/// flags bit 0: the first packet is the first of a segment (the device resets its decoder and drops
/// the format's `primingFrames`); bits 1 to 7 are zero, and readers ignore them.
public struct AudioPackets: Hashable, Sendable {
    /// The encoder's epoch, 0 to 65535 (UInt16 on the wire, wrapping).
    public var epoch: Int
    /// The first packet's number in its epoch, from 0.
    public var seq: UInt32
    /// Flags bit 0.
    public var segmentStart: Bool
    /// 1 to 255 packets of at most 65,535 bytes each (this host sends one of about 170 bytes).
    public var packets: [Data]

    /// The most packets one message carries.
    public static let maxCount = 255
    /// The longest packet the layout can carry.
    public static let maxPacketBytes = 65_535
    /// Before the packets: the type, epoch, seq, flags and count.
    public static let headerBytes = 9

    public init(epoch: Int, seq: UInt32, segmentStart: Bool, packets: [Data]) {
        self.epoch = epoch; self.seq = seq; self.segmentStart = segmentStart; self.packets = packets
    }

    /// The payload, its type byte included. The epoch is written modulo 65,536. At most `maxCount`
    /// packets are written, and at most `maxPacketBytes` of each: this host never makes more.
    public func serialized() -> Data {
        let kept = packets.prefix(Self.maxCount)
        var d = Data(capacity: Self.headerBytes + kept.reduce(0) { $0 + 2 + min($1.count, Self.maxPacketBytes) })
        d.append(AudioMessage.typePackets)
        d.appendBigEndian(UInt16(truncatingIfNeeded: epoch))
        d.appendBigEndian(seq)
        d.append(segmentStart ? 1 : 0)
        d.append(UInt8(kept.count))
        for p in kept {
            let n = min(p.count, Self.maxPacketBytes)
            d.appendBigEndian(UInt16(n))
            d.append(p.prefix(n))
        }
        return d
    }
}

/// A kind 29 payload, either type.
public enum AudioMessage: Hashable, Sendable {
    case format(AudioFormat)
    case packets(AudioPackets)

    public static let typeFormat: UInt8 = 1
    public static let typePackets: UInt8 = 2
    /// The largest payload of each type a reader takes (a format is under 1 KB; a packets message at
    /// 128 kbps is under 1 KB too), far under the 4 MB every host message may have.
    public static let maxFormatPayload = 4096
    public static let maxPacketsPayload = 16384

    /// The payload, its type byte first.
    public func serialized() -> Data {
        switch self {
        case .format(let f):
            var d = Data([Self.typeFormat])
            d.append(Wire.encode(f))
            return d
        case .packets(let p):
            return p.serialized()
        }
    }

    /// Nil for an empty payload, a type this build does not know, a format over `maxFormatPayload`
    /// or one that does not decode, and for packets over `maxPacketsPayload`, a header cut short, a
    /// count of 0, a length past the end or bytes left over. Never traps, whatever the input.
    public static func parse(_ payload: Data) -> AudioMessage? {
        guard let type = payload.first else { return nil }
        switch type {
        case typeFormat:
            guard payload.count <= maxFormatPayload,
                  let f = Wire.decode(AudioFormat.self, from: Data(payload.dropFirst())) else { return nil }
            return .format(f)
        case typePackets:
            guard payload.count <= maxPacketsPayload, payload.count >= AudioPackets.headerBytes else { return nil }
            let d = Data(payload)   // indices from 0
            let epoch = Int(d.readBigEndian(UInt16.self, at: 1))
            let seq = d.readBigEndian(UInt32.self, at: 3)
            let flags = d[7]
            let count = Int(d[8])
            guard count >= 1 else { return nil }
            var packets: [Data] = []
            packets.reserveCapacity(count)
            var offset = AudioPackets.headerBytes
            for _ in 0..<count {
                guard offset + 2 <= d.count else { return nil }
                let length = Int(d.readBigEndian(UInt16.self, at: offset))
                offset += 2
                guard offset + length <= d.count else { return nil }
                packets.append(d.subdata(in: offset..<(offset + length)))
                offset += length
            }
            guard offset == d.count else { return nil }
            return .packets(AudioPackets(epoch: epoch, seq: seq, segmentStart: flags & 1 == 1, packets: packets))
        default:
            return nil
        }
    }
}
