import Foundation

// The Mac's streaming settings as a device sees and changes them (kinds 16 and 17, see
// StreamMessage.swift). Rules for every later change, because older builds of either side must
// keep decoding what newer ones send:
//
// • A device knows the host supports settings when a `.hostSettings` arrives on this connection;
//   there is no version number.
// • Fields added later must be optional: a missing required key fails the whole decode, and the
//   device would then treat the Mac as an older one.
// • Never remove, rename or retype a field (Swift property names are the JSON keys).
// • No enums in these payloads: an unknown case would fail an older reader's whole decode, while
//   JSONDecoder ignores unknown keys, so either side can add fields.
//
// A sixth setting has to be added everywhere the five are listed by hand, and the compiler points
// at few of those places. Missing the host's whitelist is silent: a device's change is dropped with
// no refusal and no log line, the answer shows the old value, and the device takes that for a
// refusal. The places:
// • here: `StreamSettings` (optional), `HostSettingsChange` with `isEmpty` and `applied(to:)`, and
//   `SettingsChoices` when the setting takes a fixed set of values;
// • the host: `HostConfig` (`validated()`, `changes(to:)`), `streamSettings`, `applying` and
//   `DeviceSettings.accepted` in DeviceSettings.swift, and `StreamCoordinator.restartNeeded` when
//   the running pipeline depends on it;
// • Sill.app: `HostSettings` (its key, registered default, load and `save(changedFrom:)`), and the
//   status menu and Settings panes when the Mac shows it;
// • the device: `SettingsField` and `HostSettingsChange.fields`, `only` and `adding`
//   (HostSettingsLedger.swift), the panel's row, and the DEBUG mock's cases (MockCatalog.swift);
// • Scripts/sillclient.py: the keys `--set` accepts, and `describe`.

/// The five streaming settings as the Mac's menu and Settings show them. Plain values, never enums:
/// an unknown case would fail an older reader's whole decode.
public struct StreamSettings: Codable, Hashable, Sendable {
    /// Frame rate limit: a ceiling; each device still gets its own panel's rate below it.
    public var maxFPS: Int
    /// Bits per second per 60 fps (a 120 fps stream gets twice as much).
    public var bitrate: Int
    /// 2 = Retina, 1 = Standard.
    public var captureScale: Double
    public var prioritizeSpeed: Bool
    public var virtualDisplay: Bool

    public init(maxFPS: Int, bitrate: Int, captureScale: Double, prioritizeSpeed: Bool, virtualDisplay: Bool) {
        self.maxFPS = maxFPS; self.bitrate = bitrate; self.captureScale = captureScale
        self.prioritizeSpeed = prioritizeSpeed; self.virtualDisplay = virtualDisplay
    }
}

/// The pipeline as it was last started: what actually runs after the devices' rates and the
/// software encoder's caps. Read-only on the device; it confirms that a change took effect.
public struct RunningStream: Codable, Hashable, Sendable {
    /// Encoded pixels.
    public var width: Int
    public var height: Int
    public var fps: Int
    /// The encoder's target (per-60 bitrate × fps / 60), whole Mbps.
    public var mbps: Int
    public var onVirtualDisplay: Bool

    public init(width: Int, height: Int, fps: Int, mbps: Int, onVirtualDisplay: Bool) {
        self.width = width; self.height = height; self.fps = fps; self.mbps = mbps
        self.onVirtualDisplay = onVirtualDisplay
    }
}

/// Host → device (`.hostSettings`): on connect (right after the window list), whenever it changes,
/// and, with `answering` set, as the reply to one device's `HostSettingsChange`.
public struct HostSettingsState: Codable, Hashable, Sendable {
    /// The target: a change still waiting for its restart is already reported, because the Mac's
    /// menu checks it too.
    public var settings: StreamSettings
    /// Sill.app saves changes; SillHost keeps them until it quits.
    public var persistent: Bool
    /// False: this host cannot run the virtual display at all (SillHost without --virtual-display).
    public var virtualDisplayAvailable: Bool
    /// Why the virtual display is unavailable or not working; nil when nothing is wrong.
    public var virtualDisplayNote: String?
    /// The hardware encoder did not answer: streams run at up to 60 fps at Standard until the Mac
    /// restarts. `settings` can then say 120 fps and Retina while `stream` says what runs.
    public var softwareEncoder: Bool
    /// Nil while nothing streams.
    public var stream: RunningStream?
    /// Only in the reply to one device: the token of the change it answers.
    public var answering: Int?

    public init(settings: StreamSettings, persistent: Bool, virtualDisplayAvailable: Bool,
                virtualDisplayNote: String? = nil, softwareEncoder: Bool, stream: RunningStream? = nil,
                answering: Int? = nil) {
        self.settings = settings; self.persistent = persistent
        self.virtualDisplayAvailable = virtualDisplayAvailable; self.virtualDisplayNote = virtualDisplayNote
        self.softwareEncoder = softwareEncoder; self.stream = stream; self.answering = answering
    }
}

/// Device → host (`.changeSettings`): only the fields one control changed, as absolute values
/// ("set the frame rate limit to 60", never "toggle"), so sending the same change twice gives the
/// same result. A nil field is left as it is. The host answers every decodable change with one
/// `HostSettingsState` to that device alone, carrying `token` as `answering`.
public struct HostSettingsChange: Codable, Hashable, Sendable {
    /// Chosen by the device: strictly increasing for its process, never reset. Nil (a test
    /// client) is still applied, and answered without `answering`.
    public var token: Int?
    public var maxFPS: Int?
    public var bitrate: Int?
    public var captureScale: Double?
    public var prioritizeSpeed: Bool?
    public var virtualDisplay: Bool?

    public init(token: Int? = nil, maxFPS: Int? = nil, bitrate: Int? = nil, captureScale: Double? = nil,
                prioritizeSpeed: Bool? = nil, virtualDisplay: Bool? = nil) {
        self.token = token; self.maxFPS = maxFPS; self.bitrate = bitrate; self.captureScale = captureScale
        self.prioritizeSpeed = prioritizeSpeed; self.virtualDisplay = virtualDisplay
    }

    /// All five setting fields nil (the token does not count).
    public var isEmpty: Bool {
        maxFPS == nil && bitrate == nil && captureScale == nil && prioritizeSpeed == nil && virtualDisplay == nil
    }

    /// `s` with this change laid over it: the device's merge (its ledger, and the DEBUG mock's
    /// answer). The host never calls it: it keeps only what `DeviceSettings.accepted` whitelists
    /// and merges with `HostConfig.applying`, so a new field goes into all three (see the list at
    /// the top of this file).
    public func applied(to s: StreamSettings) -> StreamSettings {
        var r = s
        if let v = maxFPS { r.maxFPS = v }
        if let v = bitrate { r.bitrate = v }
        if let v = captureScale { r.captureScale = v }
        if let v = prioritizeSpeed { r.prioritizeSpeed = v }
        if let v = virtualDisplay { r.virtualDisplay = v }
        return r
    }
}

/// What a device may pick: exactly the Mac menu's choices. The host checks every change against
/// these. The Mac itself can hold other values (a `defaults write`, a launch argument); a device
/// shows those read-only and can replace them with one of these, never set one itself.
public enum SettingsChoices {
    public static let maxFPS = [60, 120]
    public static let captureScale: [Double] = [2, 1]
    public static var bitrate: [Int] { QualityPreset.allCases.map(\.rawValue) }
}

/// Bitrate presets, per 60 fps (a 120 fps stream gets twice as much). Balanced is the CLI's value.
/// Here rather than in the app so the Mac and the device name the presets the same way.
public enum QualityPreset: Int, CaseIterable, Identifiable, Sendable {
    case efficient = 8_000_000, balanced = 15_000_000, high = 25_000_000, maximum = 40_000_000

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .efficient: "Efficient"
        case .balanced: "Balanced"
        case .high: "High"
        case .maximum: "Maximum"
        }
    }

    /// "Balanced — 15 Mbps".
    public var title: String { "\(name) — \(rawValue / 1_000_000) Mbps" }

    /// The label for any stored bitrate: a preset's title, or "Custom — 12 Mbps" for one set by
    /// hand (`defaults write`, a launch argument).
    public static func title(forBitrate bitrate: Int) -> String {
        QualityPreset(rawValue: bitrate)?.title ?? "Custom — \(mbps(bitrate)) Mbps"
    }

    /// "15", or "8.5" for a bitrate that is not whole megabits. The same text as `HostConfig.mbps`
    /// in the host, which this module cannot see.
    public static func mbps(_ bitsPerSecond: Int) -> String {
        bitsPerSecond % 1_000_000 == 0 ? "\(bitsPerSecond / 1_000_000)"
                                       : String(format: "%.1f", Double(bitsPerSecond) / 1_000_000)
    }
}
