import Foundation
import StreamProtocol

/// Who each door admits (docs/home-pairing-plan.md §4.2), in one place for both listeners: the
/// home door (Bonjour, an ephemeral port; TLS in Sill.app and in SillHost --pairing) and the remote
/// door (port 7455). The remote door's rules are RemoteServer's, moved here unchanged but one:
/// pairing there needs a window the remote door takes proofs for, never one a device opened by
/// asking. The home door's are new. The Door that runs both listeners' admission asks these.
///
/// Pure (Foundation, OriginPolicy's origins, StreamProtocol's wire values), so it is checked on its
/// own with swiftc. Nothing here reads a clock, the network or the main actor: the verify block
/// and admission call it on the network queue with what the lock-protected TrustSnapshot says.
enum DoorPolicy {
    enum Door: Equatable, Sendable { case home, remote }

    /// A remote door's sessions at once; the ninth gets goodbye `busy`.
    static let maxRemoteSessions = 8

    /// What admission knows about one connection: its key, and the Mac's switches as the
    /// TrustSnapshot has them.
    struct Trust: Equatable, Sendable {
        /// The peer presented a P-256 key (it has a fingerprint). A peer without one is trusted
        /// by nothing: no pin matches it, and a session must be named and removable by its key.
        var hasKey = true
        /// The peer's key is in the trust list.
        var paired = false
        /// Require pairing (the home door's; the Mac's alone, never a device's).
        var requirePairing = true
        var remoteAccess = false
        /// Already false while Remote Access is off (RemoteAccess.apply).
        var internetAccess = false
        /// A pairing window is open: the home door takes its proofs.
        var pairingOpen = false
        /// One the remote door takes proofs for: opened by the Mac's user (or the CLI's --remote),
        /// never one a device opened by asking (§4.6).
        var remotePairingOpen = false
    }

    // MARK: Before the connection starts

    /// Before a connection starts, so a refused one gets no byte: the home door takes loopback,
    /// this Mac's own networks and peer-to-peer Wi-Fi (Direct Wireless), never a VPN or the
    /// internet; the remote door takes loopback, this Mac's networks and VPNs, the internet only
    /// with internet access, and never peer-to-peer Wi-Fi.
    static func admitsBeforeStart(_ door: Door, origin: OriginPolicy.Origin, internetAccess: Bool) -> Bool {
        switch door {
        case .home: return OriginPolicy.homeAdmits(origin)
        case .remote: return OriginPolicy.remoteAdmits(origin, internetAccess: internetAccess)
        }
    }

    /// The minute's summary's word for a connection refused before it started; nil when it is
    /// admitted. At home "vpn" or "internet", the plain door's words; at the remote door
    /// "internet" for every refused origin, peer-to-peer Wi-Fi included, as before.
    static func refusalBeforeStart(_ door: Door, origin: OriginPolicy.Origin, internetAccess: Bool) -> String? {
        guard !admitsBeforeStart(door, origin: origin, internetAccess: internetAccess) else { return nil }
        switch door {
        case .home: return origin == .vpn ? "vpn" : "internet"
        case .remote: return "internet"
        }
    }

    // MARK: The verify block

    /// The TLS handshake's verify block: trust is the key and the application protocol, nothing
    /// else. `sill/1` for a paired key, and at home for any key while Require pairing is off;
    /// `sill-pair/1` always at home (an ask needs no window), and at the remote door only while a
    /// window it takes proofs for is open; anything else never.
    static func trusts(_ door: Door, alpn: String?, _ t: Trust) -> Bool {
        guard t.hasKey else { return false }
        switch alpn {
        case RemoteTLS.sessionALPN?:
            return door == .home ? t.paired || !t.requirePairing : t.paired
        case RemoteTLS.pairingALPN?:
            return door == .home ? true : t.remotePairingOpen
        default:
            return false
        }
    }

    // MARK: At `.ready`

    enum AtReady: Equatable, Sendable {
        /// A session: registered with its route.
        case session
        /// A pairing connection: read exactly one kind 19 (at most 4 KiB, within the admission
        /// deadline), then treat it as `pairing(_:method:version:)` says.
        case pairing
        /// A paired key the door does not serve now: this goodbye ("remoteOff", "busy"), then close.
        case goodbye(String)
        /// Cancelled with no Sill byte, counted under this word in the minute's summary ("unpaired").
        case refuse(String)
    }

    /// What `.ready` does with a connection the verify block let through, judged again against the
    /// switches as they are now. Home: `sill/1` is the session while its key is still trusted,
    /// `sill-pair/1` is read. Remote, as before: an unpaired key is refused, a paired one gets
    /// goodbye `remoteOff` while Remote Access is off and `busy` at `maxRemoteSessions`, and
    /// `sill-pair/1` is read only while a window the remote door takes proofs for is open.
    static func atReady(_ door: Door, alpn: String?, _ t: Trust, remoteSessions: Int) -> AtReady {
        guard t.hasKey else { return .refuse("unpaired") }
        switch (door, alpn) {
        case (.home, RemoteTLS.sessionALPN?):
            return trusts(.home, alpn: alpn, t) ? .session : .refuse("unpaired")
        case (.home, RemoteTLS.pairingALPN?):
            return .pairing
        case (.remote, RemoteTLS.sessionALPN?):
            guard t.paired else { return .refuse("unpaired") }
            guard t.remoteAccess else { return .goodbye(Goodbye.remoteOff) }
            guard remoteSessions < maxRemoteSessions else { return .goodbye(Goodbye.busy) }
            return .session
        case (.remote, RemoteTLS.pairingALPN?):
            return t.remotePairingOpen ? .pairing : .refuse("unpaired")
        default:
            return .refuse("unpaired")
        }
    }

    // MARK: After the device gate

    /// A session the device gate held (the floor above "0": up to 2 s while it reads the hello, the
    /// first message inside TLS) is neither pending nor a client meanwhile, so a change that closes
    /// sessions (Remove, Require pairing on, Remote Access or internet access off) could not reach
    /// it. Judged again as the gate admits it, from the switches as they are then: the goodbye that
    /// change sends its sessions, or nil to admit it. `wasPaired`: its key was paired when `.ready`
    /// admitted it. Remote, in the order its changes are checked: "removed", "remoteOff",
    /// "internetOff" (an origin the internet switch now refuses), then "busy" at
    /// `maxRemoteSessions`. Home: a key that was paired and no longer is, "removed"; an unpaired
    /// key while Require pairing is on, "pairingRequired".
    static func afterGate(_ door: Door, wasPaired: Bool, origin: OriginPolicy.Origin, _ t: Trust, remoteSessions: Int) -> String? {
        switch door {
        case .remote:
            if !t.hasKey || !t.paired { return Goodbye.removed }
            if !t.remoteAccess { return Goodbye.remoteOff }
            if !OriginPolicy.remoteAdmits(origin, internetAccess: t.internetAccess) { return Goodbye.internetOff }
            if remoteSessions >= maxRemoteSessions { return Goodbye.busy }
            return nil
        case .home:
            if t.paired { return nil }
            if wasPaired { return Goodbye.removed }
            return t.requirePairing ? Goodbye.pairingRequired : nil
        }
    }

    /// Whether the Mac still serves a session it admitted, from the switches and trust list as they are
    /// now (security scan finding 10, the review of PR #254): false once a change has cut it off (Remove,
    /// Require pairing turned on, Remote Access or internet access turned off), judged as `afterGate`
    /// judges a session the device gate held, from what it was admitted as (`wasPaired`: its key was
    /// paired then; `origin`; the door). The coordinator asks it as it registers a session: one the door
    /// admitted while the Mac was deciding such a change (saving it: a keychain write, or its prompt)
    /// registers on the main actor only behind that decision, which could not name it, and every
    /// message of it comes after its registration. A plain session (`encrypted` false: the plain home
    /// door, no key) is never cut off; the remote door's limit (`busy`) is no cut.
    static func stillServes(_ door: Door, encrypted: Bool, wasPaired: Bool, origin: OriginPolicy.Origin, _ t: Trust) -> Bool {
        guard encrypted else { return true }
        return afterGate(door, wasPaired: wasPaired, origin: origin, t, remoteSessions: 0) == nil
    }

    /// How a door treats the one kind 19 of a pairing connection it admitted.
    enum Pairing: Equatable, Sendable {
        /// The ask rule (`ask(…)`): the home door's "pair me".
        case ask
        /// The device's own Cancel at the home door (kind 19 "cancel"): the window its ask opened
        /// closes, if it is still the home door's alone, without quieting its asker
        /// (`PairingWindow.CloseReason.withdrawn`). Answered `closed` whatever happened, and never
        /// judged by the window, so it counts no try and tells nobody anything.
        case withdraw
        /// The pairing window judges its proof: "qr" and "code", and any other method, which the
        /// window counts as a wrong proof, as the remote door always has.
        case window
        /// Answered `closed` at once with no try counted: an ask at the remote door, which never
        /// opens a window or pairs by itself, and at either door a request of another generation
        /// than this build's (`PairRequest.v` not 1). The window never sees it.
        case closed
    }

    /// `version`: the request's `v`. Any other than `PairRequest.version` is a later generation's
    /// method or proof format, which this host cannot judge: answered `closed` without a try, never
    /// counted as one of the window's five wrong codes (the compatibility floor).
    static func pairing(_ door: Door, method: String, version: Int) -> Pairing {
        guard version == PairRequest.version else { return .closed }
        if method == PairRequest.cancel { return door == .home ? .withdraw : .closed }
        guard method == PairRequest.ask else { return .window }
        return door == .home ? .ask : .closed
    }

    // MARK: A handshake that failed

    enum HandshakeRefusal: Equatable, Sendable {
        /// Counted under this word in the minute's summary, and one failure toward its source's
        /// backoff (5 in 60 s → refused for 300 s).
        case refused(String)
        /// Plain bytes at a TLS home door (-9836): an older Sill, or a TLS 1.2 client. Counted
        /// "older" in the summary, and shown in the menu once one source has tried so a third time
        /// within a minute (`olderSillTry`), never as a refusal toward the backoff: the backoff is
        /// checked when a connection is accepted, before any key is seen, so a device that retried
        /// plainly and was then updated would have its new build refused for up to 5 minutes. It
        /// costs what any connection that ends unadmitted costs (`Places.End.ended`): `endCost`,
        /// which an older Sill's reconnect every 2 to 10 s never adds up to a backoff with.
        case olderSill
    }

    /// What a handshake that failed before admission counts as, from the TLS status on the Mac's
    /// side (measured on loopback, 2026-09-24 and 2026-09-25, H0's P4): the verify block refused
    /// the key (-9808), no certificate (-9863), an application protocol the door does not offer
    /// (-9810), an HTTP request (-9858), and not TLS 1.3 (-9836: TLS 1.2, or any plain Sill
    /// message, whose header's first timestamp bytes are never a TLS version). Nil for a peer that
    /// went away by itself (-9816, a reset, -9825 when it refused the Mac's key): no refusal, only
    /// what holding its place cost (`charge(held:refused:)`).
    static func handshakeRefusal(_ door: Door, status: Int32) -> HandshakeRefusal? {
        switch status {
        case -9836 where door == .home: return .olderSill
        case -9808, -9863, -9810, -9836, -9858: return .refused("unpaired")
        default: return nil
        }
    }

    // MARK: The places waiting for admission

    // Finding 9 of the security scan of 2026-10-18: a door held at most 8 connections waiting for
    // admission, 2 per address, each for up to 10 s, and backed an address off only for refusals of
    // its own. A client that sent nothing and closed each connection at 9.9 s, from four addresses,
    // kept every place full for as long as it liked and was never backed off, while a real device got
    // "limit" (and IPv6 gives one host any number of addresses). Now holding a place costs its
    // source, the TLS handshake has 4 s, an IPv6 address answers for its /64 too, and two places
    // beyond the eight are kept for addresses that recently proved a paired key.

    /// Places any source may take.
    static let sharedPlaces = 8
    /// Places beyond `sharedPlaces` that only a known address takes (one that proved a paired key
    /// within `knownFor`, `Places.isKnown`), so a paired device gets in while strangers hold every
    /// shared place. A known address's waiting connections count against these first.
    static let reservedPlaces = 2
    /// Waiting connections one source may have at once: one group (`Source.group`, an IPv4 address
    /// or an IPv6 /64) for an address that is not known, one address for a known one.
    static let placesPerSource = 2
    /// From accept to `.ready`: the whole TLS handshake (a ClientHello at once, then about one round
    /// trip). Network.framework does not say when a ClientHello arrives on a server connection, so
    /// this bounds the handshake rather than its first bytes, with room for a round trip through a
    /// hotspot or a relay and one lost packet. A known address has `admissionDeadline`.
    static let handshakeDeadline: Double = 4
    /// From `.ready` to a pairing connection's one kind 19 (a device sends it at once; a typed
    /// code's PBKDF2 takes it 90 to 160 ms), and never later than `admissionDeadline` from accept.
    static let requestDeadline: Double = 4
    /// From accept to admission, at the latest, as before.
    static let admissionDeadline: Double = 10
    /// How long a place is held for `endCost`, or `waitCost` a second, alone: a device cancels the
    /// losers of its own staggered dial (1 s apart) once one is ready, within this.
    static let freeHold: Double = 2
    /// What a connection that ends unadmitted costs its source at the least, in failures: cycling
    /// connections inside `freeHold` still adds up (50 in a minute back an address off), while an
    /// older Sill's plain try every 2 to 10 s never does (3 a minute at most).
    static let endCost = 0.1
    /// What each second a place is held costs at the least, in failures: a place held without a
    /// break costs 6 a minute however its connections are cut, so its address is backed off within
    /// 50 s, and an address keeps at most 5/6 of a place for as long as it likes. With `endCost`
    /// alone a connection closed at 2 s cost a twentieth a second, 3 a minute: eight addresses, one
    /// connection each, held every shared place for good and none was backed off (the review of
    /// 2026-10-29, its second pass). A connection ended within a second (a plain try, a dial's loser
    /// cancelled at once) still costs `endCost`.
    static let waitCost = 0.1
    /// `failuresForBackoff` within `failureWindow` back an address off for `backoffSeconds`, as
    /// before. `groupFailuresForBackoff` within `groupFailureWindow` back an IPv6 /64 off, counting
    /// only its addresses that are not known, each for `groupShare` at most, so that it takes two of
    /// them at least; over the longer window, which a host taking a new address for every
    /// connection fills even holding one place at the cheapest (`waitCost` a second: 30 in 300 s, the
    /// /64 at 120 s; two places, at 60 s).
    static let failureWindow: Double = 60
    static let failuresForBackoff: Double = 5
    static let groupFailureWindow: Double = 300
    static let groupFailuresForBackoff: Double = 12
    /// The most one address counts toward its /64 within `groupFailureWindow`: half of
    /// `groupFailuresForBackoff`. Its own backoff (5 in 60 s) does not bound what an address adds over
    /// 300 s: paced under it, one address alone backed its /64 off (the review of 2026-10-29, its
    /// second pass: an older Sill's plain try every 2 s at 238 s, a refusal every 16 s at 176 s), and
    /// at home a link-local address's /64 is its whole interface, so every device not yet known there
    /// was then refused for 5 minutes; Tailscale's IPv6 is one /64 for every node.
    static let groupShare: Double = 6
    static let backoffSeconds: Double = 300
    /// How long an address that proved a paired key at `.ready` stays known.
    static let knownFor: Double = 86_400

    /// What one connection that waited `held` seconds and ended without admission costs its source,
    /// in failures: `endCost`, and one more for every `freeHold` it waited beyond the first, and
    /// never less than `waitCost` for each second it waited (which counts between 1 and 2.25 s). At
    /// least one when the door refused it (a key it does not trust, a handshake it failed, a
    /// deadline), as every refusal cost before.
    static func charge(held: Double, refused: Bool) -> Double {
        let cost = max(endCost + max(0, held - freeHold) / freeHold, held * waitCost)
        return refused ? max(1, cost) : cost
    }

    /// When a connection waiting for admission is refused, in seconds after it was accepted:
    /// `handshakeDeadline` while it is not ready (`admissionDeadline` from a known address); once
    /// ready (a pairing connection waiting for its kind 19), `requestDeadline` after `.ready`, and
    /// never later than `admissionDeadline` after accept.
    static func deadline(known: Bool, readyAfter: Double?) -> Double {
        guard let readyAfter else { return known ? admissionDeadline : handshakeDeadline }
        return min(readyAfter + requestDeadline, admissionDeadline)
    }

    /// A connection's source as the per-source rules know it.
    struct Source: Hashable, Sendable {
        /// The address itself: an IPv4-mapped one as its IPv4 address, a link-local IPv6 one with
        /// its interface ("10.0.0.5", "2601:600:1:2::41", "fe80::1%en0").
        var address: String
        /// The addresses one host can take at will, which answer for each other: an IPv6 address's
        /// /64, since SLAAC and privacy addresses give a host any number in its prefix, with the
        /// interface for a link-local one (fe80::/64 is every link's): "2601:600:1:2::/64",
        /// "fe80::/64%en0". An IPv4 address is its own group.
        var group: String
    }

    /// The source of a connection from `bytes` (4 or 16), `scope` being the interface a link-local
    /// IPv6 address is scoped to.
    static func source(_ bytes: [UInt8], scope: String?) -> Source {
        let a = IPBytes.unscoped(IPBytes.unmapped(bytes))
        guard a.count == 16 else {
            let text = IPBytes.text(a)
            return Source(address: text, group: text)
        }
        let zone = IPBytes.isLinkLocal(a) ? "%" + (scope ?? "") : ""
        let prefix = Array(a[0..<8]) + [UInt8](repeating: 0, count: 8)
        return Source(address: IPBytes.text(a) + zone, group: IPBytes.text(prefix) + "/64" + zone)
    }

    /// The places for connections a door accepted and has not admitted, and what waiting in one
    /// costs. One per door (the Door runs it on its network queue). Pure: `now` is passed in, seconds
    /// on one monotonic clock; an id is the Door's for one connection.
    ///
    /// An address that is not known takes one of `sharedPlaces`, at most `placesPerSource` per
    /// group, unless its address or its group is backed off. A known address (it proved a paired key
    /// at `.ready` within `knownFor`) also takes the `reservedPlaces`, at most `placesPerSource`
    /// from the address, has `admissionDeadline` for its handshake, and is refused only while the
    /// address itself is backed off, never for its group. Every connection that ends unadmitted, and
    /// a pairing connection when its kind 19 comes (`End.request`), costs its address
    /// `charge(held:refused:)`, known or not: an address that is known, or that someone else on the
    /// network takes while its device is away, still pays for what it holds. Its group is
    /// charged the same while the address is not known, one address counting for `groupShare` at
    /// most. A paired key at `.ready` clears its address's failures and backoff, as before.
    struct Places {
        enum Arrival: Equatable {
            /// It waits in a place now; `known`: its address is known.
            case taken(known: Bool)
            /// Refused, all counted "limit" in the minute's summary: its address or its group is
            /// backed off; every place it may take is held; its source already waits in
            /// `placesPerSource`.
            case backedOff, full, source
        }

        /// How a connection left its place.
        enum End: Equatable {
            /// Admitted: a session at `.ready`, or a goodbye there to a paired key the door does not
            /// serve now. `paired`: its key is on the trust list, which makes its address known.
            case admitted(paired: Bool)
            /// A pairing connection's one kind 19 came: it leaves its place to be judged
            /// (`Door.readPairRequest`), and pays for the place as one that ended then would
            /// (`charge(held:refused:)`, never a refusal): a device sends its kind 19 as soon as TLS
            /// is up, so a tenth. The home door's verify block takes `sill-pair/1` with any key (an
            /// ask needs no window), so a stranger that completes TLS and sends a kind 19 just before
            /// its deadline (a later generation's `v`, answered `closed` with nothing shown) would
            /// otherwise hold every place for nothing, never backed off (the review of 2026-10-29).
            case request
            /// The door refused it: at least one failure.
            case refused
            /// It ended by itself before admission: closed, reset, a handshake that failed for the
            /// peer, an older Sill's plain try.
            case ended
            /// The Mac let it go (Direct Wireless turned off): nothing counted.
            case dropped
        }

        struct Entry: Equatable {
            let source: Source
            let acceptedAt: Double
            let known: Bool
            var readyAt: Double?
        }

        let backoff: Double
        private(set) var pending: [AnyHashable: Entry] = [:]
        /// By address and by group (their keys never meet: a group's ends in "/64…").
        private var charges: [String: [Charge]] = [:]
        /// One charge: when, how many failures, and the address charged (in a group's records, which
        /// of its addresses, for `groupShare`).
        private struct Charge { let at: Double; let weight: Double; let from: String }
        private var backedOffUntil: [String: Double] = [:]
        /// By address.
        private var provenAt: [String: Double] = [:]

        init(backoff: Double = DoorPolicy.backoffSeconds) { self.backoff = backoff }

        /// The address proved a paired key at `.ready` within `knownFor`.
        func isKnown(_ address: String, now: Double) -> Bool {
            provenAt[address].map { now - $0 < DoorPolicy.knownFor } ?? false
        }

        /// Refused at accept: its address is backed off, or its group is and the address is not
        /// known.
        func backedOff(_ s: Source, now: Double) -> Bool {
            if let until = backedOffUntil[s.address], now < until { return true }
            guard s.group != s.address, let until = backedOffUntil[s.group], now < until else { return false }
            return !isKnown(s.address, now: now)
        }

        /// The failures an address is charged with now (within `failureWindow`), or a group (within
        /// `groupFailureWindow`, each of its addresses counting for `groupShare` at most).
        func failures(_ key: String, now: Double) -> Double {
            Self.total((charges[key] ?? []).filter { now - $0.at < Self.window(key) }, key: key)
        }

        /// What `list` comes to for `key`: a group's addresses each for `groupShare` at most.
        private static func total(_ list: [Charge], key: String) -> Double {
            guard key.contains("/") else { return list.reduce(0) { $0 + $1.weight } }
            var each: [String: Double] = [:]
            for c in list { each[c.from, default: 0] += c.weight }
            return each.values.reduce(0) { $0 + min($1, DoorPolicy.groupShare) }
        }

        /// A key's window: a group's (its key has the prefix length, "/64") or an address's.
        private static func window(_ key: String) -> Double {
            key.contains("/") ? DoorPolicy.groupFailureWindow : DoorPolicy.failureWindow
        }

        /// A connection accepted from `s`: does it take a place?
        mutating func arrive(_ id: AnyHashable, _ s: Source, now: Double) -> Arrival {
            if backedOff(s, now: now) { return .backedOff }
            let known = isKnown(s.address, now: now)
            if known {
                guard pending.count < DoorPolicy.sharedPlaces + DoorPolicy.reservedPlaces else { return .full }
            } else {
                // The shared places in use: every waiting connection but the known ones in the
                // reserved places.
                let inReserved = min(pending.values.filter(\.known).count, DoorPolicy.reservedPlaces)
                guard pending.count - inReserved < DoorPolicy.sharedPlaces else { return .full }
            }
            let waiting = known ? pending.values.filter { $0.source.address == s.address }.count
                                : pending.values.filter { !$0.known && $0.source.group == s.group }.count
            guard waiting < DoorPolicy.placesPerSource else { return .source }
            pending[id] = Entry(source: s, acceptedAt: now, known: known)
            return .taken(known: known)
        }

        /// It reached `.ready`: from now its deadline is the kind 19's.
        mutating func ready(_ id: AnyHashable, now: Double) {
            guard var e = pending[id], e.readyAt == nil else { return }
            e.readyAt = now
            pending[id] = e
        }

        /// When it is refused if it still waits (on the `now` clock); nil when it holds no place.
        func deadline(_ id: AnyHashable) -> Double? {
            guard let e = pending[id] else { return nil }
            return e.acceptedAt + DoorPolicy.deadline(known: e.known, readyAfter: e.readyAt.map { $0 - e.acceptedAt })
        }

        /// It left its place. Returns what this backed off: its address, its group, both or neither.
        @discardableResult
        mutating func leave(_ id: AnyHashable, _ end: End, now: Double) -> [String] {
            guard let e = pending.removeValue(forKey: id) else { return [] }
            switch end {
            case .admitted(let paired):
                if paired { proved(e.source.address, now: now) }
                return []
            case .dropped:
                return []
            case .refused, .ended, .request:
                return charge(e.source, DoorPolicy.charge(held: Self.held(e, now: now), refused: end == .refused), now: now)
            }
        }

        /// What `e` is charged for holding its place: its wait up to the deadline an address that is
        /// not known has (the review of 2026-10-29, both its findings):
        /// - never past a deadline, where the door refuses it anyway: any longer is time the door
        ///   did not run, not time a source held a place against anyone: the Mac asleep (the
        ///   monotonic clock runs on through a sleep, the deadline's timer does not, so a connection
        ///   waiting as the Mac slept ended at the wake, hours "held"), or its queue held up (one
        ///   connection across a 20 s stop of the host cost 9.25 and backed its address off);
        /// - a known address's longer handshake (`admissionDeadline`) is time it is given, not time
        ///   it is charged for: charged to its own 10 s, a paired device whose dials stalled (a path
        ///   dying mid-handshake, the device suspended) was backed off sooner than one not known,
        ///   at two cuts at 10 s (4.1 each) or four of its reconnect's own let-gos at 5 s (1.6). So
        ///   it pays at most what an address not known can (1.1 for a handshake, 3.1 for a pairing
        ///   connection, its `.ready` counted at 4 s at the latest), still at least one when
        ///   refused: someone at a paired device's address holding its places is backed off within
        ///   30 s.
        private static func held(_ e: Entry, now: Double) -> Double {
            let readyAfter = e.readyAt.map { min($0 - e.acceptedAt, DoorPolicy.handshakeDeadline) }
            return min(now - e.acceptedAt, DoorPolicy.deadline(known: false, readyAfter: readyAfter))
        }

        /// One failure for a connection refused before it took a place (its origin). Returns what
        /// this backed off.
        @discardableResult
        mutating func refusedBeforeStart(_ s: Source, now: Double) -> [String] {
            charge(s, 1, now: now)
        }

        /// A paired key at `.ready` from `address`: known for `knownFor`, and what the address owes
        /// is forgiven, as before (its group keeps what its other addresses cost).
        private mutating func proved(_ address: String, now: Double) {
            provenAt[address] = now
            charges[address] = nil
            backedOffUntil[address] = nil
        }

        /// `weight` failures for the address, and for its group (an IPv6 address's /64, where it counts
        /// for `groupShare` at most) unless the address is known: a known one's own backoff is what
        /// bounds it, and its group's would not refuse it anyway.
        private mutating func charge(_ s: Source, _ weight: Double, now: Double) -> [String] {
            var backedOff: [String] = []
            let known = isKnown(s.address, now: now)
            if add(s.address, weight, from: s.address, threshold: DoorPolicy.failuresForBackoff, now: now) { backedOff.append(s.address) }
            if s.group != s.address, !known, add(s.group, weight, from: s.address, threshold: DoorPolicy.groupFailuresForBackoff, now: now) {
                backedOff.append(s.group)
            }
            return backedOff
        }

        /// `weight` more failures for `key`, charged for the address `from`; true when they reach
        /// `threshold` within its window, which backs `key` off and starts its count again.
        private mutating func add(_ key: String, _ weight: Double, from: String, threshold: Double, now: Double) -> Bool {
            var list = (charges[key] ?? []).filter { now - $0.at < Self.window(key) }
            list.append(Charge(at: now, weight: weight, from: from))
            // A tenth fifty times sums to a hair under 5 in binary: compare with a margin.
            guard Self.total(list, key: key) + 1e-9 >= threshold else {
                charges[key] = list
                return false
            }
            charges[key] = nil
            backedOffUntil[key] = now + backoff
            return true
        }

        /// Forgets stale records, so a scan from many addresses cannot grow them for ever; the known
        /// addresses keep the newest `maxRecords`.
        mutating func prune(now: Double) {
            if charges.count > Self.maxRecords {
                charges = charges.filter { key, list in list.contains { now - $0.at < Self.window(key) } }
            }
            if backedOffUntil.count > Self.maxRecords { backedOffUntil = backedOffUntil.filter { $0.value > now } }
            if provenAt.count > Self.maxRecords {
                provenAt = provenAt.filter { now - $0.value < DoorPolicy.knownFor }
                if provenAt.count > Self.maxRecords {
                    provenAt = Dictionary(uniqueKeysWithValues: provenAt.sorted { $0.value > $1.value }.prefix(Self.maxRecords).map { ($0.key, $0.value) })
                }
            }
        }

        static let maxRecords = 256

        /// How many sources each table remembers (the check's view of `prune`).
        var records: (charged: Int, backedOff: Int, known: Int) { (charges.count, backedOffUntil.count, provenAt.count) }
    }

    // MARK: An older Sill, for the menu

    /// How many plain tries (a handshake that failed with -9836 at the home door) one source makes
    /// within `olderSillSpan` before the menu says "An iPhone or iPad Needs Sill Updated". An older
    /// Sill tries again and again (a tap, then its reconnect every 2 to 10 s), while a TLS 1.2 client
    /// (a scanner, an old TLS library), which fails the same way, usually tries once: the menu waits
    /// for the third (the security review, 2026-09-27). The minute's summary counts every one.
    static let olderSillTries = 3
    static let olderSillSpan: Double = 60

    /// One more plain try from a source, at `now`, after its earlier ones (`tries`, in seconds on
    /// one clock): the tries still inside the span, this one included, and whether the menu's item
    /// is due now (the `olderSillTries`th of them, or any later one).
    static func olderSillTry(_ tries: [Double], now: Double) -> (tries: [Double], shown: Bool) {
        let kept = tries.filter { now - $0 < olderSillSpan } + [now]
        return (kept, kept.count >= olderSillTries)
    }

    // MARK: The ask (the home door's kind 19 "ask")

    enum Ask: Equatable, Sendable {
        /// Paired now, by itself, over the USB cable: kind 20 ok with `method` "cable".
        case pairNow
        /// A window shows a code: one opened for this ask (`opened`), or one already open. Kind 20
        /// "shown".
        case shown(opened: Bool)
        /// No window by itself: "this Mac" (the ask came from this Mac), "quiet" (this key or
        /// address had a device-opened window cancelled or stopped within 10 minutes) or "often" (3
        /// device-opened windows in the last 10 minutes). The words are the log's; the device only
        /// sees kind 20 "openOnMac".
        case openOnMac(String)
        /// The Mac is locked, or another user's session is on the console. Kind 20 "locked".
        case locked
    }

    /// The ask rule, first match wins (§4.2):
    /// 1. the Mac is locked, or the console is another user's → `locked`;
    /// 2. on the cable by the Mac's own rule (`cableSeen`: CableLink found an iPhone or iPad behind
    ///    the connection) and by the device's claim (`cableClaimed`: the ask's `cable: true`), and
    ///    no other key of that device on the trust list → `pairNow`;
    /// 3. a pairing window is open → `shown(opened: false)`;
    /// 4. from this Mac itself (loopback, or one of this Mac's own addresses: `isFromThisMac`) →
    ///    `openOnMac("this Mac")`: an app that can record the screen would otherwise ask, read the
    ///    code it put up and pair, turning Screen Recording into control of the Mac through Sill;
    /// 5. this key or address is quiet (a window it opened was cancelled on the Mac or stopped
    ///    within 10 minutes) → `openOnMac("quiet")`; `AskLimits.maxWindows` device-opened windows
    ///    in the last 10 minutes → `openOnMac("often")`;
    /// 6. otherwise → `shown(opened: true)`: a window opens for it.
    static func ask(unlocked: Bool, cableSeen: Bool, cableClaimed: Bool, otherKeyOfDevice: Bool, windowOpen: Bool,
                    fromThisMac: Bool, quiet: Bool, recentDeviceWindows: Int) -> Ask {
        if !unlocked { return .locked }
        if cableSeen && cableClaimed && !otherKeyOfDevice { return .pairNow }
        if windowOpen { return .shown(opened: false) }
        if fromThisMac { return .openOnMac("this Mac") }
        if quiet { return .openOnMac("quiet") }
        if recentDeviceWindows >= AskLimits.maxWindows { return .openOnMac("often") }
        return .shown(opened: true)
    }

    /// Kind 20's reason for an ask's answer; nil for `pairNow`, which is an ok.
    static func reason(_ a: Ask) -> String? {
        switch a {
        case .pairNow: return nil
        case .shown: return PairResult.shown
        case .openOnMac: return PairResult.openOnMac
        case .locked: return PairResult.locked
        }
    }

    /// The menu's "‹device› Wants to Pair" after an ask (§4.10, §6.4), 5 minutes from it: "showing"
    /// while the window this ask opened is up, "locked", "limit" (quiet or often); nil for a
    /// pairing, for a window that was already open, and always for an ask from this Mac, locked or
    /// not: "Click to show a code." under a name an app chose is one click from the code it wants.
    static func menuRequest(_ a: Ask, fromThisMac: Bool) -> String? {
        if fromThisMac { return nil }
        switch a {
        case .pairNow, .shown(opened: false): return nil
        case .shown(opened: true): return "showing"
        case .locked: return "locked"
        case .openOnMac: return "limit"
        }
    }

    /// Whether a connection comes from this Mac itself: a loopback source, or one that is one of
    /// this Mac's own addresses (InterfaceSnapshot's owner table), on any interface: the Simulator,
    /// a local tool, or any app dialing the Mac's own address on the cable's interface arrive so.
    /// An IPv4-mapped source counts as its IPv4 address, and link-local addresses compare without
    /// the kernel's embedded scope (`IPBytes.unscoped`).
    static func isFromThisMac(source: [UInt8], ownAddresses: Set<[UInt8]>) -> Bool {
        guard source.count == 4 || source.count == 16 else { return false }
        let s = IPBytes.unscoped(IPBytes.unmapped(source))
        if IPBytes.isLoopback(s) { return true }
        return ownAddresses.contains { IPBytes.unscoped(IPBytes.unmapped($0)) == s }
    }

    /// Whether another key than `fingerprint` already carries this iPhone's or iPad's cable ID
    /// (CableLink.deviceID, kept as PairedDevice.cableDevice): then the cable pairs nothing by
    /// itself and the ask gets the window. The same key may pair again; Remove frees the device.
    static func otherKeyOfDevice(_ cableDevice: String, fingerprint: String,
                                 paired: [(fingerprint: String, cableDevice: String?)]) -> Bool {
        paired.contains { $0.cableDevice == cableDevice && $0.fingerprint != fingerprint }
    }

    // MARK: Test hooks

    /// Which hosts honour the TEST ONLY hooks that bear on who gets in or on what pairing needs
    /// (§4.3): one that does not advertise and is not Sill.app's own code (`bundled`: the app's
    /// AppIdentity, by the code's signature and bundle, wherever it runs from; the CLI is never
    /// bundled). Any process of this user can start Sill.app's own executable, or a copy of it,
    /// with an environment and arguments, and it then runs with Sill's Screen Recording and
    /// Accessibility grants; Sill.app ignores them.
    static func isTestHost(advertises: Bool, bundled: Bool) -> Bool { !advertises && !bundled }

    /// TEST ONLY: SILL_TEST_ASK_FROM_THIS_MAC=1, on a test host only, judges an ask from this Mac
    /// as one from another device: the ask rule's step 4 and its menu rule are skipped, so the
    /// gates' local clients open windows and light the menu.
    static func testAsksAsDevice(testHost: Bool, environment: [String: String]) -> Bool {
        testHost && environment["SILL_TEST_ASK_FROM_THIS_MAC"] == "1"
    }
}
