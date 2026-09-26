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

    /// A remote door's sessions at once; the ninth gets goodbye `busy` (RemoteServer.maxSessions).
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
        /// deadline), then treat it as `pairing(_:method:)` says.
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

    /// How a door treats the one kind 19 of a pairing connection it admitted.
    enum Pairing: Equatable, Sendable {
        /// The ask rule (`ask(…)`): the home door's "pair me".
        case ask
        /// The pairing window judges its proof: "qr" and "code", and any other method, which the
        /// window counts as a wrong proof, as the remote door always has.
        case window
        /// Answered `closed` at once with no try counted: an ask at the remote door, which never
        /// opens a window or pairs by itself. The window never sees it.
        case closed
    }

    static func pairing(_ door: Door, method: String) -> Pairing {
        guard method == PairRequest.ask else { return .window }
        return door == .home ? .ask : .closed
    }

    // MARK: A handshake that failed

    enum HandshakeRefusal: Equatable, Sendable {
        /// Counted under this word in the minute's summary, and one failure toward its source's
        /// backoff (5 in 60 s → refused for 300 s).
        case refused(String)
        /// Plain bytes at a TLS home door (-9836): an older Sill. Counted "older" in the summary and
        /// shown in the menu, never toward the backoff: the backoff is checked when a connection is
        /// accepted, before any key is seen, so a device that retried plainly and was then updated
        /// would have its new build refused for up to 5 minutes.
        case olderSill
    }

    /// What a handshake that failed before admission counts as, from the TLS status on the Mac's
    /// side (measured on loopback, 2026-09-24 and 2026-09-25, H0's P4): the verify block refused
    /// the key (-9808), no certificate (-9863), an application protocol the door does not offer
    /// (-9810), an HTTP request (-9858), and not TLS 1.3 (-9836: TLS 1.2, or any plain Sill
    /// message, whose header's first timestamp bytes are never a TLS version). Nil for a peer that
    /// went away by itself (-9816, a reset, -9825 when it refused the Mac's key): no count at all.
    static func handshakeRefusal(_ door: Door, status: Int32) -> HandshakeRefusal? {
        switch status {
        case -9836 where door == .home: return .olderSill
        case -9808, -9863, -9810, -9836, -9858: return .refused("unpaired")
        default: return nil
        }
    }

    // MARK: The ask (the home door's kind 19 "ask")

    enum Ask: Equatable, Sendable {
        /// Paired now, by itself, over the USB cable: kind 20 ok with `method` "cable".
        case pairNow
        /// A window shows a code: one opened for this ask (`opened`), or one already open. Kind 20
        /// "shown".
        case shown(opened: Bool)
        /// No window by itself: "this Mac" (the ask came from this Mac), "quiet" (this key or
        /// address had a device-opened window closed unused within 10 minutes) or "often" (3
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
    /// 5. this key or address is quiet → `openOnMac("quiet")`; `AskLimits.maxWindows`
    ///    device-opened windows in the last 10 minutes → `openOnMac("often")`;
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
    /// not: "Show a Code…" under a name an app chose is one click from the code it wants.
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
    /// (§4.3): one that does not advertise and is not a .app's executable. Any process of this
    /// user can start Sill.app's own executable with an environment and arguments, and it then
    /// runs with Sill's Screen Recording and Accessibility grants; the bundle ignores them.
    static func isTestHost(advertises: Bool, bundled: Bool) -> Bool { !advertises && !bundled }

    /// TEST ONLY: SILL_TEST_ASK_FROM_THIS_MAC=1, on a test host only, judges an ask from this Mac
    /// as one from another device: the ask rule's step 4 and its menu rule are skipped, so the
    /// gates' local clients open windows and light the menu.
    static func testAsksAsDevice(testHost: Bool, environment: [String: String]) -> Bool {
        testHost && environment["SILL_TEST_ASK_FROM_THIS_MAC"] == "1"
    }
}
