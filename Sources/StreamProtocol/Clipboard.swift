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

/// A part of a file (kind 34, pull request #66's layout, kept from #189): the file's ID (`UInt32` BE),
/// its name (`UInt16` BE length, then UTF-8), its whole size and this part's offset (`UInt64` BE each),
/// then the bytes.
public enum FileChunk {
    public static let maxBytes = 512 * 1024

    public static func pack(id: UInt32, name: String, total: UInt64, offset: UInt64, bytes: Data) -> Data {
        let n = Data(name.utf8.prefix(1024))
        var d = Data(capacity: 22 + n.count + bytes.count)
        d.appendBigEndian(id)
        d.appendBigEndian(UInt16(n.count))
        d.append(n)
        d.appendBigEndian(total)
        d.appendBigEndian(offset)
        d.append(bytes)
        return d
    }

    public static func unpack(_ d: Data) -> (id: UInt32, name: String, total: UInt64, offset: UInt64, bytes: Data)? {
        guard d.count >= 6 else { return nil }
        let id = d.readBigEndian(UInt32.self, at: 0)
        let n = Int(d.readBigEndian(UInt16.self, at: 4))
        guard d.count >= 6 + n + 16,
              let name = String(data: d.subdata(in: (d.startIndex + 6)..<(d.startIndex + 6 + n)), encoding: .utf8)
        else { return nil }
        let total = d.readBigEndian(UInt64.self, at: 6 + n)
        let offset = d.readBigEndian(UInt64.self, at: 14 + n)
        return (id, name, total, offset, d.subdata(in: (d.startIndex + 22 + n)..<d.endIndex))
    }
}
