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
    /// The host's own displays (never Sill's virtual ones), for a device that cycles which display
    /// Desktop mode streams (#91); nil from an older host, whose Desktop is its main display.
    public var displays: [DisplayInfo]?
    /// Which display (`DisplayInfo.id`) the Desktop streams now.
    public var desktopDisplay: UInt32?

    public init(macName: String, windows: [WindowInfo], active: StreamSource, launchID: String? = nil,
                hostVersion: String? = nil, protocol: Int? = nil, gestures: Int? = nil, clipboard: Int? = nil,
                displays: [DisplayInfo]? = nil, desktopDisplay: UInt32? = nil) {
        self.macName = macName; self.windows = windows; self.active = active; self.launchID = launchID
        self.hostVersion = hostVersion; self.protocol = `protocol`; self.gestures = gestures
        self.clipboard = clipboard; self.displays = displays; self.desktopDisplay = desktopDisplay
    }
}

/// One of the host's own displays (#91).
public struct DisplayInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: UInt32
    public var name: String
    public var width: Double
    public var height: Double
    public var main: Bool?
    public init(id: UInt32, name: String, width: Double, height: Double, main: Bool? = nil) {
        self.id = id; self.name = name; self.width = width; self.height = height; self.main = main
    }
}

/// A `.selectSource` (kind 6) payload that picks `.desktop` on a specific display (`display`:
/// `DisplayInfo.id`). Encodes as `{"desktop":{},"display":ID}` (or `{"desktop":{}}` when `display`
/// is nil), which every older host decodes as `StreamSource.desktop` while a host with #91 also
/// reads `display`.
public struct DesktopPick: Codable, Equatable, Sendable {
    private struct Empty: Codable, Equatable {}
    private var desktop = Empty()
    public var display: UInt32?
    public init(display: UInt32? = nil) { self.display = display }
}

/// What the Desktop button shows and what a tap on it picks (#91, Noah's decision of 2026-10-19):
/// with one display (or an older host that lists none), it is the plain Desktop button as today;
/// with two or more displays, it shows which display the Desktop is on (`Desktop 1`, `Desktop 2`, …)
/// and, while the Desktop streams, a tap moves to the next display in order.
public enum DesktopDisplays {
    public struct ButtonState: Equatable, Sendable {
        public var label: String
        public var accessibilityLabel: String
        public var nextDisplay: UInt32?
        public init(label: String, accessibilityLabel: String, nextDisplay: UInt32?) {
            self.label = label; self.accessibilityLabel = accessibilityLabel; self.nextDisplay = nextDisplay
        }
    }

    /// The order the Desktop button numbers and steps through the displays: the main display
    /// first, then the rest as they sit, left to right (top to bottom where two start at the same
    /// x), the arrangement System Settings › Displays shows. A display's ID says nothing about
    /// where it is. `x` and `y` are its top-left corner in global points (`SCDisplay.frame.origin`).
    public static func comesBefore(_ a: (id: UInt32, x: Double, y: Double), _ b: (id: UInt32, x: Double, y: Double), main: UInt32) -> Bool {
        if (a.id == main) != (b.id == main) { return a.id == main }
        if a.x != b.x { return a.x < b.x }
        if a.y != b.y { return a.y < b.y }
        return a.id < b.id
    }

    public static func button(displays: [DisplayInfo], current: UInt32?, desktopActive: Bool) -> ButtonState {
        guard displays.count > 1 else {
            return ButtonState(label: "Desktop", accessibilityLabel: "Show the full Mac desktop", nextDisplay: nil)
        }
        let idx = displays.firstIndex(where: { $0.id == current })
            ?? displays.firstIndex(where: { $0.main == true }) ?? 0
        let activeDisplay = displays[idx]
        let nextIdx = desktopActive ? (idx + 1) % displays.count : idx
        let next = displays[nextIdx]
        let label = "Desktop \(idx + 1)"
        let name = activeDisplay.name.isEmpty ? label : activeDisplay.name
        let nextName = next.name.isEmpty ? "Desktop \(nextIdx + 1)" : next.name
        let ax = desktopActive
            ? "\(name) (\(idx + 1) of \(displays.count)), showing now. Tap for \(nextName)."
            : "Show \(name) (\(idx + 1) of \(displays.count))"
        return ButtonState(label: label, accessibilityLabel: ax, nextDisplay: next.id)
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
