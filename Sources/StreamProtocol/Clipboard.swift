import Foundation

/// Kind 32, both ways: the clipboard (docs/clipboard-plan.md). Generation 1 is text,
/// generation 2 also handles images; the rules are ClipboardPolicy's.
///
/// - Device → host, only to a host whose window list says `clipboard` 1 or more: any kind 32
///   subscribes the connection to the Mac's copies (an empty one, `{}`, is what a device sends at
///   connect while its Share Clipboard is on); `text` also becomes the Mac's clipboard; `stop: true`
///   ends the subscription (the device's switch went off) and wins over anything else in it.
/// - Host → device, only to a connection that subscribed: `text`, copied on the Mac, or sent by
///   another device. A subscription says what the device takes, and `{}` is text alone: a host sends
///   `image` only to a connection whose subscription carries a later field saying it takes images
///   (for example `"accepts":2`, the generation), never to one that sent `{}`, which drops it
///   (`accepts: 2` opts into images).
///
/// HostSettings.swift's rules apply: JSON; every field optional and left out when nil, so `{}` is a
/// subscription; fields added later are optional. Pull request #66 (a Mac client) uses this number
/// with `text` and `image`; `stop` is this change's, and a peer that never sends it is unaffected.
public struct Clipboard: Codable, Hashable, Sendable {
    /// The text: at most `maxTextBytes` of UTF-8, never empty when sent.
    public var text: String?
    /// Generation 2: an image, PNG or JPEG. A text-only host ignores it; a host sends it only to a device
    /// whose subscription said it takes images, never to one that subscribed with `{}`.
    public var image: Data?
    /// Device → host: true, this device's Share Clipboard went off; the host sends it nothing more
    /// until its next kind 32. Never from a host.
    public var stop: Bool?

    /// Device → host: the generation this connection takes; nil means text alone.
    public var accepts: Int?

    public init(text: String? = nil, image: Data? = nil, stop: Bool? = nil, accepts: Int? = nil) {
        self.text = text; self.image = image; self.stop = stop; self.accepts = accepts
    }

    /// The most text either way: 256 KB of UTF-8 (262,144 bytes). The whole message's JSON also
    /// keeps to `ClipboardPolicy.maxPayload` (1 MiB), the host's cap on a device's message
    /// (`StreamMessage.maxClientPayload`), which is smaller than a device's on a host's (4 MiB,
    /// `maxOtherHostPayload`): JSON writes a control character as six bytes, so 256 KB of text can
    /// be more than 1 MiB as JSON, and then it is not sent.
    public static let maxTextBytes = 256 * 1024
    /// Image bytes before base64, leaving space for text and JSON under the shared 1 MiB cap.
    public static let maxImageFromDevice = 600_000
    public static let maxImageFromHost = 600_000
    public static let messageFromDevice = ClipboardPolicy.maxPayload
    public static let messageFromHost = ClipboardPolicy.maxPayload

    /// Whole when it fits the policy and wire caps, otherwise text alone when that fits.
    public func payload(within limit: Int) -> Data? {
        guard text == nil || text!.utf8.count <= Self.maxTextBytes else { return nil }
        let cap = min(limit, ClipboardPolicy.maxPayload)
        let whole = Wire.encode(self)
        if !whole.isEmpty, whole.count <= cap { return whole }
        guard image != nil, let text, let fallback = ClipboardPolicy.payload(text: text), fallback.count <= cap else { return nil }
        return fallback
    }
}
