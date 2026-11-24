import Foundation

/// Sill for Mac's side of Sill Camera's feed (docs/camera-plan.md §7, step 8), beside the extension's own rules
/// (CameraFeedPolicy) because both speak the same encodings: what Sill.app's CameraSink writes into Sill Camera's `state`
/// property for what the receiver says Sill Camera shows, which app uses Sill Camera by the `demand` the extension
/// publishes, and the sink's two frames, the newest winning. Pure: Foundation and CameraFeedPolicy, checked with swiftc
/// (Tests/checks/camera-app). CameraSink carries it out with CoreMediaIO's C API.
///
/// - The state: what the receiver says (CameraHostPolicy.Feed) as CameraFeedPolicy's JSON, written before any frame
///   (Sill Camera counts a frame only while the state names a live device), and again each time it changes. The Mac's
///   switch never reaches here: with it off Sill does not feed Sill Camera at all, so the extension shows its own words
///   for no feeder ("Open Sill on this Mac, and turn on Use iPhone and iPad cameras in its Settings.").
/// - The app: Sill Camera's demand lists the apps running its source stream by signing identifier and pid; Sill names
///   them (the running app's name, else the identifier's last part), cleaned as the extension cleans a device's name,
///   one ("FaceTime"), two ("FaceTime and Zoom") or more ("FaceTime and 2 more"), at most 40 characters.
/// - The frames: Sill Camera's sink queue holds two (`CameraFeedPolicy.sinkQueueSize`). A frame goes in while there is
///   room; otherwise it waits as the one pending, in place of any older one (the newest wins: latency beats quality),
///   and goes in when the extension takes one, unless it is a second old by then (Sill Camera would not show it).
package enum CameraSinkPolicy {
    // MARK: The state

    /// What the receiver says Sill Camera shows while no frame is live, as it reaches the sink: nothing of anyone
    /// (the switch is on but Sill Camera is not usable: not ready, the Mac locked, another user on its screen),
    /// "Turn on Share Camera…" (nobody holds the camera), or the holder's name and its pause.
    package enum Feed: Equatable {
        case unavailable
        case waiting
        case device(name: String, pause: String?)
    }

    /// CameraFeedPolicy's state for `feed`: a holder that pauses is `paused`; anything else as it is.
    package static func show(_ feed: Feed) -> CameraFeedPolicy.Show {
        switch feed {
        case .unavailable: return .unavailable
        case .waiting: return .waiting
        case .device(let name, let pause): return .device(name: name, paused: pause != nil)
        }
    }

    /// The text the sink writes into Sill Camera's `state` property for `feed`.
    package static func state(_ feed: Feed) -> String { CameraFeedPolicy.encode(show(feed)) }

    // MARK: The app

    /// An app's use of Sill Camera as the receiver takes it: who (nil when no app could be named) and the format it
    /// chose, one Sill Camera offers.
    package struct Use: Equatable {
        package var name: String?
        package var width: Int
        package var height: Int
        package var fps: Int
        package init(name: String?, width: Int, height: Int, fps: Int) {
            self.name = name; self.width = width; self.height = height; self.fps = fps
        }
    }

    /// The use the demand's text says, nil while no app runs Sill Camera or when the text is not one Sill Camera could
    /// have written (CameraFeedPolicy.decodeDemand). `name` gives a running app's name by its pid (nil when none runs).
    package static func use(_ demandText: String?, name: (Int32) -> String?) -> Use? {
        guard let text = demandText, let d = CameraFeedPolicy.decodeDemand(text), d.running else { return nil }
        return Use(name: appNames(d.apps, name: name), width: d.width, height: d.height, fps: d.fps)
    }

    /// The apps' names in the demand's order, each once: "FaceTime", "FaceTime and Zoom", "FaceTime and 2 more", at most
    /// `CameraFeedPolicy.nameCap` characters; nil when none could be named.
    package static func appNames(_ apps: [CameraFeedPolicy.App], name: (Int32) -> String?) -> String? {
        var names: [String] = []
        for app in apps {
            let raw = name(app.pid) ?? app.id.map(lastPart) ?? ""
            let clean = CameraFeedPolicy.cleanName(raw)
            if !clean.isEmpty, !names.contains(clean) { names.append(clean) }
        }
        guard let first = names.first else { return nil }
        let joined: String
        switch names.count {
        case 1: joined = first
        case 2: joined = "\(first) and \(names[1])"
        default: joined = "\(first) and \(names.count - 1) more"
        }
        return joined.count > CameraFeedPolicy.nameCap ? CameraFeedPolicy.cleanName(String(joined.prefix(CameraFeedPolicy.nameCap))) : joined
    }

    /// "com.apple.FaceTime" → "FaceTime": an identifier's last part, for an app that is not running any more.
    package static func lastPart(_ identifier: String) -> String {
        identifier.split(separator: ".").last.map(String.init) ?? identifier
    }

    // MARK: The frames

    /// The sink's frames: Sill Camera's queue, and the one frame waiting for room in it.
    package struct Slots: Equatable {
        /// When the frame waiting for room came; nil when none waits.
        package private(set) var pendingSince: Double?

        package init() {}

        package enum Arrival: Equatable {
            /// Into Sill Camera's queue now.
            case enqueue
            /// Kept as the one pending: the queue is full.
            case hold
            /// Kept as the one pending, in place of the older one, which is dropped.
            case replace
        }

        /// A decoded frame arrives while Sill Camera's queue holds `count` of its `capacity`.
        package mutating func arrive(count: Int, capacity: Int, at now: Double) -> Arrival {
            guard count >= max(1, capacity) else {
                // Room: an older pending frame would be older than this one, so it goes (never two in a row out of order).
                pendingSince = nil
                return .enqueue
            }
            let had = pendingSince != nil
            pendingSince = now
            return had ? .replace : .hold
        }

        /// Sill Camera took a frame from its queue: whether the pending one goes in now (it was waiting, there is room,
        /// and it is under `CameraFeedPolicy.frameLifetime` old). Either way nothing waits after this.
        package mutating func freed(count: Int, capacity: Int, at now: Double) -> Bool {
            guard let since = pendingSince else { return false }
            guard count < max(1, capacity) else { return false }
            pendingSince = nil
            return now - since < CameraFeedPolicy.frameLifetime
        }

        /// The feed stopped, or its format changed: nothing waits any more.
        package mutating func clear() { pendingSince = nil }
    }
}
