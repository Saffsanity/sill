import Foundation

/// What the host streams. The client decides; the host only ever streams one source.
public enum StreamSource: Codable, Hashable {
    case none
    case window(UInt32)   // CGWindowID, stable for the life of the window
    case desktop          // the Mac's main display
}

/// One on-screen Mac window, as the client sees it. WindowList order is stable: first seen first.
public struct WindowInfo: Codable, Hashable, Identifiable {
    public var id: UInt32
    public var title: String
    public var appName: String
    public var bundleID: String
    public var width: Int      // points
    public var height: Int

    public init(id: UInt32, title: String, appName: String, bundleID: String, width: Int, height: Int) {
        self.id = id; self.title = title; self.appName = appName; self.bundleID = bundleID
        self.width = width; self.height = height
    }
}

/// An installed app, for the drawer's "All apps" section.
public struct AppInfo: Codable, Hashable, Identifiable {
    public var id: String { bundleID }
    public var name: String
    public var bundleID: String

    public init(name: String, bundleID: String) { self.name = name; self.bundleID = bundleID }
}

public struct WindowList: Codable {
    public var macName: String
    public var windows: [WindowInfo]
    public var active: StreamSource
    /// Random, picked once per launch of the host and the same in every list to every device: two
    /// connections whose lists carry the same one reach the same running host. A name cannot tell
    /// that (two Macs can share one, and mDNS renames neither when they share no link), and a
    /// device moving its session from AWDL to the network must not land on another Mac. Optional:
    /// nil from a host older than 2026-09-24, and an older device ignores the key.
    public var launchID: String?
    /// The host's version: Sill.app's CFBundleShortVersionString ("0.4.0"); nil from SillHost (no
    /// bundle) and from hosts before 2026-09-25. For later devices: which Mac to update, and to what
    /// (docs/update-notice-plan.md §14).
    public var hostVersion: String?
    /// The host's SillProtocol.current; nil from hosts before 2026-09-25, which speak 1. The JSON key
    /// is "protocol".
    public var `protocol`: Int?
    /// Which trackpad gestures this host takes (kind 28, Gesture.swift): 1 is the six of
    /// `TrackpadGesture.names`, each turned into the Mac's own shortcut. Nil from every host before
    /// 2026-09-27, to which a device sends no kind 28. A later generation of gestures says 2 and
    /// goes only to a host that says so.
    public var gestures: Int?
    /// What this host takes and sends of the clipboard (kind 32, Clipboard.swift): 1 is text
    /// (`ClipboardPolicy.generation`). Nil from every host before 2026-10-14, and from one whose Share
    /// clipboard with devices is off: a device sends no kind 32 to either. A later generation
    /// (images) says 2, and a device sends images only to a host that says so. An Int, as `gestures`:
    /// pull request #66's `Bool` (never released) does not decode here and becomes an Int as it
    /// rebases.
    public var clipboard: Int?
    /// Whether this host repeats a device's key held down (KeyRepeat, #162): 1 is a key repeated between
    /// its down and its up, after the Mac's own Delay Until Repeat and at its Key Repeat Rate, each repeat
    /// the key's down again with the autorepeat flag. Nil from every host before 2026-10-29: a device then
    /// types a hardware keyboard's characters through iPadOS's text system, as it always did (iPadOS
    /// repeats Delete and Space itself; sent as keys, a Mac that repeats none would type each once), and
    /// sends them as keys only to a host that says so (the device's KeyTyping). Set after the initializer,
    /// whose parameters stay as they were: `list.keyRepeat = KeyRepeat.generation`.
    public var keyRepeat: Int?
    /// This Mac shows nothing of itself to devices (the host's LockPolicy, docs/locked-mac-plan.md): its
    /// screen is locked, or another user, the login window or nobody is on its console. True, with no
    /// windows and no `clipboard` in the list, while the host streams a placeholder (a black frame) and
    /// sends no thumbnail, icon, app list, sound, clipboard, pointer or cursor shape. Left out otherwise,
    /// and by every host before 2026-10-31, whose lists are what they were. A device covers its stream
    /// and says why (`LockedMac`). Set after the initializer, as `keyRepeat`.
    public var locked: Bool?
    /// With `locked`: true while this Mac's console is not this session's (another user's session, the
    /// login window, or none), left out while its own screen is locked. A device words its cover by it:
    /// nothing typed reaches the Mac then (`LockedMac.Why`).
    public var offConsole: Bool?

    public init(macName: String, windows: [WindowInfo], active: StreamSource, launchID: String? = nil,
                hostVersion: String? = nil, protocol: Int? = nil, gestures: Int? = nil, clipboard: Int? = nil) {
        self.macName = macName; self.windows = windows; self.active = active; self.launchID = launchID
        self.hostVersion = hostVersion; self.protocol = `protocol`; self.gestures = gestures
        self.clipboard = clipboard
    }
}

/// A locked Mac on the device (`WindowList.locked`, `offConsole`; docs/locked-mac-plan.md): why, the one
/// line the Apps drawer and the Settings panel's header show where the Mac's windows would be, and the
/// cover over the stream (`Shade`) with its words, which VoiceOver reads as they are. Pure; checked with
/// the host's rule (Tests/checks/lock-policy).
public enum LockedMac {
    /// Why a Mac's list says `locked`: its own screen is locked, or it is switched to another user (or
    /// to the login window).
    public enum Why: Equatable, Sendable { case screenLocked, otherUser }

    /// Why `list` says locked; nil for a list that does not (every host before 2026-10-31's).
    public static func why(_ list: WindowList) -> Why? {
        guard list.locked == true else { return nil }
        return list.offConsole == true ? .otherUser : .screenLocked
    }

    /// What covers the stream: the Mac locked, then, after the unlock, until its picture comes back.
    public enum Shade: Equatable, Sendable {
        case locked(Why)
        case unlocking
    }

    /// The cover after a window list that says `why` (nil: not locked): locked while it says so; after a
    /// locked one, "Unlocking…" until the next keyframe (`shade(_:frameIsKeyframe:)`); else none.
    public static func shade(_ was: Shade?, list why: Why?) -> Shade? {
        if let why { return .locked(why) }
        return was == nil ? nil : .unlocking
    }

    /// The cover after a frame: a keyframe ends "Unlocking…" (the picture is back); nothing else does.
    public static func shade(_ was: Shade?, frameIsKeyframe: Bool) -> Shade? {
        was == .unlocking && frameIsKeyframe ? nil : was
    }

    /// How long "Unlocking…" waits for the picture at most before it goes anyway.
    public static let unlockingTimeout: Double = 4

    /// The Apps drawer's and the Settings panel's line, where the Mac's windows would be.
    public static func line(mac: String, why: Why) -> String {
        switch why {
        case .screenLocked: return "\(name(mac)) is locked. Unlock it to see its windows."
        case .otherUser: return "\(name(mac)) is switched to another user. Its windows come back when you switch back on the Mac."
        }
    }

    /// The cover's title.
    public static func title(mac: String, shade: Shade) -> String {
        switch shade {
        case .locked(.screenLocked): return "\(name(mac)) is locked"
        case .locked(.otherUser): return "\(name(mac)) is switched to another user"
        case .unlocking: return "Unlocking…"
        }
    }

    /// The cover's line under its title. `paired`: this session's key is the Mac's (its settings state's
    /// `sessionPaired`; nil before it has said): only then do keys typed here reach a locked screen.
    public static func detail(shade: Shade, paired: Bool?) -> String? {
        switch shade {
        case .locked(.screenLocked):
            return paired == true ? "To unlock it from here, type its password and press Return. Its windows come back once it is unlocked."
                                  : "Its windows come back once it is unlocked."
        case .locked(.otherUser):
            return "Its windows come back when you switch back to your account on the Mac. Nothing typed here reaches it meanwhile."
        case .unlocking:
            return nil
        }
    }

    private static func name(_ mac: String) -> String { mac.isEmpty ? "The Mac" : mac }
}

public struct LaunchApp: Codable {
    public var bundleID: String
    public init(bundleID: String) { self.bundleID = bundleID }
}

/// Client → host: what the bar's long-press menu asks of a window, the three traffic lights.
public struct WindowCommand: Codable {
    public enum Action: String, Codable { case close, minimize, fullScreen }
    public var id: UInt32
    public var action: Action
    public init(id: UInt32, action: Action) { self.id = id; self.action = action }
}

/// JSON payloads. Everything here is small and infrequent; frames never go through JSON.
public enum Wire {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

/// Binary image payloads: a key, then the image bytes.
public enum ImageBlob {
    /// windowID(4, BE) + JPEG
    public static func encodeThumbnail(windowID: UInt32, jpeg: Data) -> Data {
        var d = Data(capacity: 4 + jpeg.count)
        d.appendBigEndian(windowID)
        d.append(jpeg)
        return d
    }
    public static func decodeThumbnail(_ d: Data) -> (windowID: UInt32, jpeg: Data)? {
        guard d.count > 4 else { return nil }
        return (d.readBigEndian(UInt32.self, at: 0), d.subdata(in: (d.startIndex + 4)..<d.endIndex))
    }

    /// bundleIDLength(2, BE) + bundleID UTF-8 + PNG
    public static func encodeIcon(bundleID: String, png: Data) -> Data {
        let id = Data(bundleID.utf8)
        var d = Data(capacity: 2 + id.count + png.count)
        d.appendBigEndian(UInt16(id.count))
        d.append(id)
        d.append(png)
        return d
    }
    public static func decodeIcon(_ d: Data) -> (bundleID: String, png: Data)? {
        guard d.count > 2 else { return nil }
        let len = Int(d.readBigEndian(UInt16.self, at: 0))
        guard d.count > 2 + len else { return nil }
        let idStart = d.startIndex + 2
        guard let id = String(data: d.subdata(in: idStart..<(idStart + len)), encoding: .utf8) else { return nil }
        return (id, d.subdata(in: (idStart + len)..<d.endIndex))
    }
}
