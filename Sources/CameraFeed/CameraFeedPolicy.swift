import Foundation

/// Sill Camera's rules (docs/camera-plan.md §6.4), as one reducer: Sill Camera, the Core Media I/O camera extension
/// (Sources/SillCameraExtension), pushes in what happens (Sill.app starting or stopping its feed into the sink stream,
/// what Sill.app says to show, a frame from the sink, an app choosing a format or starting and stopping the source
/// stream, a client leaving, the feed's timer) and carries out what comes back (send this frame now, send the newest
/// frame again, send the placeholder with these words, refuse this feeder). Pure: Foundation alone, no CoreMediaIO,
/// checked with swiftc (Tests/checks/camera-feed). Its own library target (`CameraFeed`), because Sill.app's sink
/// (docs/camera-plan.md §7, step 8) writes the state and reads the demand in the same encodings, and an executable
/// target cannot be imported.
///
/// - The formats: NV12 (`420v`, what VideoToolbox's decoder makes on the Mac) at 1280×720, then 1920×1080, 15 to
///   30 frames a second.
/// - The feeder: only Sill for Mac (signing identifier `me.saffer.sill.mac`, and its team's signature where the
///   extension's sandbox lets it check one by pid: docs/camera-plan.md §17, V6), one at a time, the first keeping it
///   until it stops or leaves. What it says to show and its frames count only while it feeds; when it goes, both go.
/// - Each tick of the source stream, while an app runs it: a frame from the feeder goes out as it arrives, and is sent
///   again at the app's rate while it is under a second old, so apps see a steady stream; then the placeholder, whose
///   words come from what Sill.app said ("Open Sill on this Mac." while nothing feeds). Only a device state names a
///   device; every other placeholder names nobody (another user on the Mac's screen sees "isn’t available").
/// - The demand Sill.app reads: whether an app runs Sill Camera, the size and rate it chose, and the apps that run
///   it (by signing identifier and pid; Sill.app names them).
package struct CameraFeedPolicy {
    // MARK: The constants

    package struct Format: Equatable, Hashable, Codable {
        package let width: Int
        package let height: Int
        package init(width: Int, height: Int) { self.width = width; self.height = height }
    }

    /// The formats apps see, in this order: 1280×720 first (what an app that does not choose gets), then 1920×1080.
    package static let formats = [Format(width: 1280, height: 720), Format(width: 1920, height: 1080)]
    /// NV12, video range (`420v`): what the Mac's decoder makes, so nothing converts between a device and an app.
    package static let pixelFormat: UInt32 = 0x3432_3076
    package static let fpsRange = 15...30
    package static let defaultFps = 30
    /// The newest frame stands in for this long after it came; then the placeholder.
    package static let frameLifetime: Double = 1
    /// The feed's timer, while an app runs the source stream.
    package static let tickInterval: Double = 1.0 / 60
    /// How many frames the sink's queue holds: Sill.app drops a frame rather than queue more.
    package static let sinkQueueSize = 2
    /// What Sill.app writes: at most this many bytes, a device's name at most this many characters.
    package static let stateCap = 4096
    package static let nameCap = 40
    /// The one feeder Sill Camera takes.
    package static let sillIdentifier = "me.saffer.sill.mac"
    /// The apps that may stand in a demand, and the length of each one's identifier.
    package static let appsCap = 16
    package static let appIDCap = 128

    /// The frame rate a frame duration means (an app's choice), inside `fpsRange`; anything that is not a duration
    /// means the default.
    package static func fps(frameDuration seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return defaultFps }
        let rate = (1 / seconds).rounded()     // a duration too short to divide by is infinite: capped below
        return min(max(Int(min(rate, 1000)), fpsRange.lowerBound), fpsRange.upperBound)
    }

    // MARK: What Sill.app says to show (the `state` property, written)

    /// What Sill.app says Sill Camera shows while no frame is live (CameraHostPolicy.Feed, with the Mac's switch).
    package enum Show: Equatable {
        /// The Mac's Use iPhone and iPad cameras is off.
        case off
        /// Not ready, locked, or another user on the Mac's screen: names nobody.
        case unavailable
        /// Nobody holds the camera: "Turn on Share Camera…".
        case waiting
        /// The holder's name, and whether it paused its camera.
        case device(name: String, paused: Bool)
    }

    private struct ShowJSON: Codable {
        var show: String
        var name: String?
        var paused: Bool?
    }

    /// The state as Sill.app writes it: a small JSON object, `{"show":"device","name":"iPad","paused":true}`.
    package static func encode(_ show: Show) -> String {
        let j: ShowJSON
        switch show {
        case .off: j = ShowJSON(show: "off")
        case .unavailable: j = ShowJSON(show: "unavailable")
        case .waiting: j = ShowJSON(show: "waiting")
        case .device(let name, let paused): j = ShowJSON(show: "device", name: cleanName(name), paused: paused)
        }
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return (try? e.encode(j)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"show\":\"unavailable\"}"
    }

    /// The state Sill.app wrote, or nil (not ours: too long, not JSON, an unknown word, a device without a name).
    package static func decode(_ text: String) -> Show? {
        guard text.utf8.count <= stateCap, let data = text.data(using: .utf8),
              let j = try? JSONDecoder().decode(ShowJSON.self, from: data) else { return nil }
        switch j.show {
        case "off": return .off
        case "unavailable": return .unavailable
        case "waiting": return .waiting
        case "device":
            guard let raw = j.name else { return nil }
            let name = cleanName(raw)
            return name.isEmpty ? nil : .device(name: name, paused: j.paused ?? false)
        default: return nil
        }
    }

    /// A device's name as the placeholder draws it: control characters and line breaks as spaces, runs of spaces as
    /// one, trimmed, at most `nameCap` characters (Sill.app cleans it too, SafeText; this is the extension's own
    /// guard, since it draws the name into every app's picture).
    package static func cleanName(_ raw: String) -> String {
        var out = ""
        var lastSpace = true
        for ch in raw {
            let isControl = ch.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
                    || $0.properties.generalCategory == .format
            }
            if isControl || ch.isWhitespace {
                if !lastSpace { out.append(" ") }
                lastSpace = true
            } else {
                out.append(ch)
                lastSpace = false
            }
            if out.count > nameCap + 1 { break }
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.count > nameCap ? String(trimmed.prefix(nameCap)).trimmingCharacters(in: .whitespaces) : trimmed
    }

    // MARK: What Sill Camera says back (the `demand` property, read by Sill.app)

    /// An app running Sill Camera: its signing identifier (nil when CoreMediaIO gives none) and pid.
    package struct App: Equatable, Codable {
        package var id: String?
        package var pid: Int32
        package init(id: String?, pid: Int32) {
            self.id = id.map { String($0.unicodeScalars.filter { $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }.prefix(CameraFeedPolicy.appIDCap)) }
            self.pid = pid
        }
    }

    /// Whether an app runs Sill Camera now, the size and rate it chose, and the apps that run it.
    package struct Demand: Equatable, Codable {
        package var running: Bool
        package var width: Int
        package var height: Int
        package var fps: Int
        package var apps: [App]
    }

    package static func encode(_ demand: Demand) -> String {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return (try? e.encode(demand)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// The demand Sill.app reads, or nil when it is not one Sill Camera could have written (a format it does not
    /// offer, a rate outside the range, too many apps).
    package static func decodeDemand(_ text: String) -> Demand? {
        guard text.utf8.count <= stateCap, let data = text.data(using: .utf8),
              let d = try? JSONDecoder().decode(Demand.self, from: data),
              formats.contains(Format(width: d.width, height: d.height)), fpsRange.contains(d.fps),
              d.apps.count <= appsCap else { return nil }
        var clean = d
        clean.apps = d.apps.map { App(id: $0.id, pid: $0.pid) }
        return clean
    }

    // MARK: The feeder

    package enum SinkVerdict: Equatable {
        case accept
        /// No signing identifier: not Sill.
        case unsigned
        /// Another app's signing identifier.
        case notSill
        /// Sill's identifier, but its signature is not its team's.
        case signature
        /// Another Sill already feeds it.
        case busy
    }

    /// Whether `client` may feed Sill Camera: Sill's signing identifier, its team's signature unless the sandbox
    /// would not say (nil), and nobody else feeding.
    package static func sinkVerdict(signingID: String?, signatureValid: Bool?, feeder: UUID?, client: UUID) -> SinkVerdict {
        guard let id = signingID, !id.isEmpty else { return .unsigned }
        guard id == sillIdentifier else { return .notSill }
        if signatureValid == false { return .signature }
        if let f = feeder, f != client { return .busy }
        return .accept
    }

    // MARK: The words

    /// The placeholder: "Sill Camera" over one line, at the format apps take now.
    package struct Placeholder: Equatable {
        package let title: String
        package let line: String
        package let format: Format
    }

    package enum Copy {
        package static let title = "Sill Camera"
        package static let noSill = "Open Sill on this Mac."
        package static let off = "Turn on Use iPhone and iPad cameras in Sill’s Settings on this Mac."
        package static let unavailable = "Sill Camera isn’t available right now."
        package static let waiting = "Turn on Share Camera in Sill on your iPhone or iPad."
        package static func paused(_ name: String) -> String { "\(name)’s camera is paused." }
        package static func starting(_ name: String) -> String { "Waiting for \(name)’s camera…" }
    }

    // MARK: The state

    /// The sink client feeding Sill Camera (Sill.app), by its client ID.
    package private(set) var feeder: UUID?
    /// What the feeder last said to show; nil until it says something.
    package private(set) var show: Show?
    package private(set) var formatIndex = 0
    package private(set) var fps = CameraFeedPolicy.defaultFps
    /// How many times apps started the source stream and have not stopped it: it runs while any does.
    package private(set) var starts = 0
    package private(set) var apps: [App] = []
    /// When the newest frame from the feeder came, and whether it went out yet.
    package private(set) var frameAt: Double?
    package private(set) var frameSent = true
    /// When anything last went out, and the placeholder that last went out.
    package private(set) var lastSentAt: Double?
    package private(set) var placeholderSent: Placeholder?

    package init() {}

    package var format: Format { Self.formats[formatIndex] }

    /// An app runs the source stream.
    package var running: Bool { starts > 0 }

    package var demand: Demand {
        Demand(running: running, width: format.width, height: format.height, fps: fps, apps: running ? apps : [])
    }

    /// What the placeholder says now.
    package var placeholder: Placeholder {
        let line: String
        if feeder == nil {
            line = Copy.noSill
        } else {
            switch show {
            case .none, .unavailable: line = Copy.unavailable
            case .off: line = Copy.off
            case .waiting: line = Copy.waiting
            case .device(let name, let paused): line = paused ? Copy.paused(name) : Copy.starting(name)
            }
        }
        return Placeholder(title: Copy.title, line: line, format: format)
    }

    // MARK: The events

    /// Sill.app asks to start the sink stream (CoreMediaIO's authorizedToStartStream for the sink). A new feeder
    /// starts from nothing: while nobody feeds, nothing is said and no frame is kept (`sinkStop`).
    package mutating func sinkStart(client: UUID, signingID: String?, signatureValid: Bool?) -> SinkVerdict {
        let v = Self.sinkVerdict(signingID: signingID, signatureValid: signatureValid, feeder: feeder, client: client)
        if v == .accept { feeder = client }
        return v
    }

    /// The sink stream stopped, or that client left: if it fed Sill Camera, what it said and its frames go with it.
    package mutating func sinkStop(client: UUID) {
        guard feeder == client else { return }
        feeder = nil
        show = nil
        frameAt = nil
        frameSent = true
    }

    /// A client left (its connection to Sill Camera closed): it no longer feeds or runs it.
    package mutating func clientLeft(_ client: UUID, pid: Int32) {
        sinkStop(client: client)
        apps.removeAll { $0.pid == pid }
    }

    /// The `state` property written: taken only while a feeder feeds and when it reads (nothing written while
    /// nobody feeds can name a device later). Anything but the same device's live camera retires the newest frame,
    /// so a lock, another user, a pause or another device never shows the last picture again. Returns whether it
    /// was taken.
    @discardableResult
    package mutating func stateWritten(_ text: String) -> Bool {
        guard feeder != nil, let s = Self.decode(text) else { return false }
        var keep = false
        if case .device(let name, false) = s, case .device(let before, false)? = show { keep = name == before }
        show = s
        if !keep {
            frameAt = nil
            frameSent = true
        }
        return true
    }

    /// An app chose a format (the source stream's active format index). Returns whether it is one Sill Camera
    /// offers; a new size retires the newest frame (it is of the old size).
    @discardableResult
    package mutating func formatChosen(_ index: Int) -> Bool {
        guard Self.formats.indices.contains(index) else { return false }
        if index != formatIndex {
            formatIndex = index
            frameAt = nil
            frameSent = true
        }
        return true
    }

    /// An app chose a frame duration.
    package mutating func frameDurationChosen(seconds: Double) {
        fps = Self.fps(frameDuration: seconds)
    }

    /// An app started the source stream. CoreMediaIO may say so once for each app that runs it (Apple's own camera
    /// extension template counts them), so the stream runs until as many stops came.
    package mutating func sourceStarted() {
        starts += 1
    }

    /// An app stopped it: the last stop ends the run, and with it the apps and what went out; a stop too many
    /// changes nothing.
    package mutating func sourceStopped() {
        starts = max(0, starts - 1)
        if starts == 0 { apps = []; lastSentAt = nil; placeholderSent = nil }
    }

    /// The apps that run the source stream now (CoreMediaIO's streaming clients). Returns whether they changed.
    @discardableResult
    package mutating func appsNow(_ now: [App]) -> Bool {
        let list = Array(now.prefix(Self.appsCap))
        guard list != apps else { return false }
        apps = list
        return true
    }

    package enum FrameVerdict: Equatable {
        /// Send it now.
        case send
        /// Kept as the newest, sent at the next tick or not at all (more are queued behind it, or no app runs the
        /// stream now).
        case kept
        case notFeeder
        /// Sill.app does not say a device's camera is live now (nothing said yet, off, unavailable, waiting, or
        /// paused): a frame that crossed its state on the way is never shown.
        case notLive
        case wrongSize
        case wrongFormat
    }

    /// A frame from the sink: only the feeder's, while it says a device's camera is live, of the format apps take
    /// now, in NV12. `more`: CoreMediaIO says more frames wait behind it, so only the last of them goes (latency
    /// first).
    package mutating func frame(from client: UUID, width: Int, height: Int, pixelFormat: UInt32, more: Bool,
                                at now: Double) -> FrameVerdict {
        guard client == feeder else { return .notFeeder }
        guard case .device(_, false)? = show else { return .notLive }
        guard pixelFormat == Self.pixelFormat else { return .wrongFormat }
        guard width == format.width, height == format.height else { return .wrongSize }
        frameAt = now
        guard running, !more else {
            frameSent = false
            return .kept
        }
        frameSent = true
        lastSentAt = now
        placeholderSent = nil
        return .send
    }

    package enum Send: Equatable {
        /// The newest frame (again, or for the first time if it was kept).
        case frame
        case placeholder(Placeholder)
    }

    /// The feed's timer: what goes out now, if anything. While an app runs the stream, something goes out at least
    /// once a frame duration (with half a tick of slack): the newest frame while it is under `frameLifetime` old,
    /// else the placeholder, at once when its words or size change.
    package mutating func tick(at now: Double) -> Send? {
        guard running else { return nil }
        let due = lastSentAt.map { now - $0 >= 1 / Double(fps) - Self.tickInterval / 2 } ?? true
        if feeder != nil, let at = frameAt, now - at < Self.frameLifetime {
            guard !frameSent || due else { return nil }
            frameSent = true
            lastSentAt = now
            placeholderSent = nil
            return .frame
        }
        let p = placeholder
        guard due || p != placeholderSent else { return nil }
        lastSentAt = now
        placeholderSent = p
        return .placeholder(p)
    }
}
