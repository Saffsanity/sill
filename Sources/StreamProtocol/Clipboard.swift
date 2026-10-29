import Foundation

/// Kind 32, both ways: the clipboard (docs/clipboard-plan.md). Text in this generation
/// (`WindowList.clipboard` 1); the rules are ClipboardPolicy's.
///
/// - Device → host, only to a host whose window list says `clipboard` 1 or more: any kind 32
///   subscribes the connection to the Mac's copies (an empty one, `{}`, is what a device sends at
///   connect while its Share Clipboard is on); `text` also becomes the Mac's clipboard; `stop: true`
///   ends the subscription (the device's switch went off) and wins over anything else in it.
/// - Host → device, only to a connection that subscribed: `text`, copied on the Mac, or sent by
///   another device. A subscription says what the device takes, and `{}` is text alone: a host sends
///   `image` only to a connection whose subscription carries a later field saying it takes images
///   (for example `"accepts":2`, the generation), never to one that sent `{}`, which drops it
///   (found in review: #66's host sends an image to every subscriber; as it rebases it follows this).
///
/// HostSettings.swift's rules apply: JSON; every field optional and left out when nil, so `{}` is a
/// subscription; fields added later are optional. Pull request #66 (a Mac client) uses this number
/// with `text` and `image`; `stop` is this change's, and a peer that never sends it is unaffected.
public struct Clipboard: Codable, Hashable, Sendable {
    /// The text: at most `maxTextBytes` of UTF-8, never empty when sent.
    public var text: String?
    /// Reserved for a later generation (`clipboard` 2): an image, PNG or JPEG (#66's). A host of this
    /// generation ignores it, and a device sends none to it; a later host sends it only to a device
    /// whose subscription said it takes images, never to one that subscribed with `{}`.
    public var image: Data?
    /// Device → host: true, this device's Share Clipboard went off; the host sends it nothing more
    /// until its next kind 32. Never from a host.
    public var stop: Bool?

    public init(text: String? = nil, image: Data? = nil, stop: Bool? = nil) {
        self.text = text; self.image = image; self.stop = stop
    }

    /// The most text either way: 256 KB of UTF-8 (262,144 bytes). The whole message's JSON also
    /// keeps to `ClipboardPolicy.maxPayload` (1 MiB), the host's cap on a device's message
    /// (`StreamMessage.maxClientPayload`), which is smaller than a device's on a host's (4 MiB,
    /// `maxOtherHostPayload`): JSON writes a control character as six bytes, so 256 KB of text can
    /// be more than 1 MiB as JSON, and then it is not sent.
    public static let maxTextBytes = 256 * 1024
}

/// The device's microphone on the Mac (kind 45, Roadmap Item 9; mirrors pull request #94's
/// `AudioCodec` / `AudioFormat` / `AudioPackets` / `AudioMessage` wire shape).
public enum MicrophoneCodec {
    public static let aacELD = "aac-eld"
    public static let pcm16 = "pcm16"
    public static let generation = 1
    public static let hostAccepts = [aacELD, pcm16]
    public static let deviceSends = [pcm16, aacELD]

    public static func choose(offered: [String]?, accepts: [String] = hostAccepts) -> String? {
        guard let offered else { return nil }
        return offered.first { accepts.contains($0) }
    }
}

/// Device → host (kind 45, type 1): how to decode the microphone packets that follow, or `stop: true`
/// when the device turns its microphone switch off.
public struct MicrophoneFormat: Codable, Hashable, Sendable {
    public var codec: String?
    public var sampleRate: Int?
    public var channels: Int?
    public var framesPerPacket: Int?
    public var primingFrames: Int?
    public var bitrate: Int?
    public var epoch: Int?
    public var cookie: Data?
    public var stop: Bool?

    public init(codec: String? = nil, sampleRate: Int? = nil, channels: Int? = nil, framesPerPacket: Int? = nil,
                primingFrames: Int? = nil, bitrate: Int? = nil, epoch: Int? = nil, cookie: Data? = nil,
                stop: Bool? = nil) {
        self.codec = codec; self.sampleRate = sampleRate; self.channels = channels
        self.framesPerPacket = framesPerPacket; self.primingFrames = primingFrames; self.bitrate = bitrate
        self.epoch = epoch; self.cookie = cookie; self.stop = stop
    }
}

/// Device → host (kind 45, type 2): one or more microphone packets of one epoch, back to back:
/// `type 2 · epoch UInt16 · seq UInt32 · flags UInt8 · count UInt8 · count × (length UInt16 · bytes)`
public struct MicrophonePackets: Hashable, Sendable {
    public var epoch: Int
    public var seq: UInt32
    public var segmentStart: Bool
    public var packets: [Data]

    public static let maxCount = 255
    public static let maxPacketBytes = 65_535
    public static let headerBytes = 9

    public init(epoch: Int, seq: UInt32, segmentStart: Bool, packets: [Data]) {
        self.epoch = epoch; self.seq = seq; self.segmentStart = segmentStart; self.packets = packets
    }

    public func serialized() -> Data {
        let kept = packets.prefix(Self.maxCount)
        var d = Data(capacity: Self.headerBytes + kept.reduce(0) { $0 + 2 + min($1.count, Self.maxPacketBytes) })
        d.append(MicrophoneMessage.typePackets)
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

/// A kind 45 payload, either type 1 (`format`) or type 2 (`packets`).
public enum MicrophoneMessage: Hashable, Sendable {
    case format(MicrophoneFormat)
    case packets(MicrophonePackets)

    public static let typeFormat: UInt8 = 1
    public static let typePackets: UInt8 = 2
    public static let maxFormatPayload = 4096
    public static let maxPacketsPayload = 16384

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

    public static func parse(_ payload: Data) -> MicrophoneMessage? {
        guard let type = payload.first else { return nil }
        switch type {
        case typeFormat:
            guard payload.count <= maxFormatPayload,
                  let f = Wire.decode(MicrophoneFormat.self, from: Data(payload.dropFirst())) else { return nil }
            return .format(f)
        case typePackets:
            guard payload.count <= maxPacketsPayload, payload.count >= MicrophonePackets.headerBytes else { return nil }
            let d = Data(payload)
            let epoch = Int(d.readBigEndian(UInt16.self, at: 1))
            let seq = d.readBigEndian(UInt32.self, at: 3)
            let flags = d[7]
            let count = Int(d[8])
            guard count >= 1 else { return nil }
            var packets: [Data] = []
            packets.reserveCapacity(count)
            var offset = MicrophonePackets.headerBytes
            for _ in 0..<count {
                guard offset + 2 <= d.count else { return nil }
                let length = Int(d.readBigEndian(UInt16.self, at: offset))
                offset += 2
                guard offset + length <= d.count else { return nil }
                packets.append(d.subdata(in: offset..<(offset + length)))
                offset += length
            }
            guard offset == d.count else { return nil }
            return .packets(MicrophonePackets(epoch: epoch, seq: seq, segmentStart: flags & 1 == 1, packets: packets))
        default:
            return nil
        }
    }
}
