import Foundation

/// More of the host's windows live at once (kinds 29–31), for the Mac client, whose windows are the
/// host's windows: the one it streams (kind 6) at full rate, and these at a lower one, each with its
/// own capture and encoder on the host. A device sends kinds 29 only to a host whose window list
/// says `sideStreams` (the most it streams this way), and reads 30 and 31 by the window ID in front.
public struct SideStreamRequest: Codable, Hashable, Sendable {
    /// The host's window IDs; the one the device streams is left out by the host if listed.
    public var windows: [UInt32]
    /// Frames a second for each (the host caps it, `SideStreamRequest.maxFPS`).
    public var fps: Int?
    /// True: every window this device shows (the picked one too) is captured with what belongs to it,
    /// its menus, popovers, sheets and the system's panels over it, and no other app's window. A host
    /// before it captures the window alone.
    public var wholeApp: Bool?
    /// The device's largest screen in points, [width, height]: the host's room for each of its
    /// windows (Sill's desk) is made at least this big, so growing a window up to full screen there
    /// never makes it again.
    public var screen: [Double]?
    /// True: send the sound of the apps these windows belong to (and the picked one's), kind 33, and
    /// silence them on the host while it does. A host whose list does not say `audio` ignores it.
    public var audio: Bool?

    public init(windows: [UInt32], fps: Int? = nil, wholeApp: Bool? = nil, screen: [Double]? = nil, audio: Bool? = nil) {
        self.windows = windows; self.fps = fps; self.wholeApp = wholeApp; self.screen = screen; self.audio = audio
    }

    public static let defaultFPS = 15
    public static let maxFPS = 30

    /// A side stream's payload (kinds 30 and 31): the window ID, then the rest.
    public static func pack(window: UInt32, _ payload: Data) -> Data {
        var d = Data(capacity: 4 + payload.count)
        d.appendBigEndian(window)
        d.append(payload)
        return d
    }

    /// The window ID and the rest of a kind 30 or 31; nil when too short.
    public static func unpack(_ d: Data) -> (window: UInt32, payload: Data)? {
        guard d.count >= 4 else { return nil }
        return (d.readBigEndian(UInt32.self, at: 0), d.subdata(in: (d.startIndex + 4)..<d.endIndex))
    }
}

/// About 10 ms of sound (kind 33): the sample rate (UInt32 BE), the channel count (UInt8), then
/// interleaved signed 16-bit little-endian samples. Plain PCM: on a home network its 1.5 Mbit/s at
/// 48 kHz stereo costs less than an encoder's delay.
public enum AudioPacket {
    public static func pack(sampleRate: UInt32, channels: UInt8, samples: UnsafeBufferPointer<Int16>) -> Data {
        var d = Data(capacity: 5 + samples.count * 2)
        d.appendBigEndian(sampleRate)
        d.append(channels)
        samples.withMemoryRebound(to: UInt8.self) { d.append(contentsOf: $0) }   // Apple silicon is little-endian
        return d
    }

    /// The rate, channels and samples of a kind 33; nil when malformed.
    public static func unpack(_ d: Data) -> (sampleRate: Double, channels: Int, samples: [Int16])? {
        guard d.count >= 5 else { return nil }
        let rate = d.readBigEndian(UInt32.self, at: 0)
        let channels = Int(d[d.startIndex + 4])
        let body = d.subdata(in: (d.startIndex + 5)..<d.endIndex)
        guard rate >= 8_000, rate <= 192_000, (1...8).contains(channels), body.count % (2 * channels) == 0 else { return nil }
        let samples = body.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        return (Double(rate), channels, samples)
    }
}

/// A part of a dropped file (kind 34): the transfer's ID (UInt32 BE), the file's name (UInt16 BE
/// length, then UTF-8), its whole size and this part's offset (UInt64 BE each), then the bytes.
/// Parts come in order, each under the host's 1 MB limit for a device's message.
public enum FileChunk {
    public static let maxBytes = 512 * 1024
    /// The most a drop sends in all.
    public static let maxTotal: UInt64 = 512 * 1024 * 1024   // what a drop may queue on the connection

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
        guard d.count >= 6 + n + 16, let name = String(data: d.subdata(in: (d.startIndex + 6)..<(d.startIndex + 6 + n)), encoding: .utf8)
        else { return nil }
        let total = d.readBigEndian(UInt64.self, at: 6 + n)
        let offset = d.readBigEndian(UInt64.self, at: 14 + n)
        return (id, name, total, offset, d.subdata(in: (d.startIndex + 22 + n)..<d.endIndex))
    }
}

/// Files the device sent (kind 34, by ID) dropped on the picture at (x, y), fractions of the
/// streamed frame as a pointer's are: the host's app under that point gets them as a drop.
public struct FileDrop: Codable, Hashable, Sendable {
    public var files: [UInt32]
    public var x: Double
    public var y: Double
    public init(files: [UInt32], x: Double, y: Double) { self.files = files; self.x = x; self.y = y }
}

/// What an app on the host is dragging under a device's held button (kind 36): files, by name and
/// size, the device may carry on dragging on its own Mac and ask for when they are dropped there.
public struct DragOffer: Codable, Hashable, Sendable {
    public struct File: Codable, Hashable, Sendable {
        public var name: String
        public var size: UInt64
        public init(name: String, size: UInt64) { self.name = name; self.size = size }
    }
    public var id: UInt32
    public var files: [File]
    public init(id: UInt32, files: [File]) { self.id = id; self.files = files }
}

/// One file of a drag offer (kind 37), sent back as kind 34 parts with `transfer` as their ID.
public struct FileRequest: Codable, Hashable, Sendable {
    public var offer: UInt32
    public var index: Int
    public var transfer: UInt32
    /// True: the file was dragged to the device's Trash; the host moves it to its own instead of sending it.
    public var trash: Bool?
    public init(offer: UInt32, index: Int, transfer: UInt32, trash: Bool? = nil) {
        self.offer = offer; self.index = index; self.transfer = transfer; self.trash = trash
    }
}

/// A clipboard's text and image, either way (kind 32). From a device, neither asks the host to send
/// its clipboard from now on, which it then does whenever it changes; a host never sends one
/// unasked. The image is PNG or JPEG (`ClipboardImage.fit`); older readers skip the key.
public struct Clipboard: Codable, Hashable, Sendable {
    public var text: String?
    public var image: Data?
    public init(text: String? = nil, image: Data? = nil) { self.text = text; self.image = image }
    /// Under the host's 1 MB limit for a device's message, with room for the JSON.
    public static let maxBytes = 900_000
    /// An image's bytes, base64 in the JSON (a third more): from a device under its 1 MB message,
    /// from the host under a device's 4 MB.
    public static let maxImageFromDevice = 600_000
    public static let maxImageFromHost = 2_600_000
    /// The whole message's limits: a host closes a device's message over 1 MB, a device a host's
    /// over 4 MB.
    public static let messageFromDevice = 1_000_000
    public static let messageFromHost = 4_000_000

    /// The JSON for one message under `limit`: whole, else without the image, else nothing.
    public func payload(within limit: Int) -> Data? {
        if let whole = try? JSONEncoder().encode(self), whole.count <= limit { return whole }
        guard image != nil, let text = try? JSONEncoder().encode(Clipboard(text: self.text)), text.count <= limit,
              self.text != nil else { return nil }
        return text
    }
}

#if canImport(ImageIO)
import ImageIO
import CoreGraphics

/// A clipboard image made to fit a message: as it is when small enough, else JPEG at 0.85, halved
/// in size until it fits (at most four times); nil when it never does or is not an image.
public enum ClipboardImage {
    public static func fit(_ data: Data, limit: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let type = CGImageSourceGetType(source) as String?
        if data.count <= limit, type == "public.png" || type == "public.jpeg" { return data }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var width = image.width, height = image.height
        for _ in 0..<5 {
            guard let scaled = scale(image, width: width, height: height) else { return nil }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            if out.length <= limit { return out as Data }
            width /= 2; height /= 2
            guard width >= 16, height >= 16 else { return nil }
        }
        return nil
    }

    private static func scale(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        if width == image.width && height == image.height { return image }
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
#endif

#if canImport(AppKit)
import AppKit

/// This Mac's general pasteboard as a `Clipboard`, for the host (HostClipboard) and the Mac client
/// (ClipboardSync) alike.
public enum ClipboardPasteboard {
    /// Its text (when not too long) and its image (PNG, TIFF or JPEG, made to fit `imageLimit`).
    public static func read(imageLimit: Int) -> Clipboard {
        let board = NSPasteboard.general
        var text = board.string(forType: .string)
        if let t = text, t.isEmpty || t.utf8.count > Clipboard.maxBytes { text = nil }
        var image: Data?
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")] {
            if let data = board.data(forType: type) { image = ClipboardImage.fit(data, limit: imageLimit); break }
        }
        return Clipboard(text: text, image: image)
    }

    /// Text and an image (PNG or JPEG, with TIFF beside it for apps that read only that), both if both.
    public static func write(_ clip: Clipboard) {
        let board = NSPasteboard.general
        board.clearContents()
        let item = NSPasteboardItem()
        if let text = clip.text { item.setString(text, forType: .string) }
        if let image = clip.image {
            let isPNG = image.starts(with: [0x89, 0x50, 0x4E, 0x47])
            item.setData(image, forType: isPNG ? .png : NSPasteboard.PasteboardType("public.jpeg"))
            if let rep = NSBitmapImageRep(data: image), let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        }
        board.writeObjects([item])
    }
}
#endif
