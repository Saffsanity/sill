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

/// The device's camera on the Mac (kind 46, Roadmap Item 10).
public enum CameraCodec {
    public static let jpeg = "jpeg"
    public static let hevc = "hevc"
    public static let generation = 1
    public static let positionFront = "front"
    public static let positionBack = "back"
}

/// Device → host (kind 46, type 1): how to decode the camera frames that follow, or `stop: true`
/// when the device turns its camera switch off.
public struct CameraFormat: Codable, Hashable, Sendable {
    public var codec: String?
    public var width: Int?
    public var height: Int?
    public var fps: Int?
    public var position: String?
    public var epoch: Int?
    public var stop: Bool?

    public init(codec: String? = nil, width: Int? = nil, height: Int? = nil, fps: Int? = nil,
                position: String? = nil, epoch: Int? = nil, stop: Bool? = nil) {
        self.codec = codec; self.width = width; self.height = height
        self.fps = fps; self.position = position; self.epoch = epoch; self.stop = stop
    }
}

/// Device → host (kind 46, type 2): one camera frame of an epoch:
/// `type 2 · epoch UInt16 · seq UInt32 · width UInt16 · height UInt16 · flags UInt8 · data`
public struct CameraFrame: Hashable, Sendable {
    public var epoch: Int
    public var seq: UInt32
    public var width: Int
    public var height: Int
    public var keyframe: Bool
    public var data: Data

    public static let headerBytes = 12
    public static let maxFrameBytes = 512 * 1024

    public init(epoch: Int, seq: UInt32, width: Int, height: Int, keyframe: Bool, data: Data) {
        self.epoch = epoch; self.seq = seq; self.width = width; self.height = height
        self.keyframe = keyframe; self.data = data
    }

    public func serialized() -> Data {
        let kept = data.prefix(Self.maxFrameBytes)
        var d = Data(capacity: Self.headerBytes + kept.count)
        d.append(CameraMessage.typeFrame)
        d.appendBigEndian(UInt16(truncatingIfNeeded: epoch))
        d.appendBigEndian(seq)
        d.appendBigEndian(UInt16(clamping: max(0, width)))
        d.appendBigEndian(UInt16(clamping: max(0, height)))
        d.append(keyframe ? 1 : 0)
        d.append(kept)
        return d
    }
}

/// A kind 46 payload, either type 1 (`format`) or type 2 (`frame`).
public enum CameraMessage: Hashable, Sendable {
    case format(CameraFormat)
    case frame(CameraFrame)

    public static let typeFormat: UInt8 = 1
    public static let typeFrame: UInt8 = 2
    public static let maxFormatPayload = 4096
    public static let maxFramePayload = CameraFrame.headerBytes + CameraFrame.maxFrameBytes

    public func serialized() -> Data {
        switch self {
        case .format(let f):
            var d = Data([Self.typeFormat])
            d.append(Wire.encode(f))
            return d
        case .frame(let f):
            return f.serialized()
        }
    }

    public static func parse(_ payload: Data) -> CameraMessage? {
        guard let type = payload.first else { return nil }
        switch type {
        case typeFormat:
            guard payload.count <= maxFormatPayload,
                  let f = Wire.decode(CameraFormat.self, from: Data(payload.dropFirst())) else { return nil }
            return .format(f)
        case typeFrame:
            guard payload.count <= maxFramePayload, payload.count > CameraFrame.headerBytes else { return nil }
            let d = Data(payload)
            let epoch = Int(d.readBigEndian(UInt16.self, at: 1))
            let seq = d.readBigEndian(UInt32.self, at: 3)
            let width = Int(d.readBigEndian(UInt16.self, at: 7))
            let height = Int(d.readBigEndian(UInt16.self, at: 9))
            let flags = d[11]
            let frameData = d.subdata(in: CameraFrame.headerBytes..<d.count)
            guard width > 0, height > 0, !frameData.isEmpty else { return nil }
            return .frame(CameraFrame(epoch: epoch, seq: seq, width: width, height: height, keyframe: flags & 1 == 1, data: frameData))
        default:
            return nil
        }
    }
}
