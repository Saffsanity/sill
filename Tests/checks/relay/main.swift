// Reach from Anywhere (docs/relay-plan.md), the pure parts: Relay.swift's wire and RelayPolicy,
// MacInfo.relay in kind 18, RemoteDialPolicy.withRelay on the device, and the relay door's fixed
// origin judged by DoorPolicy and OriginPolicy as the remote door's rules judge it.
import Foundation
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }; fflush(stdout) }
func json(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

let fp = "0123456789abcdef0123456789abcdef"
let relay = RelayInfo(fingerprint: fp, domain: "headfwd.net")

// MARK: The kinds

check("kind 60 is relayInvite", StreamMessageKind(rawValue: 60) == .relayInvite)
check("kind 61 is relayJoin", StreamMessageKind(rawValue: 61) == .relayJoin)
for k: UInt8 in 33...46 {
    check("kind \(k) left to the open pull requests", StreamMessageKind(rawValue: k) == nil)
}
do {
    var header = StreamMessage(kind: .relayInvite, timestamp: 1, isKeyframe: false, payload: Data("{}".utf8)).serialized()
    check("a kind 60 header parses as relayInvite", StreamMessage.parseHeader(header)?.kind == .relayInvite)
    header[0] = 62
    check("a kind this build does not know parses as unknown", StreamMessage.parseHeader(header)?.kind == .unknown)
}

// MARK: RelayInfo

check("a well-formed relay", relay.isWellFormed)
check("a fingerprint of 31", !RelayInfo(fingerprint: String(fp.dropLast()), domain: "headfwd.net").isWellFormed)
check("a fingerprint of 33", !RelayInfo(fingerprint: fp + "0", domain: "headfwd.net").isWellFormed)
check("an uppercase fingerprint", !RelayInfo(fingerprint: fp.uppercased(), domain: "headfwd.net").isWellFormed)
check("a fingerprint that is not hex", !RelayInfo(fingerprint: String(fp.dropLast()) + "g", domain: "headfwd.net").isWellFormed)
for bad in ["", "headfwd", "headfwd.net.", ".headfwd.net", "head fwd.net", "-x.net", "x-.net", "HEADFWD.NET", "a..b",
            "headfwd.net/x", "headfwd.net:443", "user@headfwd.net", String(repeating: "a", count: 64) + ".net",
            String(repeating: "a.", count: 127) + "net"] {
    check("domain \(bad.prefix(30)) refused", !RelayInfo(fingerprint: fp, domain: bad).isWellFormed)
}
for good in ["headfwd.net", "relay.example.com", "x-1.y.z"] {
    check("domain \(good) taken", RelayInfo(fingerprint: fp, domain: good).isWellFormed)
}
check("RelayInfo's JSON", json(Wire.encode(relay)) == #"{"fingerprint":"0123456789abcdef0123456789abcdef","domain":"headfwd.net"}"#
      || json(Wire.encode(relay)) == #"{"domain":"headfwd.net","fingerprint":"0123456789abcdef0123456789abcdef"}"#)

// MARK: RelayInvite

let key = "hskey-auth-abcDEF123_-xyz"
check("an invite", RelayInvite(relay: relay, key: key).isWellFormed)
check("an invite with an empty key", !RelayInvite(relay: relay, key: "").isWellFormed)
check("an invite with a space in its key", !RelayInvite(relay: relay, key: "hskey auth").isWellFormed)
check("an invite with a newline in its key", !RelayInvite(relay: relay, key: "hskey\nauth").isWellFormed)
check("an invite with a non-ASCII key", !RelayInvite(relay: relay, key: "hskey-é").isWellFormed)
check("a key of 512 taken", RelayInvite(relay: relay, key: String(repeating: "a", count: 512)).isWellFormed)
check("a key of 513 refused", !RelayInvite(relay: relay, key: String(repeating: "a", count: 513)).isWellFormed)
check("an invite for a malformed relay", !RelayInvite(relay: RelayInfo(fingerprint: "x", domain: "headfwd.net"), key: key).isWellFormed)
do {
    let back = Wire.decode(RelayInvite.self, from: Wire.encode(RelayInvite(relay: relay, key: key)))
    check("an invite round-trips", back == RelayInvite(relay: relay, key: key))
    check("kind 61 is {}", json(Wire.encode(RelayJoin())) == "{}" && Wire.decode(RelayJoin.self, from: Data("{}".utf8)) != nil)
    check("kind 61 with more decodes (a later generation)", Wire.decode(RelayJoin.self, from: Data(#"{"v":2}"#.utf8)) != nil)
    check("an invite without its key does not decode", Wire.decode(RelayInvite.self, from: Data(#"{"relay":{"fingerprint":"\#(fp)","domain":"headfwd.net"}}"#.utf8)) == nil)
}

// MARK: MacInfo.relay in kind 18

do {
    let before = MacInfo(macID: "M", name: "Mac", issuedAt: 1, remoteAccess: true, remotePort: 7455, internet: false, addresses: [])
    let text = json(Wire.encode(before))
    check("a Mac without a relay writes no relay key (the same bytes as before)", !text.contains("relay"))
    var with = before
    with.relay = relay
    let t2 = json(Wire.encode(with))
    check("a Mac with one writes it", t2.contains("\"relay\"") && t2.contains(fp))
    check("kind 18 with a relay round-trips", Wire.decode(MacInfo.self, from: Wire.encode(with))?.relay == relay)
    // An older device's MacInfo: the same fields, no relay. It must read a new kind 18.
    struct OlderMacInfo: Codable { var v: Int; var macID: String; var name: String; var issuedAt: Double; var remoteAccess: Bool
        var remotePort: Int; var internet: Bool; var addresses: [MacAddress] }
    let older = Wire.decode(OlderMacInfo.self, from: Wire.encode(with))
    check("an older device reads a kind 18 that carries a relay", older?.macID == "M" && older?.remotePort == 7455)
    check("a kind 18 from before decodes with no relay", Wire.decode(MacInfo.self, from: Data(text.utf8))?.relay == nil)
    let made = MacInfo(macID: "M", name: "Mac", issuedAt: 1, remoteAccess: true, remotePort: 7455, internet: false, addresses: [], relay: relay)
    check("the init keeps the relay it is given (the host's currentInfo)", made.relay == relay)
}

// MARK: RelayPolicy, host

check("host: a paired key, the tailnet up, first ask: a key", RelayPolicy.hostInvites(paired: true, relayReady: true, sinceLast: nil))
check("host: an unpaired key: none", !RelayPolicy.hostInvites(paired: false, relayReady: true, sinceLast: nil))
check("host: the tailnet not up: none", !RelayPolicy.hostInvites(paired: true, relayReady: false, sinceLast: nil))
check("host: again within 30 s: none", !RelayPolicy.hostInvites(paired: true, relayReady: true, sinceLast: 29.9))
check("host: again at 30 s: a key", RelayPolicy.hostInvites(paired: true, relayReady: true, sinceLast: 30))
check("the spacing is 30 s", RelayPolicy.inviteSpacing == 30)

// MARK: RelayPolicy, device

check("device: asks a pinned session's Mac that offers one", RelayPolicy.deviceAsks(pinned: true, offered: relay, joined: nil, askedThisSession: false))
check("device: never on an unpinned session", !RelayPolicy.deviceAsks(pinned: false, offered: relay, joined: nil, askedThisSession: false))
check("device: never when the Mac offers none", !RelayPolicy.deviceAsks(pinned: true, offered: nil, joined: nil, askedThisSession: false))
check("device: never twice a session", !RelayPolicy.deviceAsks(pinned: true, offered: relay, joined: nil, askedThisSession: true))
check("device: not for the tailnet it joined", !RelayPolicy.deviceAsks(pinned: true, offered: relay, joined: fp, askedThisSession: false))
check("device: for another tailnet of the same Mac (set up again)",
      RelayPolicy.deviceAsks(pinned: true, offered: relay, joined: "f" + fp.dropFirst(), askedThisSession: false))
check("device: never for a malformed offer",
      !RelayPolicy.deviceAsks(pinned: true, offered: RelayInfo(fingerprint: fp, domain: "x"), joined: nil, askedThisSession: false))
let invite = RelayInvite(relay: relay, key: key)
check("device: takes the key it asked for, for the tailnet offered", RelayPolicy.deviceTakes(invite, asked: true, offered: relay))
check("device: not one it never asked for", !RelayPolicy.deviceTakes(invite, asked: false, offered: relay))
check("device: not one with no offer on this session", !RelayPolicy.deviceTakes(invite, asked: true, offered: nil))
check("device: not one for another tailnet",
      !RelayPolicy.deviceTakes(RelayInvite(relay: RelayInfo(fingerprint: "f" + fp.dropFirst(), domain: "headfwd.net"), key: key), asked: true, offered: relay))
check("device: not one through another relay",
      !RelayPolicy.deviceTakes(RelayInvite(relay: RelayInfo(fingerprint: fp, domain: "evil.example"), key: key), asked: true, offered: relay))
check("device: not a malformed one", !RelayPolicy.deviceTakes(RelayInvite(relay: relay, key: ""), asked: true, offered: relay))

// MARK: The device's dial order

typealias D = RemoteDialPolicy
let addresses = [MacAddress(host: "mac.tail1.ts.net", kind: MacAddress.vpn, via: "Tailscale"),
                 MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi‑Fi")]
let ordered = D.order(addresses, remotePort: 7455, lastWorked: nil, localIPv4: [])
let fw = (host: "127.0.0.1", port: 62000)
do {
    let with = D.withRelay(ordered, forwarder: fw, lastWorked: nil)
    check("the relay is last", with.last?.host == "127.0.0.1" && with.last?.port == 62000 && with.count == ordered.count + 1)
    check("the others keep their order", Array(with.dropLast()) == ordered)
    check("the relay's candidate is a VPN through Sill Relay", with.last?.kind == MacAddress.vpn && with.last?.via == "Sill Relay")
    check("isRelay names it", with.last.map(D.isRelay) == true && !ordered.contains(where: D.isRelay))
    check("a test host's 127.0.0.1 is not the relay", !D.isRelay(D.Candidate(host: "127.0.0.1", port: 17455, kind: MacAddress.lan, via: "This Mac")))
    let first = D.withRelay(ordered, forwarder: fw, lastWorked: D.relayKey)
    check("the relay first when it won last time", first.first.map(D.isRelay) == true && Array(first.dropFirst()) == ordered)
    check("no forwarder: unchanged", D.withRelay(ordered, forwarder: nil, lastWorked: D.relayKey) == ordered)
    check("a forwarder on port 0: unchanged", D.withRelay(ordered, forwarder: ("127.0.0.1", 0), lastWorked: nil) == ordered)
    let twice = D.withRelay(with, forwarder: fw, lastWorked: nil)
    check("the relay is listed once", twice.filter(D.isRelay).count == 1)
    check("the relay's lastWorked key is fixed (its port changes with each launch)", D.relayKey == "relay")
}

// MARK: The relay door's origin

// Every connection at the relay door comes from 127.0.0.1 (sill-net); RelayDoor fixes its origin to
// .vpn. The remote door's rules then treat it as away from home: admitted while Remote Access is on
// whatever the internet switch, never peer-to-peer, never this Mac itself.
check("the remote door admits the relay's origin with internet access off", DoorPolicy.admitsBeforeStart(.remote, origin: .vpn, internetAccess: false))
check("the home door never admits it", !DoorPolicy.admitsBeforeStart(.home, origin: .vpn, internetAccess: true))
check("its label is through Sill Relay", OriginPolicy.label(.vpn, interface: nil, serviceName: RelayPolicy.serviceName) == "through Sill Relay")
check("as loopback it would read by address (why the origin is fixed)", OriginPolicy.label(.loopback, interface: nil, serviceName: nil) == "by address")
var t = DoorPolicy.Trust()
t.paired = true; t.remoteAccess = true
check("a paired key at .ready: a session", DoorPolicy.atReady(.remote, alpn: RemoteTLS.sessionALPN, t, remoteSessions: 0) == .session)
t.remoteAccess = false
check("Remote Access off: goodbye remoteOff", DoorPolicy.atReady(.remote, alpn: RemoteTLS.sessionALPN, t, remoteSessions: 0) == .goodbye(Goodbye.remoteOff))
t.remoteAccess = true; t.paired = false
check("an unpaired key: refused", DoorPolicy.atReady(.remote, alpn: RemoteTLS.sessionALPN, t, remoteSessions: 0) == .refuse("unpaired"))
check("an ask at the relay door is closed (no window by asking from afar)", DoorPolicy.pairing(.remote, method: PairRequest.ask, version: PairRequest.version) == .closed)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
