# Remote access: bring your own VPN or public IP — the plan

2026-09-24. The judging step's final plan. It stands alone: the implementer needs no other design
document. Written from a read-only survey of `/Users/noah/Downloads/winstream-ipad-settings`;
nothing in either checkout was changed and no host was started. Line numbers are at origin/main
a9cc248 unless marked "(fixes)", which means the `direct-wireless-fixes` head e51f254.

**Noah's request (2026-09-23):** "implement the ability to bring your own VPN/public IP so that you
can use this outside of your home WiFi network."

**Reading of it.** The user brings the reachability: a VPN (Tailscale, WireGuard, a work VPN) or a
port forward on the home router to a public IP. Sill connects through it when Bonjour cannot see
the Mac, and the Mac makes its addresses easy to find. No hole punching, no relay, no server of
ours, Apple frameworks only.

---

## Decision

### The base, and Noah's correction

Noah is right: PRs #3 and #4 are merged, and #5 too.

- origin/main is a9cc248, "Merge pull request #5" (2026-09-24 15:45). Its history holds ba320da
  ("Merge pull request #3", menu-bar-app) and 610d3ee ("Merge pull request #4",
  ipad-host-settings). Its tree is identical to `direct-wireless` 22209db.
- The only thing that says otherwise is the local `main` ref: it is still at 21287af
  (2026-09-22), 33 commits behind origin/main. Anything that compares against `main` reports #3 and
  #4 as unmerged. Compare with origin/main only; fast-forwarding local `main` is Noah's call (this
  workflow changed no git state).
- **Branch `remote-access` from origin/main after `git fetch`.**
- Work in flight: `direct-wireless-fixes` (0cf25ae host, e51f254 iOS) adds `ClientLink`, the host
  disconnecting AWDL clients when Direct Wireless turns off, and on the device `directWait` (6 s),
  `networkGrace` (10 s), `NetworkSightings` and `moveToNetwork`. This plan's reconnect order builds
  on those. If that branch has merged when work starts, branch from origin/main. If not, branch from
  its head and rebase onto origin/main once it merges. Either way, re-read StreamServer.swift,
  StreamClient.swift, DiscoveryPolicy.swift, ContentView.swift and HostSettingsPanel.swift before
  editing them.

### The security verdict, plainly

**Shipping a port that is reachable from the internet, or from a VPN that others share, without
per-device pairing and encryption is not acceptable.**

- Today any socket that connects gets the Mac's name, every window title, bundle ID and icon, the
  app list, thumbnails and a forced keyframe (StreamServer.swift:370-393, StreamCoordinator.swift:
  141-150, :1208-1224).
- It can then stream the whole Desktop, type and click as the user (⌘Space → Terminal: commands as
  the user), launch apps, close windows and change saved settings (StreamCoordinator.swift:447-512).
- All of it is plaintext, including passwords typed from the device.
- The listener is already a `tcp46` wildcard that accepts on Tailscale's utun. Scanners find a
  forwarded IPv4 port within hours.
- A shared 100-bit key over TLS-PSK (design d0) is cryptographically sound, but it is not pairing:
  - one bearer secret for every device, and no per-device revocation;
  - TLS 1.2 legacy PSK suites, which are unproven on iOS;
  - a channel that milestone 5 would throw away.

This plan ships the remote port only behind pairing and mutual TLS 1.3 with pinned keys.

### Scores (0–10; implementation risk scored so that 10 is the lowest risk)

| Criterion | d0 minimal | d1 security-first | d2 UX-first |
|---|---|---|---|
| Security for an internet-reachable port | 6 | 10 | 8 |
| High-RTT link, and the existing discovery (Bonjour, Direct rows) | 8 | 7 | 7 |
| Fit with M5 iCloud pairing (nothing thrown away) | 4 | 10 | 9 |
| Native feel on Mac, iPad and the Duo sizes | 5 | 7 | 9 |
| Implementation risk | 6 | 3 | 5 |
| Adherence to the BRIEF and CLAUDE.md | 7 | 5 | 9 |
| **Overall (mean)** | **6.0** | **7.0** | **7.8** |

**d0, minimal (6.0).** A second, TLS 1.2 ECDHE-PSK listener with one 100-bit key per Mac, delivered
as a `sill://` link, a QR code or typed.
- Strongest on the slow link: register at ready, a 1 MB cap, a kind 17 limit, eviction by silence,
  and keyframe pacing. All of these are grafted below.
- But the key is a shared bearer secret, shown in Settings and carried in a claimable URL scheme,
  with no per-device revocation (Reset Key drops everyone).
- Its channel rests on TLS 1.2 PSK suites passed as raw values: probed on macOS only, and a
  non-forward-secret fallback.
- M5 would replace the channel, the key UI and the link.
- Typing a 20-character key is not native.

**d1, security-first (7.0).** Mutual TLS 1.3 and pairing on every path, the LAN included.
- The best security:
  - PBKDF2-hardened typed code;
  - a rotating Bonjour tag;
  - revocation;
  - pre-auth caps;
  - it closes the café, radio-range and loopback confused-deputy exposure.
- The best M5 fit.
- But it pulls M5's pairing onto the home network now. A Mac at home no longer "just appears"
  usable, which pre-empts the decision CLAUDE.md reserves for M5 ("iCloud auto-pairing, Mac just
  appears").
- It is a protocol break on every path, including the CLI and all existing test tooling.
- It changes the CLI's default output (a new startup line), against the byte-for-byte rule.
- The largest scope: about M5's 2–4 weeks.

**d2, UX-first (7.8), the winner.**
- The home door stays exactly as it is until M5, apart from an origin gate and caps. That respects
  the M5 decision, keeps the CLI default path byte-identical and keeps every existing gate valid.
- A separate remote door with pairing and pinned TLS 1.3.
- One QR scan pairs the device and saves the Mac.
- A signed kind 18 keeps addresses current over any connection.
- "Pair This iPad…" from the panel at home.
- Per-cause failure copy, and the most careful Duo layouts (the crease, short heights, narrow
  iPhones).
- M5 inherits everything.
- Its weak points are fixed by the grafts below:
  - a typed code with no key stretching;
  - a static Mac ID broadcast in TXT;
  - pairing that silently turns Remote Access on;
  - a frame-rate-based slow-link callout, which a still window would trip.

### What the final plan takes from each

- **From d2 (the frame):**
  - two doors;
  - a fixed remote port 7455;
  - the QR code that carries the identity, the addresses and a secret;
  - signed kind 18;
  - kind 21 "Pair This iPad…";
  - the Remote Access pane and the pairing window;
  - Add a Mac with an embedded scanner;
  - Remote rows and their menus;
  - the panel's route line and Away from home group;
  - failure copy by cause;
  - the layouts per size;
  - the CLI's throwaway `--remote` identity;
  - excluding Sill's own windows from the Desktop stream.
- **From d1:**
  - the typed code hardened with PBKDF2, as digits so the Duo's number pad works;
  - the rotating TXT recognition tag instead of a stable ID;
  - a goodbye message, so the device can say why;
  - `SafeText` for every device-supplied name;
  - a verify block that reads a lock-protected snapshot and never waits on the main actor;
  - SNI "sill", P-256 only, and the ALPN check;
  - per-source backoff;
  - cancelling failed connections at once;
  - a dial order that knows the device's own subnet;
  - "Pair iPhone or iPad…" in the status menu;
  - keeping the Mac from idle sleep while a remote device is connected;
  - the Python standard library TLS test client.
- **From d0:**
  - keyframe pacing and spaced forced keyframes for remote clients;
  - eviction by silence for remote clients;
  - the 1 MB client message cap and the kind 17 limit on both doors;
  - register at `.ready`;
  - a shaping relay for headless slow-link tests;
  - the strict address parser;
  - the TLS error mapping;
  - a 120 s automatic redial window;
  - never an automatic dial at launch.
- **New here:**
  - two ALPN values, so a pairing connection is told from a session before any data;
  - a pairing never turns Remote Access on by itself;
  - the slow-link callout judged by round trip;
  - a pin mismatch on a LAN-kind address does not count as "wrong Mac";
  - pairing dials go one address at a time (pairing is single-use).
- **Rejected:**
  - d1's pairing on the home network (open question 1);
  - d1's moving a live session from a remote route to the network (later);
  - d0's shared key and its link.

---

## Final plan

### 1. Scope

**In this step:**

1. **The home door** (today's listener) keeps serving the home network and Direct Wireless as now.
   It gains:
   - an origin gate: only loopback, link-local (AWDL included) and this Mac's own networks;
   - a 1 MB cap on client messages;
   - a kind 17 limit;
   - registration at `.ready`;
   - failed connections cancelled.
2. **The remote door**, new: its own listener on a fixed port, TLS 1.3 only, both sides present
   self-signed P-256 certificates, each pins the other's key.
   - Paired devices only.
   - It runs while Remote Access (Mac-only, off by default) is on, or while a pairing window is
     open.
   - Internet sources are refused unless the Mac's internet switch (off by default) is on.
3. **Pairing:**
   - started at the Mac (the menu, the pane) or requested by a device at home;
   - a QR code (128-bit secret), and a 12-digit typed code as the fallback;
   - Paired Devices with Remove.
4. **Addresses.** The Mac lists its own:
   - VPN services by name, with Tailscale's MagicDNS name when it resolves;
   - this network;
   - the router's public IPv4, asked read-only, only with the internet switch on;
   - an optional dynamic DNS name;
   - a stable global IPv6.

   It signs them (kind 18). Paired devices save them and keep them current.
5. **The device:**
   - "Add a Mac…";
   - Remote rows;
   - a reconnect order of network, then Direct, then saved addresses;
   - "connected" meaning the first window list on remote routes;
   - liveness on every route;
   - caps on what the host sends;
   - a route line in the panel;
   - an Away from home group;
   - "Pair This iPad…";
   - `sill://pair` links, always behind a confirmation.
6. **Link basics:**
   - remote sessions ask for 60 fps;
   - a "Low — 4 Mbps" preset;
   - eviction by silence, a 15 s drain backstop and keyframe pacing for remote clients;
   - a slow-link callout.

**Not in this step:**

- pairing or encryption on the home network (M5; open question 1);
- iCloud;
- hole punching, relays, STUN or "what's my IP" services;
- opening router ports (UPnP, NAT-PMP or PCP mappings);
- updating dynamic DNS;
- "is my port reachable" checks;
- waking or unlocking a Mac;
- adaptive bitrate, ack-based pacing, QUIC;
- moving a live session between routes;
- moving the Direct Wireless memory and the window order from the Bonjour or Mac name to the Mac
  ID;
- audio and multi-window (out of v1).

### 2. The design on one page

```
                         ┌────────────────────── Mac (Sill.app / SillHost) ─────────────────────────┐
 device at home ──────▶  │ HOME DOOR  plain TCP, _sill._tcp (+TXT r=tag), ephemeral port             │
 (Bonjour / Direct row)  │   admits: loopback · link-local (awdl too) · this Mac's own networks      │
                         │   refuses: anything through a tunnel, anything from the internet          │
                         │                                                                           │
 device away ─────────▶  │ REMOTE DOOR  TLS 1.3, both keys pinned, port 7455, no Bonjour             │
 (VPN / port forward)    │   ALPN sill/1: a session (paired devices, Remote Access on)               │
                         │   ALPN sill-pair/1: pairing (only while a pairing window is open)         │
                         │   refuses internet sources before TLS unless "Allow connections from      │
                         │   the internet" is on                                                     │
                         │ Both doors: the same framing and kinds; kind 18 (signed addresses) on     │
                         │ both, to every session                                                    │
                         └───────────────────────────────────────────────────────────────────────────┘
```

**Only the Mac widens exposure.**
- Remote Access, the internet switch, the port and pairing have no device-writable field.
- They are not in `StreamSettings`, `HostSettingsChange` or `DeviceSettings.accepted`.
- A remote session cannot change Direct Wireless.

**The honest limit.** The home network stays as open as it is today until M5: anyone who can reach
the home door (the same Wi‑Fi, radio range with Direct Wireless on, or a local process) can do what
the Mac's user can. The origin gate stops that door from being reached through a VPN or from the
internet, which it can be today.

### 3. Wire protocol

#### 3.1 New kinds (`Sources/StreamProtocol/StreamMessage.swift`, continuing the enum)

```swift
case macInfo = 18        // host → device: JSON SignedMacInfo (Remote.swift) — who this Mac is and how to reach
                         // it from afar, signed with its identity key. In the catalog right after kind 16, on both
                         // doors, and again whenever it changes. Only from a host with an identity (Sill.app always;
                         // SillHost with --remote)
case pairRequest = 19    // device → host: JSON PairRequest — the one message of a pairing connection (ALPN
                         // sill-pair/1), at most 4 KB, within 10 s of the connection
case pairResult = 20     // host → device: JSON PairResult — the answer to 19; the host then closes the connection
case pairingWanted = 21  // device → host, empty payload: "show your pairing code" (Pair This iPad…). Home door only,
                         // from this Mac's own networks, at most once per 30 s per connection; ignored elsewhere
case goodbye = 22        // host → device: JSON Goodbye — why the host is about to close this session
```

- Older readers map unknown kinds to `.unknown` and skip them (StreamMessage.swift:69-71), so both
  sides stay compatible.
- Kinds 16 and 17 are untouched. The only change in their world is one new allowed bitrate value,
  the Low preset (§7.11).
- **New constants** in StreamMessage.swift:
  - `maxClientPayload = 1 << 20`;
  - `maxPairingPayload = 4096`;
  - `maxFramePayload = 32 << 20`;
  - `maxOtherHostPayload = 4 << 20`.

#### 3.2 Payloads (`Sources/StreamProtocol/Remote.swift`, new)

```swift
/// One way to reach the Mac from afar. Plain values, never enums (an unknown case would fail an older reader).
public struct MacAddress: Codable, Hashable, Sendable {
    public var host: String      // "mac-mini.tail1234.ts.net", "100.101.102.103", "fd7a:115c:a1e0::1234" (no brackets)
    public var port: Int?        // nil: MacInfo.remotePort. Set only for an address name with another outside port
    public var kind: String      // "vpn" | "lan" | "internet"
    public var via: String       // "Tailscale", "Wi‑Fi", "Router", "Address name", "IPv6", "VPN (utun6)"
}

/// Inside kind 18. Nothing here is secret: whoever can connect at all already shares a network with the Mac.
public struct MacInfo: Codable, Hashable, Sendable {
    public var v: Int                 // 1
    public var macID: String          // 16 Crockford characters (§3.4)
    public var name: String           // the Mac's name, SafeText
    public var issuedAt: Double       // seconds since 1970; a device takes only a newer one
    public var remoteAccess: Bool     // the Mac's switch
    public var remotePort: Int        // the configured remote port, also while Remote Access is off (pairing uses it)
    public var internet: Bool         // "Allow connections from the internet"
    public var addresses: [MacAddress]   // dial order (§4.8); [] while Remote Access is off and no window is open
}

/// Kind 18. `info` is the exact JSON bytes of a MacInfo; `sig` covers those bytes.
public struct SignedMacInfo: Codable, Sendable {
    public var info: String           // base64 of MacInfo's JSON bytes
    public var key: String            // base64 of the Mac's public key, X9.63 (65 bytes)
    public var sig: String            // base64 DER ECDSA P-256 / SHA-256 over the `info` bytes
}

/// Kind 19.
public struct PairRequest: Codable, Sendable {
    public var v: Int                 // 1
    public var method: String         // "qr" | "code"
    public var proof: String          // base64url(proof_D) (§3.6)
    public var name: String           // "iPad" (the Mac applies SafeText)
    public var model: String?         // "iPad14,1"
}

/// Kind 20.
public struct PairResult: Codable, Sendable {
    public var ok: Bool
    public var proof: String?          // ok: base64url(proof_M), checked by the device before it saves anything
    public var macID: String?          // ok
    public var name: String?           // ok: the Mac's name
    public var recognitionKey: String? // ok: base64url, 32 bytes: resolves the TXT tag (§3.5); never sent elsewhere
    public var reason: String?         // not ok: "code" | "closed" | "expired" | "stopped" | "busy"
    public var triesLeft: Int?         // with "code"
    public var retryAfter: Double?     // with "busy", seconds
}

/// Kind 22.
public struct Goodbye: Codable, Sendable {
    public var reason: String          // "removed" | "remoteOff" | "internetOff" | "quit" | "busy"
}
```

**Examples as they cross the wire.**

```json
// kind 18 (SignedMacInfo); the decoded `info`:
{"v":1,"macID":"A3C5HR4RBV67YR21","name":"Mac mini","issuedAt":1790265600.5,
 "remoteAccess":true,"remotePort":7455,"internet":false,
 "addresses":[{"host":"mac-mini.tail1234.ts.net","kind":"vpn","via":"Tailscale"},
              {"host":"100.101.102.103","kind":"vpn","via":"Tailscale"},
              {"host":"fd7a:115c:a1e0::1234","kind":"vpn","via":"Tailscale"},
              {"host":"192.168.1.20","kind":"lan","via":"Wi‑Fi"}]}
// with the internet switch on, these follow in this order:
//   {"host":"home.example.net","port":17455,"kind":"internet","via":"Address name"}
//   {"host":"203.0.113.9","kind":"internet","via":"Router"}
//   {"host":"2001:db8::20","kind":"internet","via":"IPv6"}

// kind 19
{"v":1,"method":"qr","proof":"AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo","name":"iPad","model":"iPad14,1"}
// kind 20
{"ok":true,"proof":"XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE","macID":"A3C5HR4RBV67YR21","name":"Mac mini",
 "recognitionKey":"ERERERERERERERERERERERERERERERERERERERERERE"}
{"ok":false,"reason":"code","triesLeft":4}
{"ok":false,"reason":"busy","retryAfter":2}
// kind 22
{"reason":"removed"}
```

Every byte string is base64url without padding, except `SignedMacInfo`'s fields, which use plain
base64 (they are bulk). All JSON goes through the existing `Wire` helpers.

#### 3.3 The remote door's TLS and TCP (`Sources/StreamProtocol/RemoteTLS.swift`, new; imports Network)

One builder serves the host, the device and the tests:

`RemoteTLS.options(identity: sec_identity_t, role: Role, verify: @escaping (Data?) -> Bool, queue: DispatchQueue) -> NWProtocolTLS.Options`

where `Role` is `.server` or `.client(alpn: String)`.

**Both ends:**
- `sec_protocol_options_set_min_tls_protocol_version(.TLSv13)` and `set_max_tls_protocol_version(.TLSv13)`.
- `set_local_identity`.
- `set_tls_tickets_enabled(false)` and `set_tls_resumption_enabled(false)`. Resumption would skip the
  certificate, so a removed device could come back on an old ticket. With both off, the server's
  verify block ran on 3 of 3 reconnects (probe, re-run 2026-09-24).
- **The verify block** decides trust entirely:
  - it never calls `SecTrustEvaluate` (names, dates and chains mean nothing here);
  - it takes the leaf from `SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue())`;
  - it requires a P-256 key, via `SecCertificateCopyKey` and a 65-byte `SecKeyCopyExternalRepresentation`;
  - it computes the fingerprint (§3.4) and calls `verify(fp)`.

**Server:**
- `set_peer_authentication_required(true)`.
- ALPN list `["sill/1", "sill-pair/1"]` (`add_tls_application_protocol` twice).

**Client:**
- ALPN exactly one of the two.
- `set_tls_server_name("sill")`, so a DDNS or MagicDNS name never goes out in clear SNI. The Mac
  ignores SNI.

**At `.ready`,** both ends read:
- the negotiated ALPN, with `sec_protocol_metadata_copy_negotiated_protocol` (the `get_` form is
  deprecated since macOS 15.5 and iOS 18.5);
- the peer leaf, with `sec_protocol_metadata_access_peer_certificate_chain`.

They close the connection on an unexpected ALPN or an unexpected key.

**TCP and parameters:**
- `noDelay`;
- keepalive 5 s idle, 2 s interval, 3 probes;
- `connectionDropTime = 15` (unacknowledged retransmits; a slow but live link is not affected);
- device dials `connectionTimeout = 10`;
- `serviceClass = .interactiveVideo`;
- `includePeerToPeer = false`;
- no Bonjour service on the remote door.

**Inside TLS:** the same 14-byte header and the same kinds.

**Measured on loopback (the d1 probe, re-run by the judge on 2026-09-24):**

| Case | Result |
|---|---|
| Mutual TLS 1.3 | Ready in 12–16 ms; suite 0x1302 |
| The server refuses the client's key | The client is `.ready`, then its first read fails with -9825 about 2 ms later |
| The client's pin does not match | The client goes `.waiting(-9808)` and never sends its certificate |
| The client sends no certificate | -9829 |
| A plain TCP client on the TLS listener | The server fails with -9858 at 3 ms. The client sees EOF only once the server cancels, so cancel at once |
| A TLS client against a plain listener that greets first | `.waiting(-9836)` |
| Cost | TLS 0.9 ms of CPU per MB for both ends, plain TCP 0.4 |

#### 3.4 Identities (`Sources/StreamProtocol/RemoteIdentity.swift`, new; Foundation, Security, CryptoKit)

- **Keys.** P-256 (`kSecAttrKeyTypeECSECPrimeRandom`, 256 bits): one per Mac install, one per
  device install.
- **Fingerprint `fp`.** SHA-256 of the SubjectPublicKeyInfo DER:
  `SEQUENCE { SEQUENCE { OID 1.2.840.10045.2.1, OID 1.2.840.10045.3.1.7 }, BIT STRING (0x00 ‖ the 65-byte point) }`.
  - On the wire: base64url, 43 characters.
  - This is what every pin compares.
- **Mac ID.** Crockford base32 of `fp[0..<10]`: 80 bits, big-endian, most significant bits first.
  - Alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, 16 characters.
  - Vector: `fp[0..<10] = 50d858e0985ecc7f6041` (the first 10 bytes of SHA-256("example")) gives
    `A3C5HR4RBV67YR21`.
  - It keys saved Macs. A device always checks `macID == MacID(fp)`.
- **Certificate.** `SelfSignedCertificate.make(key:) -> Data`, shared by both ends. About 100
  lines, taken from the d1 probe (`scratchpad/remote-access/d1-probe/mtls-probe.swift`,
  `makeCertificate`):
  - X.509 v3 with no extensions: `[0] EXPLICIT INTEGER 2`;
  - a serial of 16 random bytes (first byte `& 0x7F | 0x01`);
  - `ecdsa-with-SHA256` (1.2.840.10045.4.3.2);
  - issuer = subject = CN (UTF8String) of 16 random hex characters, so it names nothing;
  - validity UTCTime `260101000000Z` to GeneralizedTime `99991231235959Z`;
  - the SPKI above;
  - signed by `SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, tbs)`.

  About 287 bytes. It is rebuilt at every launch from the stored key: the pin is the key, so the
  certificate is never stored.
- **TLS identity.** `SecIdentityCreate(nil, certificate, privateKey)` (public on macOS 10.12+ and
  iOS 11.2+; `SecIdentity.h` in both 27.0 SDKs), then `sec_identity_create`.
- **Why no package.** No Apple API creates a certificate (`SecCertificateCreateWithData` only
  parses). The hand-built DER is verified by `SecCertificateCreateWithData`, by Network.framework on
  both ends and by `openssl x509`. Apple's swift-certificates package would be a dependency
  (open question 5).

#### 3.5 The TXT recognition tag (`Sources/StreamProtocol/Pairing.swift`)

A host with an identity adds a TXT record to its Bonjour registration:
`NWListener.Service(name:type:domain:txtRecord:)` with `NWTXTRecord(["r": tag])`.

- **The tag.** base64url (16 characters) of 12 bytes: `p ‖ HMAC-SHA256(recognitionKey,
  UTF8("sill-tag-v1") ‖ p)[0..<6]`.
  - `p` is 6 fresh random bytes at **every registration**: each launch, and each Direct Wireless
    replacement's re-advertisement.
  - `recognitionKey` is 32 random bytes kept with the host identity. It is sent only in kind 20 ok.
- **Vector:** key `0x11` × 32 and `p = a1a2a3a4a5a6` give `r=oaKjpKWmL4V47Ctm` (Swift and Python
  must agree).
- **What devices do.** Both browsers use `.bonjourWithTXTRecord(type: "_sill._tcp", domain: nil)`.
  For each result they check the tag against every saved Mac's recognition key; a match names the
  row's Mac exactly.
- **Why a tag.** It recognises a saved Mac on a network whatever its Bonjour name ("Mac (2)" after a
  clash, a renamed Mac, a stranger's Mac of the same name at a café), without broadcasting a stable
  identifier anyone could track.
  - It is replayable, so it is a recognition hint, not authentication. The home door is
    unauthenticated anyway until M5.
- **Where it does not apply.** The CLI without `--remote`, and older hosts, register no TXT record,
  as today.

#### 3.6 Pairing (`Sources/StreamProtocol/Pairing.swift` and `Remote.swift`)

**The link and the QR code (`PairLink`).** Built and parsed with `URLComponents`:

```
sill://pair?v=1&m=<macID>&k=<fp, base64url 43>&s=<secret, base64url 22>&n=<Mac name>&p=<port>&a=<address>&a=<address>…
```

- `a` is `host` or `host:port`, with IPv6 in brackets. At most 5, in the Mac's dial order (§4.8).
- The parser refuses:
  - `v ≠ 1`;
  - a missing or malformed `m`, `k`, `s` or `p` (1–65535);
  - `m ≠ MacID(k)`;
  - any `a` the address parser (§7.9) refuses.
- It ignores unknown parameters.
- `n` is capped at 64 characters after `SafeText`.
- About 230 bytes: a version 11 QR code at level M (61×61 modules), 7 px per module at 220 pt on
  Retina.

**The typed code (`PairingCode`).**
- 12 digits: 11 uniformly random digits (`SecRandomCopyBytes` with rejection sampling), then one
  **Damm** check digit.
- Shown as `4829 1355 7208` (the example's 11 digits give the check digit 8).
- Input: spaces and hyphens are removed; exactly 12 digits; the check digit must validate, else
  "That code has a typo…" is shown locally, so a typo never uses up one of the Mac's five tries.
- The Damm table (interim starts at 0, then `interim = T[interim][digit]` for each digit; the check
  digit is the final interim; a valid code ends at 0). Verified: every single-digit substitution and
  adjacent transposition over 20,000 random codes is caught.

  ```
  0 3 1 7 5 9 8 6 4 2 / 7 0 9 2 1 5 4 8 6 3 / 4 2 0 6 8 7 1 3 5 9 / 1 7 5 0 9 8 3 4 2 6 / 6 1 2 3 0 4 5 9 7 8
  3 6 7 4 2 0 9 5 8 1 / 5 8 6 9 7 2 0 1 3 4 / 8 9 4 5 3 6 2 0 1 7 / 9 4 3 8 6 1 7 2 0 5 / 2 5 8 1 4 3 6 7 9 0
  ```

**Keys and proofs (`PairingProof`).**
- QR key: the 16-byte secret `s`.
- Code key: `K = PBKDF2-HMAC-SHA256(password: the 12 ASCII digits, salt: UTF8("sill-pair-v1") ‖
  fp_mac (32 raw bytes), rounds: 600_000, length: 32)`, with CommonCrypto `CCKeyDerivationPBKDF`
  (an Apple framework). About 120–160 ms on this Mac.
- `proof_D = HMAC-SHA256(key, UTF8("sill-pair-v1 device") ‖ 0x00 ‖ fp_device ‖ fp_mac_as_seen)`.
- `proof_M = HMAC-SHA256(key, UTF8("sill-pair-v1 mac") ‖ 0x00 ‖ fp_mac ‖ fp_device)`.
- Each side takes the other's fingerprint **from the TLS session, never from a message**. The Mac
  compares with `HMAC<SHA256>.isValidAuthenticationCode` (constant time).
- **Why a relaying man-in-the-middle fails.** It must present its own key to the device, so the
  device's proof binds the wrong fingerprint and the Mac rejects it. With the QR code the device
  refuses the relay's certificate before sending anything.
- **The typed path's margin.** Online: 5 tries against 10¹¹ codes. Offline, one intercepted proof
  must be ground within the 5-minute window at 600,000 PBKDF2 rounds a guess: about 6·10¹⁶ SHA-256
  compressions on average, which is about 10,000 high-end GPUs for 5 minutes.
- **Vectors.** Computed in Python (`hashlib`, `hmac`); Swift (CryptoKit plus CommonCrypto) must
  match. The script is `scratchpad/remote-access/judge-pairing-vectors.py`.
  ```
  fp_mac       348a629f5ceed032c3e8706ec47d9bfafb00fb4250b018dd965435ca50cb836e   (SHA-256 of "mac", a stand-in)
  fp_device    263a4dbe41488fb87214b0032339dbb9f0c8da14c16dfcf13084bf3c2552eca5   (SHA-256 of "device")
  code         482913557208
  code K       e9baf879a1cc4ac8b21554df480b6c1621671319107c91e7cb05d154f649d31d
  code proof_D dk7PZj4vHsAxj--1u9Vg7ehSn8a1tWc0RCG46YpFVO8
  code proof_M 6BmGWC9XT8J8OY8phhq9bASgoSnoWpRxBeqZtvRrWmk
  QR secret    22 × 16 bytes
  qr proof_D   AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo
  qr proof_M   XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE
  ```

**The exchange.**

```
device                                                Mac, remote door (port 7455)
TCP ──────────────────────────────────────────────▶  pre-auth caps; origin check (refused: closed before TLS)
ClientHello (ALPN sill-pair/1, SNI "sill") ───────▶
            ◀──────────────────────────────────────  ServerHello … Certificate(Mac) … Finished
device verify: QR path, the Mac's fp must equal k (else abort:
the device's certificate is never sent); typed path, any P-256
key, bound into the proof
Certificate(device) … Finished ───────────────────▶  Mac verify: a pairing window is open → accept; else alert
kind 19 PairRequest {method, proof_D} ────────────▶  the only message read: ≤ 4 KB, within 10 s of accept
            ◀──────────────────────────────────────  kind 20 {ok, proof_M, macID, name, recognitionKey}, or
                                                     {ok:false, reason, triesLeft | retryAfter}; the Mac closes
device checks proof_M, saves the Mac, closes. Then a session:
ClientHello (ALPN sill/1), both pinned ───────────▶  Mac: fp paired and Remote Access on → the session
            ◀──────────────────────────────────────  kinds 2, 16, 18, 4…, 5, 14 (today's catalog order), frames
```

- **One exchange, then close.** A pairing connection never becomes a session. The device dials a
  session right after, unless it paired from the overlay while streaming at home: then it just
  closes.
- **Not ok.** The device gives up. The one exception is `busy`: it redials once, silently, after
  `retryAfter`.
- **Re-pairing** a device the Mac already lists (same fingerprint) replaces its record.

#### 3.7 Caps

| Where | Limit | On violation |
|---|---|---|
| Remote door, before admission | 8 pending connections in total, 2 per source address. A source with 5 failures in 60 s is refused for 300 s | Closed before TLS; counted for the minute's summary |
| Remote door, before admission | 10 s from accept to admission (TLS, plus kind 19 on a pairing connection) | Closed |
| Remote door, pairing connection | Exactly one message: kind 19, at most 4 KB | Anything else, or more: closed |
| Remote door, admitted | 8 sessions | The 9th: goodbye `busy`, then closed |
| Both doors, admitted | Any client → host payload at most 1 MiB (today a header can announce 4 GiB and the host waits for it all: StreamServer.swift:462) | Closed with one line |
| Both doors | Kind 17: at most 4 applied per second per connection | The excess is answered with the current state (`answering` set) and applies nothing; at most one line a second |
| Both doors | Device names (`ClientStats.device`, `PairRequest.name` and `model`) go through `SafeText.label`: control and format characters removed (bidi overrides U+202A–202E and U+2066–2069 included), whitespace collapsed, at most 64 characters | — |
| Device | Frames at most 32 MiB; every other host message at most 4 MiB (today StreamClient.swift:705 waits for any length: an SSH banner parses as a 1.7 GB payload) | Closed. On a remote dial this counts as "not Sill" |
| Kind 21 | Home door; loopback, link-local or LAN origin only; once per 30 s per connection; ignored while a window is open | Ignored |

#### 3.8 Compatibility

| Device | Host | Result |
|---|---|---|
| Older (PR #5) | This host | Home door as today. It skips kinds 18 and 22. It never finds the remote door (nothing advertises it). The origin gate refuses it only through a VPN, which only DEBUG `-SillConnect` ever did |
| This device | Older host, or the CLI without `--remote` | Home door as today. No TXT tag and no kind 18: no Away from home group, and a saved Mac is not recognised on that host's row (only development builds hit this). A remote dial to such a host: `.waiting(-9836)` or refused, "…isn't Sill, or its Sill is too old to pair" |
| This device | This host, Remote Access off | Home door as today. Kind 18 says `remoteAccess: false`. A remote dial to a listening door (window open) with ALPN sill/1 gets goodbye `remoteOff`; with the door down, it is refused |
| `sillclient.py` from a9cc248 | This host's home door | Unchanged: it skips unknown kinds |

#### 3.9 Rules for later changes

These are the HostSettings.swift rules, applied to every new payload:
- JSON only;
- new fields optional;
- no enums on the wire (strings instead; an unknown value is skipped);
- never rename or retype a field.

The protocol generation is in the ALPN (`sill/2` can later be offered beside `sill/1`) and in
`MacInfo.v`, `PairRequest.v` and the link's `v`.

---

### 4. Host (`SillHostCore`, folder `Sources/SillHost`), file by file

All new types are `package` or internal; nothing becomes `public`. The network queue is
StreamServer's `sill.net`. Everything that hops to the main actor uses `Task { @MainActor }`,
never `MainActor.assumeIsolated`.

#### 4.1 `HostConfig.swift`

Three Mac-only knobs, beside `directWireless`:

```swift
/// Remote access: the remote door runs (TLS 1.3, paired devices only). The Mac's alone: absent from
/// StreamSettings, HostSettingsChange, DeviceSettings.accepted, `applying` and `restartNeeded`.
package var remoteAccess: Bool
/// The remote door's port. 7455 in `standard`; 0 = any free port (SillHost --remote without a port).
package var remotePort: Int
/// The remote door also admits sources outside this Mac's networks and VPNs (a router port forward).
package var internetAccess: Bool
```

- **Init.** Every knob stays required, so the compiler finds each place that builds a config (the
  CLI, HostSettings, previews and checks).
- **`standard`:** `remoteAccess: false, remotePort: 7455, internetAccess: false`.
- **`validated()`:** `remotePort` must be 0 or 1024…65535; anything else becomes 7455.
- **`changes(to:)`** adds "remote access off → on", "remote port 7455 → 7460" and "internet access
  off → on".
- **`adopt`** hands them to `RemoteAccess.apply` (§4.10). No pipeline ever restarts for them.

#### 4.2 `DeviceSettings.swift`

`accepted(_:virtualDisplayAvailable:fromRemote:)`. With `fromRemote`, `directWireless` is refused as
"direct wireless (not from a remote connection)". The refusal is per field: the rest of the change
applies, as today. The doc comment says Remote Access, the port and internet access can never enter
this whitelist.

#### 4.3 `HostStatus.swift`

```swift
package struct RemoteStatus: Equatable {
    package enum Listener: Equatable { case off, listening(Int), portInUse(Int), failed(String) }
    package enum Router: Equatable { case off, asking, address(String), carrierNAT(String), doubleNAT, noAnswer }
    package enum Pairing: Equatable {
        case closed
        case open(requestedBy: String?, expiresAt: Date, triesLeft: Int, lastWrongFrom: String?)
        case paired(String)
        case stopped
        case expired
    }
    package var remoteAccess: Bool
    package var internetAccess: Bool
    package var listener: Listener
    package var addresses: [MacAddress]
    /// Named VPN services with no address: "Tailscale — Not connected".
    package var vpnDown: [String]
    package var lanAddress: String?       // for the port-forward instruction and the typed pairing path
    package var router: Router
    package var addressName: String       // the app's setting, as shown
    package var pairing: Pairing
    package var paired: [PairedDeviceSummary]   // fingerprint prefix, name, model, pairedAt, method, lastSeen, lastRoute
    package var identityProblem: String?  // "The keychain couldn’t be used: …"
}
```

- `HostStatusSnapshot` gains `remote: RemoteStatus?` (nil on a host without an identity).
- `Device` gains `route: String?`: nil on the home door; "through Tailscale", "through your VPN",
  "over the internet" or "by address" on the remote door.
- The pairing **code and secret are never in the status.** They reach the app and the CLI only
  through `RemoteAccess.onPairingOffer` (§4.10).

#### 4.4 `OriginPolicy.swift` (new; pure, Foundation only, checked with swiftc)

```swift
enum OriginPolicy {
    enum Origin: String { case loopback, direct, vpn, lan, internet }
    enum InterfaceKind { case loopback, lan, tunnel, peerToPeer, other }
    struct Interfaces {                        // a snapshot (InterfaceSnapshot below)
        var kind: [String: InterfaceKind]      // "en0": .lan, "utun4": .tunnel, "awdl0": .peerToPeer
        var owner: [String: String]            // local address → interface name
        var prefixes: [(interface: String, network: [UInt8], bits: Int)]   // on-link prefixes of non-tunnel interfaces
    }
    static func classify(remote: String, localAddress: String?, scope: String?, interfaces: Interfaces) -> Origin
    static func homeAdmits(_ o: Origin) -> Bool                          // loopback, direct, lan
    static func remoteAdmits(_ o: Origin, internetAccess: Bool) -> Bool  // loopback, lan, vpn; internet only with it; never direct
    static func label(_ o: Origin, interface: String?, serviceName: String?) -> String?   // "through Tailscale"…
}
```

**Classification, first match wins:**

1. Unmap `::ffff:a.b.c.d` to IPv4.
2. 127/8 or ::1 → `loopback`.
3. The arrival interface is:
   - the endpoint's scope (`ClientLink.scope(ofEndpoint:)` (fixes), for link-local; if the fixes
     have not landed, port that function and its checks from e51f254);
   - else the interface that owns `localAddress` (`currentPath?.localEndpoint`);
   - else unknown.

   `currentPath.availableInterfaces` is not used: the fixes saw it list en0 and lo0 for one
   connection.
4. Arrival on `awdl*` or `llw*` → `direct`.
5. Arrival on a tunnel (`utun*`, `ipsec*`, `ppp*`, `tun*`, `tap*`, `wg*`, `feth*`, `zt*`) → `vpn`.
6. Otherwise, arrival on a LAN interface (`en*`, `bridge*`, `anpi*`, `anri*`) or an unknown one:
   - a link-local source (169.254/16, fe80::/10) → `lan`;
   - inside an on-link prefix of that interface (of any LAN interface when unknown) → `lan`. This
     covers LANs numbered from public space, and IPv6 LAN peers on global addresses;
   - RFC 1918 or ULA (fc00::/7) → `lan`: routed private sources, such as a VPN that ends on the home
     router;
   - 100.64/10 that is not on-link → `internet` (carrier space from outside);
   - anything else → `internet`.

**Two notes.**
- `InterfaceSnapshot.current()` reads `getifaddrs` (addresses, netmasks, `IFF_POINTOPOINT`), is
  cached for 2 s and is used on the network queue. It serves both doors, so the home door needs no
  SystemConfiguration watcher.
- It is defence in depth, not the boundary. A router that source-NATs or hairpins a forward makes an
  internet peer look like `lan`. Pairing is the boundary.

**TEST ONLY:** `SILL_TEST_ORIGIN=vpn|internet` makes loopback sources classify as that origin, on a
host that does not advertise.

#### 4.5 `HostIdentity.swift` and `PairedDevices.swift` (new)

- **`HostIdentity`:** the key (`SecKey`), the certificate DER, `fp`, `macID`, `sec_identity_t` and
  `recognitionKey`. It can sign (`SecKeyCreateSignature`, for kind 18).
- **`IdentityStore` (protocol), three backends:**
  - **`KeychainIdentityStore` (Sill.app).** The legacy login keychain. The data-protection keychain
    needs `keychain-access-groups` and so a provisioning profile, which make-app.sh's bundle does not
    have (`Packaging/SillDebug.entitlements` holds only `get-task-allow`).
    - Key: `SecKeyCreateRandomKey` with `kSecAttrIsPermanent: true`, application tag
      `me.saffer.sill.remote.host-key`, label "Sill Remote Access". Looked up by tag.
    - Recognition key: a generic password, service `me.saffer.sill.remote`, account
      `recognition-key`.
    - Paired list: a generic password, service `me.saffer.sill.remote`, account `paired-devices`,
      JSON.
    - The default ACL trusts the creating app's designated requirement, which survives rebuilds
      signed with the same Apple Development identity, as TCC grants do (R8 checks it).
  - **`MemoryIdentityStore`:** SillHost `--remote`. New every run; nothing outlives the process.
  - **`FileIdentityStore`:** TEST ONLY, `SILL_TEST_REMOTE_DIR=<dir>`, honoured only by a host that
    does not advertise.
    - The directory has mode 0700: `host-key` (X9.63 private key, 0600), `recognition-key` (32
      bytes, 0600), `paired.json`.
    - With `-SillPairAfter`, also `pairing.url` and `pairing.code` (0600).
- **`PairedDevice`,** stored in the keychain item:
  `{fingerprint (base64url), name, model?, pairedAt, method ("qr" | "code"; M5 adds "icloud")}`.
  - Display-only data (`lastSeenAt`, `lastRoute`) lives in the app's defaults under
    `remoteDevicesSeen` (fingerprint prefix → `{at, route}`), written at most once a minute per
    device.
  - The trust list never lives in UserDefaults or a plist: any process of the same user can edit
    those, add its own key, and then use Sill's Screen Recording and Accessibility grants.
- **`TrustSnapshot`:** `{paired: Set<Data>, pairingOpen: Bool, remoteAccess: Bool, internetAccess: Bool}`.
  - Immutable, replaced whole under an `NSLock` on every change.
  - The verify block and admission read it on the network queue. **Nothing there ever waits on the
    main actor.**
- **Loading.** Sill.app loads or creates the identity at launch, before `start()`, so the TXT tag is
  in the first registration.
  - A keychain failure: no identity, no TXT tag, no kind 18, the remote door unavailable, and
    `identityProblem` shown in the pane and the menu. The app keeps running.
  - The CLI creates an identity only with `--remote`.

#### 4.6 `PairingWindow.swift` (new; pure, checked with swiftc)

- **State:** `closed(reason: used | expired | stopped | cancelled | none)`, or `open` with:
  - the secret (16 bytes), the code, `codeKey: SymmetricKey?` (nil until derived);
  - `expiresAt` (now + 300 s; `SILL_TEST_PAIRING_TTL` on test hosts);
  - `failures`, `nextAllowedAt`, `lastAttemptBySource`;
  - `requestedBy: String?`.
- **`tryProof(method:proof:fpDevice:fpMac:source:now:) -> Verdict`**, where Verdict is
  `.accept(proofM)`, `.reject(triesLeft)`, `.busy(retryAfter)` or `.closed(reason)`.
  - Not open → `.closed`.
  - Past `expiresAt` → `.closed(expired)`.
  - `now < nextAllowedAt`, or the same source within 5 s → `.busy`.
  - A code proof before `codeKey` is ready → `.busy(1)`.
  - Valid → `.accept` and closed(used).
  - Invalid → failures + 1; the next evaluation waits 1, 2, 4, then 8 s; the 5th failure →
    closed(stopped).
- **Deriving K:** once per window, off the main actor.

#### 4.7 `RemoteServer.swift` (new): the remote door

It runs on StreamServer's queue. It is owned by `RemoteAccess` and hands admitted sessions to
`StreamServer.serve`.

- **Build:** `NWParameters(tls: RemoteTLS.options(identity, .server, verify, queue), tcp: …)` with the
  §3.3 TCP options, then `NWListener(using:on: port)`, or any port when `remotePort == 0`.
- **Running:** while `remoteAccess || pairingOpen`.
- **EADDRINUSE and other failures:**
  - `listener = .portInUse(P)`, with one line "Remote access: port P is in use by another app;
    trying again every 30 s.";
  - a retry every 30 s and on network changes;
  - **never another port**, because saved addresses depend on this one;
  - once bound: "Remote access: listening on port P (TLS, paired devices only; N paired).";
  - any other failure: `.failed(e)`, the same retry.
  - The remote door never exits the process.
- **`newConnectionHandler(c)`:**
  - source = `c.endpoint`'s host;
  - over the caps (§3.7) or in backoff → `cancel()` at once and count;
  - else record it as pending (source, acceptedAt), arm the 10 s deadline, set the state handler and
    `start(queue:)`.
- **On the first state with a path (`.preparing`):**
  - classify with `OriginPolicy` (local endpoint, scope, `InterfaceSnapshot`);
  - `!remoteAdmits(origin, internetAccess)` → cancel, and count "from the internet (internet access
    off)".
- **Verify block:** `fp ∈ paired` or `pairingOpen` → `complete(true)`; else `complete(false)`,
  counted as unpaired.
- **At `.ready`,** read ALPN and fp from the metadata, then:
  - **`sill/1`:**
    - requires `fp ∈ paired` and `remoteAccess`;
    - not paired → cancel (counted);
    - paired but Remote Access off → goodbye `remoteOff`, then close;
    - 8 sessions already → goodbye `busy`, then close;
    - else `server.serve(c, route: .remote(origin, label, fp))` and print
      "Remote client connected: ‹paired name› ‹label› (‹endpoint›)".
  - **`sill-pair/1`:**
    - requires `pairingOpen`, else cancel;
    - read exactly one header and payload (kind 19, at most 4096 bytes) within the deadline;
    - hop to the main actor: `PairingWindow.tryProof`;
    - answer kind 20 on the queue;
    - on accept: `PairedDevices.add` (the snapshot is updated first, then kind 20 ok is sent), and
      print "Paired ‹name› (‹model›) (key ‹fp prefix›…) from ‹source›, with the QR code | with the
      code.";
    - either way, close after the send completes or 250 ms.
  - Any other ALPN → cancel.
- **`.failed` or `.cancelled` before admission:** `cancel()`, remove the pending entry, and count one
  failure for the source (5 in 60 s → a 300 s backoff; `SILL_TEST_BACKOFF_SECONDS` on test hosts).
- **Summary line,** at most once a minute: "Remote access refused N connections in the last minute:
  a unpaired, b from the internet (internet access off), c over the limit."
- **`apply(want:)`:**
  - **Off:** cancel the listener; every remote session gets goodbye `remoteOff` and is closed, one
    line each: "Remote access off: disconnecting ‹name› at ‹endpoint›." Turning Remote Access off
    also closes an open pairing window.
  - **Port changed:** replace the listener on the new port. Accepted connections are independent of
    it (measured in PR #5), so live sessions continue.
  - **Internet access off:** sessions whose origin is `internet` get goodbye `internetOff` and close.
- **`remove(fp)`:** remove the device from the store, then the snapshot; every session with that fp
  gets goodbye `removed` and closes. Print "Removed ‹name›; closed N connection(s)." Its next
  handshake fails in the verify block.

#### 4.8 `Reachability.swift` (new), `RouterAddress.swift` (new)

- **`Reachability`** runs while `remoteAccess || pairingOpen`, in Sill.app and SillHost `--remote`.
  There is no watcher otherwise, and never on the CLI's default path.
  - **What it reads (SCDynamicStore):**
    - `State:/Network/Service/*/IPv4` and `IPv6`, joined with `Setup:/Network/Service/<id>`
      `UserDefinedName`;
    - `State:/Network/Interface/<if>/IPv6` flags (temporary 0x80, deprecated 0x10);
    - `State:/Network/Global/IPv4` (the primary interface);
    - the Tailscale service's DNS `SupplementalMatchDomains`.
  - It also reads `getifaddrs`, for point-to-point interfaces that are not network services
    (Tunnelblick, ZeroTier).
  - **Changes:** `SCDynamicStoreSetNotificationKeys` plus `SCDynamicStoreSetDispatchQueue` on a
    utility queue, coalesced to 0.5 s, then a hop to the main actor. No polling.
- **`AddressList.build(services:interfaces:internet:addressName:router:) -> [MacAddress]`** (pure,
  checked with swiftc). The rules come from the host map's probe (`scratchpad/remote-access/
  addresses-probe.swift`):
  - **Show:**
    - a named service on a tunnel with non-link-local addresses, `kind "vpn"`, `via` = the
      service's name;
    - 100.64/10 only on a tunnel (on `en*` it is carrier NAT on the LAN);
    - Tailscale's fd7a:115c:a1e0::/48;
    - a point-to-point interface that is not a service but has a non-link-local IPv4, shown as
      `"VPN (utun6)"`;
    - the primary Wi‑Fi or Ethernet service's IPv4, `kind "lan"`.
  - **Hide:**
    - loopback and link-local addresses;
    - awdl, llw and nan;
    - unnamed utuns (utun0–3, and the CoreDevice tunnel's ULA);
    - temporary and deprecated IPv6;
    - LAN ULAs.
  - **Order:** VPN names, VPN IPv4, VPN IPv6, LAN IPv4. With the internet switch on, then the
    address name (with its port), the router's IPv4 and one stable global IPv6. At most 12.
  - **TEST ONLY:** a host that does not advertise lists `127.0.0.1` first (`kind "lan"`, `via "This
    Mac"`), so the simulator can reach it.
- **MagicDNS name.** Candidate: `LocalHostName` lowercased, then ".", then the tailnet domain.
  - It is kept only if `getaddrinfo` resolves it to the tunnel's own address (a utility queue, 2 s
    budget). Otherwise the IP stands alone: the guess fails on a machine renamed in Tailscale's admin
    console.
  - Reverse lookups are not used (Tailscale serves no in-addr.arpa zone).
- **`RouterAddress`,** only while the internet switch is on:
  `DNSServiceNATPortMappingCreate(&ref, 0, <index of the primary non-tunnel interface>, 0, 0, 0, 0,
  cb, nil)` with `DNSServiceSetDispatchQueue` (Swift module `dnssd`).
  - Zero protocol, ports and TTL mean "just discover the external address" (`dns_sd.h`): **no mapping
    is ever created.**
  - The non-tunnel index matters: a Tailscale exit node can make utun the primary interface.
  - The callback repeats when the address changes.
  - **Results:**
    - an address in 100.64/10 → `carrierNAT`;
    - a private address, or `kDNSServiceErr_DoubleNAT` (-65558) → `doubleNAT`;
    - -65564 or -65565 → `noAnswer`;
    - otherwise `address`.
  - `SILL_TEST_NO_ROUTER=1` skips the query on test hosts. The query was compiled but never run here
    (`scratchpad/remote-access/natpmp-probe.swift`): R0 runs it.

#### 4.9 `StreamServer.swift`

1. **`Client`** gains:
   - `route` (`.home`, or `.remote(origin, label, fingerprint)`);
   - `admittedAt`, `lastHeardAt`;
   - `awaitingFirstKeyframe`, `keyframeWanted`;
   - `device` (fixes).
2. **`accept(_:)`, the home door:**
   - at `.ready`, first the origin check (`homeAdmits`);
   - refused: `cancel()`, never registered, counted for the minute's summary "Home listener refused
     N connections in the last minute (a through a VPN, b from the internet): only this Mac's own
     networks reach it.";
   - admitted: registered only now (`clients[id]`, `onClientCountChanged`, `updateTicking`, "Client
     connected: …" with today's text, `receiveLoop`, `onClientConnected`);
   - `.failed`: `cancel()` first (today it is removed but never cancelled, which held the socket in
     the probe);
   - "Client left" is printed only for registered clients.
3. **`serve(_ c: NWConnection, route:)`,** for the remote door's admitted, already-ready connections:
   the state handler for `.failed`/`.cancelled`, registration, `receiveLoop`, `onClientConnected(c,
   route)`.
4. **`receiveLoop`:**
   - `lastHeardAt = now` at every header;
   - `payloadLength > maxClientPayload` → "Closing ‹endpoint›: it announced a ‹N›-byte message (the
     limit is 1 MB)." and `cancel()`;
   - kind 21 is delivered to the coordinator only from home-route clients.
5. **Eviction:**
   - **Home clients:** unchanged (4 s without draining, 8 s grace).
   - **Remote clients:**
     - a 1 s timer on the queue while any exists;
     - silent for more than 8 s, once 8 s have passed since admission → "Client silent for N s,
       dropping: ‹endpoint›";
     - the drain backstop at 15 s, with a 15 s grace. On a 2 Mbps uplink a 1.5 MB keyframe takes
       6 s to hand off, so the 4 s rule would evict live devices.
6. **Keyframe pacing** in `broadcast`, remote clients only (home clients keep today's logic byte for
   byte). For each frame message and remote client:
   - **`needsKeyframe`:**
     - a delta → skip it (`net.waitKey`); if `keyframeWanted` and `inflight ≤ 2` and 2 s have
       passed since the last forced request made for a remote client, request one
       (`onKeyframeNeeded`) and clear `keyframeWanted`;
     - a keyframe → send it only if `awaitingFirstKeyframe || inflight ≤ 2`, with the parameter sets
       first, as today; then clear `needsKeyframe` and `awaitingFirstKeyframe`.
   - **Otherwise, `inflight > 2`:** drop the frame, delta or keyframe (`net.dropped`), and set
     `needsKeyframe` and `keyframeWanted`. Never queue anything behind a full queue.
   - `awaitingFirstKeyframe` is set at `serve` and by `resetForNewStream`.
   - No new Stats key.
   - The encoder's own 4 s keyframe stays.
   - The kernel's autotuned send buffer stays invisible to this rule (Network.framework has no
     `SO_SNDBUF` or `TCP_NOTSENT_LOWAT`). Bounding that queue is the later transport step.
7. **`goodbye(_ reason:, to:)`:** send kind 22, cancel after the send completes or 250 ms.
   `goodbyeAll("quit", within: 0.1)` for the app's Quit and `HostShutdown`.
8. **TXT:** `var txtRecord: (() -> NWTXTRecord?)?`, set by the coordinator before `start()`.
   - The service is built by `makeService()` each time it is attached: at init, in `start()`, and in
     `settled` after a Direct Wireless replacement. So every registration carries a fresh tag.
   - The test registration (`SILL_TEST_SERVICE_TYPE`) carries it too.
   - Nil → no TXT record, as today.

#### 4.10 `RemoteAccess.swift` (new; main actor)

The coordinator owns one, in Sill.app always and in SillHost only with `--remote`. It ties together
the identity, the store, `PairingWindow`, `Reachability`, `RouterAddress` and `RemoteServer`.

- **`apply(config)`:** the three knobs. Starts or stops the door, the watcher and the router query;
  publishes `status.remote`; broadcasts kind 18 when it changed.
- **`openPairing(requestedBy: String?)`:**
  - opens a window;
  - derives K in `Task.detached`;
  - starts the door if needed;
  - calls `onPairingOffer?(PairingOffer(url, code, expiresAt, requestedBy))`: the app shows the
    window; the CLI prints.
  - Opening again while open keeps the same code and sends the current offer again: the app brings
    its window forward, and the CLI prints the code again (its answer to kind 21).
  - The CLI's `--remote` re-opens a fresh window whenever one closes, for the whole run.
- **`cancelPairing()`,** `remove(fingerprint:)`, `rename(fingerprint:to:)`, `setAddressName(_:)` (the
  app's setting, parsed by the address parser).
- **`macInfoMessage() -> StreamMessage`:**
  - kind 18, signed, with `issuedAt = now`;
  - compared without `issuedAt` to decide a broadcast (deduplicated like `publishSettings`,
    StreamCoordinator.swift:1264-1269).
- **The sleep counter:** `remoteDevices`, read by the app (§6.5).

#### 4.11 `StreamCoordinator.swift`

- **`init`:** if a `RemoteAccess` is given, set `server.txtRecord` from it before `server.start()`.
- **`onClientConnected(connection, route)`:**
  - the device row gets `route` (its label), and its name from the paired record until the first
    stats arrive;
  - the remote-device count;
  - the rest as today (catalog, thumbnails, keyframe request).
- **`sendCatalog`** (:1208-1224): after kind 16, kind 18 when there is an identity. The order is 2,
  16, 18, 4…, 5, 14. The "Catalog → …" line keeps its text.
- **`handle`:**
  - **`.changeSettings`** (:491-508):
    - per-connection rate: the 5th and later changes within one second apply nothing and are
      answered with `settingsState(answering: token)`, plus at most one line a second: "Settings from
      ‹device› ignored: more than 4 changes a second.";
    - `DeviceSettings.accepted(…, fromRemote: route is remote)`.
  - **`.pairingWanted`:** a home route with origin loopback, lan or direct, not within 30 s of this
    connection's last one, and no window open → `remote?.openPairing(requestedBy: deviceName(c))`.
    Anything else is ignored.
- **`adopt`** (:384-398): when `remoteAccess`, `remotePort` or `internetAccess` changed →
  `remote?.apply(next)`. The "Settings: …" line comes from `changes(to:)`.
- **The Desktop filter** (:804): `SCContentFilter(display: d, excludingApplications: [own],
  exceptingWindows: [])`.
  - `own` is Sill's `SCRunningApplication` from the catalog's last `SCShareableContent`
    (`WindowCatalog` exposes it). Not found (the CLI) → `excludingWindows: []` as today.
  - Sill's windows (Settings, Log, the pairing window) never go out in a Desktop stream. The window
    catalog already skips them (WindowCatalog.swift:225).
  - The filter is fixed at pipeline start: no running SCStream is ever reconfigured.
- **`deviceName(_:)`:** the paired name for remote clients before stats, then the stats name through
  `SafeText`.

#### 4.12 `WindowCatalog.swift`, `HostShutdown.swift`

- **`WindowCatalog`** keeps `ownApplication: SCRunningApplication?` from each refresh.
- **`HostShutdown` and `releaseForQuit`** call `server.goodbyeAll("quit", within: 0.1)` first. The
  CLI without `--virtual-display` still dies on a plain SIGINT with no goodbye: its devices notice by
  liveness.

#### 4.13 Log lines (exact; each appears only when its event happens; never a code or a secret)

```
Remote access: listening on port 7455 (TLS, paired devices only; 2 paired).
Remote access off.
Remote access: port 7455 is in use by another app; trying again every 30 s.
Pairing window open for 5 minutes (asked by iPad (iPad14,1)).        | (opened on this Mac)
Paired iPad (iPad14,1) (key 5KD2Q7…) from 192.168.1.23, with the QR code.
Pairing: a wrong code from 203.0.113.9 (4 tries left).
Pairing stopped after 5 wrong codes.
Removed iPad (iPad14,1); closed 1 connection.
Remote client connected: iPad (iPad14,1) through Tailscale (100.84.3.2:61022)
Remote access off: disconnecting iPad (iPad14,1) at 100.84.3.2:61022.
Remote access refused 14 connections in the last minute: 9 unpaired, 5 from the internet (internet access off), 0 over the limit.
Home listener refused 3 connections in the last minute (2 through a VPN, 1 from the internet): only this Mac's own networks reach it.
Closing 100.84.3.2:61022: it announced a 5242880-byte message (the limit is 1 MB).
Client silent for 9 s, dropping: 100.84.3.2:61022
Settings from iPad (iPad14,1) ignored: more than 4 changes a second.
Settings from iPad (iPad14,1) refused: direct wireless (not from a remote connection)
Settings: remote access off → on
```

"Client connected: …" and "Catalog → …" keep their exact text, because tests grep for them.

---

### 5. CLI (`Sources/SillHostCLI/main.swift`)

| Flag | Effect |
|---|---|
| `--remote[=PORT]` | Runs the remote door for this run: `remoteAccess = true`, `remotePort = PORT ?? 0` (any free port, so it never collides with Sill.app's 7455: N12, W8). A new in-memory identity and pairings (TEST ONLY: `SILL_TEST_REMOTE_DIR` on a host that does not advertise). A pairing window is always open: a fresh one after each use or expiry. main.swift prints, from the `onPairingOffer` hook: `Remote access for this run on port 51234 (TLS, paired devices only). Pair with 4829 1355 7208 or sill://pair?v=1&…`, and `Pairing: new code 7310 2284 9915 or sill://pair?…` for each later window. Answers kind 21 by printing the current code again. |
| `--internet` | With `--remote`, also admits internet sources; one line says so. Without `--remote`: "--internet needs --remote." and exit 2. |
| `--print-reachability` | Prints the address list as the Mac's pane would show it (label, address, kind), then exits. Read-only SystemConfiguration, and no listener. For H18. |
| none of them | Output byte-identical to the base (masked and sorted), idle and streaming, with and without `--direct-wireless`. No identity, no TXT record, no kind 18. The home door's gate and caps print only when they refuse something, which never happens on the baseline runs. |

- The code and URL printed by the CLI go to its own stdout only. HostLog's shadow records nothing in
  the CLI.
- Core code never prints a code or a secret: the hook in main.swift does.
- The CLI is a development host: a device on the LAN that streams the Desktop could read its code in
  Terminal. The README says so.

---

### 6. Sill.app (`Sources/SillMenuBar`)

All errors show inline, never in alerts. Windows open only from AppKit target/action, SwiftUI
`Button` actions, or (for a device's request) a main-actor hop that shows a window without a modal
loop. `WindowPlacement.bringForward` keeps every window off the virtual display.

#### 6.1 Settings › Remote Access (a fifth tab)

`SettingsTab.remoteAccess`, titled "Remote Access", symbol `globe`, after Permissions
(SettingsWindow.swift:6-26). New file `RemoteAccessPane.swift`: a grouped Form 520 pt wide, like
the other panes. The pane follows `HostStatus` live; nothing polls.

**Section 1**
- Toggle **"Remote access"** (`$settings.config.remoteAccess`).
- Footer: "Lets the iPhone and iPad you pair connect to this Mac from other networks: through a VPN
  such as Tailscale, or through a port you forward on your router. Sill turns away every device you
  haven’t paired, and encrypts everything the paired ones send and receive."
- `identityProblem`, when set (orange): "Remote access isn’t available: Sill couldn’t use the
  keychain (‹error›)."

**Section 2 "Addresses"** (only while on)
- One `LabeledContent` per address:
  - label: the service name ("Tailscale", "Wi‑Fi", a WireGuard tunnel's own name);
  - value: selectable text, the MagicDNS name first and the IPs behind it on a second, muted line;
  - a **Copy** button, spoken as "Copy the Tailscale address", showing "Copied" for 1.5 s.
- **Wi‑Fi row note:** "This network. Use it with a VPN into your home network, such as WireGuard on
  your router."
- **"Port"** `7455` with **Change…**, which turns into a field with Save and Cancel:
  - "Choose a port from 1024 to 65535."
  - "Port 5000 belongs to AirPlay Receiver. Choose another." (also 7000)
  - At 49152 and up: "Ports from 49152 up can be taken by any app at any moment."
  - After a save: "Paired devices learn the new port the next time they connect at home."
- **States:**
  - A VPN service with no address: "Tailscale — Not connected", muted, with the footer "Your devices
    can’t reach this Mac through Tailscale until it connects."
  - No VPN: "No VPN is running on this Mac. Install one such as Tailscale on this Mac and on your
    iPhone or iPad, or allow connections from the internet below."
  - Port in use (orange, the first row): "Port 7455 is in use by another app, so devices can’t reach
    this Mac remotely. Sill tries again every 30 seconds." with **Change…**.
  - Another failure: "Remote access couldn’t start (‹error›). Sill tries again every 30 seconds."
- Footer: "Your devices learn these when they pair and keep them current whenever they connect."

**Section 3 "Paired Devices"** (always)
- **Each row:** the name ("iPad (iPad14,1)"); double-click renames it (commit on Return, Esc
  cancels). The detail line: "Paired Sep 24 · last connected 2 minutes ago through Tailscale".
  **Remove**, with no confirmation, since it only takes access away.
- **After Remove:** "iPad (iPad14,1) can no longer connect. To use it again, pair it again."
- **Empty:** "No paired devices yet."
- **[Pair iPhone or iPad…]**.
- Footer: "A paired device can see and control this Mac wherever it can reach it. If one is lost,
  remove it here."

**Section 4 "Internet"** (only while Remote Access is on)
- Toggle **"Allow connections from the internet"** (`$settings.config.internetAccess`).
- Footer while off: "Only needed for a port forward on your router. A VPN is simpler and keeps this
  Mac off the open internet."
- **While on:**
  - "Forward TCP port 7455 on your router to this Mac (192.168.1.20), and reserve that address for
    this Mac in the router’s settings." with **Copy**.
  - **"Router’s internet address":**
    - "Asking your router…";
    - "203.0.113.9" with **Copy**;
    - orange: "Your internet provider shares this address among many homes (100.72.x.x), so a port
      forward can’t reach this Mac. Use a VPN such as Tailscale instead.";
    - orange: "Your router sits behind another router. Forward the port on both, or use a VPN.";
    - "Your router didn’t say. You’ll find the address in its settings."
  - **"Address name (optional)"**, a field with placeholder "home.example.net". It accepts `host` or
    `host:port` and is checked by the address parser. Footer: "If your router has a dynamic DNS name,
    enter it so your devices keep finding this Mac when your internet address changes. Add :port if
    the router forwards a different outside port."
  - **IPv6**, only with a stable global address: "2001:db8::20" with **Copy**, and "Works only if
    your router lets incoming IPv6 connections reach this Mac; most don’t."
  - Footer while on: "Anyone on the internet can now reach port 7455 and try to connect. Sill turns
    away every device you haven’t paired. Turning this off doesn’t close the port on your router:
    remove the forward there too."

**Section 5** (always)
- "This Mac can’t be reached while it’s asleep. While a device is connected from away, Sill keeps it
  from going to sleep by itself." with **[Open Energy Settings…]**. The implementer checks the
  settings URL on macOS 27 (Energy on a desktop; Battery › Options on a laptop).

#### 6.2 The pairing window (`PairDeviceWindow.swift`, new)

An `NSWindowController` hosting a SwiftUI `PairDeviceView`.
- A standalone window titled "Pair iPhone or iPad": not a sheet, because a device can open it while
  Settings is closed.
- `sharingType = .none`, as a best effort (reports say ScreenCaptureKit ignores it on macOS 15+; the
  Desktop filter is what counts).
- One instance: opening it again brings it forward with the same code.
- Closing it cancels the window, and the code dies with it.

```
┌─ Pair iPhone or iPad ───────────────────────────────┐
│ iPad (iPad14,1) on this network asked to pair.      │   (only when requested by a device)
│ In Sill on your iPhone or iPad, tap Add a Mac…,     │
│ then point it at this code.                         │
│                 ██▀▀▀▀██ ▄▀▄ ██▀▀▀▀██               │   CIFilter.qrCodeGenerator, level M, integer
│                 ██ ██ ██ ▀▄█ ██ ██ ██   (220 pt)    │   scale, no interpolation, always dark on white
│                 ██▄▄▄▄██ █▀▄ ██▄▄▄▄██               │   with a 4-module quiet zone
│ Can’t scan? Tap Enter Code Instead, and type:       │
│   Address   mac-mini.tail1234.ts.net                │   Tailscale's name, its IPv4 under it (muted), else
│             or 100.101.102.103                      │   a Tailscale IP, else this network's address (below)
│   Code      4829 1355 7208                          │   22 pt monospaced digits, selectable
│ Works once, for the next 4:58.                      │   updating, not announced every second
│ A paired device can see and control this Mac.       │
│ Remote Access is off. Paired devices can connect    │   (only while off)
│ away from home once you turn it on.                 │
│                   [Turn On Remote Access]  [Cancel] │
└─────────────────────────────────────────────────────┘
```

| State | Shown (inline, replacing the lines under the code) |
|---|---|
| Pairing | "Pairing with iPad (iPad14,1)…" |
| Paired | "Paired with iPad (iPad14,1)." and [Done]; it closes itself after 3 s, unless Remote Access is off (the Turn On line stays) |
| Wrong code | orange: "A wrong code came from 203.0.113.9. 4 tries left." |
| Stopped | "Pairing stopped after 5 wrong codes." and [New Code] |
| Expired | "This code expired." and [New Code] |
| Door not ready | "Can’t pair while port 7455 is in use." and [Change Port…] (opens the pane) |

- **Pairing never turns Remote Access on by itself.** [Turn On Remote Access] is the Mac user's
  click.
- The QR image is labelled "Pairing code image"; the code and address are plain text VoiceOver
  reads.
- **The address to type** (`PairingWindowAddress.choose`, pure, checked with swiftc). Noah,
  2026-09-25: pairing from an iPhone's hotspot with a typed code, this network's address
  (10.128.0.34, which the window gave first) answered nothing, while Tailscale's 100.65.142.55 and
  its MagicDNS name both paired. So the window shows those two instead:
  1. the first VPN with a name (Tailscale's MagicDNS name), with that VPN's first IPv4 under it,
     muted: "or 100.65.142.55";
  2. else the first VPN IPv4 in Tailscale's 100.64.0.0/10, else the first VPN IPv6 in its
     fd7a:115c:a1e0::/48, alone, whichever VPN is listed first (open-source tailscaled's unnamed
     "VPN (utun4)" included; Headscale's tailnets use the same ranges);
  3. else this network's address, as before, with another VPN's first IPv4 (else IPv6) under it,
     muted: "or 10.8.0.6". Another VPN's address never takes this network's place: a privacy
     VPN's answers from nowhere (NordVPN's NordLynx gives every Mac 10.5.0.2, Cloudflare WARP
     172.16.0.2), while this network's answers at home and through a VPN into the home network
     (the pane's LAN row, the README's second way in). The order of the two is Noah's call (the
     review of ae7f5c9); this one keeps the line the window gave before his decision first;
  4. else another VPN's first IPv4, else its first IPv6 (no LAN address), as before;
  5. else the first address listed, as before (with no VPN and no LAN address only an internet
     address or a test host's 127.0.0.1 is left);
  6. else "this Mac’s address".
  - VPNs are picked by their kind, names told from IPs by the address parser and Tailscale's
    addresses by the parsed address's range (the device's `RemoteDialPolicy.isVPNAddress` has the
    same ranges), never by the text of a name or a service. Each value carries the port when it is
    not 7455 (an address name's own port first).
  - Both lines are selectable, "or" apart from the address; the window has no Copy button (the
    pane's rows have them). The router's address and the address name stay in the pane, unless
    nothing else is listed (step 5).

#### 6.3 Status menu and card (`StatusItemController.swift`, `StatusText.swift`)

- **Second group,** after Direct Wireless Connection (StatusItemController.swift:84-88):
  **"Remote Access…"** opens Settings on the tab (`.showSettings(.remoteAccess)`). Its subtitle is
  one of:
  - "Off";
  - "On · Tailscale";
  - "On · Tailscale and the internet";
  - "On · no VPN on this Mac";
  - "Port 7455 is in use";
  - "Unavailable: the keychain couldn’t be used".
- **Third group,** above Show Log…: **"Pair iPhone or iPad…"** (`.showPairing`).
- **Attention item** (first group, orange) while on and the port is in use: "Remote Access Can’t
  Start" / "Port 7455 is in use by another app." It opens the tab.
- The internet switch is not in the menu: it stays one deliberate step deeper.
- **Card:** a device row's detail appends its route: "60 fps · frame age 41 ms · RTT 48 ms · through
  Tailscale", or "· over the internet", "· through your VPN", "· by address". Home devices are
  unchanged.
- New `MenuEntry.Action` cases: `.showSettings(SettingsTab)` (the parameterless one stays for ⌘,)
  and `.showPairing`.

#### 6.4 Settings keys and wiring (`HostSettings.swift`, `AppModel.swift`)

- **Keys, with registered defaults from `HostConfig.standard`:**
  - `remoteAccess` (false), `remotePort` (7455), `internetAccess` (false);
  - `remoteAddressName` (""), not in HostConfig: handed to `RemoteAccess.setAddressName`;
  - `remoteDevicesSeen` (display only).
- Saved only when changed; launch-argument overrides work as for the others (`-remotePort 7456`).
- **`AppModel`:**
  - creates the `KeychainIdentityStore` and the `RemoteAccess`, and passes it to the coordinator;
  - wires `onPairingOffer` to show `PairDeviceWindow`;
  - holds the pane's actions: pair, cancel, remove, rename, turn on;
  - on `--synthetic` with `SILL_TEST_REMOTE_DIR`, uses the `FileIdentityStore`. The bare binary
    never touches Noah's login keychain in a test.
- **StreamProtocol's HostSettings.swift header** ("every place a new setting must go") gains one
  line: a Mac-only listener knob (remote access, its port, internet access) goes in HostConfig, the
  app's HostSettings, DebugHooks, the pane and the menu, and **never** in StreamSettings,
  HostSettingsChange or DeviceSettings.accepted.

#### 6.5 Sleep (`AppModel.holdAppNapOff`, AppModel.swift:117-125)

- While any **remote-door** device is connected: `[.userInitiated, .latencyCritical]`. This prevents
  idle system sleep; the display may still sleep.
- Otherwise, while any device is connected: today's `[.userInitiatedAllowingIdleSystemSleep,
  .latencyCritical]`.
- Switching between the two ends one activity and begins the other.
- The CLI is unchanged.
- Whether a sleeping or locked display stops capture is checked in R6 (open question 7).

#### 6.6 DebugHooks and previews

- **`-SillSetAfter`** learns `remoteAccess=1|0`, `remotePort=N`, `internetAccess=1|0` and
  `remoteAddressName=host[:port]` (DebugHooks.apply, :72-86).
- **`-SillPairAfter <s>`** opens the pairing window. On `--synthetic` with `SILL_TEST_REMOTE_DIR`, it
  also writes `pairing.url` and `pairing.code` there (0600). It never prints them: the app's print
  shadow copies stdout into Sill.log.
- **`-SillUnpairAfter <s>`** removes every paired device.
- **`-SillRenderPreviews`** adds:
  - `pane-remote-{off,tailscale,notconnected,novpn,internet,cgnat,doublenat,inuse,keychain}-{light,dark}.png`;
  - `pairing-{waiting,requested,wrong,paired,stopped,expired,remoteoff,novpn,othervpn,longname}-{light,dark}.png`
    (`novpn`: this network's address; `othervpn`: this network's address with a WireGuard tunnel's
    10.8.0.6 under it; `longname`: a long name, 40 characters, on port 17455, on one line. Not the
    longest: LocalHostName allows 63 characters, and from about 46 with the port (52 without) a
    MagicDNS name wraps after a hyphen, never cut);
  - menu.txt's two new items;
  - a card sample with a remote device.
- **Packaging/Info.plist:** unchanged. Listening and accepting need no Local Network access (TN3179),
  and the existing Local Network description covers the router query.

---

### 7. iOS client

#### 7.1 Files (each new file needs its four pbxproj entries, by hand)

| File | Change |
|---|---|
| `Sources/StreamProtocol/*` (shared) | Remote.swift, RemoteTLS.swift, RemoteIdentity.swift, Pairing.swift, AddressParser.swift, SafeText.swift (new); StreamMessage.swift (kinds 18–22 and caps); HostSettings.swift (the Low preset, §7.11) |
| `iOSClient/DeviceIdentity.swift` (new) | The device's key and certificate, and its `sec_identity_t` |
| `iOSClient/SavedMacs.swift` (new) | `SavedMac`, storage, merge and refresh rules (pure parts checked with swiftc) |
| `iOSClient/RemoteDialPolicy.swift` (new, pure) | Dial order, failure kinds and copy priority |
| `iOSClient/RemoteConnector.swift` (new) | One remote dial of a saved Mac: attempts, timeouts, the winner |
| `iOSClient/StreamClient+Remote.swift` (new) | Pairing, the session gate, kinds 18/20/22, the route, links |
| `iOSClient/AddMacCard.swift` (new) | The connect screen's Add a Mac card (scan and type) |
| `iOSClient/CodeScanner.swift` (new) | `DataScannerViewController`, embedded |
| `iOSClient/PairingOverlay.swift` (new) | Pair This iPad… over the stream |
| `iOSClient/StreamClient.swift` | `FoundMac`, TXT browsing, rows, reconnect, liveness, caps, `readPayload` EOF handling |
| `iOSClient/DiscoveryPolicy.swift` | Remote rows and remote dial timing (pure) |
| `iOSClient/ContentView.swift` | The connect screen (the line, the card, Remote rows and their menus), `onOpenURL`, the harness |
| `iOSClient/HostSettingsPanel.swift` | The route line, Away from home, the Direct Wireless row on remote, footnotes, the callout |
| `iOSClient/StreamScreen.swift`, `PortraitStreamScreen.swift` | Host the overlay; `wantedFPS(remote:)` |
| `iOSClient/StreamClient+Viewport.swift` | `wantedFPS(remote:)` caps at 60 |
| `iOSClient/MockCatalog.swift` | The new connect and settings cases |
| `iOSClient/Info.plist` | `NSCameraUsageDescription` "Sill scans the code on your Mac to pair with it.", and `CFBundleURLTypes` with scheme `sill` |

#### 7.2 The device's identity and saved Macs

- **`DeviceIdentity`:**
  - a P-256 key with tag `me.saffer.sill.device-key`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
    never synchronizable;
  - in the Secure Enclave when R0-a shows Network.framework can sign the handshake with it (open
    question 12), else a software Keychain key;
  - created at the first pairing; its certificate rebuilt at launch.
  - A locked or stolen device cannot use it; it is not in backups.
- **`SavedMac`** (Codable, UserDefaults key `Sill.savedMacs`, JSON, at most 16; the oldest
  `lastConnectedAt ?? pairedAt` is dropped first):

  ```swift
  struct SavedMac: Codable, Hashable {
      var macID: String            // 16 Crockford characters; == MacID(fingerprint)
      var fingerprint: String      // base64url SHA-256 of the Mac's SPKI: the pin
      var name: String             // from kind 20, then verified kind 18
      var recognitionKey: String   // base64url, from kind 20: resolves the TXT tag
      var remotePort: Int          // from the link, then kind 18
      var addresses: [MacAddress]  // from the link, then kind 18; plus typed ones (kept on refresh)
      var infoIssuedAt: Double     // the newest kind 18 taken
      var bonjourName: String?     // the service name of the last network or Direct connection to it
      var lastWorked: String?      // "host|port" of the last address that won a remote dial
      var pairedAt: Date
      var method: String           // "qr" | "code"
      var lastConnectedAt: Date?
      var lastRoute: String?       // "Tailscale", "your VPN", "the internet", "by address"
  }
  ```

- **Saved** only after kind 20 ok with a valid `proof_M`, so a typo or a stranger is never stored.
- **Refreshed** only by a verified kind 18:
  - `SHA256(SPKI(key)) == fingerprint`;
  - the ECDSA signature verifies (`SecKeyCreateWithData`, then `SecKeyVerifySignature`);
  - `macID` matches;
  - `issuedAt` is newer.

  Refreshed: name, port and the Mac's addresses. Typed addresses and `lastWorked` are kept. The
  `bonjourName` is learned from the connection's `.service` endpoint.
- **An unpaired device** decodes kind 18 without verifying it, for display only (the Away from home
  group). Nothing is saved.
- **Never saved:** link-local, zone-scoped and (in Release) loopback addresses. DEBUG builds keep
  `127.0.0.1` for the simulator tests.
- **At launch,** if saved Macs exist but the device key does not (a restore from backup, since the
  key is `ThisDeviceOnly`), the saved Macs are cleared.
- **Forget** removes the record only. The Mac lists the device until it is removed there, and the
  copy says so.

#### 7.3 Discovery and rows (`StreamClient`, `DiscoveryPolicy`)

- **Browsers.** Both use `.bonjourWithTXTRecord`. `recomputeMacs` resolves each result's `r` against
  every saved Mac's recognition key (`RecognitionTag.matches`).
- **`FoundMac`:** `name`, `endpoint: NWEndpoint?`, `route: .network | .direct | .remote`,
  `macID: String?`, `id = "\(route):\(macID ?? name)"`, and `direct` kept as a computed property.
  Today's `id = name` would collide between a network "Mac mini" and a Remote "Mac mini".
- **Rows, in order:**
  1. network rows, then Direct rows (the existing rules);
  2. **Remote rows:** saved Macs whose `macID` neither browser lists. They appear once
     `now ≥ searchingSince + networkFirst` (3 s), or at once when Local Network access is denied
     (then they are the only route left).
- **Remote rows count as listed,** so the hint stays away while one shows.
- **The nearby search** for a remembered Direct Wireless Mac still starts by itself, unchanged.
- **Two saved Macs of one name** read "Mac mini" and "Mac mini (2)", by `pairedAt`.
- **New pure API in `DiscoveryPolicy`:**

  ```swift
  static let remoteWait = 3.0
  static let redialWindow = 120.0
  static func remoteRows(saved: [(macID: String, name: String)], listedIDs: Set<String>, now: Double,
                         searchingSince: Double, localNetworkDenied: Bool) -> [(macID: String, name: String)]
  static func remoteDialDue(listed: Bool, lostAt: Double, networkLeftAt: Double?, rememberedDirect: Bool,
                            pathChangedSinceLoss: Bool, now: Double) -> (dial: Bool, recheckAt: Double?)
  ```

#### 7.4 Reconnect order (automatic, after a session ends on its own)

A session to a **saved** Mac ends. It was not Disconnect and not goodbye `removed`. `lostAt` is
recorded, with the device's path signature at that moment (NWPathMonitor: status, interface names
and types, `isExpensive`). Then, at every browser change and at every due time:

1. **Its network row** (tag match, or the exact `bonjourName` when the host has no tag) → connect at
   once, over the home door.
2. **Its Direct row** → the existing rule: listed as Direct for `directWait` (6 s), and the network
   last listed the Mac at least `networkGrace` (10 s) ago (fixes). On origin/main without the fixes,
   Direct at 3 s.
3. **Neither → a remote dial** of its saved addresses (§7.5) once `remoteDialDue` says so:
   - `due = lostAt + (rememberedDirect ? directWait : remoteWait)`;
   - unless the device's own path changed since the loss (it left home, or Wi‑Fi became cellular),
     `due = max(due, networkLeftAt + networkGrace)`: a Mac the network listed moments ago is taken to
     be blinking;
   - status "Reconnecting to ‹Mac› remotely…";
   - a failed dial retries after 2, 4, 8, then every 10 s.
4. **After `lostAt + 120 s`:** no more automatic remote dials. Status "Stopped trying to reach ‹Mac›.
   Tap it to try again."

**More rules:**
- A network or Direct row for that Mac that appears while a remote dial has no window list yet
  cancels the dial and takes the row.
- An established remote session is never moved (a later step may reuse `moveToNetwork`).
- By goodbye reason:
  - `quit`: as above (the Mac comes back);
  - `remoteOff` or `internetOff`: steps 1–2 only;
  - `removed`: nothing automatic.
- **Unsaved Macs:** today's rules, by exact Bonjour name.
- **No automatic dial at launch,** as today: a tap starts everything.
- **Taps:**
  - on a Remote row: a remote dial, "Connecting to ‹Mac› remotely…";
  - on a saved Mac's network row's menu, **Connect Remotely**: a remote dial at home, to test the VPN
    path.

#### 7.5 Dialing a saved Mac (`RemoteConnector`, `RemoteDialPolicy`)

- **Order (`RemoteDialPolicy.order`):**
  1. the address that last worked;
  2. VPN names, VPN IPv4, VPN IPv6;
  3. LAN addresses in a subnet this device shares (it is at home, but Bonjour failed);
  4. internet names, internet IPs;
  5. the other LAN addresses (a VPN into the home network).

  The port is `address.port ?? remotePort`.
- **Timing:**
  - attempts start 1 s apart, or at once when the previous one fails;
  - each has TCP `connectionTimeout` 10 s;
  - the whole dial gives up after 20 s.
- **Parameters:**
  - TLS from `RemoteTLS` with ALPN `sill/1`;
  - a verify block that accepts only the saved fingerprint;
  - the §3.3 TCP options;
  - `includePeerToPeer = false`.
- **The winner** is the first attempt to reach `.ready` (pinned). The others are cancelled at once,
  so the Mac does not serve a second catalog.
  - The winner still has to deliver a window list within 10 s, or the dial fails as "didn't answer".
  - A read error of -9825 or -9829 right after `.ready` means revoked.
- **`.waiting(e)`** on an attempt ends that attempt at once: no 5 s wait as at StreamClient.swift:
  465-473.
- **Error kinds, for the copy (§7.8):**

  | Error | Kind |
  |---|---|
  | `.tls(-9808)` while waiting, the pin failed | wrong Mac. On a LAN-kind address it is only another machine at that number, not a wrong Mac, and does not count |
  | -9825 or -9829 after `.ready`, or goodbye `removed` | revoked |
  | `.posix(ECONNREFUSED)` | refused |
  | `.dns(NoSuchRecord or NoSuchName)` | name not found |
  | `.tls(-9836)`, another TLS error, a wrong ALPN, or an oversized message | not Sill |
  | `ETIMEDOUT`, `ENETUNREACH`, `EHOSTUNREACH`, the 10 s timeout | didn't answer |
  | `.dns(PolicyDenied)` on a LAN address | Local Network |
  | A VPN-kind address (100.64/10, fd7a:115c:a1e0::/48, a `.ts.net` name, or kind "vpn") whose attempt's path used no tunnel interface (`!path.usesInterfaceType(.other)`), or a `.ts.net` name that does not resolve | VPN off here |

- **Priority when every attempt failed:** wrong Mac, revoked, refused, VPN off here, name not found,
  not Sill, didn't answer.
- **Pairing dials** use the link's addresses one at a time (never raced: pairing is single-use), in
  the same order, each with the 10 s timeout. A typed pairing dials the typed address only.
- **The address that wins** is saved as `lastWorked`, and the session's `lastRoute` is set.

#### 7.6 The session on a remote route (`StreamClient+Remote.swift`)

- **`connected`, `connectedAt` and "Connected to ‹Mac›"** are set at the first window list that
  decodes, not at `.ready`: with TLS 1.3 the device is `.ready` before the Mac has judged its
  certificate. The panel's 2 s wait for an older Mac then counts from the right moment
  (HostSettingsPanel.swift:66-71). Home-door sessions keep today's rule.
- **`route`** (`@Published`): `.network`, `.direct` or `.remote(label)`. `connectedDirectly` stays for
  the fixes' code. The remote label comes from the winning address and the path:
  - the path uses a tunnel interface → the address's `via` if it is a VPN service name, else "your
    VPN";
  - an internet-kind address → "the internet";
  - otherwise → "by address".
- **Liveness, on every route:**
  - `lastReceivedAt` is updated on the network queue at every completed receive with data (frames,
    ticks, pongs);
  - the 0.25 s ping timer calls `connectionLost` when `now − lastReceivedAt > max(6 s, 4 × the worst
    RTT of the last second that measured one)`;
  - it is reset at `.ready`, at the first window list, and on `willEnterForegroundNotification`, so
    returning from the background never counts as a loss;
  - remote routes also: `viabilityUpdateHandler(false)` for more than 3 s is a loss.
  - Today the client has no liveness rule, and a dead path keeps a frozen picture.
- **Caps:**
  - `readPayload` refuses frames over 32 MiB and anything else over 4 MiB;
  - it stops ignoring EOF and errors (StreamClient.swift:698-710): a nil payload with `isComplete` or
    an error is `connectionLost`.
- **Frame rate:** `Viewport.fps` is at most 60 when the route is remote and the label is a VPN or the
  internet (`StreamClient+Viewport.wantedFPS(remote:)`). A LAN device at 120 beside it still keeps
  the shared stream at 120.
- **The automatic Desktop wait** after a watched window closes becomes 2 s plus the worst recent RTT
  (StreamClient.swift:754).
- **Pings** stay at 0.25 s. The settings pick timeout stays `max(4 s, 4 × RTT)` (:911).

#### 7.7 Pairing flows on the device

- **Add a Mac, scan** (the default): the embedded scanner reads a `sill://pair` link →
  `PairLink.parse` → a pairing dial with the pin `k` → kind 19 `method "qr"` → kind 20 ok → check
  `proof_M` → save → a session dial (pinned) → the stream screen.
  - A code that is not `sill://pair` shows "That’s not a Sill code." under the viewfinder for 2 s.
  - The person chose to point the camera, so there is no confirmation step.
- **Add a Mac, typed:** Address plus Code.
  - The code's check digit is validated locally.
  - A pairing dial with no pin: any P-256 key, bound into `proof_D` with `method "code"`.
  - Save only after `proof_M` checks, then pin.
- **An outside link** (`onOpenURL`: the system Camera, Messages, `xcrun simctl openurl`):
  - never acted on by itself;
  - it shows a confirmation in the card's place, or over the stream when connected: "Pair with ‹Mac›
    at ‹first address›? Only pair with a code your own Mac shows." with **Pair** and **Cancel**.
  - This covers a hostile poster or message, which could otherwise add a look-alike "Mac" that
    collects keystrokes.
- **Pair This iPad…** (the panel, while connected at home to a Mac whose kind 18 says
  `remoteAccess: true` and which this device has not saved):
  - it sends kind 21 and covers the stream with the overlay (§7.10);
  - scan → the pairing dial as above;
  - the typed path needs only the code, since the address comes from this connection's kind 18
    (preferring a LAN address in a subnet this device shares);
  - on kind 20 ok it saves and **closes the pairing connection**: the home session goes on.
- **After kind 20 ok with no session within 10 s** (a new pairing, not the overlay): the card closes
  and the Mac is left as a saved row. Status "Mac mini is saved. Tap it to connect."

#### 7.8 Copy on the device (every message inline; VoiceOver announces each)

**Connect screen:**

| Where | Text |
|---|---|
| Remote row | `DrawerRow` with trailing "Remote"; hint "Connects through your VPN or the internet." |
| The line | "Add a Mac…"; hint "Pairs this ‹iPad› with a Mac so you can reach it away from home." (‹iPad› = iPhone or iPad by idiom, as elsewhere) |
| The hint sentence (ContentView.swift:245), shown only when nothing is listed, as today | "Your Mac has to be on the same Wi‑Fi network as this ‹iPad›, or have Direct Wireless Connection turned on in Sill. Away from home, add it once with a code from your Mac." |
| Status | "Connecting to Mac mini remotely…" · "Reconnecting to Mac mini remotely…" · "Pairing with Mac mini…" / "Pairing with 100.101.102.103…" · "Mac mini disconnected. Sill will reconnect when it can reach it." (a saved Mac) · "Stopped trying to reach Mac mini. Tap it to try again." · "Mac mini is saved. Tap it to connect." |
| Goodbyes | quit: "Mac mini quit Sill. This ‹iPad› reconnects when it’s back." · removed: "Mac mini removed this ‹iPad›. To use it again, pair it again." · remoteOff: "Mac mini turned off Remote Access." · internetOff: "Mac mini stopped accepting connections from the internet. Connect through your VPN." · busy: "Mac mini is already serving 8 devices." |
| Row menus (system context menus, as the panel's Quality picker already is) | Remote row: **Connect**, **Forget Mac mini**. A saved Mac's network row: **Connect Remotely**, **Forget Mac mini** |

**Add a Mac card:**

| Where | Text |
|---|---|
| Title | "Add a Mac" (a heading; VoiceOver focus moves to it) |
| Intro | "Pair once, and Sill reaches your Mac from anywhere, through your VPN or the internet." |
| Scan instruction | "On your Mac, choose Pair iPhone or iPad… in the Sill menu, then point this ‹iPad› at the code." |
| Viewfinder | Caption "Point at the code on your Mac"; spoken "Camera. Point it at the code on your Mac." |
| Links | "Enter Code Instead" / "Scan Code Instead" · "Cancel" |
| Typed | "Type the address and code that Sill shows on your Mac." Fields: Address (placeholder "100.101.102.103 or mac.example.net"; `.URL` keyboard; no autocorrection or capitalization; Return moves on) and Code (placeholder "0000 0000 0000"; `.numberPad`; groups of 4 as typed; paste accepted). [Pair] |
| Camera | "Sill can’t use the camera. Enter the code instead, or allow the camera in Settings." [Open Settings]. The simulator (`isSupported == false`) goes straight to the typed path |

**Inline pairing errors** (orange, under the field they belong to):
- "That doesn’t look like an address. Try 100.101.102.103 or mac.example.net."
- "A code has 12 digits."
- "That code has a typo. Check it against your Mac."
- "That code didn’t work. Check the code on your Mac. 4 tries left."
- "Mac mini isn’t pairing right now. On your Mac, choose Pair iPhone or iPad… first." (-9825 on a
  pairing dial)
- "Mac mini stopped pairing after too many wrong codes. Choose Pair iPhone or iPad… on your Mac for
  a new code."
- "This code expired. Choose Pair iPhone or iPad… on your Mac for a new one."
- "Pairing didn’t finish: the Mac at 100.101.102.103 couldn’t show it knows the code. Pair from the
  same network as your Mac, or scan the code instead." (a bad `proof_M`, or no kind 20 in 15 s)
- "Nothing answered at 100.101.102.103. Check the address, and that Sill is open on your Mac."
- "Something answered at 100.101.102.103, but it isn’t Sill, or its Sill is too old to pair."
- "That’s not a Sill code."

**Remote dial failures** (the status line, by the priority of §7.5):

| Kind | Text |
|---|---|
| wrong Mac | "This isn’t the Mac mini this ‹iPad› paired with. If Sill was set up again on it, forget it here and pair again." (no Connect Anyway) |
| revoked | "Mac mini no longer accepts this ‹iPad›. Pair it again from Sill’s Settings on the Mac." |
| refused | "Mac mini answered, but Sill isn’t accepting remote connections there. Check that Sill is open and Remote Access is on. If you changed its port, connect at home once." |
| VPN off here | "Tailscale looks off on this ‹iPad›. Turn it on, then tap Mac mini." ("Your VPN" when the address has no service name) |
| name not found | ".ts.net" names: "This ‹iPad› can’t look up mac-mini.tail1234.ts.net. Is Tailscale on?"; others: "This ‹iPad› can’t look up home.example.net." |
| not Sill | "Something answered at 203.0.113.9, but it isn’t Sill. Your home’s internet address may have changed." |
| didn't answer | "Mac mini didn’t answer. It may be asleep, or Tailscale may be off on the Mac." For a raw internet IP: "Mac mini didn’t answer at 203.0.113.9. If your home’s internet address changed, connect at home once to update it, or add an address name on the Mac." |
| Local Network | "To reach 192.168.1.20, allow Local Network for Sill in Settings." |

#### 7.9 The address parser (`Sources/StreamProtocol/AddressParser.swift`, pure; Foundation and `inet_pton`)

- Trim the ends; refuse whitespace inside. A pasted " 100.1.1.1" would otherwise become a DNS name.
- `[v6]` and `[v6]:port`. A string with two or more colons and no brackets must parse as a bare IPv6
  address with no port, so `fd7a::1:7455` is an address, never an address plus a port.
- Zone IDs (`%en0`) are refused: "Remove the part after %: it only works on this network."
- `::ffff:a.b.c.d` is treated as IPv4.
- An all-numeric dotted string must be exactly four decimal octets 0–255, with no leading zeros.
  `NWEndpoint.Host` silently dials `1.2.3` as 1.2.0.3, `100.1` as 100.0.0.1 and `0x64.0x65.1.2` as
  100.101.1.2; all are refused here.
- Names follow RFC 1123: labels of 1–63 letters, digits and hyphens (not at either end), 253
  characters in all, an optional trailing dot. Single labels are allowed (MagicDNS short names,
  `localhost`). Names whose labels are all numeric are refused.
- Ports are 1–65535. With none, the Mac's remote port applies (7455 when unknown).
- `sill://pair…` input is handed to `PairLink`.
- DEBUG `-SillConnect` uses this parser too, so `[::1]:P` works (today's split at the last colon
  breaks IPv6).

#### 7.10 Layout per size (connect screen, Add a Mac card, overlay)

- **The connect column** is 380 pt, leading-aligned, centred vertically (ContentView.swift:212-282).
  - "Add a Mac…" is always its last item: 15 pt semibold, accent colour, at least 44 pt tall, leading
    (the Search Nearby style). It is there from the first frame, so nothing moves later.
  - Tapping it unfolds the card in place: the rows and the hint fold away and the title reads "Add a
    Mac". Esc, Cancel or the VoiceOver escape gesture folds it back.
- **The viewfinder** is the column's width × 230 pt, corner radius 12, on `Palette.control`.
- **The fields** are 48 pt tall, like the drawer's search field (StreamScreen.swift:1034-1052).

| Screen | Layout |
|---|---|
| Duo inner 1000×710 | As described, centred |
| Duo half-folded or laptop 710×1000 | The whole column is anchored in the top half (centre at y = 250, height at most 470), so nothing crosses the crease at y = 500. The keyboard fills the lower half |
| Duo outer 500×710 | As described. While a field has focus, the intro and the instruction collapse to one line, "Type the address and code from your Mac.", and the column anchors to the top |
| Duo outer 710×500, iPhone landscape 874×402, any height under 520 pt | The card goes side by side: the viewfinder (260×200) leading, text and buttons trailing. The typed path shows only the two fields, Pair and the collapsed line while the keyboard is up |
| iPhone portrait, 402 pt and wider | As described |
| Narrower than 412 pt (375×667) | The column is the screen width minus 32 pt. This also fixes today's zero margin |
| iPad mini 744×1133 and 1133×744 | As described |

- **The overlay** (Pair This iPad…): full-bleed, 85 % black, in the view hierarchy (never a
  presentation).
  - Title "Scan the Code on ‹Mac›" (a heading); caption "‹Mac› is showing a code now."
  - The viewfinder, at most 420×300; **Enter Code Instead** and **Cancel**.
  - The keyboard and the panel are put away first (`InputOverlayProxy.setKeyboard`), so no key
    reaches the Mac.
  - The same size rules: the top half at 710×1000; side by side under 520 pt.
  - On success: "Paired with ‹Mac›." and a fade after 1 s.
- **Accessibility:**
  - fields and errors capped at `.xxLarge`, like the panel;
  - Reduce Motion fades instead of unfolding;
  - hardware keyboard: Return moves between fields and then pairs; Esc folds the card or closes the
    overlay;
  - the connect screen keeps its fixed 17, 13 and 15 pt sizes (Dynamic Type there is a separate
    job).

#### 7.11 The panel (`HostSettingsPanel.swift`) and the Low preset

- **Header readout** (:97-105): one route line where "Connected directly" sits.
  - "Connected through Tailscale · 48 ms", "Connected through your VPN · 60 ms", "Connected over the
    internet · 120 ms" or "Connected by address · 6 ms".
  - The figure is `linkStats.rtt.median`, updated once a second; "–" for a second without a pong.
  - Spoken: ", connected through Tailscale, 48 millisecond round trip" (`spokenReadout`, :282-287).
  - Round trip needs no clock agreement between the two devices, unlike frame age.
- **"Away from home"**, a new last group after the Direct Wireless one. Hidden when no kind 18
  arrived within 2 s of the first window list.

  | Situation | Group |
  |---|---|
  | This device saved this Mac (the macID of kind 18 is saved) | A row with a leading checkmark, "Paired for remote access". Footnote: "Away from home, Sill reaches Mac mini through Tailscale (mac-mini.tail1234.ts.net)." (the first VPN or internet address; otherwise "through your VPN or the internet") |
  | Not saved, `remoteAccess` on | A button row **Pair This ‹iPad›…**. Footnote: "Pair once to reach Mac mini through your VPN or the internet. Mac mini shows a code; scan it with this ‹iPad›." |
  | Not saved, `remoteAccess` off | Footnote only: "To reach Mac mini away from home, turn on Remote Access in Sill’s Settings on the Mac." |
  | Connected remotely | The paired row, and "Connected through Tailscale." |

- **The Direct Wireless row on a remote route:** disabled, with "Change this on Mac mini, or from a
  device near it." The host refuses it anyway.
- **Frame-rate footnote** (:303-314), while remote: "Away from home, this ‹iPad› asks for 60 fps,
  which halves the data your Mac sends."
- **Slow-link callout** (the existing `Callout`, above the groups): while remote, when the median of
  the last five one-second RTT medians is over 250 ms: "The picture is arriving slowly from Mac
  mini. Choose Low quality or Standard resolution."
  - It goes when the link recovers or the panel closes.
  - It is judged by round trip, because a still window legitimately sends no frames.
- **The Low preset.** `QualityPreset.low = 4_000_000`, first in `allCases`, titled "Low".
  - So `SettingsChoices.bitrate`, `DeviceSettings.accepted`, the Mac's menu and Settings picker, and
    the device's picker all gain it.
  - An older device shows it as "Custom — 4 Mbps", read-only (HostSettings.swift:182-184).
  - An older host refuses a 4 Mbps pick, and the panel goes back with the warning haptic.
  - Quality is host-wide and Sill.app saves it, so a remote downgrade follows the user home. The
    README says so.

#### 7.12 Harness and DEBUG arguments (the contract comment at ContentView.swift:56-91, and CLAUDE.md)

- **`-SillConnectCase`** keeps `looking|hint|nearby|denied` (re-shot: they now show the Add a Mac
  line) and gains:
  - `remote`: a network row, a Direct row, and two Remote rows (one long name, one "(2)");
  - `addmac`: the card with a placeholder viewfinder;
  - `addcode`: the typed path, empty;
  - `addcodeerror`: "That code didn’t work…";
  - `pairing`: "Pairing with Mac mini…";
  - `remotedial`: "Connecting to Mac mini remotely…";
  - `remotefail`, with `-SillRemoteFailure vpnoff|timeout|refused|dns|wrongmac|revoked|notsill|gaveup|quit|removed|remoteoff`;
  - `camera`: the camera refused;
  - `externalpair`: the link confirmation.
- **`-SillSettingsCase`** gains:
  - `remote`: Tailscale, 48 ms, paired;
  - `remoteinternet`;
  - `remoteslow`: the callout;
  - `remotepair`: on, not paired, Pair This iPad…;
  - `remoteoff`;
  - `noremote`: no kind 18, so no group.
- **`-SillScanOverlay 1`:** the stream screen with the overlay.
- **`-Sill.savedMacs '<JSON>'`** seeds saved Macs for one run (the argument domain, never written);
  `'[]'` empties them.
- **`-SillPairURL '<url>'`** (normal app): pairs with that link at launch, without the confirmation,
  then streams.
- **`-SillPairCode <12 digits> -SillPairAddress host:port`:** the typed path at launch.
- **`-SillDialSaved 1`:** dials the first saved Mac's addresses at launch, as a tap on its Remote row
  would.
- **`-SillForgetMacs 1`:** clears saved Macs and the device key at launch.
- **`-SillConnect host:port`:** unchanged (a plain dial to the home door); it now uses the address
  parser, and **never saves anything**.

---

### 8. Timeouts and limits (one table)

| What | Value |
|---|---|
| Remote door: accept → admission (TLS, plus kind 19 on a pairing connection) | 10 s |
| Remote door: pending connections | 8 in total, 2 per source; 5 failures in 60 s → refused for 300 s |
| Remote door: sessions | 8 |
| Remote door: port retry | every 30 s and on network changes; never another port |
| Remote clients: silence eviction | 8 s, after 8 s since admission |
| Remote clients: drain backstop | 15 s, after a 15 s grace |
| Remote clients: forced keyframe requests | at least 2 s apart |
| Remote door TCP | keepalive 5/2/3; `connectionDropTime` 15 s |
| Home clients | unchanged: drain 4 s, grace 8 s |
| Pairing window | 300 s; 5 wrong proofs; spacing 1/2/4/8 s; 5 s per source; one proof per connection; K ready about 0.15 s after opening |
| Kind 21 | once per 30 s per connection |
| Kind 17 | 4 applied per second per connection |
| Client → host payload | 1 MiB (pairing: 4 KiB) |
| Host → device payload | frames 32 MiB, other 4 MiB |
| Goodbye then close | after the send completes or 250 ms; quit 100 ms for everyone |
| Summary log lines | at most once a minute (refusals); once a second (kind 17) |
| Device: attempt connect timeout | 10 s |
| Device: attempt stagger / whole dial | 1 s / 20 s |
| Device: first window list after `.ready` (remote) | 10 s |
| Device: kind 20 after kind 19 | 15 s |
| Device: liveness | no byte for max(6 s, 4 × worst RTT); remote also viability false > 3 s |
| Device: Remote rows appear | 3 s after searching began (at once with Local Network denied) |
| Device: automatic remote dial | 3 s after the loss (6 s if remembered Direct); not within 10 s of the network last listing the Mac unless the device's path changed |
| Device: automatic redials | 2, 4, 8, then 10 s; stop 120 s after the loss |
| Device: auto-Desktop wait | 2 s plus the worst recent RTT |
| Device: Away from home group | hidden without a kind 18 within 2 s of the first window list |
| Device: slow-link callout | the median of the last 5 RTT medians over 250 ms |
| Mac: MagicDNS check | `getaddrinfo`, 2 s budget |
| Mac: address change coalescing | 0.5 s |

---

### 9. Edge cases

| Case | Behaviour |
|---|---|
| Tailscale on both, at home | Bonjour lists the Mac and the tag matches, so the device shows only the network row, over the home door. **Connect Remotely** tests the tailnet path on purpose |
| A Tailscale exit node on the device (Bonjour quiet at home) | The Remote row after 3 s. The remote door admits it as `vpn` |
| A Tailscale exit node on the Mac | The primary interface becomes utun. The router is asked on the primary non-tunnel interface. LAN addresses are still listed |
| Tailscale shields up, or ACLs that block 7455 | Dials time out with the "didn't answer" copy. The README's troubleshooting names both (an ACL must allow TCP 7455 to the Mac) |
| MagicDNS off on the device | The `.ts.net` name fails at once, and the IPs beside it are tried |
| A WireGuard VPN into the home router | The Mac lists "Wi‑Fi — 192.168.1.20" with its note. Away, the LAN address is dialled through the tunnel; the remote door classifies the routed private source as `lan` |
| The VPN off on the device | "Tailscale looks off on this ‹iPad›…"; the Remote row stays (it is a saved Mac) |
| The VPN off on the Mac | The pane shows "Tailscale — Not connected". The device: "didn't answer…" |
| The home's public IP changes | Names follow by themselves. A raw IP gets the "didn't answer at …" copy, and refreshes at the next home connection (verified kind 18) |
| Carrier-grade NAT or double NAT | The pane says so, in orange; a VPN is the way. Sill never opens router ports |
| The router forwards another outside port (17455 → 7455) | The Mac's address name `home.example.net:17455`, or typed on the device; the saved address keeps its own port |
| IPv6 | Temporary, deprecated and link-local addresses are never listed; zone IDs are refused; a global address shows only with the internet switch, with its router warning; brackets in links and typed input |
| Two Macs of one name | Keyed by Mac ID; "Mac mini" and "Mac mini (2)"; tags tell their network rows apart; pairing one never touches the other |
| One Mac, a Bonjour clash ("Mac (2)") | Matched by the tag, whatever the name |
| Sill reinstalled on the Mac (new key) | Pins fail: "This isn't the Mac mini this ‹iPad› paired with…". Forget, then pair again. The network row is the new Mac, untagged for this device until it pairs |
| The device restored from a backup | No device key (`ThisDeviceOnly`), so its saved Macs are cleared at launch; it pairs again, and the Mac shows the old record with an old "last connected" date until Remove |
| Remote Access turned off while devices stream remotely | goodbye `remoteOff`; the pairing window closes; redials are refused ("…isn't accepting remote connections…") |
| Internet access turned off while an internet device streams | goodbye `internetOff`; VPN devices carry on |
| The port changed while devices stream remotely | Live sessions continue; kind 18 carries the new port. An away device that missed it gets the refused copy, "connect at home once" |
| The port in use at launch | The attention item and the orange row; a retry every 30 s; the home door is unaffected |
| Sill.app and the CLI side by side | The CLI takes any port for `--remote`; the app keeps 7455. Two identities; tags tell them apart |
| A remote device changes Quality | Allowed and saved, as today; it follows the person home; the menu shows it |
| A remote device toggles Direct Wireless | Refused and answered unchanged; the panel's row is disabled with its reason |
| A kind 21 flood from a home device | One per 30 s per connection; an open window is not reopened |
| A scanned code whose Mac is unreachable from here (office Mac, device on cellular) | Every address fails: "Nothing answered…". Pairing needs the device to reach the Mac once |
| Pairing through a relay (on-path attacker) | QR: the pin refuses it before anything is sent. Code: proofs bind both keys; offline grinding costs about 10,000 GPUs for 5 minutes |
| Scanners on a forwarded port (internet switch on) | TLS alerts only, never a byte of Sill; caps; one summary line a minute |
| A stranger's Sill on a café LAN, with the same name | Its tag does not match: a plain network row, not the saved Mac. The home door stays unauthenticated until M5, as today |
| A local process connecting over loopback | The home door serves it, as today (a confused deputy for Sill's TCC grants). Closing that is M5's, with the home door behind pairing (open question 1) |
| The Mac asleep, or a closed laptop lid | "didn't answer"; the pane's sleep line. Bonjour Sleep Proxy wakes work only on the LAN |
| The Mac's display asleep or locked during a remote session | Unknown whether capture continues (R6) |
| The app backgrounded during a remote session | The host drops it after 8 s of silence; on return, liveness is reset, and a reconnect follows if the session is gone |
| Wi‑Fi → cellular during a remote session | A VPN usually keeps the inner TCP connection. Over a public IP the connection dies; liveness, then a redial that skips `networkGrace` (the path changed) |
| Hotel or café networks that block outbound ports | Tailscale still works (DERP over 443). A direct public-IP dial to 7455 may not ("didn't answer") |
| A clock-skewed device | The route line uses RTT, never frame age |
| Direct Wireless and a saved Mac | A Direct row hides that Mac's Remote row. After a drop: Direct at 6 s, remote after that. Remote dials never use peer-to-peer and never teach the Direct memory (which needs a `.service` endpoint) |

---

### 10. Test gates

**Hard rules for the implementing session:**
- Only synthetic hosts from `.build/release`, started from Python with `start_new_session=True`,
  killed by PID, none left running.
- The bare `SillMenuBar --synthetic` for app paths, with `SILL_TEST_REMOTE_DIR`. Never
  `/Applications/Sill.app`, the `me.saffer.sill.mac` domain, Noah's login keychain (except R0-b,
  with his OK) or his iPad. Run `defaults delete SillMenuBar` afterwards.
- `SILL_TEST_NO_ROUTER=1` on every headless host. Never talk to the router.
- Never tap a real Mac's row in the simulator: Noah's Mac is listed.
- Keep AWDL-on tests under 20 s and on test service types.
- `$T` is a fresh temporary directory per gate. `sillclient.py --identity=$T/…` keeps its identity
  there.

**New test tools (in the repo):**
- **`Scripts/sillrelay.py`** (standard library, asyncio):
  `--listen 0 --to HOST:PORT [--delay-ms N] [--rate-mbps R] [--blackhole-after S]`.
  - A passthrough relay: TLS stays end to end.
  - Host → client shaping reads from the host only as fast as R allows, so the host's own queue
    fills as on a real uplink.
  - `--blackhole-after` stops forwarding both ways without closing.
  - It prints "sillrelay listening on 127.0.0.1:P".
- **`Scripts/sillclient.py`** gains (each checked before connecting, as today):
  - `--host=H`;
  - `--tls` with `--identity=DIR`. The identity is made on first use with
    `/usr/bin/openssl ecparam -name prime256v1 -genkey -noout -param_enc named_curve` and
    `openssl req -x509 -new -key … -subj /CN=sillclient -days 3650`. This was checked to load in
    Python 3.11.9 / OpenSSL 3.0.13 with TLS 1.3 and ALPN. It pins the Mac's SPKI hash from
    `getpeercert(binary_form=True)` with a small DER walk, and exits 3 before sending a byte on a
    mismatch;
  - `--pair-url=URL` (the QR path) and `--pair-code=CODE` (the typed path; PBKDF2 and HMAC with
    `hashlib`/`hmac`);
  - `--expect-tls-fail`, `--big-payload=BYTES`, `--flood=N`, `--pairing-wanted@T`, `--stop-ping@T`,
    `--stop-read@T`, `--device=NAME`.
  - It prints kinds 18, 20 and 22 one line each, and checks kind 18's signature with
    `openssl dgst -sha256 -verify`.

**Headless (H): no permissions needed.**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). Record the base commit; `git archive` it to `$SP/base` and build it. Baselines: `SillHost --synthetic` idle 35 s; with `sillclient.py PORT 5 desktop`; both again with `--direct-wireless`; the bare app's and the bundle's `-SillRenderPreviews`; the policy and ledger check counts; the base host through `sillrelay.py --rate-mbps 2 --delay-ms 150` for 90 s. **Probes:** P1, the loopback mTLS probe with the two ALPN values and the random-CN certificate; P2, PBKDF2 600k in Swift (CommonCrypto) equals §3.6's vector, and its time; P3, an accepted connection's `currentPath.localEndpoint` at `.preparing`, on loopback and when the Mac connects to its own Tailscale address (which interface does the local address map to?); P4, `NWBrowser.Descriptor.bonjourWithTXTRecord` reads `r` from a `_silltest._tcp` registration | Files exist; every probe answers, or the plan changes first |
| H1 | Builds: `swift build -c release`; iOS Debug and Release as the earlier steps built them | Only the known warnings (CaptureProbe; the old `StreamClient` capture warning) |
| H2 | **The CLI byte for byte.** H0's runs on the new build, digits masked, sorted | Identical, idle and streaming, with and without `--direct-wireless`; "Advertising _sill._tcp…" present; no TXT record (`dns-sd` on a test-type run) |
| H3 | **Pure checks** (swiftc; each with mutants caught): the address parser (at least 40 cases, including every §7.9 rule); `PairingCode` (Damm over 20,000 codes: every substitution and adjacent transposition caught; normalisation; lengths); `PairingProof` (§3.6's vectors exactly; the labels differ; swapped fingerprints change the proofs); certificate, fingerprint and Mac ID (`SecCertificateCreateWithData` accepts; `openssl x509 -inform der -noout -text` parses a named curve; the fingerprint agrees in Swift and Python; the Mac ID vector); `RecognitionTag` (the vector; 10,000 wrong keys never match); `SafeText`; `PairLink` (round trip, IPv6, `v≠1`, `m≠MacID(k)`, missing fields); kind 18 signing (verifies; one flipped byte fails; the wrong key fails); `OriginPolicy` (every rule, by door and switch, including 100.64/10 on utun and on en0, ULA on utun and en0, on-link and off-link global IPv6, awdl, mapped IPv4); `AddressList.build` (fixtures shaped like Noah's store: utun0–3 link-local, Tailscale on utun4, the CoreDevice ULA on utun5, en0 private plus a deprecated ULA → exactly Tailscale v4, Tailscale v6, Wi‑Fi v4, and the MagicDNS name with the resolver stubbed; also a WireGuard service, a non-NE point-to-point tunnel, Wi‑Fi plus Ethernet, temporary IPv6, and global IPv6 only with the switch); `PairingWindow` (expiry, 5 failures, single use, spacing, per source, busy before K); `DiscoveryPolicy` and `RemoteDialPolicy` (the existing checks unchanged, plus Remote rows, due times, the path-change exemption, the 120 s stop, dial order with the subnet rule, the copy priority, and a LAN pin mismatch not counting); `SavedMacs` (merge, refresh, cap, never-save rules, clearing without a key) | All pass |
| H4 | **Home door caps.** `--big-payload=5242880`; ten `--set` within 1 s; `--device` with control characters, bidi overrides and 500 characters; 50 connections reset before sending | One "Closing …" line and that client closed while a second streams; at most 4 applied, 10 answers, at most one "ignored" line a second; a clean name of at most 64 characters in the log; no descriptor growth (`lsof`) and no "Client left" lines for the reset ones |
| H5 | **Home door origin gate.** `SILL_TEST_ORIGIN=vpn`, then `=internet`, then unset; also the fixes' `SILL_TEST_PEER_TO_PEER_INTERFACE=en0` link-local client | Refused with zero bytes and one summary line; served without the variable; the en0 link-local client is served, and is disconnected when Direct Wireless turns off (the fixes' gate still passes) |
| H6 | **The remote door up.** `SillHost --synthetic --remote` | Two new lines only: the core's "Remote access: listening on port P (TLS, paired devices only; 0 paired)." and main.swift's startup line with the port, the code and the URL; `lsof` shows two listeners; without `--remote` one listener, and H2 holds; `--internet` alone exits 2 |
| H7 | **QR pairing.** `sillclient.py --tls --pair-url=URL --identity=$T/a`, then a session dial | Kind 20 ok with a valid `proof_M`; the "Paired … with the QR code" line; the session's catalog order 2, 16, 18, 4…, 5, 14; frames; kind 18 verifies and its macID equals MacID(fp) |
| H8 | **A paired session.** The same identity, no code; then `--pair-url` again | A session with negotiated ALPN `sill/1`; re-pairing replaces the record (one row in `paired.json`) |
| H9 | **Typed pairing.** `--pair-code=CODE` with no pin | `proof_M` checked, the pin saved, then a session |
| H10 | **Refusals.** (a) A new identity against the bare app with remote on and no window. (b) Five wrong codes, then the right one, and attempts under 1 s apart. (c) `SILL_TEST_PAIRING_TTL=5` and a correct code at 6 s. (d) Two clients with one code, 50 ms apart. (e) A plain client at the remote door; a TLS client at the home door; `curl http://127.0.0.1:P/` and a raw "POST /" at the remote door. (f) A paired `sill/1` session while Remote Access is off and a window is open (bare app) | (a) The client reaches ready and then a TLS read error; no Sill byte; only the minute's summary. (b) `triesLeft` 4…1, then `stopped`; the right code then gets `closed`; too soon gets `busy`. (c) `expired`. (d) Exactly one ok. (e) Dropped, with zero bytes; -9836; closed within 100 ms with no plaintext answer. (f) Goodbye `remoteOff` |
| H11 | **Pre-auth caps.** 12 raw TCP connections to the remote door from 127.0.0.1 and ::1, while a paired client streams; then 5 failed handshakes from one source (`SILL_TEST_BACKOFF_SECONDS=5`) | At most 2 held per source and 8 in all, the rest closed at once; each held one closed at 10 ± 0.5 s; the paired client served throughout; the source refused during the backoff, then allowed |
| H12 | **No plaintext.** A passthrough `sillrelay.py` records both directions of a 10 s paired session | None of "macName", "windows", "Test Pattern" or the device name appears in either direction; the host's first byte is 0x16 |
| H13 | **Remote-route rules.** From a paired session, `--set=directWireless=1,bitrate=25000000@3`; kind 21 on the remote door; kind 21 from a loopback home session (twice within 30 s); `SILL_TEST_ORIGIN=internet` with `--internet`, then internet access turned off on the bare app | Direct Wireless refused with its line, the bitrate applied, one answer; kind 21 ignored on the remote door; the CLI prints its code once in 30 s; the internet session is served, then gets goodbye `internetOff` within 1 s and EOF |
| H14 | **Slow link.** `sillrelay.py --rate-mbps 2 --delay-ms 150`, 90 s, remote session vs H0's base; also an unshaped home-door client on the new build | The base shows a "not draining" eviction or a keyframe storm. The new build: no eviction, frames in every 5 s window, forced keyframe requests at least 2 s apart, keyframes a minute at most the base's; record the pong RTT p95. The unshaped home client's keyframes a minute and `net.dropped` equal the base's within noise |
| H15 | **Liveness.** `sillrelay.py --blackhole-after 5` on a remote session, and on a home session | Remote: "Client silent for … dropping" at about 13 s (5 + 8). Home: the 4 s drain rule, as today |
| H16 | **Port.** The bare app, remote on, `-remotePort P` with P held by a Python socket; then released; then `-SillSetAfter '3 remotePort=P2'` while a remote session streams | The "in use" line and status; listening within 30 s of the release; a rebind with the session continuing, and kind 18 carrying P2 |
| H17 | **The TXT tag.** `SILL_TEST_SERVICE_TYPE=_silltest._tcp SILL_TEST_REMOTE_DIR=$T/h SillHost --synthetic --remote`; `dns-sd -t 3 -L "Sill test <pid>" _silltest._tcp local`; a Direct Wireless toggle through `sillclient --set` | An `r=` that Python resolves with `$T/h/recognition-key`; a new `r` after the replacement that still resolves; no TXT record without `--remote` |
| H18 | **Reachability.** `SillHost --print-reachability` (addresses masked in the log); kind 18 of a `--remote` host | Tailscale (plus MagicDNS when it resolves) and Wi‑Fi; no utun0–3, CoreDevice tunnel, temporary or deprecated IPv6, awdl or llw; kind 18's list equals it (with 127.0.0.1 first on test hosts); no router query with `SILL_TEST_NO_ROUTER=1` |
| H19 | **The app, persistence.** The bare `SillMenuBar --synthetic` with `SILL_TEST_REMOTE_DIR=$T/app -SillPairAfter 1 -SillLogFile $T/app.log`, then `-SillSetAfter '3 remoteAccess=1,internetAccess=1,remotePort=P'`, then a relaunch, then `-SillUnpairAfter 8` | `sillclient` pairs with `$T/app/pairing.url`; the settings save and apply (`defaults read SillMenuBar`); after the relaunch the same Mac ID, the same port and a valid pairing; goodbye `removed` within 1 s, and the next dial refused; **the log contains neither the code nor the secret** (grep both); then `defaults delete SillMenuBar` |
| H20 | **TLS cost.** 60 s at 60 fps synthetic, `sillclient --stats` over the remote door vs the home door | Host CPU within +0.5 percentage points (`ps`, release); median frame age within 1 ms |
| H21 | **Compatibility.** A swiftc decode check with a9cc248's StreamProtocol against the new kind 16 and window list; a9cc248's `sillclient.py` against the new home door; the new device decoder against an older host's messages | All decode; unknown kinds are skipped; the old client is unaffected |
| H22 | **Previews.** Before and after | Only the new tab's samples, the pairing window samples, menu.txt's new items (Remote Access…, Pair iPhone or iPad…, and Low from step 7) and the remote card sample differ. Look at each |
| H23 | **Hard rules** (grep) | No `assumeIsolated` or `updateConfiguration` in Sources/SillHost. `HostConfig.standard` has `remoteAccess: false` and `internetAccess: false`. `remoteAccess`, `remotePort` and `internetAccess` appear in neither `StreamSettings`, `HostSettingsChange` nor `DeviceSettings`. No new Stats key on the default path. No `print` of a code or secret in Sources/SillHost. `StreamServer(advertise: !synthetic)` unchanged |
| H24 | **Regression.** Spot runs of the direct-wireless and host-settings gates: the ledger check, the policy check, the swap fallbacks, the move test | As before |

**Simulator (S):** the iPad Pro 13" simulator the earlier steps used (40522E9E-8B13-4676-BC94-D94FDD048471), driven with launch arguments and the iOS Simulator control tool (inspect, then tap).

| # | Check |
|---|---|
| S1 | **The photo matrix.** Every new connect case at 1000x710, 710x1000, 500x710, 710x500, 402x874, 874x402 and 375x667; the four re-shot cases at the Duo sizes; every new settings case at the four Duo sizes and at `content_size accessibility-extra-large` (reset afterwards); the overlay at the four Duo sizes. Check: nothing crosses y = 500 at 710x1000; the card goes side by side under 520 pt; "Remote" is never truncated; errors wrap; the title does not move sideways. Send Noah the sheet |
| S2 | **Taps.** Add a Mac unfolds and Cancel folds it; Enter Code Instead and back; Esc; Return moves between fields; a check-digit error with nothing sent (no connection opened); Forget in a Remote row's menu (mock) |
| S3 | **Live pairing.** `SillHost --synthetic --remote`; the normal app with `-SillPairURL '<printed URL>'` → paired over TLS (the host's line), streaming, "Connected by address · N ms". Then `xcrun simctl openurl <udid> '<URL>'` shows the confirmation (photo). Disconnect → the Remote row appears after 3 s (synthetic hosts do not advertise); relaunch with `-SillDialSaved 1` → a pinned session. The typed path with `-SillPairCode … -SillPairAddress 127.0.0.1:P`. Afterwards `-SillForgetMacs 1`, or reset the simulator's keychain for Sill |
| S4 | **Reconnect.** The bare app with `SILL_TEST_REMOTE_DIR`, killed mid-stream → "Reconnecting to … remotely…" within about 6 s; relaunched → back without a tap. Through `sillrelay.py --blackhole-after 5` → the device's liveness fires in 6–7 s |
| S5 | **Live failure copy.** Refused (host stopped); timeout (a seeded Mac at 192.0.2.1); wrong Mac (another test directory on the same port); revoked (`-SillUnpairAfter`); name (`nowhere.invalid`); not Sill (a Python listener sending an SSH banner); goodbye `quit` and `removed` |
| S6 | **Accessibility.** The labels, hints, headings and focus moves of §7.10, from the accessibility tree |
| S7 | **An older host.** a9cc248's `SillHost --synthetic`, built from `$SP/base`, with `-SillConnect` → no Away from home group after 2 s; no kind 19 or 21 sent |
| S8 | **A slow link.** `sillrelay.py --delay-ms 150 --rate-mbps 5` between the simulator and a remote session: pairing completes; the device asks for 60 fps; with `--delay-ms 300` the slow-link callout appears |

**Noah's devices (R), handed over at the end:** the iPad mini, and an iPhone for hotspot or cellular.

| # | Check |
|---|---|
| R0 | **Probes, with Noah.** (a) A DEBUG-only check: a Secure Enclave key signing TLS client authentication against `SillHost --synthetic --remote` over the LAN (decides open question 12). (b) With Noah's OK, since it writes to his login keychain: `make-app.sh --install --open` creates the identity; rebuild and relaunch read it without a prompt. (c) `natpmp-probe` from Terminal (`scratchpad/remote-access/natpmp-probe.swift`). (d) The embedded scanner on the iPad |
| R1 | **Tailscale setup, timed (under 2 minutes).** Remote Access on; menu › Pair iPhone or iPad…; on the iPad, Add a Mac… and scan. "Paired" on both; the Mac lists the iPad. At home the Mac stays a plain row, and the host logs no utun origin for the home session |
| R2 | **Away.** The iPad on the iPhone's hotspot or cellular, Tailscale on. The Remote row about 3 s after launch; tap. "Connected through Tailscale · N ms"; the Mac's card says "through Tailscale". Ten minutes on a real window with the trackpad and typing, at Balanced and at Low; note frame age and RTT; no eviction |
| R3 | **Leaving the house mid-stream** (LAN to hotspot): "Reconnecting to ‹Mac› remotely…" and streaming again within about 10 s, without a tap |
| R4 | **Wi‑Fi to cellular** during a remote session: the session carries on, or is back within about 8 s |
| R5 | **Tailscale off on the iPad:** "Tailscale looks off…". Off on the Mac: the pane shows "Not connected", the iPad "didn't answer…" |
| R6 | **Sleep.** Lid closed or asleep: the copy. Then 15 minutes remote with nobody at the Mac: it stays awake (idle sleep held off); does a sleeping or locked display stop the picture? |
| R7 | **Remove the iPad on the Mac** while it streams remotely: closed within 1 s, "Mac mini removed this iPad…"; the next tap "no longer accepts…"; pairing again works |
| R8 | **A `make-app.sh --install` rebuild and relaunch:** the same port and Mac ID, no keychain prompt, and the iPad reconnects |
| R9 | **Pair This iPad… from the panel at home:** the Mac's window comes forward by itself; scan; paired; the stream never stops |
| R10 | **Port forward** (optional, if the router allows): the switch on shows the router address, or the CGNAT or double NAT line; forward 7455; connect over cellular by IP, then by address name; switch off → "stopped accepting connections from the internet" |
| R11 | **Direct Wireless at the café** (the iPhone's hotspot) with the Mac at home, both on: the Direct row wins; a drop reconnects Direct at 6 s, not remotely |
| R12 | **VoiceOver and a hardware keyboard** on the card, the scanner's announcements, the overlay and the pane's Copy buttons. The pairing window never shows in a Desktop stream |
| R13 | **Mixed builds:** this iPad against PR #5's Sill.app (plain works, no Away from home group); PR #5's iPad against this host (plain works; nothing remote) |

---

### 11. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

0. **Preflight** (no commit). Fetch; decide the base (§Decision); H0 with its probes. Copy this plan
   to `docs/remote-access-plan.md` (committed in step 8).
1. **"Protocol: remote access types, identities, pairing codes and addresses"** (StreamProtocol):
   - kinds 18–22 and the caps;
   - Remote.swift, RemoteTLS.swift, RemoteIdentity.swift (certificate, fingerprint, Mac ID),
     Pairing.swift (code, proofs, tag, link), AddressParser.swift, SafeText.swift.

   Gates: H1, H3 (the protocol parts), H21.
2. **"Host: the home listener admits only this Mac's networks, with caps"**:
   - `OriginPolicy` and `InterfaceSnapshot`;
   - the home door gate;
   - register at `.ready`; cancel on `.failed`;
   - the 1 MB cap; the kind 17 limit; `SafeText` at the log and status seams;
   - the Desktop filter excluding Sill;
   - `sillrelay.py`; `sillclient.py` `--host`, `--big-payload`, `--flood`, `--device`, `--stop-ping`
     and `--stop-read`.

   Gates: H1, H2, H3 (`OriginPolicy`), H4, H5, H24.
3. **"Host: the remote door, pairing and the Mac's addresses"**:
   - the memory and file identity stores, `PairedDevices`, `PairingWindow`, `RemoteServer`,
     `StreamServer.serve`;
   - the TXT tag;
   - `Reachability`, `AddressList`, `RouterAddress`, `RemoteAccess`;
   - kinds 18–22 in the coordinator;
   - the remote-route rules: the Direct Wireless refusal, silence eviction, the 15 s drain,
     keyframe pacing, goodbyes;
   - the `HostConfig` knobs and `HostStatus.remote`;
   - the CLI's `--remote`, `--internet` and `--print-reachability`;
   - `sillclient.py` `--tls`, `--identity`, `--pair-url`, `--pair-code`, `--expect-tls-fail` and
     `--pairing-wanted`.

   Gates: H1, H2, H3 (`AddressList`, `PairingWindow`), H6–H15, H17, H18, H20, H23.
4. **"Sill.app: Remote Access settings, the pairing window and the menu"**:
   - `KeychainIdentityStore`;
   - the pane, the pairing window, the menu items and attention item, the card route;
   - the `HostSettings` keys, the sleep rule, `DebugHooks`, previews.

   Gates: H1, H16, H19, H22. Delete the `SillMenuBar` domain afterwards.
5. **"iOS: device identity, saved Macs, remote dialing and reconnect"** (the model):
   - `DeviceIdentity`, `SavedMacs`, `RemoteDialPolicy`, `RemoteConnector`, StreamClient+Remote;
   - TXT browsing and tags; rows; the reconnect order;
   - the session gate; liveness; caps; the route;
   - `onOpenURL` routing; Info.plist; the pbxproj entries.

   Gates: H1 (iOS), H3 (policy, dialing, saved Macs), S3, S4, S5.
6. **"iOS: Add a Mac, Remote rows, pairing and the panel"** (the UI):
   - the line and the card; the scanner; the typed path; the confirmation;
   - Remote rows and their menus;
   - the overlay;
   - the panel's route line, Away from home and the Direct Wireless row;
   - the harness cases.

   Gates: S1, S2, S6, S7.
7. **"Remote link: the Low preset and 60 fps away from home"**:
   - `QualityPreset.low` on both sides;
   - `wantedFPS(remote:)`;
   - the frame-rate footnote and the slow-link callout.

   Gates: H1, H14 again (also at Low), H22, the ledger check with Low in its alphabet, S8.
8. **"docs: Remote access"**:
   - `docs/remote-access-plan.md` (this plan, with results).
   - CLAUDE.md:
     - the Current step;
     - Layout (the new files);
     - Build and run: `--remote`, `--internet`, `--print-reachability`, the TEST ONLY variables
       (`SILL_TEST_REMOTE_DIR`, `SILL_TEST_PAIRING_TTL`, `SILL_TEST_BACKOFF_SECONDS`,
       `SILL_TEST_ORIGIN`, `SILL_TEST_NO_ROUTER`), `sillrelay.py`, the `sillclient.py` flags, the
       harness lines;
     - Untested, for Noah: R0–R13.
   - README: a Remote access section:
     - Tailscale, WireGuard and a port forward;
     - troubleshooting (AllowedIPs, shields up and ACLs, CGNAT, hairpin, sleep);
     - quality following you home;
     - the CLI's code in Terminal;
     - `defaults delete me.saffer.sill.mac remoteAccess remotePort internetAccess remoteAddressName`;
     - the keychain items (Keychain Access › login › "Sill Remote Access" and service
       `me.saffer.sill.remote`).
9. **Review and hand-over.**
   - Three lenses: security and protocol (the pre-auth surface, the proof binding, pins,
     revocation, no code in any log); listeners and concurrency (admission states, the verify
     block's snapshot, the TLS listener replacement, eviction and pacing on the network queue); the
     device UI and accessibility at every size.
   - A "Review fixes" commit if needed.
   - Then adversarial re-runs of H6–H19 and S3–S5.
   - Hand R0–R13 to Noah. **Stop there.**

### 12. Hard rules (for every step)

- **Never `MainActor.assumeIsolated`** in core code: under the CLI's `dispatchMain` the main queue
  drains on a worker thread and it traps. Hop with `Task { @MainActor }`. The verify block and
  admission never wait on the main actor; they read the lock-protected `TrustSnapshot`.
- **Never `SCStream.updateConfiguration`**, and never reconfigure a running SCStream. The Desktop
  filter is chosen at pipeline start.
- **The CLI's stdout stays byte for byte** on the default path (masked and sorted), idle and
  streaming, with and without `--direct-wireless`. New lines print only with `--remote`,
  `--internet` or `--print-reachability`, or on events that baseline runs never produce. Core
  `print`s go through HostLog's shadow.
- **Kinds 16 and 17 stay compatible both ways.**
  - Nothing new in `StreamSettings` or `HostSettingsChange`.
  - Remote Access, the port and internet access are never device-writable.
  - The only new value is the Low bitrate, which older builds show as Custom.
  - New kinds 18–22 are skipped by older readers.
- **Apple frameworks only:** Network, Security, CryptoKit, CommonCrypto, CoreImage, VisionKit,
  SystemConfiguration, dnssd.
  - No packages: the certificate is hand-built unless Noah approves swift-certificates.
  - The test tools use the Python standard library and the system `openssl`.
- **Zero operating cost:**
  - no servers, relays, STUN or "what's my IP" lookups;
  - the router is asked read-only, only while the internet switch is on;
  - no port mapping is ever created.
- **The modal-loop rule** in the app: no `NSMenu.popUp`, `runModal` or `.terminateLater` terminate
  from a Task, a continuation or a main-queue block. Errors inline, never alerts. No system
  presentations on the device except the existing context-menu style.
- **Secrets:** the pairing code and secret are never logged by Sill.app, never in `HostStatus`, never
  in kind 16 or 18, never in a TXT record. The trust list and keys live in the keychain (the app),
  in memory (the CLI) or in a 0700 directory (tests only). They are never in UserDefaults.
- **Tests never touch** Noah's running Sill.app, `/Applications`, `me.saffer.sill.mac`, his login
  keychain (except R0-b with his OK) or his iPad. TEST ONLY hooks are honoured only by hosts that do
  not advertise.
- **New iOS files** need their four pbxproj entries by hand. Swift 5 language mode.

### 13. What M5 inherits, and what comes later

**M5 (iCloud pairing) keeps, unchanged:**
- the identities and SPKI pins;
- mutual TLS 1.3 and the verify blocks;
- the paired store with `method` and Remove;
- the pairing exchange and its versions;
- saved Macs keyed by Mac ID;
- the signed kind 18;
- the recognition tag;
- the pre-auth caps;
- the QR code, which stays as the fallback for other Apple Accounts ("manual as fallback",
  BRIEF.md:48-49).

**M5 adds a second way to exchange the same public keys.** Each install writes its ID, name and
public key to the user's CloudKit private database; the Mac also writes its addresses, port and
`recognitionKey` (in `encryptedValues`). Same-account devices then trust each other with no scan,
and both verify blocks consult "paired store ∪ iCloud set" with `method: "icloud"`.
- It probably puts the home network behind the same pairing (open question 1): Bonjour would
  advertise the remote door, and the home door would retire.
- Its CloudKit entitlement brings a provisioning profile and so the data-protection keychain. The
  Mac's key is a software key the app can export, so it can move without re-pairing.
- Rules to keep now: only public keys and non-secret metadata ever sync; device keys are never
  synchronizable; every record says how it was trusted.

**Later steps:**
- moving a live remote session to the network (reuse the fixes' `moveToNetwork`);
- the Direct Wireless memory and the window order keyed by Mac ID (the tag makes it possible);
- adaptive bitrate from RTT and frame age;
- ack-based pacing that bounds the kernel's send buffer;
- QUIC (the TLS 1.3 options carry over);
- per-route quality profiles.

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **Pair the home network too, now?** Default: **no.**
   - The home door stays as it is until M5, when iCloud makes pairing automatic for same-account
     devices.
   - The alternative is one TLS door for everything, with every device scanning once now. It would
     also close the café, radio-range and loopback exposure a milestone early, at the cost of a
     first-run step, a protocol break and a new CLI default line.
2. **Ship the internet (port forward) path in this step?** Default: **yes**, behind its own Mac-only
   switch, off by default. The remote door is identical either way.
3. **"Pair This iPad…" from a device at home (kind 21)?** Default: **yes**, from this Mac's own
   networks only, once per 30 s. The Mac shows the code only on its own screen. The alternative is
   pairing started only at the Mac.
4. **Remote sessions and Direct Wireless.** Default: **refused from afar**, allowed from nearby, as
   today.
5. **Certificates.** Default: **hand-built DER** (about 100 lines, verified by Security,
   Network.framework and OpenSSL). The alternative is Apple's swift-certificates package, a
   dependency.
6. **A "Low — 4 Mbps" preset.** Default: **yes**, first in every Quality list.
7. **Keep the Mac from idle sleep while a remote device is connected?** Default: **yes**
   (`.userInitiated` while connected remotely; the display may sleep).
8. **Leave Sill's own windows out of the Desktop stream?** Default: **yes**. It keeps the pairing
   code off every device. The cost: a device no longer sees Sill's Settings or Log windows in the
   Desktop.
9. **The typed code.** Default: **12 digits (11 random plus a Damm check digit), PBKDF2 at 600,000
   rounds.** It suits the Duo's number pad. The alternative is 10 Crockford characters with a check
   character.
10. **Does pairing turn Remote Access on?** Default: **no**. The pairing window offers [Turn On Remote
    Access] as the Mac user's click. The alternative (d2) turns it on with the first pairing.
11. **Port 7455, changeable only on the Mac?** Default: **yes.** It is unassigned at IANA (7444–7470),
    absent from `/etc/services` and below the ephemeral range. It is never another port by itself.
12. **The Secure Enclave for the device key, if R0-a passes?** Default: **yes**; otherwise a software
    key with `WhenUnlockedThisDeviceOnly`.
13. **`sill://pair` links from the Camera and Messages?** Default: **register the scheme, always with
    a confirmation**. The in-app scanner is the main path, since another app could claim the scheme.
14. **The CLI's `--remote`.** Default: **a throwaway in-memory identity**, for tests; Sill.app is the
    remote host.
15. **Fast-forward the local `main` ref to origin/main?** Default: **leave it to Noah.** Nothing in
    this plan compares against local `main`.

---

## Results (implementation, 2026-09-24/25, branch `remote-access`)

Steps 1–8 are done, one commit each, on `a9cc248` (origin/main when the work began; origin/main has
since gained PRs #6–#8, which this branch does not contain). Step 9, the review, is under way: the
fixes of its first round are one commit ("Review fixes (step 9)" below). Every open
question above took its default: the home door stays unpaired (1), the internet path ships behind
its own switch (2), Pair This iPad… from home (3), Direct Wireless refused from afar (4),
hand-built DER certificates (5), the Low preset (6), idle sleep held off while a device is
connected remotely (7), Sill's windows left out of the Desktop stream (8), 12 digits with a Damm
check digit and PBKDF2 at 600,000 rounds (9), pairing never turns Remote Access on (10), port 7455
changed only on the Mac (11), a software device key until R0-a says otherwise (12; DEBUG
`-SillDeviceKeySE 1` tries the Secure Enclave), `sill://pair` registered but always confirmed (13)
and the CLI's throwaway identity (14).

| Step | Commit | Gates run and passed |
|---|---|---|
| 1 Protocol | `4de3efb` | H1, H3 (188 checks, 20/20 mutants, the plan's vectors, a live loopback mTLS handshake per rule), H21 |
| 2 Home door | `5112041` | H1, H2, H3 (OriginPolicy 66, 10/10 mutants), H4, H5, H24 |
| 3 Remote door | `be66c33`, review fixes `b481c71` | H1, H2, H3 (AddressList and PairingWindow 41, 15/15 mutants), H6–H15, H17, H18, H20 (remote 5.79 % CPU vs home 6.08 %), H23, the goodbyes, and the review's own gates |
| 4 Sill.app | `4c562de` | H1, H16 (listening 26.6 s after the port was freed; a rebind under a streaming session), H19 (neither the code nor the secret in any log), H22 |
| 5 iOS model | `3c1bd97` | H1, H3 (49 checks, 26/26 mutants; the discovery policy's 68), S3, S4 (reconnect at 3.1 s; liveness 6 s after a blackhole), S5 (every failure's words, live) |
| 6 iOS UI | `5468bdc` | S1 (≈200 photos: every new connect case at the seven sizes, the re-shot cases, every settings case at the Duo sizes and at accessibility-extra-large, the overlay), S2 and S6 as XCUITests, S3's outside link live, S7 |
| 7 Low and 60 fps | `fc39a45` | H1, H2, H14 (Balanced and Low), H22, the ledger check with Low, S8 |
| 8 Docs | `47e4e7c` | — |
| 9 Review fixes | the commit after `47e4e7c` | H1, H2, H3 (the step 5 checks at 60, 33/33 mutants), H22 (only the three spent-code pairing samples), the host's own gates and S2, S3, S6 again, below |

**Measured.** Through `sillrelay.py --rate-mbps 2 --delay-ms 150` for 90 s, a paired TLS session
kept every 5 s window full (≈300 frames), was never evicted and saw keyframes at the encoder's 4 s
cadence (15.3 a minute at Balanced; 16.0 at Low, the extra one being the restart for the change);
the pong round trip was 153 ms at the median and 157–158 ms at p95; an unshaped home client on the
same build equalled a9cc248's (5,398 frames, 23 keyframes, nothing dropped). On the simulator
through `--delay-ms 150 --rate-mbps 5`, typed pairing finished 1.7 s after launch; with
`-SillScreenFPS 120` the device asked for 60 fps through a VPN route and 120 by address; through
`--delay-ms 300` the panel read "Connected through Tailscale · 303 ms" with the slow-link
callout. The CLI's output is still a9cc248's, byte for byte (masked and sorted), after step 7.

**Where the code and this plan differ (the code wins).**
- TLS: the server's verify block also sees the negotiated ALPN, so an unpaired key is refused
  inside TLS even while a pairing window is open, and a pairing dial with no window is refused
  the same way (the device reads it as "isn't pairing right now"). The verify block reads the
  peer's leaf from the handshake metadata, never SecTrust (§3.3 named
  `SecTrustCopyCertificateChain`, which let an AIA URL stall the network queue).
- The remote door judges a connection's origin before it starts, and again at `.ready` and at
  kind 19; its backoff counts only its own refusals, and a paired key clears its source's count
  (§4.7 counted every end before admission). A keyframe forced for a slow remote client waits
  for the encoder's 4 s interval while a home client is connected.
- The CLI notices an expired pairing window at the next attempt ("expired"), then opens a fresh
  one. A plain client whose bytes parse as a TLS record gets a 7-byte TLS alert, never a Sill byte.
  The certificate's CN is 16 random hex characters (about 312 bytes, not 287).
- Sill.app keeps its key, recognition key and trust list in the legacy login keychain: the
  data-protection keychain needs a provisioning profile, which a Developer ID app does not have.
- The device: on an iPad the code field uses the numbers-and-punctuation keyboard, because the
  floating number pad swallowed the next tap (Pair took two). The scanner asks for the camera
  itself when a live viewfinder first shows (DataScannerViewController never asks). Esc is a
  priority key command (`EscapeKey`), since a focused text field can claim the key before
  SwiftUI's `.cancelAction` sees it. The connect column is placed by its leading edge and the
  side-by-side card grows to the trailing side (at most 620 pt, 24 pt from the edge), so the title
  never moves sideways; with a field's keyboard up the column goes to the top on every layout, not
  only the outer display, so Pair stays above the keyboard; the card's two links stack on a
  667 pt phone on its side. The Away from home group appears when kind 18 does (no timer: an
  older Mac never sends one). The frame-rate footnote's away sentence shows only when the 60 fps
  request halves what the screen could show. The overlay's Cancel also stops a pairing still
  dialing and drops a waiting link.
- `defaults delete` takes one key at a time, so the README's reset is a loop over the keys.
- DEBUG arguments beyond §7.12: `-SillSettingsEnd 1` (the panel scrolled to its end, for photos),
  `-SillRemoteRoute vpn|internet` and `-SillScreenFPS 120` (S8 on a loopback host and a 60 Hz
  simulator), `-SillDeviceKeySE 1` (R0-a).
- Commit trailers name the model that wrote them (Claude Opus 5.5), not the one the task named.

**Review fixes (step 9).** Fourteen confirmed findings; each fix below, and where it departs from
the plan.
- A pick never streams one of Sill's own windows: `WindowCatalog.resolveWindow` (the fallback of a
  pick with the virtual display on) and the staged window's pin skip this process's windows, as
  the catalog did; a device guessing the ID just above the newest could stage the pairing window.
  A Desktop stream on a host with remote access looks for Sill among every window when the
  on-screen look missed it (the status item leaves that list while a full-screen app hides the
  menu bar); excluding nothing let a pairing window opened later reach the devices.
- The internet switch counts only while Remote Access is on (§1 made it the only gate): a pairing
  window with Remote Access off admitted internet sources, asked the router and put internet
  addresses into the link and kind 18 while the pane hid the switch. The saved setting stays for
  when Remote Access is back; turning Remote Access off sends each session one goodbye.
- Remove saves first: when the keychain write fails (a locked login keychain, its prompt
  cancelled) nothing changes, one line is logged and the pane says the device is still paired;
  the device was trusted again after a relaunch while the pane said it could no longer connect.
- A spent code (used, expired, stopped, cancelled) no longer shows in the pairing window, only its
  frame: a scanner read it at 20 % and every try was refused at the door.
- Kind 18 lists no addresses before the Mac's first look at its networks, and a device keeps its
  saved addresses when a verified kind 18 lists none or says Remote Access is off (§7.2 replaced
  them whole): a device that connected at home while Remote Access was off had nothing to dial
  once away.
- A pairing over a home session (the overlay) ties that session to the Mac just paired only when
  the session's verified kind 18 is signed by the same key, and then takes that kind 18's
  addresses (the typed path saved only the address it dialed). Before, pairing another Mac's link
  over the stream named the session after it: its end read as that Mac's, and the reconnect
  dialed it.
- The scanner never restarts a pairing by itself (`RemoteDialPolicy.scanStartsPairing`): nothing
  while one runs or has just succeeded, and after a failure the same code only from a tap on it
  (the caption says "Tap the code to try again."); another code starts at once. A card showing the
  scanner again after a failure re-read the code and looped into the door's backoff, and a
  re-read during an exchange spent the code for nothing. The silent retry after "busy" stays
  cancelled after Cancel.
- An outside link confirmed over the stream keeps the overlay up for its progress, its error or
  "Paired with …" (Pair used to close it); Pair This iPad… starts from a clean state.
- The overlay's typed path reads "Enter the Code from ‹Mac›" and moves to the top while the code
  is typed, as the card does.
- The connect screen's status line is announced to VoiceOver (§7.8), also the line a session
  ended with, when the screen comes back.
- Saved Macs are cleared at launch only when the Keychain says no device key exists under any tag
  (errSecItemNotFound); a DEBUG `-SillDeviceKeySE 1` run, whose tag had no key, cleared real
  pairings.
- Not applied: the route line's wrap after "·" (unverified; it matches the readout's rule on
  origin/main, where a wrap falls after the "·"). The merge applied it, and its review kept the
  route whole as well (below).
- Gates on this build: the host's own (the internet source refused with Remote Access off and a
  window open, internet=0 and no address name in kind 18 until Remote Access is on again; one
  goodbye each for Remote Access off and for internet off; a Remove whose save fails changes
  nothing, the device still paired after a relaunch, then a kept Remove works; kind 18 empty until
  the first look, then 127.0.0.1 first); on the simulator, three new XCUITests against live
  synthetic hosts (another Mac's link over a stream through a 1.5 s relay: "Pair with …", "Pairing
  with …", "Paired with …", then the used link's error in the overlay until Cancel, and after the
  first Mac quit nothing dialed the second; Pair This iPad… typed: the title, the content at the
  top while typing, the record with the Mac's five kind 18 addresses and the typed one) and the
  keys (a `-SillDeviceKeySE 1` launch keeps the saved Macs, an empty Keychain clears them). The
  pre-fix build fails the link test (the overlay gone after Pair; the second Mac dialed by itself
  after the first quit) and the keys test (the saved Mac cleared).

**Not verified here, for Noah (R0–R13 as built).**
- R0 probes: (a) `-SillDeviceKeySE 1` against `SillHost --synthetic --remote` over the LAN (does a
  Secure Enclave key sign TLS client authentication?); (b) with your OK, since it writes to your
  login keychain: `make-app.sh --install --open`, Settings › Remote Access on, then a rebuild and
  relaunch read the same identity without a prompt (`KeychainIdentityStore` never ran here: every
  test host used `SILL_TEST_REMOTE_DIR` or memory); (c) `natpmp-probe` from Terminal; (d) the
  embedded scanner on the iPad (the simulator has none), including the camera prompt, a
  non-Sill QR code, and a failed pairing: the code still in view is held until tapped ("Tap the
  code to try again."), and a spent code shows no QR on the Mac.
- R1–R11 as written above: Tailscale setup and pairing timed; away on the hotspot; leaving home
  mid-stream; Wi‑Fi to cellular; Tailscale off at either end; sleep (15 minutes with nobody at the
  Mac); removing the iPad while it streams; a rebuild keeping port, Mac ID and pairing; Pair This
  iPad… from the panel; the port forward; Direct Wireless at the café.
- R12: VoiceOver and a hardware keyboard on the card, the scanner, the overlay and the pane's Copy
  buttons. Esc in particular: the iPadOS 27 simulator never delivers Escape to an app (a
  first-responder probe saw no key press at all), so only ⌘. was tested. Also that the pairing
  window never shows in a Desktop stream (also with a full-screen app in front when it starts),
  and that the connect screen's status lines are spoken.
- R13: mixed builds (this iPad against PR #5's Sill.app: no Away from home group; PR #5's iPad
  against this host).
- Also: the Local Network prompt on a fresh install before the first remote dial; the live menu
  and Settings in the macOS 26 look (only offscreen renders were checked); one unexplained failure
  in four runs of the outside-link UI test (the first after a rebuild: the pairing dial was refused
  and no log was captured; three reruns passed).
- The pairing window's Address row, live (added after cb0ec55; only its offscreen previews were
  seen): what to check is at the end of these Results, after the row's review.

**Merged with main (2026-09-25).** Main's PRs #6–#10 came in by one merge (0f7f50d), not a rebase:
the Direct Wireless fixes, the connect screen's Wired/Wi-Fi/Direct, the quality presets, the route
in Settings and prefer-cable. What changed here with it: Low is the first of seven presets (main's
six after it, the 200 Mbps cap main's); the Mac card keeps main's link word for home devices and
this plan's label for remote ones, the label winning (`StatusText.routeWord`, also on the source
row with one device); the device keeps main's route word for the readout and a remote session's
way in apart (`StreamClient.remoteRoute`); a Direct row waits `directWait` and `networkGrace` in
the reconnect (§7.4's 3 s became main's rule), and every row dial goes through the cable first
when the row says Wired; Direct Wireless off never ends a remote session. CLAUDE.md's first
current-step entry lists the resolution and what was checked.

**The merge's review (2026-09-25).** Three fixes beside two doc comments. §7.4 step 3's
`networkLeftAt` is the moment the network stopped listing the Mac, and the device passed the last
browser change while it was listed, often the connect (since step 5), so a Mac that blinked off at
home was dialled remotely 3 s after the loss: the saved Macs now keep main's sightings by Mac ID
(`StreamClient.savedSightings`). §3.7's caps now also bound the reader main added for the move to
the network (`probeMove`), which also drops a message cut short. The route line's own spaces are
no-break ones, so at larger text it wraps before the route, never inside it ("Connected" /
"through Tailscale · 48 ms"), as the Mac card does since ee922db. CLAUDE.md's entry lists the
checks, and the gates the review reran on the merged build.

**The pairing window's address (2026-09-25, after cb0ec55).** Noah paired his iPad from an iPhone's
hotspot with a typed code: the window gave this network's address first (10.128.0.34), which
answered nothing from there ("Nothing answered at 10.128.0.34"), while Tailscale's 100.65.142.55 and
noahs-macbook-pro.tailc94091.ts.net both paired. His decision: the window shows those two instead of
the local IP; §6.2 has the rule (`PairingWindowAddress.choose`). It is the app's alone: nothing in
Sources/SillHost, SillHostCLI or StreamProtocol changed, so the CLI's output cannot. Checked: a
clean release build (only the CaptureProbe warning) and `make-app.sh` without `--install`; the rule
with swiftc against StreamProtocol's sources and the real `AddressList.build`, 36 checks (Noah's
store with and without the internet switch and its router address, no MagicDNS name, IPv6 only, a
name with IPv6 only, several VPNs, a point-to-point tunnel, LAN only, nothing, ports 7456 and 17455,
kinds over text, and 5,000 random runs, 1,686 of them without a VPN and equal to the window before)
and 15 of 15 mutants caught; the previews from the bundle against cb0ec55's with the same saved
settings: only the four waiting-state pairing samples changed, each 18 pt taller with nothing but
the Address row's band different, plus the new `novpn` and `longname`, light and dark. The value
column is 336.5 pt wide: Noah's name takes 229, the 40-character name on port 17455 292; a
57-character one wraps after a hyphen and is never cut.

**The Address row's review (2026-09-25).** Three confirmed findings, one commit.
- Another VPN hid this network's address. ae7f5c9 put the first VPN IPv4 of any VPN first, so a Mac
  on NordVPN, Mullvad, Cloudflare WARP or a work VPN beside Wi‑Fi 192.168.1.20 gave only 10.5.0.2,
  10.64.12.34, 172.16.0.2 or 10.200.1.5 (cb0ec55 gave 192.168.1.20), and with Tailscale's MagicDNS
  name missing, a VPN whose name sorts before "Tailscale" came before 100.65.142.55. The typed path
  dials exactly the address typed, and NordLynx gives every client 10.5.0.2 and WARP 172.16.0.2,
  so nothing answered there. Now only Tailscale's ranges take this network's place (§6.2 step 2,
  by the parsed address) and another VPN's address goes under this network's (step 3). Noah's
  decision covered Tailscale only, so the order for other VPNs is his call: this one keeps
  cb0ec55's first line, and the other order, or this network's address alone, is one line in
  `PairingWindowAddress.choose`.
- `longname` is not the widest the row gets (§6.6 and the DebugHooks comment said so); a name from
  about 46 characters with the port wraps.
- Noah's list had nothing for the row, which only offscreen previews had shown (below).

Checked: the rule with swiftc against StreamProtocol's sources and the real `AddressList.build`, 80
checks (the review's scenarios A–K: NordVPN, Mullvad, WARP and a work VPN beside Wi‑Fi, each also
beside Tailscale without its name; a WireGuard mesh; open-source tailscaled on an unnamed utun; an
exit node; the ranges' edges 100.63.255.255, 100.64.0.0, 100.127.255.255, 100.128.0.0,
fd7a:115c:a1df:ffff::1, fd7a:115c:a1e0:: and fd7a:115c:a1e1::1, an uppercase and an IPv4-mapped
form; a range, not a service's name, deciding; and 5,000 random runs against a restatement of the
rule, 1,686 of them without a VPN and 1,947 with a LAN address and no Tailscale, each giving the
first line cb0ec55 gave) and 35 of 35 mutants caught (among them ae7f5c9's rule, the prototype's
order, each range edge and a /32 or /16 read of the IPv6 range); this Mac's live list
(`SillHost --print-reachability`) still gives the name with "or 100.65.142.55", without
Tailscale's entries 10.128.0.34 alone, and without the name 100.65.142.55 alone; a clean release
build (only the CaptureProbe warning) and `make-app.sh` without `--install`; the previews from the bundle against 78d76e0's, rendered back
to back with the same saved settings: every file byte for byte the same (the nine pairing samples
and menu.txt among them) but for the new `othervpn`, light and dark, and the General pane, whose
"Running from" path and build number are each bundle's own. Nothing in Sources/SillHost,
SillHostCLI or StreamProtocol changed, so the CLI's output cannot.

**Not verified here, for Noah (the Address row).** With this build's Sill.app, Pair iPhone or iPad…
should read noahs-macbook-pro.tailc94091.ts.net with "or 100.65.142.55" muted under it (what
`SillHost --print-reachability` lists). With the window open, Tailscale off on the Mac: 10.128.0.34
alone, and the window 18 pt shorter; back on: the name and the "or" line return (100.65.142.55 alone
for a few seconds, until MagicDNS answers, is expected; note it if it stays). Each line can be
selected without "or" coming along, and pasted (Universal Clipboard) or typed into Enter Code
Instead; a code works once, so New Code or reopening the window gives a second try. VoiceOver reads
"or 100.65.142.55" as one element.
