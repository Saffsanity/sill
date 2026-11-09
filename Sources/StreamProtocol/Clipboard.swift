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
    /// Generation 2 (`clipboard` 2, 2026-11-02): an image, PNG or JPEG (#66's shape), at most
    /// `maxImageBytes`. A host of generation 1 ignores it, and a device sends none to it; a host sends it
    /// only to a device whose subscription said `accepts` 2, never to one that subscribed with `{}`.
    public var image: Data?
    /// Device → host: true, this device's Share Clipboard went off; the host sends it nothing more
    /// until its next kind 32. Never from a host.
    public var stop: Bool?
    /// Device → host, on any kind 32: the generation this device takes, 2 for images too. Left out
    /// (generation 1's `{}`), the host sends it text alone.
    public var accepts: Int?

    public init(text: String? = nil, image: Data? = nil, stop: Bool? = nil, accepts: Int? = nil) {
        self.text = text; self.image = image; self.stop = stop; self.accepts = accepts
    }

    /// The most image either way: 8 MiB of PNG or JPEG (Noah's call, 2026-11-02); a bigger copy is
    /// re-encoded to fit (ClipboardImage.fitted). Its base64 JSON keeps to `StreamMessage.maxClipboardPayload`.
    public static let maxImageBytes = 8 << 20

    /// "public.png" or "public.jpeg" by the image's first bytes, else nil: what either side takes.
    public static func imageType(_ data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "public.png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "public.jpeg" }
        return nil
    }

    /// The most text either way: 256 KB of UTF-8 (262,144 bytes). The whole message's JSON also
    /// keeps to `ClipboardPolicy.maxPayload` (1 MiB), the host's cap on a device's message
    /// (`StreamMessage.maxClientPayload`), which is smaller than a device's on a host's (4 MiB,
    /// `maxOtherHostPayload`): JSON writes a control character as six bytes, so 256 KB of text can
    /// be more than 1 MiB as JSON, and then it is not sent.
    public static let maxTextBytes = 256 * 1024
}
