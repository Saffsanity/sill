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
    /// The sound compressed (`AudioPacket.aacELD`, about 96 kbit/s instead of 1.5 Mbit/s); nil, plain
    /// PCM. A host that cannot encode sends PCM.
    public var audioCodec: String?

    public init(windows: [UInt32], fps: Int? = nil, wholeApp: Bool? = nil, screen: [Double]? = nil, audio: Bool? = nil,
                audioCodec: String? = nil) {
        self.windows = windows; self.fps = fps; self.wholeApp = wholeApp; self.screen = screen; self.audio = audio
        self.audioCodec = audioCodec
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
/// interleaved signed 16-bit little-endian samples. Plain PCM, 1.5 Mbit/s at 48 kHz stereo, for a
/// device that asks for no codec; compressed (`packEncoded`) for one that does.
public enum AudioPacket {
    public static func pack(sampleRate: UInt32, channels: UInt8, samples: UnsafeBufferPointer<Int16>) -> Data {
        var d = Data(capacity: 5 + samples.count * 2)
        d.appendBigEndian(sampleRate)
        d.append(channels)
        samples.withMemoryRebound(to: UInt8.self) { d.append(contentsOf: $0) }   // Apple silicon is little-endian
        return d
    }

    /// A compressed packet (one AAC-ELD packet, about 10 ms), for a device that asked for it
    /// (`SideStreamRequest.audioCodec`): the rate, the channels with the high bit set (which a reader of
    /// plain packets refuses: more than 8 channels), the decoder's magic cookie (UInt8 length, then
    /// the bytes) and the packet.
    public static let aacELD = "aac-eld"
    public static func packEncoded(sampleRate: UInt32, channels: UInt8, cookie: Data, packet: Data) -> Data {
        var d = Data(capacity: 6 + cookie.count + packet.count)
        d.appendBigEndian(sampleRate)
        d.append(channels | 0x80)
        d.append(UInt8(min(cookie.count, 255)))
        d.append(cookie.prefix(255))
        d.append(packet)
        return d
    }

    /// The rate, channels, cookie and packet of a compressed kind 33; nil when it is plain or malformed.
    public static func unpackEncoded(_ d: Data) -> (sampleRate: Double, channels: Int, cookie: Data, packet: Data)? {
        guard d.count >= 6 else { return nil }
        let rate = d.readBigEndian(UInt32.self, at: 0)
        let flagged = d[d.startIndex + 4]
        guard flagged & 0x80 != 0 else { return nil }
        let channels = Int(flagged & 0x7F)
        let cookieLength = Int(d[d.startIndex + 5])
        guard rate >= 8_000, rate <= 192_000, (1...8).contains(channels), d.count > 6 + cookieLength else { return nil }
        let cookie = d.subdata(in: (d.startIndex + 6)..<(d.startIndex + 6 + cookieLength))
        let packet = d.subdata(in: (d.startIndex + 6 + cookieLength)..<d.endIndex)
        return (Double(rate), channels, cookie, packet)
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
/// With `offer`, `files` are indices into that drag offer (kind 36): the host's own files, dragged
/// out of one of its windows and dropped on another, dropped from where they are with nothing copied.
/// With `window`, (x, y) are in that window's picture, not the streamed one's (a window shown beside it).
public struct FileDrop: Codable, Hashable, Sendable {
    public var files: [UInt32]
    public var x: Double
    public var y: Double
    public var offer: UInt32?
    public var window: UInt32?
    /// The files (of `files`) that are folders sent zipped (`FolderZip`): unpacked before the drop.
    public var folders: [UInt32]?
    public init(files: [UInt32], x: Double, y: Double, offer: UInt32? = nil, window: UInt32? = nil, folders: [UInt32]? = nil) {
        self.files = files; self.x = x; self.y = y; self.offer = offer; self.window = window; self.folders = folders
    }
}

/// A drag of files over the host's windows, followed as it goes (kind 38), so the app under the pointer
/// takes it as a drag of its own: it shows where the files would land, and the modifier keys choose
/// what a drop does (Finder: move, ⌥ copy, ⌥⌘ alias). One drag is one `id`, in phases:
/// - `start`: the drag came over a window of the host. With `offer`, the files are the host's own (a
///   drag out of one of its windows, whose button the host still holds); without, the device's own,
///   sent as kind 34 parts.
/// - `files`: those parts have all been sent (`files`, `folders` as kind 35's): the host starts its
///   drag of them under the pointer.
/// - `move`: the pointer over a window (`window`, or the streamed one), `modifiers` as InputEvent's.
/// - `drop`: let go there. `cancel`: the drag ended elsewhere, or was given up (the host lets go of its
///   own with Esc, and removes the copies it received).
/// Phases a host does not know are ignored; the device keeps sending moves only while the drag is over
/// one of the host's windows.
public struct LiveDrag: Codable, Hashable, Sendable {
    public var id: UInt32
    public var phase: String
    public var window: UInt32?
    public var x: Double
    public var y: Double
    public var modifiers: UInt64?
    public var offer: UInt32?
    public var files: [UInt32]?
    public var folders: [UInt32]?
    public init(id: UInt32, phase: String, window: UInt32? = nil, x: Double = 0, y: Double = 0, modifiers: UInt64? = nil,
                offer: UInt32? = nil, files: [UInt32]? = nil, folders: [UInt32]? = nil) {
        self.id = id; self.phase = phase; self.window = window; self.x = x; self.y = y; self.modifiers = modifiers
        self.offer = offer; self.files = files; self.folders = folders
    }
    public static let start = "start", filesSent = "files", move = "move", drop = "drop", cancel = "cancel"
}

/// An app's own Dock menu on the host (kind 39), for the Dock icon a Mac client shows for it: the
/// items the app adds (Finder's New Finder Window…, a browser's profiles), without the app's windows
/// (the client lists its own) or the Dock's own items (Options, Show All Windows, Hide, Quit, which
/// the client's Dock adds itself). The host reads it by showing the app's menu in its Dock for a
/// moment (Accessibility has it only while shown).
/// - Device → host: `app` and `token`; with `press`, that item (an `Item.id`, its `title` as shown).
/// - Host → device: `app`, the `token` answered, and `items` (empty: none, or the app is not running
///   there), or `pressed`.
public struct DockMenu: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable {
        /// Its place in the Dock's menu as read, which a press names.
        public var id: Int
        public var title: String
        public var enabled: Bool
        public var separator: Bool?
        public init(id: Int, title: String, enabled: Bool, separator: Bool? = nil) {
            self.id = id; self.title = title; self.enabled = enabled; self.separator = separator
        }
    }
    public var app: String
    public var token: UInt32
    public var press: Int?
    public var title: String?
    public var items: [Item]?
    public var pressed: Bool?
    public init(app: String, token: UInt32, press: Int? = nil, title: String? = nil, items: [Item]? = nil, pressed: Bool? = nil) {
        self.app = app; self.token = token; self.press = press; self.title = title; self.items = items; self.pressed = pressed
    }
}

/// What an app on the host is dragging under a device's held button (kind 36): files, by name and
/// size, the device may carry on dragging on its own Mac and ask for when they are dropped there.
public struct DragOffer: Codable, Hashable, Sendable {
    public struct File: Codable, Hashable, Sendable {
        public var name: String
        public var size: UInt64
        /// A folder: sent zipped (`FolderZip`) when asked for, its size then the zip's.
        public var folder: Bool?
        public init(name: String, size: UInt64, folder: Bool? = nil) { self.name = name; self.size = size; self.folder = folder }
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

#if os(macOS)
/// A folder as one file for kinds 34–37: zipped with `ditto` (Finder's own archive: resource forks,
/// extended attributes, symbolic links kept), unpacked where it lands.
public enum FolderZip {
    /// `folder` zipped into a new temporary file, its top folder kept; nil when ditto fails.
    public static func zip(_ folder: URL) -> URL? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("sill-\(UUID().uuidString).zip")
        return run(["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, out.path]) ? out : nil
    }

    /// `zip` unpacked into `directory`; the folder it held (named `name`), or nil.
    public static func unzip(_ zip: URL, into directory: URL, name: String) -> URL? {
        guard run(["-x", "-k", zip.path, directory.path]) else { return nil }
        let folder = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    private static func run(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
#endif

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
/// (ClipboardSync) alike. Two Macs that each view the other run both on each Mac, so a copy reaches the
/// other Mac twice (host to viewer, viewer to host): what came from the other Mac is marked
/// (`fromOtherMac`) and never sent back, and a copy already there is not written again. Without both,
/// the copy went back and forth for good, a new clipboard entry each time, and a late one replaced a
/// newer copy.
public enum ClipboardPasteboard {
    /// The private type on a pasteboard item Sill wrote from the other Mac's clipboard.
    public static let fromOtherMacType = NSPasteboard.PasteboardType("me.saffer.sill.clipboard.from-other-mac")

    /// Reading the permission answer itself never reads clipboard contents or brings an alert.
    public static var access: ClipboardPolicy.MacAccess {
        if #available(macOS 15.4, *) {
            return ClipboardPolicy.macAccess(raw: NSPasteboard.general.accessBehavior.rawValue)
        }
        return .allowed
    }

    /// Unprompted reads only: a received copy's duplicate check must never bring an alert.
    public static var canRead: Bool { ClipboardPolicy.hostLooks(access) }

    /// Whether the pasteboard holds what Sill wrote from the other Mac (not a copy made on this one).
    public static var fromOtherMac: Bool {
        guard ClipboardPolicy.viewerMayRead(access: access) else { return false }
        let types = NSPasteboard.general.types ?? []
        return types.contains(fromOtherMacType) || types.contains(NSPasteboard.PasteboardType(ClipboardPolicy.ownType))
    }

    /// Its text (when not too long) and its image (PNG, TIFF or JPEG, made to fit `imageLimit`).
    public static func read(imageLimit: Int) -> Clipboard {
        guard ClipboardPolicy.viewerMayRead(access: access) else { return Clipboard() }
        let board = NSPasteboard.general
        let types = (board.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }
        guard !types.contains(where: { ClipboardPolicy.markerTypes.contains($0) }),
              !types.contains(ClipboardPolicy.remoteClipboardType), !fromOtherMac else { return Clipboard() }
        guard ClipboardPolicy.viewerMayRead(access: access) else { return Clipboard() }
        var text = board.string(forType: .string)
        if let t = text, t.isEmpty || t.utf8.count > Clipboard.maxTextBytes { text = nil }
        // The first read may have brought macOS's alert. Honor its answer before reading more.
        guard ClipboardPolicy.viewerMayRead(access: access) else { return Clipboard() }
        var image: Data?
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")] where imageLimit > 0 {
            guard ClipboardPolicy.viewerMayRead(access: access) else { return Clipboard() }
            if let data = board.data(forType: type) {
                guard ClipboardPolicy.viewerMayRead(access: access) else { return Clipboard() }
                image = ClipboardImage.fit(data, limit: imageLimit)
                break
            }
        }
        return Clipboard(text: text, image: image)
    }

    /// Text and an image (PNG or JPEG, with TIFF beside it for apps that read only that), both if both,
    /// marked as the other Mac's; nothing when the pasteboard holds that already.
    public static func write(_ clip: Clipboard) {
        let board = NSPasteboard.general
        guard clip.text != nil || clip.image.flatMap(NSBitmapImageRep.init(data:)) != nil else { return }
        if canRead, holds(clip) { return }
        board.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setData(Data(), forType: fromOtherMacType)
        if let text = clip.text { item.setString(text, forType: .string) }
        if let image = clip.image {
            let isPNG = image.starts(with: [0x89, 0x50, 0x4E, 0x47])
            item.setData(image, forType: isPNG ? .png : NSPasteboard.PasteboardType("public.jpeg"))
            if let rep = NSBitmapImageRep(data: image), let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        }
        board.writeObjects([item])
    }

    /// Whether the pasteboard's text and image are `clip`'s.
    private static func holds(_ clip: Clipboard) -> Bool {
        let board = NSPasteboard.general
        guard board.string(forType: .string) == clip.text else { return false }
        let image = board.data(forType: .png) ?? board.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
        return clip.image == nil ? board.data(forType: .tiff) == nil && image == nil : image == clip.image
    }
}
#endif

/// Input over a window shown beside the streamed one: what a Mac lets a person do to a window that is
/// visible but not in front, without bringing it forward: scroll it, and hover over it. Kind 8, its
/// InputEvent with a `window` key beside the event's own (a fraction of that window's picture, as
/// kind 8's is of the streamed one; window IDs as side streams name them), sent only to a host whose
/// list says `windowInput`: a host from before ignores the key, and would take the input as the
/// streamed window's. The host takes only
/// a pointer move, a scroll and a scroll's phases this way (a click focuses the window, which makes it
/// the streamed one).
public struct WindowInput: Hashable {
    public var window: UInt32?
    public var event: InputEvent
    public init(window: UInt32?, event: InputEvent) { self.window = window; self.event = event }

    /// Whether the host takes `event` for a window not in front.
    public static func allowed(_ event: InputEvent) -> Bool {
        switch event {
        case .pointer(.move, _, _), .scroll, .scrollGesture: return true
        default: return false
        }
    }

    /// Kind 8's payload: the event alone without a window, as every device has sent it.
    public func encoded() -> Data {
        let plain = Wire.encode(event)
        guard let window, var object = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any] else { return plain }
        object["window"] = window
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? plain
    }

    /// A kind 8 payload, with or without a window.
    public static func decode(_ data: Data) -> WindowInput? {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard object["window"] != nil else { return Wire.decode(InputEvent.self, from: data).map { WindowInput(window: nil, event: $0) } }
        guard object.count == 2,
              let window = (object.removeValue(forKey: "window") as? NSNumber)?.uint32Value,
              let rest = try? JSONSerialization.data(withJSONObject: object),
              let event = Wire.decode(InputEvent.self, from: rest) else { return nil }
        return WindowInput(window: window, event: event)
    }
}

/// Windows the person at the host stopped sharing (kind 41): each went back to where it was on the
/// Mac and stopped streaming; a device closes its windows of them and may open them again. Window IDs
/// as side streams name them (a Desktop window's display tagged, DesktopWindow).
public struct TakenBack: Codable, Hashable, Sendable {
    public var windows: [UInt32]
    public init(windows: [UInt32]) { self.windows = windows }
}
