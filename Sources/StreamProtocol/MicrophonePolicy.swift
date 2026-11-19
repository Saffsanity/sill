import Foundation

/// The device's microphone as Sill Microphone on the Mac (kind 48, docs/microphone-plan.md §3.3, with the
/// 2026-11-18 overview's rules over the plan's where they differ): both ends' rules and every word, as
/// ClipboardPolicy holds the clipboard's. Pure (Foundation only): the Mac's MicrophoneReceiver and the
/// device's StreamClient+Microphone do only what reads a microphone, encodes, decodes or plays, and
/// Tests/checks/microphone checks this file with StreamProtocol's sources, the two ends together.
///
/// The device (`Device`, `DeviceLink`):
/// - Offers its microphone (kind 48 type 1) while its Share Microphone is on with the permission granted, the
///   session connected, the Mac's window list saying `microphone` 1 or more and not locked, this window the
///   chosen one (the one used last among those in front), and kind 16 not saying no (`takesOffers`; none yet
///   counts as yes). The first offer after the person turned the switch on carries `claim`.
/// - Records and sends packets only while it offers, kind 16 says `inUse` with a codec it makes, Sill is in
///   front, no call holds the audio, and a microphone is there: so nothing records before an app on the Mac
///   uses Sill Microphone, and nothing in the background.
/// - Says `pause` with its offer while it cannot record (in the background, a call, no input), an end
///   (type 3) when its switch goes off, and an end too when the Mac says `inUse` to a connection that does not
///   offer (another window took over, the switch went off while the Mac was locked): the Mac never waits for
///   sound that cannot come.
/// - Never sends kind 48 to a Mac whose list leaves `microphone` out or says 0 (an older Mac, the CLI, a
///   locked Mac): the overview's rule 1.
///
/// The Mac (`Host`, a reducer the receiver feeds on its own queue):
/// - Takes a device's microphone while Use iPhone and iPad microphones is on, Sill Microphone is set up, this
///   Mac is unlocked with this user on its console (LockPolicy refuses kind 48 at a locked screen and off
///   console before it reaches here), and the session's key is on the trust list now (Require pairing off
///   lets an unpaired device in, never its microphone).
/// - One device is Sill Microphone's at a time (`holder`), by its paired key. A claim takes it from anyone;
///   an offer without one takes it only while nobody holds it. The holder's end, its removal, or `grace`
///   seconds without its offer standing (its session gone and no other of its sessions offering again: a move
///   or a quick reconnect keeps it) free it; the most recent standing offer then takes it. The others hear
///   `another`, with the holder's name.
/// - The holder's offering session is wanted (kind 16 `inUse`) exactly while it may, an app uses Sill
///   Microphone and its offer stands. Its packets count only from that session, of the epoch its last format
///   announced, within the limits: at most `maxOffersPerSecond` type 1 a second and `maxEpochsPerMinute`
///   epochs a minute, and at most `maxSoundPerSecond` seconds of sound a second over `soundWindow`; past any,
///   the session is refused for `refusedFor`, with one line, and its kind 16 says `refused`.
public enum MicrophonePolicy {
    // MARK: - The device

    /// The microphone's permission as iOS reports it (AVAudioApplication.recordPermission).
    public enum Permission: String, Equatable, Sendable { case undetermined, granted, denied }

    /// Everything the device's rule reads, for one window's session.
    public struct Device: Equatable, Sendable {
        /// Share Microphone: app-wide, in memory, off at every launch.
        public var switchOn = false
        public var permission = Permission.undetermined
        /// The session is connected (between its first window list and its end).
        public var connected = false
        /// The Mac's window list: `microphone`, and `locked`.
        public var list: Int?
        public var locked = false
        /// The Mac's kind 16 `microphone` for this connection; nil before one came, and from a Mac without it.
        public var state: MicrophoneState?
        /// This window's scene is foreground active (Picture in Picture does not count).
        public var foreground = true
        /// This window is the one the microphone goes from (`chosen`).
        public var chosen = true
        /// An audio interruption (a call, another app's recording) holds the audio.
        public var interrupted = false
        /// A microphone is there to record from (AVAudioSession.isInputAvailable).
        public var inputAvailable = true

        public init() {}
    }

    /// The Mac takes this device's kind 48 at all: its list says generation 1 or more, and it is not locked.
    public static func macTakes(_ d: Device) -> Bool {
        d.connected && (d.list ?? 0) >= MicrophoneCodec.generation && !d.locked
    }

    /// This connection offers the device's microphone (type 1).
    public static func offers(_ d: Device) -> Bool {
        d.switchOn && d.permission == .granted && macTakes(d) && d.chosen && (d.state.map(\.takesOffers) ?? true)
    }

    /// Why no sound comes while the offer stands, the first that applies: Sill not in front, a call, no input.
    public static func pause(_ d: Device) -> String? {
        if !d.foreground { return MicrophoneFormat.background }
        if d.interrupted { return MicrophoneFormat.busy }
        if !d.inputAvailable { return MicrophoneFormat.unavailable }
        return nil
    }

    /// The codec the device records in now: the first of kind 16's list it makes.
    public static func codec(_ d: Device) -> String? { MicrophoneCodec.choose(taken: d.state?.codecs) }

    /// The device records and sends packets now.
    public static func records(_ d: Device) -> Bool {
        offers(d) && pause(d) == nil && d.state?.wanted == true && codec(d) != nil
    }

    /// What one connection has sent of the microphone, and what it owes: the messages each step sends. One per
    /// connection: a move's new connection starts afresh (its offer and, while recording, the epoch's format
    /// again, the capture's).
    public struct DeviceLink: Equatable, Sendable {
        /// An offer went on this connection since it began, or since its end.
        public private(set) var offered = false
        /// The pause the last offer carried.
        public private(set) var pauseSent: String?
        /// An end already answers the Mac's `inUse` for a connection that does not offer.
        public private(set) var endedInUse = false

        public init() {}

        /// The kind 48 messages to send now for `d` (type 1 offers and type 3 ends; the capture sends the
        /// epoch's format and its packets), and whether a claim went: `claimOwed`, the person just turned the
        /// switch on, is spent by the first offer that goes.
        public mutating func step(_ d: Device, claimOwed: Bool) -> (send: [MicrophoneMessage], claimed: Bool) {
            guard MicrophonePolicy.macTakes(d) else {
                // Nothing goes to a Mac that does not take it now; what was offered is offered again after.
                offered = false; pauseSent = nil; endedInUse = false
                return ([], false)
            }
            if MicrophonePolicy.offers(d) {
                endedInUse = false
                let pause = MicrophonePolicy.pause(d)
                guard !offered || pause != pauseSent || claimOwed else { return ([], false) }
                offered = true
                pauseSent = pause
                return ([.format(MicrophoneFormat(claim: claimOwed ? true : nil, pause: pause))], claimOwed)
            }
            var send: [MicrophoneMessage] = []
            if offered, !d.switchOn || d.permission == .denied {
                // The switch went off: this connection's offer ends.
                send.append(.end)
                endedInUse = d.state?.wanted == true
            } else if d.state?.wanted == true, !endedInUse {
                // The Mac wants sound this connection will not record: say so once.
                send.append(.end)
                endedInUse = true
            }
            if d.state?.wanted != true { endedInUse = false }
            offered = false
            pauseSent = nil
            return (send, false)
        }
    }

    /// At most this much of the microphone's sound handed to the session's connection and not yet taken by it
    /// (`.contentProcessed`): two messages. Past it a message is skipped (latency beats quality): the Mac sees
    /// a gap in the seq and starts its decoder afresh.
    public static let maxUnsentSeconds = 0.2
    /// Messages, at the device's ten packets of 10 ms each.
    public static var maxUnsentMessages: Int {
        Int((maxUnsentSeconds * Double(MicrophoneCodec.sampleRate) / Double(MicrophoneCodec.framesPerPacket * MicrophoneCodec.packetsPerMessage)).rounded())
    }

    /// One of Sill's windows, for the choice of the one the microphone goes from.
    public struct Window: Equatable, Sendable {
        public var id: Int
        /// Its scene is foreground active.
        public var foregroundActive: Bool
        /// Its session's Mac takes the microphone (`macTakes`).
        public var takes: Bool
        /// When the person last used it; nil when never.
        public var lastUsedAt: Double?
        public init(id: Int, foregroundActive: Bool, takes: Bool, lastUsedAt: Double?) {
            self.id = id; self.foregroundActive = foregroundActive; self.takes = takes; self.lastUsedAt = lastUsedAt
        }
    }

    /// The window the microphone goes from: of the windows in front whose Mac takes it, the one used last (one
    /// never used counts as used before every other; at the same moment, the first listed). While none is in
    /// front, `previous` stands as long as it is listed: in the background nothing records anyway, and the
    /// choice is the same when Sill comes back. Nil: none.
    public static func chosen(_ windows: [Window], previous: Int?) -> Int? {
        guard windows.contains(where: \.foregroundActive) else {
            guard let previous, windows.contains(where: { $0.id == previous }) else { return nil }
            return previous
        }
        var best: Window?
        for w in windows where w.foregroundActive && w.takes {
            guard let b = best else { best = w; continue }
            if (w.lastUsedAt ?? -.infinity) > (b.lastUsedAt ?? -.infinity) { best = w }
        }
        return best?.id
    }

    /// The device's row and its words. `mac`: the Mac's name; `device`: "iPad" or "iPhone".
    public enum Row: Equatable, Sendable {
        /// No row: a Mac that cannot take it at all (the CLI, a test host without its hook).
        case hidden
        /// The switch, with its footnote; `enabled` false shows it off and dimmed.
        case shown(enabled: Bool, footnote: String)
    }

    /// The row for the session as it is: hidden for a host without a version (the CLI) whose list says nothing
    /// of it, or a locked Mac (the panel's header says why); "Update Sill" for a Sill.app without the field; the
    /// Mac's own word otherwise. `otherWindow`: another of Sill's windows sends it.
    public static func row(_ d: Device, hostVersion: String?, mac: String, device: String, otherWindow: Bool) -> Row {
        guard d.connected, !d.locked else { return .hidden }
        guard let list = d.list else {
            return hostVersion == nil ? .hidden : .shown(enabled: false, footnote: Copy.olderMac(mac: mac))
        }
        if d.permission == .denied { return .shown(enabled: true, footnote: Copy.denied) }
        guard list >= MicrophoneCodec.generation else {
            let state = d.state?.knownState
            return .shown(enabled: false, footnote: state == MicrophoneState.notReady ? Copy.notReady(mac: mac) : Copy.macOff(mac: mac))
        }
        let state = d.state?.knownState
        switch state {
        case MicrophoneState.off?: return .shown(enabled: false, footnote: Copy.macOff(mac: mac))
        case MicrophoneState.notReady?: return .shown(enabled: false, footnote: Copy.notReady(mac: mac))
        case MicrophoneState.unpaired?: return .shown(enabled: false, footnote: Copy.unpaired(mac: mac, device: device))
        case MicrophoneState.refused?: return .shown(enabled: true, footnote: Copy.refused(mac: mac, device: device))
        default: break
        }
        guard d.switchOn else {
            if state == MicrophoneState.another, let other = d.state?.device, !other.isEmpty {
                return .shown(enabled: true, footnote: Copy.anotherOff(mac: mac, other: other, device: device))
            }
            return .shown(enabled: true, footnote: Copy.ready(mac: mac, device: device))
        }
        if otherWindow { return .shown(enabled: true, footnote: Copy.otherWindow) }
        if d.interrupted { return .shown(enabled: true, footnote: Copy.paused(device: device)) }
        if !d.inputAvailable { return .shown(enabled: true, footnote: Copy.noInput(device: device)) }
        switch state {
        case MicrophoneState.another?:
            return .shown(enabled: true, footnote: Copy.another(mac: mac, other: d.state?.device ?? ""))
        case MicrophoneState.inUse?:
            return .shown(enabled: true, footnote: Copy.inUse(mac: mac, device: device))
        default:
            return .shown(enabled: true, footnote: Copy.waiting(mac: mac))
        }
    }

    // MARK: - The Mac

    /// The Mac's rule as a reducer: the receiver pushes in what happens (a session joins or leaves, a kind 48's
    /// type 1 or 3, the Mac's switch, Sill Microphone's readiness, the lock, an app using Sill Microphone,
    /// time) and carries out what comes back (kind 16's microphone per session, the playout's source, lines and
    /// counts). Packets are judged by `takesPackets`. Times are seconds of a monotonic clock.
    public struct Host: Equatable, Sendable {
        // MARK: The constants

        /// How long a device's offer outlives its session without a word from another of its sessions.
        public static let grace: Double = 10
        /// Type 1 a second, per session; epochs (type 1 with a codec) a minute, per session.
        public static let maxOffersPerSecond = 10
        public static let maxEpochsPerMinute = 6
        /// Seconds of sound a second, measured over `soundWindow` seconds: a device sends one a second, and a
        /// burst after a stall a little more.
        public static let maxSoundPerSecond = 1.5
        public static let soundWindow: Double = 2
        /// How long a session that broke a limit is refused.
        public static let refusedFor: Double = 60
        /// No packet from the session in use for this long: a line, once.
        public static let silenceAfter: Double = 2
        /// A refusal's line, per session and reason, at most this often.
        public static let refusalLineSpacing: Double = 60

        // MARK: The inputs and what comes out

        /// Why a session's microphone is refused: each a `mic.refused.<raw value>` count and, for its kind 16,
        /// the state it says.
        public enum Refusal: String, CaseIterable, Equatable, Sendable {
            case off, notReady, unpaired, refused, unknown
        }

        public enum Event: Equatable, Sendable {
            /// A session joined: its key (the paired key's fingerprint; nil at a plain door), whether that key is
            /// on the trust list now, and its cleaned name.
            case joined(Int, key: String?, paired: Bool, name: String)
            /// The trust list changed for a session's key: false, its offer goes at once.
            case paired(Int, Bool)
            /// The device of that key was removed from the trust list (cut off): its offer goes at once.
            case removed(key: String)
            case left(Int)
            /// A type 1, parsed and valid (`MicrophoneFormat.isValid`).
            case format(Int, MicrophoneFormat)
            /// A type 3.
            case end(Int)
            case switchChanged(Bool)
            case readyChanged(Bool)
            /// This user on the console with its screen unlocked (LockPolicy's `.unlocked`), or not.
            case unlockedChanged(Bool)
            /// An app uses Sill Microphone (reads from it), or none does.
            case appChanged(Bool)
            /// Time passes (the grace, the silence, the end of a refusal).
            case tick
        }

        public enum Effect: Equatable, Sendable {
            /// Kind 16's microphone for that session changed (nil: none, as while the Mac is locked).
            case state(Int, MicrophoneState?)
            /// The playout's source: the holder's offering session and its epoch's format (`key` the holder's:
            /// a new key is a new device, whose sound starts afresh), or nothing (it fades and plays silence).
            case playout(key: String, session: Int, format: MicrophoneFormat)
            case noPlayout
            case line(String)
            /// A Stats key to bump.
            case count(String)
        }

        // MARK: The state

        /// Sound taken from a session at a time, in frames at 48 kHz (whole numbers: the limit holds exactly
        /// at its edge).
        public struct Sound: Equatable, Sendable {
            public var at: Double
            public var frames: Int
        }

        public struct Session: Equatable, Sendable {
            public var key: String?
            public var paired: Bool
            public var name: String
            /// The format of the epoch it records now (the last valid type 1 with a codec while it was wanted);
            /// gone whenever it stops being wanted, since every recording starts a new epoch.
            public var epoch: MicrophoneFormat?
            public var state: MicrophoneState?
            public var refusedUntil: Double?
            public var secondStart: Double = -.infinity
            public var offersThisSecond = 0
            public var epochTimes: [Double] = []
            public var sound: [Sound] = []
            public var lastPacketAt: Double?
            public var silenceSaid = false
            public var refusalLineAt: [Refusal: Double] = [:]
            public var lockedLineAt: Double = -.infinity
        }

        /// What the playout plays: the holder's offering session and the epoch it records.
        public struct Source: Equatable, Sendable {
            public var key: String
            public var session: Int
            public var epoch: Int
        }

        /// A device's offer, by its key.
        public struct Offer: Equatable, Sendable {
            /// The session that last said it (its type 1); nil once that session left.
            public var session: Int?
            /// The device's name as its session last gave it.
            public var name: String
            /// When the offer began or was last claimed: the order successors take the microphone in.
            public var since: Double
            /// When its session left, for the grace.
            public var leftAt: Double?
            public var pause: String?
        }

        public private(set) var switchOn = false
        public private(set) var ready = false
        public private(set) var unlocked = false
        public private(set) var appUses = false
        public private(set) var sessions: [Int: Session] = [:]
        public private(set) var offers: [String: Offer] = [:]
        public private(set) var holder: String?
        /// What the playout plays: the holder's offering session and the epoch it records.
        public private(set) var playing: Source?
        /// The device and epoch whose "is Sill Microphone's input now" was said: a move's new session of the
        /// same epoch says nothing.
        private var liveSaid: (key: String, epoch: Int)?

        public init() {}

        public static func == (a: Host, b: Host) -> Bool {
            a.switchOn == b.switchOn && a.ready == b.ready && a.unlocked == b.unlocked && a.appUses == b.appUses
                && a.sessions == b.sessions && a.offers == b.offers && a.holder == b.holder && a.playing == b.playing
        }

        // MARK: Readings

        /// The microphone may be used at all: the switch on, Sill Microphone set up, this Mac unlocked.
        public var available: Bool { switchOn && ready && unlocked }

        /// Why session `id`'s microphone is refused at `now`, nil when it may be used. The lock is not one: a
        /// locked Mac's sessions have no state at all (`state(of:)`).
        public func refusal(_ id: Int, at now: Double) -> Refusal? {
            guard let s = sessions[id] else { return .unknown }
            if !switchOn { return .off }
            if !ready { return .notReady }
            if !s.paired || s.key == nil { return .unpaired }
            if let until = s.refusedUntil, now < until { return .refused }
            return nil
        }

        /// The offer stands: its session is here, or left less than `grace` ago.
        public func stands(_ o: Offer, at now: Double) -> Bool {
            guard let left = o.leftAt else { return o.session != nil }
            return now - left < Self.grace
        }

        /// Session `id` records now: it may, it is the holder's offering session, an app uses Sill Microphone.
        public func wanted(_ id: Int, at now: Double) -> Bool {
            guard unlocked, refusal(id, at: now) == nil, appUses, let key = sessions[id]?.key, key == holder,
                  let o = offers[key], o.session == id, o.leftAt == nil else { return false }
            return true
        }

        /// Kind 16's microphone for session `id`: nil while the Mac is locked (its list leaves `microphone`
        /// out) or for no such session.
        public func state(of id: Int, at now: Double) -> MicrophoneState? {
            guard let s = sessions[id], unlocked else { return nil }
            if let r = refusal(id, at: now) {
                switch r {
                case .off: return MicrophoneState(state: MicrophoneState.off)
                case .notReady: return MicrophoneState(state: MicrophoneState.notReady)
                case .unpaired: return MicrophoneState(state: MicrophoneState.unpaired)
                case .refused: return MicrophoneState(state: MicrophoneState.refused)
                case .unknown: return nil
                }
            }
            let codecs = MicrophoneCodec.hostTakes
            if let h = holder, h != s.key, let o = offers[h] {
                return MicrophoneState(state: MicrophoneState.another, codecs: codecs, device: o.name)
            }
            if wanted(id, at: now) { return MicrophoneState(state: MicrophoneState.inUse, codecs: codecs) }
            return MicrophoneState(state: MicrophoneState.idle, codecs: codecs)
        }

        /// What the window list says: generation 1 while the microphone may be used, 0 while the switch is off
        /// or Sill Microphone is not set up. LockPolicy.list leaves it out while locked.
        public var advertised: Int { switchOn && ready ? MicrophoneCodec.generation : 0 }

        /// The name of the device in use, for the Mac's card: the holder's, while its session records.
        public func inUse(at now: Double) -> String? {
            guard let h = holder, let o = offers[h], let id = o.session, wanted(id, at: now) else { return nil }
            return o.name
        }

        // MARK: Events

        public mutating func handle(_ event: Event, at now: Double) -> [Effect] {
            let before = snapshot(at: now)
            var out: [Effect] = []
            switch event {
            case .joined(let id, let key, let paired, let name):
                sessions[id] = Session(key: key, paired: paired, name: Self.clean(name))
            case .paired(let id, let isPaired):
                guard sessions[id] != nil else { break }
                sessions[id]?.paired = isPaired
                if !isPaired, let key = sessions[id]?.key, offers[key]?.session == id {
                    out += withdraw(key, why: .removed, at: now)
                }
            case .removed(let key):
                for id in sessions.keys where sessions[id]?.key == key { sessions[id]?.paired = false }
                if offers[key] != nil { out += withdraw(key, why: .removed, at: now) }
            case .left(let id):
                if let key = sessions[id]?.key, offers[key]?.session == id {
                    offers[key]?.session = nil
                    offers[key]?.leftAt = now
                }
                sessions[id] = nil
            case .format(let id, let f):
                out += format(id, f, at: now)
            case .end(let id):
                guard let key = sessions[id]?.key, offers[key]?.session == id else { break }
                out += withdraw(key, why: .stopped, at: now)
            case .switchChanged(let on):
                switchOn = on
            case .readyChanged(let r):
                ready = r
            case .unlockedChanged(let u):
                unlocked = u
            case .appChanged(let uses):
                appUses = uses
            case .tick:
                out += tick(at: now)
            }
            out += settle(before, at: now)
            return out
        }

        /// One type 2 of `packets` packets of `framesPerPacket` frames, of epoch `epoch`, from session `id` at
        /// `now`: whether the playout takes it, and what follows (a refusal, its line, counts).
        public mutating func takesPackets(_ id: Int, epoch: Int, packets: Int, framesPerPacket: Int, at now: Double) -> (take: Bool, effects: [Effect]) {
            if let r = refusal(id, at: now) {
                return (false, [.count("mic.refused.\(r.rawValue)")])
            }
            guard wanted(id, at: now) else { return (false, [.count("mic.dropped.notWanted")]) }
            guard let s = sessions[id], s.epoch?.format.epoch == epoch else { return (false, [.count("mic.dropped.epoch")]) }
            let frames = min(max(0, packets), AudioPackets.maxCount) * min(max(0, framesPerPacket), 8192)
            var sound = s.sound.filter { now - $0.at < Self.soundWindow }
            sound.append(Sound(at: now, frames: frames))
            let total = sound.reduce(0) { $0 + $1.frames }
            if Double(total) > Self.maxSoundPerSecond * Self.soundWindow * Double(MicrophoneCodec.sampleRate) {
                let before = snapshot(at: now)
                let seconds = Double(total) / Double(MicrophoneCodec.sampleRate) / Self.soundWindow
                var out = refuse(id, line: Copy.tooMuch(name: s.name, seconds: seconds), at: now)
                out += settle(before, at: now)
                return (false, out + [.count("mic.refused.refused")])
            }
            sessions[id]?.sound = sound
            sessions[id]?.lastPacketAt = now
            sessions[id]?.silenceSaid = false
            return (true, [.count("mic.in")])
        }

        /// A kind 48 refused by the lock as it arrived (LockPolicy), from session `id`: counted, and said once a
        /// minute per session.
        public mutating func lockedArrival(_ id: Int, offConsole: Bool, at now: Double) -> [Effect] {
            var out: [Effect] = [.count("mic.refused.locked")]
            guard let s = sessions[id] else { return out }
            if now - s.lockedLineAt >= Self.refusalLineSpacing {
                sessions[id]?.lockedLineAt = now
                out.append(.line(Copy.refusedLine(name: s.name, why: offConsole ? Copy.whyOffConsole : Copy.whyLocked)))
            }
            return out
        }

        // MARK: Inside

        private enum Withdrawal { case stopped, removed, left }

        /// A type 1 from session `id`.
        private mutating func format(_ id: Int, _ f: MicrophoneFormat, at now: Double) -> [Effect] {
            guard var s = sessions[id] else { return [.count("mic.refused.unknown")] }
            if let r = refusal(id, at: now) {
                var out: [Effect] = [.count("mic.refused.\(r.rawValue)")]
                if r != .refused, now - (s.refusalLineAt[r] ?? -.infinity) >= Self.refusalLineSpacing {
                    sessions[id]?.refusalLineAt[r] = now
                    out.append(.line(Copy.refusedLine(name: s.name, why: Copy.why(r))))
                }
                return out
            }
            // The limits: type 1 a second, epochs a minute.
            if now - s.secondStart >= 1 { s.secondStart = now; s.offersThisSecond = 0 }
            s.offersThisSecond += 1
            if f.isEpoch {
                s.epochTimes = s.epochTimes.filter { now - $0 < 60 } + [now]
            }
            sessions[id] = s
            if s.offersThisSecond > Self.maxOffersPerSecond {
                return refuse(id, line: Copy.tooManyOffers(name: s.name), at: now) + [.count("mic.refused.refused")]
            }
            if s.epochTimes.count > Self.maxEpochsPerMinute {
                return refuse(id, line: Copy.tooManyFormats(name: s.name), at: now) + [.count("mic.refused.refused")]
            }
            guard let key = s.key else { return [] }
            var out: [Effect] = []
            if f.isEpoch { sessions[id]?.epoch = f }
            var o = offers[key] ?? Offer(session: id, name: s.name, since: now, leftAt: nil, pause: nil)
            o.session = id
            o.name = s.name
            o.leftAt = nil
            o.pause = f.knownPause
            if f.claim == true { o.since = now }
            offers[key] = o
            if holder == nil || (f.claim == true && holder != key) {
                if let previous = holder, previous != key, let p = offers[previous] {
                    out.append(.line(Copy.tookOver(name: o.name, from: p.name)))
                }
                holder = key
            }
            out.append(.count(f.isEpoch ? "mic.formats" : "mic.offers"))
            return out
        }

        /// Session `id` broke a limit: refused for `refusedFor`, its offer withdrawn, one line.
        private mutating func refuse(_ id: Int, line: String, at now: Double) -> [Effect] {
            guard let s = sessions[id] else { return [] }
            sessions[id]?.refusedUntil = now + Self.refusedFor
            sessions[id]?.epoch = nil
            sessions[id]?.sound = []
            var out: [Effect] = []
            if now - (s.refusalLineAt[.refused] ?? -.infinity) >= Self.refusalLineSpacing {
                sessions[id]?.refusalLineAt[.refused] = now
                out.append(.line(line))
            }
            if let key = s.key, offers[key]?.session == id { out += withdraw(key, why: nil, at: now) }
            return out
        }

        /// The offer of `key` ends; the holder, if it was, goes to the most recent standing offer.
        private mutating func withdraw(_ key: String, why: Withdrawal?, at now: Double) -> [Effect] {
            guard let o = offers.removeValue(forKey: key) else { return [] }
            var out: [Effect] = []
            if let why, holder == key {
                switch why {
                case .stopped: out.append(.line(Copy.stopped(name: o.name)))
                case .removed: out.append(.line(Copy.removed(name: o.name)))
                case .left: out.append(.line(Copy.left(name: o.name)))
                }
            }
            if holder == key { holder = successor(at: now) }
            return out
        }

        /// The standing offer most recently begun or claimed whose session may use the microphone; nil: none.
        private func successor(at now: Double) -> String? {
            var best: (key: String, since: Double)?
            for (key, o) in offers where stands(o, at: now) {
                guard let id = o.session, refusal(id, at: now) == nil else { continue }
                if best == nil || o.since > best!.since || (o.since == best!.since && key < best!.key) { best = (key, o.since) }
            }
            return best?.key
        }

        private mutating func tick(at now: Double) -> [Effect] {
            var out: [Effect] = []
            // A refusal's minute over.
            for id in sessions.keys where (sessions[id]?.refusedUntil).map({ now >= $0 }) == true { sessions[id]?.refusedUntil = nil }
            // The grace: an offer whose session left long enough ago goes.
            for key in offers.keys.sorted() {
                guard let o = offers[key], let left = o.leftAt, now - left >= Self.grace else { continue }
                out += withdraw(key, why: .left, at: now)
            }
            // A holder freed while its successor's session was refused, or none stood: look again.
            if holder == nil { holder = successor(at: now) }
            // The session in use went quiet.
            for id in sessions.keys.sorted() where wanted(id, at: now) {
                guard let s = sessions[id], let last = s.lastPacketAt, now - last >= Self.silenceAfter, !s.silenceSaid else { continue }
                sessions[id]?.silenceSaid = true
                out.append(.line(Copy.silent(name: s.name)))
            }
            return out
        }

        private struct Snapshot {
            var playing: Source?
        }

        private func snapshot(at now: Double) -> Snapshot {
            Snapshot(playing: playing)
        }

        /// After an event: each session's kind 16 that changed (and the epoch of one no longer wanted, since
        /// its next recording starts a new one), the playout's source when it changed, and the line when a
        /// device's sound becomes Sill Microphone's.
        private mutating func settle(_ before: Snapshot, at now: Double) -> [Effect] {
            var out: [Effect] = []
            for id in sessions.keys.sorted() {
                if !wanted(id, at: now) { sessions[id]?.epoch = nil }
                let s = state(of: id, at: now)
                if sessions[id]?.state != s {
                    sessions[id]?.state = s
                    out.append(.state(id, s))
                }
            }
            var next: Source?
            var nextFormat: MicrophoneFormat?
            if let h = holder, let id = offers[h]?.session, wanted(id, at: now), let f = sessions[id]?.epoch, let e = f.format.epoch {
                next = Source(key: h, session: id, epoch: e)
                nextFormat = f
            }
            guard next != playing else { return out }
            playing = next
            if let next, let f = nextFormat {
                out.append(.playout(key: next.key, session: next.session, format: f))
                if liveSaid?.key != next.key || liveSaid?.epoch != next.epoch {
                    out.append(.line(Copy.live(name: offers[next.key]?.name ?? "A device", format: f)))
                }
                liveSaid = (next.key, next.epoch)
            } else {
                out.append(.noPlayout)
            }
            return out
        }

        /// A device's name for the lines and `another`: one clean line of at most 64 characters.
        static func clean(_ name: String) -> String {
            let n = SafeText.label(name)
            return n.isEmpty ? "A device" : n
        }
    }

    // MARK: - Words

    /// Every word of the microphone, both ends. ‹device› is "iPad" or "iPhone", ‹Mac› the Mac's name.
    public enum Copy {
        // The device's row (the Settings panel, This ‹device›).
        public static let rowTitle = "Share Microphone"
        public static func rowSpoken(mac: String, device: String) -> String { "Send this \(device)’s microphone to \(mac)" }
        public static func ready(mac: String, device: String) -> String {
            "Turn this on to use this \(device)’s microphone on \(mac): choose Sill Microphone there, in a call, a recording or dictation. It turns off when Sill closes."
        }
        public static func waiting(mac: String) -> String {
            "Ready: \(mac) hears this microphone once an app there uses Sill Microphone."
        }
        public static func inUse(mac: String, device: String) -> String {
            "\(mac) hears this \(device)’s microphone as Sill Microphone. While it’s on, sound from \(mac) plays as on a call."
        }
        public static func another(mac: String, other: String) -> String {
            "\(mac) is using \(other.isEmpty ? "another device" : other)’s microphone. Turn this off and on again to use this one instead."
        }
        public static func anotherOff(mac: String, other: String, device: String) -> String {
            "\(mac) is using \(other)’s microphone. Turn this on to use this \(device)’s instead."
        }
        public static func macOff(mac: String) -> String {
            "Turn on Use iPhone and iPad microphones in Sill’s settings on \(mac) to use this."
        }
        public static func notReady(mac: String) -> String {
            "Set up Sill Microphone in Sill’s settings on \(mac) to use this."
        }
        public static func unpaired(mac: String, device: String) -> String {
            "Pair this \(device) with \(mac) to use its microphone there."
        }
        public static func olderMac(mac: String) -> String { "Update Sill on \(mac) to use this." }
        public static func refused(mac: String, device: String) -> String {
            "\(mac) stopped taking this \(device)’s microphone for a minute."
        }
        public static let denied = "Sill isn’t allowed to use the microphone. You can allow it in Settings."
        public static let openSettings = "Open Settings"
        public static func paused(device: String) -> String { "Paused during the call on this \(device)." }
        public static func noInput(device: String) -> String { "This \(device) has no microphone to use right now." }
        public static let otherWindow = "Your other Sill window sends the microphone."

        // The Mac's log.
        public static func live(name: String, format f: MicrophoneFormat) -> String {
            let kbps = (f.format.bitrate ?? MicrophoneCodec.bitrate) / 1000
            return "Microphone: \(name) is Sill Microphone’s input now (AAC-ELD 48 kHz mono, \(kbps) kbps)."
        }
        public static func tookOver(name: String, from other: String) -> String { "Microphone: \(name) took over from \(other)." }
        public static func stopped(name: String) -> String { "Microphone: \(name) stopped." }
        public static func left(name: String) -> String { "Microphone: \(name) left." }
        public static func removed(name: String) -> String { "Microphone: \(name) is no longer paired: its microphone stopped." }
        public static func silent(name: String) -> String { "Microphone: \(name) went silent for 2 s." }
        public static let whyLocked = "this Mac is locked"
        public static let whyOffConsole = "another user is on the screen"
        public static func why(_ r: Host.Refusal) -> String {
            switch r {
            case .off: return "Use iPhone and iPad microphones is off"
            case .notReady: return "Sill Microphone isn’t set up"
            case .unpaired: return "it isn’t paired with this Mac"
            case .refused: return "it sent more than this Mac takes"
            case .unknown: return "its session is unknown"
            }
        }
        public static func refusedLine(name: String, why: String) -> String { "Microphone: refused from \(name): \(why)." }
        public static func tooMuch(name: String, seconds: Double) -> String {
            "Microphone: \(name) sent \(String(format: "%.1f", seconds)) s of sound in a second: refused for a minute."
        }
        public static func tooManyOffers(name: String) -> String {
            "Microphone: \(name) sent more than \(Host.maxOffersPerSecond) offers in a second: refused for a minute."
        }
        public static func tooManyFormats(name: String) -> String {
            "Microphone: \(name) started more than \(Host.maxEpochsPerMinute) recordings in a minute: refused for a minute."
        }
        public static func switchChange(from: Bool, to: Bool) -> String {
            "Settings: device microphones \(from ? "on" : "off") → \(to ? "on" : "off")"
        }
    }
}
