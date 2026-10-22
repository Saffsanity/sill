import Foundation

// Reach from Anywhere (docs/relay-plan.md): a Mac's own private tailnet, its control plane reached
// through a HeadFwd relay, so a paired device reaches the Mac from any network without a VPN
// account or a port forward. What travels on it is Sill's own TLS 1.3 with both keys pinned, at a
// door of its own (the relay door, origin "vpn"), so the tailnet is a path and never a trust
// anchor: the relay, Tailscale's DERP servers and even the Mac's Headscale could at most refuse
// service.
//
// Three additions to the wire, all optional, for which an older peer is unchanged:
// - `MacInfo.relay` (kind 18, signed): the tailnet's control fingerprint and the relay's domain,
//   while the Mac's Reach from Anywhere is on and its tailnet is up.
// - Kind 61 `relayJoin`, device → host, `{}`: "give me a key", only on a paired session (sill/1 at
//   either door, a paired key) to a Mac whose kind 18 carries `relay`.
// - Kind 60 `relayInvite`, host → device: a single-use, ten-minute preauth key for that tailnet,
//   to that device alone, and only over a paired, pinned session. The device stores the
//   fingerprint and the domain, never the key.

/// Inside kind 18 while Reach from Anywhere is on: which tailnet, through which relay.
public struct RelayInfo: Codable, Hashable, Sendable {
    /// 32 lowercase hex characters: SHA-256 of the tailnet control plane's Noise public key
    /// ("mkey:…"), truncated. The relay routes by it (`https://<fingerprint>.<domain>`), and the
    /// device checks the key the relay serves against it before it sends anything.
    public var fingerprint: String
    /// The relay's domain: "headfwd.net".
    public var domain: String

    public init(fingerprint: String, domain: String) {
        self.fingerprint = fingerprint; self.domain = domain
    }

    /// Well-formed: a 32-character lowercase hex fingerprint and a plausible DNS name (letters,
    /// digits, hyphens and dots, at most 253 characters, with a dot, no empty label). Anything else
    /// is ignored by the device.
    public var isWellFormed: Bool {
        Self.isFingerprint(fingerprint) && Self.isDomain(domain)
    }

    public static func isFingerprint(_ s: String) -> Bool {
        s.utf8.count == 32 && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    public static func isDomain(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 253, s.contains(".") else { return false }
        for label in s.split(separator: ".", omittingEmptySubsequences: false) {
            guard (1...63).contains(label.utf8.count), label.first != "-", label.last != "-",
                  label.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7a) || $0 == 0x2d })
            else { return false }
        }
        return true
    }
}

/// Kind 61, device → host: asks for a key to join the Mac's tailnet. Empty in this generation.
public struct RelayJoin: Codable, Hashable, Sendable {
    public init() {}
}

/// Kind 60, host → device: the key, to the device that asked alone.
public struct RelayInvite: Codable, Hashable, Sendable {
    /// The tailnet and the relay, as kind 18's `relay`.
    public var relay: RelayInfo
    /// A Headscale preauth key ("hskey-auth-…"): single use, ten minutes, tagged for devices.
    /// Secret: never logged, never stored.
    public var key: String

    public init(relay: RelayInfo, key: String) { self.relay = relay; self.key = key }

    /// The most a key may be: Headscale's are under 100 characters.
    public static let maxKeyLength = 512

    public var isWellFormed: Bool {
        relay.isWellFormed && !key.isEmpty && key.utf8.count <= Self.maxKeyLength
            && key.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7f }
    }
}

/// The relay's rules, both ends: pure, so Tests/checks/relay checks them on their own.
public enum RelayPolicy {
    /// What the device dials through its tailnet: the Mac's node and its relay door's port.
    public static let macHost = "sill-mac"
    public static let doorPort = 7455
    /// How the Mac's card and log, and the device, name the route: "through Sill Relay".
    public static let serviceName = "Sill Relay"
    /// The least time between two keys for one connection (a device asks once per session).
    public static let inviteSpacing: TimeInterval = 30

    /// Host: whether a kind 61 on a session gets a key. Only a paired key (the session's TLS
    /// fingerprint is on the trust list) on a session that is not a pairing connection, while the
    /// Mac's tailnet is up, and not within `inviteSpacing` of the last one to this connection.
    public static func hostInvites(paired: Bool, relayReady: Bool, sinceLast: TimeInterval?) -> Bool {
        guard paired, relayReady else { return false }
        if let sinceLast, sinceLast < inviteSpacing { return false }
        return true
    }

    /// Device: whether to ask this Mac for a key on this session: the session is pinned to this
    /// saved Mac's key, the Mac's signed kind 18 carries a well-formed `relay`, and this device has
    /// not already joined that same tailnet (its fingerprint), nor asked on this session.
    public static func deviceAsks(pinned: Bool, offered: RelayInfo?, joined: String?, askedThisSession: Bool) -> Bool {
        guard pinned, !askedThisSession, let offered, offered.isWellFormed else { return false }
        return joined != offered.fingerprint
    }

    /// Device: whether a kind 60 is taken: well formed, on the session that asked, for the tailnet
    /// that session's Mac offers (its signed kind 18), never another.
    public static func deviceTakes(_ invite: RelayInvite, asked: Bool, offered: RelayInfo?) -> Bool {
        guard asked, invite.isWellFormed, let offered else { return false }
        return invite.relay == offered
    }
}
