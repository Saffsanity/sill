import Foundation
import StreamProtocol

/// The Mac's rules for the devices' cameras (docs/camera-plan.md §6.3), as one reducer: CameraReceiver
/// pushes in what happens (a session joins or leaves, a kind 46 arrives, the Mac's switch, Sill Camera's
/// readiness, the lock, an app opening Sill Camera, time) and carries out what comes back (kind 16's camera
/// per connection, type 3 demands, the decoder's epoch, what Sill Camera shows, lines and counts). Pure:
/// Foundation and StreamProtocol's types, checked with swiftc (Tests/checks/camera-host).
///
/// - Who may: a session counts only while the Mac's Use iPhone and iPad cameras is on, Sill Camera is
///   ready, this Mac is unlocked with this user on its console (refused at a locked screen and off console:
///   nothing a device sends acts on a locked Mac), and its key is on the trust list now (Require pairing
///   off lets an unpaired device in, never its camera). Anything else is refused, counted
///   (`cam.refused.<why>`), said once a minute, and kind 16 says why.
/// - One device is Sill Camera's at a time (`holder`), by its paired key. A `claim` (Share Camera just
///   turned on) takes it from anyone; an offer without one takes it only while nobody holds it. The
///   holder's stop, its removal, or `grace` seconds without its offer standing (its session gone with no
///   other of its sessions offering again: a move or a quick reconnect keeps it; the camera unavailable,
///   then available again with no word from it) free it; the most recent standing offer then takes it (the
///   device whose person turned Share Camera on last). The others hear `another`, with the holder's name.
/// - The holder's offering session is wanted (kind 16 `inUse`) exactly while it may, an app uses Sill
///   Camera and its offer stands; it is sent the app's size and rate (`demand`: at most 1280×720 and
///   1.2 Mbit/s away), and a keyframe when it becomes wanted, the app or its size changes, or a frame of it
///   did not decode (at most one a second).
/// - A frame counts only from that session, of the epoch its last format announced, within the rates
///   (type 1 at most 10 a second, type 2 at most 60, per session).
struct CameraHostPolicy {
    // MARK: The constants

    /// How long a device's offer outlives its session, or the camera's return, without a word from it.
    static let grace: Double = 10
    /// Type 1 and type 2 a second, per session.
    static let maxFormatsPerSecond = 10
    static let maxFramesPerSecond = 60
    /// A keyframe asked of one device at most this often.
    static let keyframeSpacing: Double = 1
    /// A refusal's line, per session and reason, at most this often.
    static let refusalLineSpacing: Double = 60
    /// Away from home (a remote session): at most 1280×720 and 1.2 Mbit/s.
    static let awayMaxWidth = 1280, awayMaxHeight = 720
    static let awayMaxBitrate = 1_200_000
    /// At home: 2.5 Mbit/s for 1280×720 at 30 fps, 4 for 1920×1080, by the picture's area and rate.
    static func homeBitrate(width: Int, height: Int, fps: Int) -> Int {
        let pixels = Double(width * height) * Double(max(1, fps)) / 30
        let rate = pixels <= 1280 * 720 ? 2_500_000 * pixels / Double(1280 * 720) : 2_500_000 + 1_500_000 * (pixels - 1280 * 720) / Double(1920 * 1080 - 1280 * 720)
        return min(4_000_000, max(300_000, Int(rate.rounded())))
    }

    // MARK: The inputs and what comes out

    /// An app's use of Sill Camera: its name (cleaned; nil when Sill Camera cannot tell) and the format
    /// it chose.
    struct AppUse: Equatable {
        var name: String?
        var width: Int
        var height: Int
        var fps: Int
    }

    /// What Sill Camera shows: nothing of anyone (`unavailable`: the switch off, Sill Camera not ready, the
    /// Mac locked or another user on its screen), "Turn on Share Camera…" (`waiting`: nobody holds it), or
    /// the holder's picture, its name, and its pause while it pauses.
    enum Feed: Equatable {
        case unavailable
        case waiting
        case device(name: String, pause: String?)
    }

    /// Why a session's camera is refused: each a `cam.refused.<raw value>` count and, for the session's own
    /// state, the word kind 16 says.
    enum Refusal: String, CaseIterable, Equatable {
        case off, notReady, locked, unpaired, unknown
    }

    enum Event: Equatable {
        /// A session joined: its key (the paired key's fingerprint, base64url; nil at a plain door), whether
        /// that key is on the trust list now, its cleaned name, whether it is away, and whether its hello said
        /// it reads type 3 (`Hello.camera`).
        case joined(Int, key: String?, paired: Bool, name: String, away: Bool, reads: Bool)
        /// The trust list changed for a session's key (it paired, or was removed: then `removed` too).
        case paired(Int, Bool)
        /// The device of that key was removed from the trust list (cut off): its offer and the camera go at
        /// once, without the grace.
        case removed(key: String)
        case left(Int)
        /// A type 1 (parsed and valid, `CameraFormat.isValid`).
        case format(Int, CameraFormat)
        /// A frame of the session's own epoch failed to decode.
        case decodeFailed(Int)
        case switchChanged(Bool)
        case readyChanged(Bool)
        /// This user on the console with its screen unlocked (LockPolicy's `.unlocked`), or not.
        case unlockedChanged(Bool)
        case appChanged(AppUse?)
        /// Time passes (the grace).
        case tick
    }

    enum Effect: Equatable {
        /// Kind 16's camera for that session changed (nil: none, the list says no `camera`).
        case state(Int, CameraState?)
        /// A type 3 to that session.
        case demand(Int, CameraDemand)
        /// The decoder's epoch: the holder's offering session's current format, or nil (no decoding).
        case decoder(session: Int, CameraFormat)
        case noDecoder
        case feed(Feed)
        case line(String)
        /// A Stats key to bump.
        case count(String)
    }

    // MARK: The state

    struct Session: Equatable {
        var key: String?
        var paired: Bool
        var name: String
        var away: Bool
        var reads: Bool
        /// Its last valid epoch's format, of an offer that stands.
        var epoch: CameraFormat?
        var state: CameraState?
        var demand: CameraDemand?
        var wasWanted = false
        var secondStart: Double = -1
        var formatsThisSecond = 0
        var framesThisSecond = 0
        var refusalLineAt: [Refusal: Double] = [:]
    }

    /// A device's offer, by its key.
    struct Offer: Equatable {
        /// The session that last said it (its type 1); nil once that session left.
        var session: Int?
        /// The device's name as its session last gave it, for the lines and `another` while it is away.
        var name: String
        var position: String
        /// When the offer began or was last claimed: the order successors take the camera in.
        var since: Double
        /// When it was last said (any type 1).
        var said: Double
        /// When its session left, for the grace.
        var leftAt: Double?
        var pause: String?
    }

    private(set) var switchOn = false
    private(set) var ready = false
    private(set) var unlocked = false
    private(set) var app: AppUse?
    private(set) var sessions: [Int: Session] = [:]
    private(set) var offers: [String: Offer] = [:]
    private(set) var holder: String?
    /// When the camera last became available (the switch, readiness and the lock all allowing it): an offer
    /// must be said again after it, within the grace.
    private(set) var availableSince: Double = 0
    private(set) var feed: Feed = .unavailable
    private(set) var token = 0
    private var decoding: (session: Int, format: CameraFormat)?
    private var keyframeAskedAt: [String: Double] = [:]
    private var lockedLineAt: Double = -.infinity

    init() {}

    // MARK: Readings

    /// The camera may be used at all: the switch on, Sill Camera ready, this Mac unlocked.
    var available: Bool { switchOn && ready && unlocked }

    /// Why session `id`'s camera is refused now, nil when it may be used.
    func refusal(_ id: Int) -> Refusal? {
        guard let s = sessions[id] else { return .unknown }
        if !switchOn { return .off }
        if !ready { return .notReady }
        if !unlocked { return .locked }
        if !s.paired || s.key == nil { return .unpaired }
        return nil
    }

    /// The offer stands: said by a session that is still here, since the camera last became available, or
    /// within the grace of either.
    func stands(_ o: Offer, at now: Double) -> Bool {
        if let left = o.leftAt { return now - left < Self.grace }
        return o.said >= availableSince || now - availableSince < Self.grace
    }

    /// Session `id` sends frames now: it may, it is the holder's offering session, an app uses Sill Camera.
    func wanted(_ id: Int) -> Bool {
        guard refusal(id) == nil, app != nil, let key = sessions[id]?.key, key == holder,
              let o = offers[key], o.session == id, o.leftAt == nil else { return false }
        return true
    }

    /// Kind 16's camera for session `id`: nil while the camera is not listed (locked, or no such session).
    func state(of id: Int) -> CameraState? {
        guard let s = sessions[id], unlocked else { return nil }
        if let r = refusal(id) {
            switch r {
            case .off: return CameraState(state: CameraState.off)
            case .notReady: return CameraState(state: CameraState.notReady)
            case .unpaired: return CameraState(state: CameraState.unpaired)
            case .locked, .unknown: return nil
            }
        }
        if wanted(id) { return CameraState(state: CameraState.inUse, app: app?.name) }
        if let h = holder, h != s.key { return CameraState(state: CameraState.another, holder: holderName) }
        return CameraState(state: CameraState.idle)
    }

    /// The holder's name, as its offer last gave it.
    var holderName: String? { holder.map { name(ofKey: $0) } }

    /// What a demand to session `id` asks for, without its keyframe and token: the app's size and rate
    /// (away, fitted into 1280×720 keeping its shape, sides even), and the bitrate ceiling.
    func demandShape(for id: Int) -> CameraDemand? {
        guard let a = app, let s = sessions[id] else { return nil }
        var w = a.width, h = a.height
        if s.away, w > Self.awayMaxWidth || h > Self.awayMaxHeight {
            let k = min(Double(Self.awayMaxWidth) / Double(w), Double(Self.awayMaxHeight) / Double(h))
            w = max(16, Int((Double(w) * k).rounded(.down)) & ~1)
            h = max(16, Int((Double(h) * k).rounded(.down)) & ~1)
        }
        let fps = min(max(a.fps, CameraCodec.rates.lowerBound), CameraCodec.rates.upperBound)
        let ceiling = s.away ? min(Self.awayMaxBitrate, Self.homeBitrate(width: w, height: h, fps: fps)) : Self.homeBitrate(width: w, height: h, fps: fps)
        return CameraDemand(width: w, height: h, fps: fps, maxBitrate: ceiling)
    }

    // MARK: The reducer

    mutating func handle(_ event: Event, at now: Double) -> [Effect] {
        var out: [Effect] = []
        let wasAvailable = available
        switch event {
        case .joined(let id, let key, let paired, let name, let away, let reads):
            sessions[id] = Session(key: key, paired: paired, name: name, away: away, reads: reads)
        case .paired(let id, let paired):
            sessions[id]?.paired = paired
            if !paired, let key = sessions[id]?.key, offers[key]?.session == id {
                offers[key]?.session = nil
                offers[key]?.leftAt = now
            }
        case .removed(let key):
            for id in sessions.keys where sessions[id]?.key == key { sessions[id]?.paired = false; sessions[id]?.epoch = nil }
            if let o = offers.removeValue(forKey: key), holder == key {
                out.append(.line("Camera: \(o.name) was removed; Sill Camera is free."))
                holder = nil
            }
        case .left(let id):
            if let key = sessions[id]?.key, offers[key]?.session == id {
                offers[key]?.session = nil
                offers[key]?.leftAt = now
            }
            sessions[id] = nil
        case .format(let id, let f):
            format(id, f, at: now, into: &out)
        case .decodeFailed(let id):
            if let key = sessions[id]?.key, wanted(id), now - (keyframeAskedAt[key] ?? -.infinity) >= Self.keyframeSpacing {
                keyframeAskedAt[key] = now
                sendDemand(id, keyframe: true, at: now, into: &out)
                out.append(.count("cam.keyframeAsked"))
            }
        case .switchChanged(let on):
            if on != switchOn { out.append(.line("Camera: Use iPhone and iPad cameras \(on ? "on" : "off").")) }
            switchOn = on
        case .readyChanged(let r):
            ready = r
        case .unlockedChanged(let u):
            unlocked = u
        case .appChanged(let a):
            if a != app {
                if let a { out.append(.line("Camera: \(a.name ?? "An app") uses Sill Camera at \(a.width)×\(a.height), \(a.fps) fps.")) }
                else if app != nil { out.append(.line("Camera: no app uses Sill Camera now.")) }
            }
            app = a
        case .tick:
            break
        }
        if available && !wasAvailable { availableSince = now }
        expire(at: now, into: &out)
        settle(at: now, into: &out)
        return out
    }

    /// A frame of `epoch` from session `id`: taken, or dropped and counted.
    mutating func takesFrame(_ id: Int, epoch: Int, at now: Double) -> (take: Bool, effects: [Effect]) {
        var out: [Effect] = []
        if let r = refusal(id) {
            refused(id, r, at: now, into: &out)
            return (false, out)
        }
        guard countWithinRate(id, frames: true, at: now) else { return (false, [.count("cam.dropped.rate")]) }
        guard wanted(id) else { return (false, [.count("cam.dropped.notWanted")]) }
        guard sessions[id]?.epoch?.epoch == epoch else { return (false, [.count("cam.dropped.epoch")]) }
        return (true, [])
    }

    // MARK: Inside

    private func name(ofKey key: String) -> String {
        if let o = offers[key] { return o.name }
        return sessions.values.first { $0.key == key }?.name ?? "A device"
    }

    private mutating func countWithinRate(_ id: Int, frames: Bool, at now: Double) -> Bool {
        guard var s = sessions[id] else { return false }
        if now - s.secondStart >= 1 || now < s.secondStart { s.secondStart = now; s.formatsThisSecond = 0; s.framesThisSecond = 0 }
        let ok: Bool
        if frames { s.framesThisSecond += 1; ok = s.framesThisSecond <= Self.maxFramesPerSecond }
        else { s.formatsThisSecond += 1; ok = s.formatsThisSecond <= Self.maxFormatsPerSecond }
        sessions[id] = s
        return ok
    }

    private mutating func refused(_ id: Int, _ r: Refusal, at now: Double, into out: inout [Effect]) {
        out.append(.count("cam.refused.\(r.rawValue)"))
        if r == .locked {
            if now - lockedLineAt >= Self.refusalLineSpacing {
                lockedLineAt = now
                out.append(.line("Camera: dropped while this Mac is locked or another user is on its screen."))
            }
            return
        }
        guard var s = sessions[id] else { return }
        if now - (s.refusalLineAt[r] ?? -.infinity) >= Self.refusalLineSpacing {
            s.refusalLineAt[r] = now
            sessions[id] = s
            let why: String
            switch r {
            case .off: why = "Use iPhone and iPad cameras is off"
            case .notReady: why = "Sill Camera isn’t ready"
            case .unpaired: why = "not paired"
            case .locked, .unknown: why = "not known"
            }
            out.append(.line("Camera: refused from \(s.name): \(why)."))
        }
    }

    private mutating func format(_ id: Int, _ f: CameraFormat, at now: Double, into out: inout [Effect]) {
        if let r = refusal(id) { refused(id, r, at: now, into: &out); return }
        guard countWithinRate(id, frames: false, at: now) else { out.append(.count("cam.dropped.rate")); return }
        guard let s = sessions[id], let key = s.key else { return }
        if f.stop == true {
            sessions[id]?.epoch = nil
            if offers.removeValue(forKey: key) != nil {
                out.append(.line("Camera: \(s.name) stopped sharing its camera."))
                if holder == key { holder = nil }
            }
            return
        }
        let position = CameraCodec.position(f.position)
        if var o = offers[key] {
            if o.session != id || o.leftAt != nil { o.session = id; o.leftAt = nil }
            o.name = s.name
            o.said = now
            o.position = position
            if f.claim == true { o.since = now }
            if f.knownPause != o.pause, let p = f.knownPause, holder == key {
                out.append(.line("Camera: \(s.name) paused its camera (\(p))."))
            }
            o.pause = f.knownPause
            offers[key] = o
        } else {
            offers[key] = Offer(session: id, name: s.name, position: position, since: now, said: now, leftAt: nil, pause: f.knownPause)
            out.append(.line("Camera: \(s.name) offers its \(position) camera."))
        }
        if f.claim == true, holder != key {
            if let old = holder { out.append(.line("Camera: \(s.name) took Sill Camera from \(name(ofKey: old)).")) }
            holder = key
        } else if holder == nil {
            holder = key
        }
        if f.isEpoch { sessions[id]?.epoch = f }
    }

    /// Offers whose grace ran out go; a holder without one is freed.
    private mutating func expire(at now: Double, into out: inout [Effect]) {
        for (key, o) in offers where !stands(o, at: now) {
            offers[key] = nil
            if holder == key {
                holder = nil
                out.append(.line("Camera: \(o.name) is gone; Sill Camera is free."))
            }
        }
        if let h = holder, offers[h] == nil { holder = nil }
    }

    /// The holder, every session's state and demand, the decoder and the feed, made to agree with the
    /// rules, each said only when it changes.
    private mutating func settle(at now: Double, into out: inout [Effect]) {
        // A free camera goes to the most recent standing offer (the device whose person turned Share Camera
        // on last), said by a session still here.
        if holder == nil, available {
            let next = offers.filter { $0.value.session != nil && $0.value.leftAt == nil && stands($0.value, at: now) }
                .max { ($0.value.since, $0.key) < ($1.value.since, $1.key) }
            if let next {
                holder = next.key
                out.append(.line("Camera: \(name(ofKey: next.key)) is Sill Camera now."))
            }
        }
        for id in sessions.keys.sorted() {
            let st = state(of: id)
            if sessions[id]?.state != st {
                sessions[id]?.state = st
                out.append(.state(id, st))
            }
            let w = wanted(id)
            if w { sendDemand(id, keyframe: !(sessions[id]?.wasWanted ?? false), at: now, into: &out) }
            else {
                // No longer wanted: its next frames come of a new epoch, announced again.
                sessions[id]?.demand = nil
                if sessions[id]?.wasWanted == true { sessions[id]?.epoch = nil }
            }
            sessions[id]?.wasWanted = w
        }
        // The decoder follows the holder's offering session's epoch while it is wanted.
        let current: (session: Int, format: CameraFormat)? = {
            guard let h = holder, let id = offers[h]?.session, wanted(id), let f = sessions[id]?.epoch else { return nil }
            return (id, f)
        }()
        if current?.session != decoding?.session || current?.format != decoding?.format {
            if let c = current { out.append(.decoder(session: c.session, c.format)) } else if decoding != nil { out.append(.noDecoder) }
            decoding = current
        }
        let f: Feed = !available ? .unavailable : holder.map { .device(name: name(ofKey: $0), pause: offers[$0]?.pause) } ?? .waiting
        if f != feed { feed = f; out.append(.feed(f)) }
    }

    /// A type 3 to session `id` when its shape changed or a keyframe is asked.
    private mutating func sendDemand(_ id: Int, keyframe: Bool, at now: Double, into out: inout [Effect]) {
        guard let s = sessions[id], var d = demandShape(for: id) else { return }
        guard keyframe || s.demand != d else { return }
        sessions[id]?.demand = d
        guard s.reads else { return }
        token += 1
        d.keyframe = keyframe ? true : nil
        d.token = token
        if keyframe, let key = s.key { keyframeAskedAt[key] = now }
        out.append(.demand(id, d))
        if s.demand.map({ $0.width != d.width || $0.height != d.height || $0.fps != d.fps }) ?? true {
            out.append(.line("Camera: asked \(s.name) for \(d.width ?? 0)×\(d.height ?? 0) at \(d.fps ?? 0) fps, at most \(String(format: "%.1f", Double(d.maxBitrate ?? 0) / 1_000_000)) Mbps."))
        }
    }
}
