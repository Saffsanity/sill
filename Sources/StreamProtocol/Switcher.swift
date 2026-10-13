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
    /// True: this host takes the middle button (PointerAction.middleDown and .middleUp). Nil from every
    /// host before 2026-10-12, to which a device sends neither: its kind 8 would not decode there.
    public var middleButton: Bool?
    /// How many windows this host streams besides the one picked (kinds 29–31, SideStreams.swift); nil
    /// from every host before 2026-10-12, to which a device sends no kind 29.
    public var sideStreams: Int?
    /// True: this host shares its clipboard's text (kind 32) with a device that asks. Nil before 2026-10-12.
    public var clipboard: Bool?
    /// True: this host sends the sound of the apps a device shows (kind 33) when it asks. Nil before 2026-10-12.
    public var audio: Bool?
    /// True: this host takes files dropped on its windows (kinds 34 and 35). Nil before 2026-10-12.
    public var fileDrop: Bool?
    /// True: this host follows a drag of files over its windows as it goes (kind 38, LiveDrag), so the app
    /// under the pointer shows where they would land and the modifier keys choose move, copy or alias.
    /// Nil before 2026-10-12, to which a device sends no kind 38 and drops only where it lets go (kind 35).
    public var liveDrag: Bool?
    /// True: this host reads and presses its apps' own Dock menus for a device (kind 39, DockMenu). Nil
    /// before 2026-10-12, to which a device sends no kind 39.
    public var dockMenu: Bool?
    /// True: this host takes a scroll or a hover over a window shown beside the streamed one (kind 8
    /// with a `window`, WindowInput). Nil before 2026-10-12, to which a device sends none.
    public var windowInput: Bool?
    /// Each app's Dock badge on the host ("3", "•"), by bundle ID, for the apps with a window listed:
    /// a Mac client shows it on its Dock icon of that app. Nil before 2026-10-12 and from a host that
    /// reads none (no Accessibility, a test host); an app without a badge is left out.
    public var badges: [String: String]?
    /// The apps with a window listed whose Dock icon bounces on the host now (they asked for the user's
    /// attention), by bundle ID, sorted: a Mac client bounces its Dock icon of that app until it is left
    /// out again. Nil before 2026-10-13 and from a host that reads none; empty is left out too.
    public var attention: [String]?
    /// The host's own displays (never Sill's hidden ones), for a device that picks which the Desktop
    /// is (kind 40); nil from a host before 2026-10-12, whose Desktop is its main display.
    public var displays: [DisplayInfo]?
    /// The one the Desktop shows now.
    public var desktopDisplay: UInt32?

    public init(macName: String, windows: [WindowInfo], active: StreamSource, launchID: String? = nil,
                hostVersion: String? = nil, protocol: Int? = nil, gestures: Int? = nil, middleButton: Bool? = nil,
                sideStreams: Int? = nil, clipboard: Bool? = nil, audio: Bool? = nil, fileDrop: Bool? = nil,
                liveDrag: Bool? = nil, dockMenu: Bool? = nil, displays: [DisplayInfo]? = nil, desktopDisplay: UInt32? = nil,
                windowInput: Bool? = nil, badges: [String: String]? = nil, attention: [String]? = nil) {
        self.macName = macName; self.windows = windows; self.active = active; self.launchID = launchID
        self.hostVersion = hostVersion; self.protocol = `protocol`; self.gestures = gestures
        self.middleButton = middleButton; self.sideStreams = sideStreams; self.clipboard = clipboard
        self.audio = audio; self.fileDrop = fileDrop; self.liveDrag = liveDrag
        self.dockMenu = dockMenu; self.windowInput = windowInput; self.badges = badges
        self.attention = attention
        self.displays = displays; self.desktopDisplay = desktopDisplay
    }
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

/// One of the host's own displays, as a device lists it to pick the Desktop (kind 40).
public struct DisplayInfo: Codable, Hashable, Sendable {
    public var id: UInt32
    public var name: String
    public var width: Double
    public var height: Double
    public var main: Bool?
    public init(id: UInt32, name: String, width: Double, height: Double, main: Bool? = nil) {
        self.id = id; self.name = name; self.width = width; self.height = height; self.main = main
    }
}

/// Which of the host's displays the Desktop is (kind 40).
public struct PickDisplay: Codable, Hashable, Sendable {
    public var display: UInt32
    public init(display: UInt32) { self.display = display }
}

/// One of the host's displays where a window ID goes (a side stream, kind 29–31; a drop's `window`):
/// its display ID with the top bit set, which no window ID has. A Mac client shows each of the host's
/// displays as a Desktop window of its own, the focused one the Desktop (`PickDisplay`) and the others
/// side streams; only to a host that lists its `displays`.
public enum DesktopWindow {
    public static let bit: UInt32 = 0x8000_0000
    public static func id(display: UInt32) -> UInt32 { display | bit }
    /// The display a tagged ID names; nil for a window's.
    public static func display(of id: UInt32) -> UInt32? { id & bit != 0 ? id & ~bit : nil }
}
