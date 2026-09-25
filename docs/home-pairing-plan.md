# Pairing at home: Wi‑Fi, Direct and the cable — the plan

2026-09-25. It stands alone: the implementer needs no other design document, though it builds on
`docs/remote-access-plan.md` (PR #13) and names its sections as "the remote plan §…". Written from
a read-only survey of origin/main `ba91136` ("Merge pull request #13", remote access) in the
worktree `/Users/noah/Downloads/winstream-pairing` (branch `home-pairing`), and from read-only
probes of this Mac's interfaces while Noah's iPad mini was on the USB cable. This plan is the only
file written; no host was started. Line numbers are at `ba91136`. PR #11 (`encoder-recovery`, host)
and PR #12 (`follow-best-path`, iOS) are not in this base: §12 says how they meet this work.

**Noah's request (2026-09-25):** "add a pairing process for Wi-Fi/Direct connect, something easy to
do but still secure, similar to how Tailscale is being paired. Wired should still pair
automatically."

**Reading of it.**
- Today the home door (Bonjour `_sill._tcp`, plain TCP, StreamServer.swift:591) serves any socket
  that reaches it from this Mac's own networks, from peer-to-peer Wi‑Fi (Direct Wireless) or over
  loopback (OriginPolicy). Whoever is on the Wi‑Fi can stream the Desktop, click and type as the
  Mac's user, and read what the iPad types, passwords included, in plaintext.
- "Similar to how Tailscale is being paired" is PR #13's pairing, which Noah used for Tailscale on
  2026-09-25: the Mac shows a QR code and a 12-digit code, the device scans or types, both keys are
  pinned, and everything runs over TLS 1.3 with both sides authenticated.
- So the home door becomes that door. A device pairs once, with the same QR code or code, and is
  then paired for Wi‑Fi, Direct, the cable and remote access alike, because there is one trust
  list. Over the USB cable it needs no code at all.

---

## Decision

### In one paragraph

Sill.app's Bonjour port speaks the remote door's TLS 1.3 with both keys pinned: the same
identities, the same application protocols (`sill/1` for a session, `sill-pair/1` for pairing),
the same trust list and the same pairing window. An unpaired device's tap on a Mac's row sends one
"pair me" request: kind 19 with a new method, `ask`. Over the USB cable to an iPhone or iPad, while
the Mac is unlocked, the Mac pairs the device on the spot and shows a notice. Everywhere else it
opens its existing pairing window by itself (rate-limited, never taking the keyboard), and the
device scans the QR code or types the 12 digits, exactly as it pairs for remote access but over
the home door. "Require pairing" (on by default) lives in a new Settings › Devices with the paired
list; turned off, any device at home gets in without pairing, still encrypted. The CLI keeps
today's plain open door unless `--pairing` is given, so its output stays byte for byte.

### The door: TLS on the Bonjour port, two listeners, one policy

- **Chosen.** The home listener keeps what makes it the home door: an ephemeral port that never
  collides, the Bonjour registration with its TXT record, the Direct Wireless swap and the origin
  gate. Its parameters gain the remote door's TLS server options (RemoteTLS.swift, unchanged). The
  remote door keeps port 7455 and its own rules. Admission is one code path for both listeners: a
  `Door` (extracted from RemoteServer) driven by a pure `DoorPolicy`, so a rule changes in one
  place.
- **Rejected:**
  - *One listener on 7455 for both.* The home door would fail whenever another app holds 7455
    (today it cannot collide), and Direct Wireless would put the remote door on AWDL.
  - *A plain listener kept beside the TLS one, or a sniffer below TLS (an `NWProtocolFramer`
    under the TLS options) that answers older builds with a plain goodbye.* No goodbye an older
    build can read says "update": it knows `quit`, `removed`, `remoteOff`, `internetOff` and
    `busy`, and treats anything else as a plain disconnect. Only Noah's own devices run older
    builds, and a sniffer would sit in the path of every byte of the stream. The Mac says it
    instead (§6.4).
  - *A new service type (`_sills._tcp`) instead of a TXT key.* Two browsers per route on the
    device, and the Mac would never learn that an older device tried.
  - *The Mac ID or a key prefix in the TXT record.* A stable identifier anyone nearby could
    track (the remote plan chose a rotating tag for exactly this), and unauthenticated anyway: a
    new device learns the key from the QR code, and a saved Mac is named by its tag.
- **The TXT record gains `p`:** `1` pairing required, `0` open (TLS, any device). No `p` is a plain
  door: Sill.app before this change, or the CLI without `--pairing`. The device reads `p` before it
  dials, so it never dials TLS at a plain door, nor plain at a TLS one, by accident.

### Showing the code: option A, the Mac opens its window when a device asks

| Criterion (0–10) | A: the window opens when a device asks | A′: a prompt, the code on a click | B: Pair iPhone or iPad… on the Mac first |
|---|---|---|---|
| Ease | 9: tap the Mac on the iPad, the code is there | 7: one more click on the Mac | 5: the menu bar first, then the iPad |
| The pairing's own security | 8: the same code and proofs, but a code shown at a stranger's request can end up in a screen share | 9 | 9 |
| Nuisance from strangers on the network | 6: at most 3 windows in 10 minutes, then quiet | 7 | 10 |
| Implementation risk | 8 | 7 | 9 |
| Native feel (Apple TV, AirPlay and Bluetooth show a code when a device asks) | 9 | 7 | 6 |
| **Mean** | **8.0** | 7.4 | 7.8 |

**A, with these limits** (`AskLimits`, pure; §4.7):
- A window opens only for a request from this Mac's own networks, peer-to-peer Wi‑Fi or loopback
  (the home door's origins). Never through a VPN or from the internet, never on the remote door.
- One window at a time. A request while one is open is told the code is showing.
- Never while the Mac is locked, or while another user's session is on the console: the device is
  told to unlock the Mac.
- When the Mac's user closes a window a device opened, or lets it expire, that device (its key,
  and its address) opens no other for 10 minutes. At most 3 device-opened windows in any 10
  minutes. Past either limit the device is told to use the Mac's menu, and the menu says "iPad
  Wants to Pair".
- The window comes to the front without taking the keyboard (`orderFrontRegardless`, no app
  activation), so a request can never swallow a password being typed in another app.
- Its code is the one pairing code there is: 12 digits, 5 tries, 5 minutes, single use. A window a
  device opened never starts the remote door, and the remote door takes no proof while only such a
  window is open: its code works at the home door alone.

### The typed code stays 12 digits

- **Not 6.** The typed path cannot pin the Mac's key: the device has only the code. A man in the
  middle on the Wi‑Fi (a look-alike row, ARP spoofing) receives the device's proof bound to its own
  key and grinds the code offline, then pairs its own key with the real Mac while the window is
  still open. At 600,000 PBKDF2 rounds a high-end GPU tries about 15,000 codes a second (hashcat's
  PBKDF2-HMAC-SHA256 rate, about 8.8·10⁹ rounds a second), so 6 digits fall in about 70 s at
  worst. 12 digits cost about 10,000 such GPUs for the 5-minute window (the remote plan §3.6).
- **A short code needs a PAKE** (SPAKE2+, CPace), which makes every guess an online one. CryptoKit
  has none: its interface in the macOS 27 SDK lists AES, ChaChaPoly, HPKE, the KEMs, ML-KEM, ML-DSA,
  P256/384/521, Curve25519, HKDF and HMAC, and no PAKE (checked for this plan). Hand-rolling one
  for a once-per-device step is not worth it.
- **The easy paths need no typing:** the QR code (it also pins the Mac's key before anything is
  sent) and the cable.

### The cable: what counts, measured on this Mac today

Noah's iPad mini (iPad14,1) was on the cable during the survey. Read-only: `ifconfig`,
`networksetup -listallhardwareports`, `system_profiler SPUSBDataType`, `ioreg`, and a small swiftc
probe of SystemConfiguration, IOKit, getifaddrs, NWPathMonitor and CGSession
(`scratchpad/home-pairing-plan/probe/cable-probe.swift`).

| Witness | What it says about the cable's two Mac-side interfaces, `en14` and `anri0` | Usable? |
|---|---|---|
| `networksetup -listallhardwareports`, `SCNetworkInterfaceCopyAll` | Neither is listed: only en4–en6 "Ethernet Adapter", Thunderbolt Bridge, Wi‑Fi and Thunderbolt 1–3 | No |
| NWInterface type | wired Ethernet (as the iPad's anpi0 and en2 are), exactly what any Ethernet adapter says | No |
| getifaddrs | not point-to-point (`UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST`); anri0 has only `fe80::…`, en14 `fe80::…` and `169.254.222.62` | Only as a second condition |
| The client's address | `fe80::…%anri0` or `fe80::…%en14` (the Mac's log on 2026-09-22 and 09-25) | Names the arrival interface |
| IOKit, the IOService plane | en14: `IOEthernetInterface ← AppleUSBNCM11Data ← AppleUSBNCM11Control ← IOUSBHostInterface "NCM Control@2" ← IOUSBHostDevice "iPad"` (idVendor 0x05AC, idProduct 0x12AB, `USB Product Name` and `kUSBProductString` "iPad", a `sessionID` per plug-in). anri0: `AppleUSBHostNCMRestrictedEthernetInterface ← …"NCM Control@4" ←` the same iPad. The iPad's configuration also has "Apple USB Multiplexor" (class 255, subclass 254) and PTP. This Mac's own anpi0–2 and en4–en6 hang off `AppleT8112USBXDCI` (the Mac as a USB *device*), en1–en3 off Thunderbolt, en0 off PCIe Wi‑Fi: none has a USB host device above it | **Yes** |
| CGSession | unlocked: `kCGSSessionOnConsoleKey` = 1 and no `CGSSessionScreenIsLocked` key | For the unlock rule |

**The rule** (`CableLink`, pure, over what IOKit read; §4.3). A connection is on the cable when all
three hold, and otherwise it is not:
1. its arrival interface (the address's scope, else the owner of its local address: OriginPolicy's
   rule) has above it, in the IOService plane, a CDC NCM interface (`IOUSBHostInterface`, class 2,
   subclass 13) of an `IOUSBHostDevice` whose idVendor is 0x05AC and whose product name
   (`USB Product Name`, else `kUSBProductString`) is "iPhone" or "iPad";
2. its source address is link-local (fe80::/10 or 169.254/16). Nothing routed carries one, so it is
   the device at the other end of the cable itself, never something behind it (the other clients
   of an iPhone's Personal Hotspot over USB);
3. anything unread or unexpected (no registry entry, a missing property, this Mac's own
   device-mode ports, Thunderbolt, an Ethernet adapter including Apple's own USB one, another Mac)
   means not the cable.

**Pairing by itself over the cable** also needs, at that moment, the Mac unlocked with the user's
session on the console, and at most one key per plug-in (the USB device's `sessionID`): a second,
different key over the same plug-in gets the code window instead, the same key may pair again.
Each such pairing is logged, listed as "over the USB cable" and shown in a notice with Remove.

### The security argument, plainly

- **Wi‑Fi and Direct.** A device gets in only with a code or QR code the Mac showed on its own
  screen, bound to both keys by the remote path's proofs. A stranger on the network, within radio
  range (Direct) or a local process (loopback) gets nothing, and everything is encrypted. This
  closes the three exposures the remote plan left open until M5: the café LAN, radio range, and
  the loopback confused deputy that could borrow Sill's Screen Recording and Accessibility grants.
- **The cable.** Whoever plugs an iPhone or iPad into an unlocked Mac already has the Mac in hand.
  A locked Mac pairs nothing.
- **What stays open:**
  - an app on the plugged-in device could pair its own key before Sill does; it must win the race
    against Sill's own tap, whose request then falls back to a code, and the notice and the list
    show the extra device;
  - a code shown at a stranger's request could end up in a screen share (`sharingType = .none` on
    the window is best effort on macOS 15 and later); it would still work only at the home door,
    from this Mac's own network or nearby, within the window's 5 minutes, and only if the real
    device has not used it first;
  - with Require pairing off, the home door is as open as it is today, but encrypted;
  - the CLI's default door stays plain and open: a development host, reached only by development
    builds (§5, §7.3).

---

## Final plan

### 1. Scope

**In this step:**

1. **The home door speaks TLS** in Sill.app and in `SillHost --pairing`: TLS 1.3 only, both keys
   pinned, the remote door's options. Pairing required by default; `p` in the TXT record.
2. **Pairing at home:** a tap on an unpaired row asks (kind 19 `ask`). The cable pairs at once;
   elsewhere the Mac's window opens and the device scans or types over the home door.
3. **The cable pairs by itself:** the IOKit rule, the Mac unlocked, one key per plug-in, a notice.
4. **Direct (AWDL):** the same door and the same rules. Direct Wireless off still disconnects the
   devices on peer-to-peer Wi‑Fi.
5. **Every connection a device opens to a home door is TLS:** a tap, the wired dial and its
   fallback, the automatic reconnect, the move from AWDL to the network, PR #12's moves between the
   cable and Wi‑Fi, the session after a pairing. The fences are unchanged.
6. **Settings › Devices** (a new tab): Require pairing, the paired devices with how each paired and
   how it last connected (any route, not only remote), Pair iPhone or iPad….
7. **The menu:** "iPad Wants to Pair", an older device refused, the keychain unusable.
8. **Ticks:** every TLS client skips a tick right after a send (the remote rule); a device on the
   USB cable gets none.
9. **The CLI:** `--pairing` and `--print-cable`; the default stays plain.

**Not in this step:**
- iCloud pairing (M5), which adds a way to exchange the same keys;
- a PAKE and a short code;
- pairing over the cable without a tap (the device pairs when its user taps the row);
- per-device permissions (a device that may watch but not type);
- moving a remote session home (the remote follow-up bundle);
- App Attest, to tell Sill's key from another app's on the cable;
- any in-band message for builds from before this change (the Mac says it, §6.4);
- removing plain dialing from DEBUG device builds.

### 2. The design on one page

```
                 ┌─────────────────────── Mac (Sill.app, or SillHost --pairing) ────────────────────────┐
 device nearby ─▶│ HOME DOOR  TLS 1.3, both keys pinned; _sill._tcp, TXT r=<tag> p=1|0; ephemeral port  │
 Wi‑Fi, Direct,  │   before TLS: loopback · link-local (awdl0 too) · this Mac's own networks, else      │
 the USB cable   │   closed with no byte                                                                │
                 │   sill/1: a paired key (any key while Require pairing is off) → the session          │
                 │   sill-pair/1: one kind 19                                                           │
                 │     ask  → on the cable, unlocked: paired now (kind 20 ok, method "cable")           │
                 │          → else: the pairing window opens (kind 20 "shown"), or "openOnMac",         │
                 │            "locked"                                                                  │
                 │     qr, code → judged by the pairing window, exactly as on the remote door           │
 device away ───▶│ REMOTE DOOR  7455: paired keys while Remote Access is on; pairing only while         │
 VPN, internet   │   a window the Mac's user opened is open (new); ask → "closed"                       │
                 │ One identity · one trust list · one pairing window · one Door/DoorPolicy             │
                 └──────────────────────────────────────────────────────────────────────────────────────┘
 SillHost without --pairing: today's plain home door, byte for byte (no identity, no TXT record)
```

**Only the Mac decides who gets in.** Require pairing is the Mac's alone: absent from
`StreamSettings`, `HostSettingsChange` and `DeviceSettings.accepted`, like Remote Access. A device
says "pair me"; whether that happens by itself (the cable) or needs the code on the Mac's screen
is the Mac's judgment of the connection, never the device's claim.

### 3. Wire protocol

#### 3.1 Kinds: none new

Everything the device and the Mac say is already in kinds 19, 20 and 22 (Remote.swift); only
their string values grow, and every new field is optional.

- **Kind 19 `PairRequest.method`** gains `"ask"`: "pair me: now if you can, else show me your
  code". Its `proof` is `""`. Accepted on the home door only. The remote door answers it
  `closed` without counting a try; PairingWindow never sees it. An older host never receives one:
  the device sends it only to a Mac whose TXT record carries `p`.
- **Kind 20 `PairResult`:**
  - `ok: true`, no `proof`, and a new optional field `method: "cable"`: paired over the cable.
    The device accepts an ok without a proof only as the answer to its own `ask`, and only on a
    connection that runs over its wired interface to the Mac's link-local address (§7.5).
  - New reasons: `"shown"` (the window shows a code now: scan it or type it), `"openOnMac"` (the
    Mac did not show one by itself: choose Pair iPhone or iPad… on the Mac), `"locked"` (the Mac is
    locked).
- **Kind 22 `Goodbye.reason`** gains `"pairingRequired"`: Require pairing was turned on while this
  unpaired device was connected.
- **Kind 21** (`pairingWanted`) is unchanged; only an unpaired session (Require pairing off) still
  has a reason to send it.
- **Constants:** none new. The 4 KiB pairing message and the 1 MiB client message caps apply to
  the home door as they do to the remote one.

```swift
// Remote.swift
extension PairRequest { public static let ask = "ask" }
public struct PairResult: Codable, Sendable {
    …                                   // as today
    /// ok without a proof: how the Mac paired this device by itself. "cable"; nil otherwise.
    public var method: String?
    public static let shown = "shown", openOnMac = "openOnMac", locked = "locked"
}
extension Goodbye { public static let pairingRequired = "pairingRequired" }
```

**Examples as they cross the wire:**

```json
// kind 19, a tap on an unpaired row
{"v":1,"method":"ask","proof":"","name":"iPad","model":"iPad14,1"}
// kind 20 over the cable
{"ok":true,"method":"cable","macID":"A3C5HR4RBV67YR21","name":"Mac mini",
 "recognitionKey":"ERERERERERERERERERERERERERERERERERERERERERE"}
// kind 20 elsewhere
{"ok":false,"reason":"shown"}
{"ok":false,"reason":"openOnMac"}
{"ok":false,"reason":"locked"}
// then, on a second pairing connection to the same home door, exactly the remote path's kind 19
{"v":1,"method":"qr","proof":"AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo","name":"iPad","model":"iPad14,1"}
// kind 22
{"reason":"pairingRequired"}
```

#### 3.2 The TXT record (`HomeDoorTXT`, Pairing.swift, both ends)

- `r`: the recognition tag, unchanged (the remote plan §3.5).
- `p`, new: `"1"` pairing required, `"0"` open (TLS, any device). Absent: a plain door. Any other
  value reads as `"1"`, the safe side.
- Built at every registration (init, `start()`, a Direct Wireless replacement's settle) and when
  Require pairing changes: the listener's `service` is set again on the network queue, or, during
  a Direct Wireless replacement, left to its settle step, which reads the current value. H0's
  probe P1 checks that NWListener updates the record in place (no "(2)", nothing orphaned on
  awdl0).

```swift
public enum HomeDoorTXT {
    public static let key = "p"
    public enum Door: Equatable, Sendable { case plain, pairingRequired, open }
    public static func value(requirePairing: Bool) -> String { requirePairing ? "1" : "0" }
    public static func door(_ txt: [String: String]) -> Door   // no "p": .plain; "0": .open; else .pairingRequired
}
```

#### 3.3 TLS on the home door

- **The Mac:** `RemoteTLS.options(identity: identity.remote.tls, role: .server, queue: queue,
  verify:)`, unchanged (TLS 1.3 only, tickets and resumption off, a client certificate required,
  both ALPNs), over the home door's own TCP options (no Nagle; keepalive 5 s idle, 2 s, 3 probes;
  no `connectionDropTime`, because home clients keep their 4 s drain rule), the interactive video
  service class, and `includePeerToPeer` as Direct Wireless says. A new overload
  `RemoteTLS.parameters(tls:tcp:peerToPeer:)` builds it; the remote door keeps its own.
- **The device:** `RemoteTLS.options(identity:role: .client(alpn:), verify:queue:)` over its
  home TCP options (no Nagle), `includePeerToPeer` for a Direct row only, SNI "sill".

**The Mac's verify block at home** (DoorPolicy.trusts; the home door's origins were checked before
the connection started):

| ALPN | Trusted when |
|---|---|
| `sill/1` | the key is paired, or Require pairing is off |
| `sill-pair/1` | always |
| anything else | never |

**At `.ready`** (DoorPolicy.atReady): `sill/1` → the session, with the paired device's name and key
on its route; `sill-pair/1` → exactly one kind 19 of at most 4 KiB within 10 s of the accept:
`ask` to the ask rule (§4.6), `qr` and `code` to the pairing window. A refused connection is
cancelled with no Sill byte, counted for the minute's summary.

**Measured in the remote plan and still true here** (loopback, 2026-09-24): mutual TLS 1.3 ready in
12–20 ms, suite 0x1302; a key the server refuses leaves the client `.ready`, then its first read
fails with -9825 about 2 ms later; a client whose pin does not match goes `.waiting(-9808)`
without sending its certificate; a plain client makes the server fail with -9858 within about
3 ms, and gets EOF once the server cancels; TLS costs 0.9 ms of CPU per MB at each end, plain TCP
0.4.

#### 3.4 Compatibility

"Main" is origin/main at `ba91136` (PR #13); "this" is a build from this plan.

| Device | Host | Result |
|---|---|---|
| main | this Sill.app (either setting) | The device dials plain. The door fails the handshake as the first bytes arrive (a viewport or a ping, within 0.25 s of the connect) and closes; the device reads EOF. Because main sets `connected` at TCP `.ready`, it shows the stream screen for a moment, then "Mac mini disconnected…", and retries every 2 s; after 5 refusals in 60 s its address is refused at once for 300 s. The Mac counts it as "from an older Sill (not TLS)" and its menu says "An iPhone or iPad Needs Sill Updated" (§6.4). **Install the device build first.** |
| main | SillHost without `--pairing` | As today (plain) |
| this, DEBUG | main's Sill.app (plain door, TXT `r`, no `p`) | Plain, as today: saved Macs recognised by the tag, no pairing at home, remote access as PR #13. Until the device has seen that Mac with `p` (§7.3) |
| this, Release | main's Sill.app | The row says "Update Sill"; a tap says why; nothing is dialed |
| this | this Sill.app, `p=1` | TLS. A saved Mac: a pinned session. An unsaved one: "Not paired", a tap asks. On the cable: paired at once |
| this | this Sill.app, `p=0` | TLS. A saved Mac: pinned. An unsaved one: a session with any Mac key, nothing saved |
| this, DEBUG | SillHost without `--pairing` (no TXT record) | Plain, as today |
| this, Release | SillHost without `--pairing` | "Update Sill"; nothing dialed. The CLI is a development host |
| this | SillHost `--pairing` | As `p=1`; its window is always open and its code printed |
| main's `sillclient.py` | this Sill.app's home door | Refused, as main's device. Every gate against the app uses `--tls` |
| main's `sillclient.py` | SillHost without `--pairing` | Unchanged |
| any | the remote door | Unchanged, except that `ask` there is answered `closed` |

**The floor for 1.0:** Sill.app and the iOS app both from this change on. A Release device never
speaks plain to anything. Nothing has shipped, so nobody but Noah meets the rows above with "main"
in them.

#### 3.5 Rules for later changes

HostSettings.swift's rules, as for every payload since PR #13: JSON only; new fields optional; no
enums on the wire (strings; an unknown value is skipped or, for `p`, read as "1"); never rename or
retype a field. A later generation goes in the ALPN (`sill/2`), `PairRequest.v` and `MacInfo.v`.

---

### 4. Host (`SillHostCore`, folder `Sources/SillHost`), file by file

All new types are `package` or internal. The network queue is StreamServer's `sill.net`; every hop
to the main actor is `Task { @MainActor }`, never `MainActor.assumeIsolated`. The verify blocks and
admission read the lock-protected `TrustSnapshot` and never wait on the main actor.

#### 4.1 `HostConfig.swift`

```swift
/// Require pairing: the home door admits only paired keys (TLS either way). The Mac's alone, like
/// Remote Access: absent from StreamSettings, HostSettingsChange, DeviceSettings.accepted,
/// `applying` and `restartNeeded`. Counts only on a host whose home door speaks TLS (Sill.app;
/// SillHost --pairing); the CLI's default plain door has no pairing at all.
package var requirePairing: Bool
```
- `standard`: `requirePairing: true`. The init keeps every knob required.
- `changes(to:)`: "require pairing on → off".
- `adopt` hands it to `RemoteAccess.apply` (§4.6); no pipeline ever restarts for it.

#### 4.2 `DoorPolicy.swift` (new; pure, Foundation only, checked with swiftc)

Who each door admits, in one place, for both listeners (`Door`, §4.4). RemoteServer's rules move
here unchanged; the home door's are new.

```swift
enum DoorPolicy {
    enum Door: Equatable, Sendable { case home, remote }
    struct Trust: Equatable, Sendable {
        var paired: Bool            // the peer's key is in the trust list
        var requirePairing: Bool
        var remoteAccess: Bool
        var internetAccess: Bool    // already false while Remote Access is off (RemoteAccess.apply)
        var pairingOpen: Bool       // a pairing window is open (the home door's proofs)
        var remotePairingOpen: Bool // one the remote door takes proofs for (§4.6)
    }
    static func admitsBeforeStart(_ door: Door, origin: OriginPolicy.Origin, internetAccess: Bool) -> Bool
    static func trusts(_ door: Door, alpn: String?, _ t: Trust) -> Bool          // the verify block
    enum AtReady: Equatable, Sendable {
        case session
        case pairing(methods: Set<String>)   // what its one kind 19 may be
        case goodbye(String)                 // "remoteOff", "busy"
        case refuse(String)                  // counted for the summary ("unpaired")
    }
    static func atReady(_ door: Door, alpn: String?, _ t: Trust, remoteSessions: Int) -> AtReady
    enum Ask: Equatable, Sendable { case pairNow, shown(opened: Bool), openOnMac(String), locked }
    static func ask(unlocked: Bool, onCable: Bool, cableKeyTaken: Bool, windowOpen: Bool,
                    quiet: Bool, recentDeviceWindows: Int) -> Ask
}
```

| Door | Before start (origin) | Verify block, `sill/1` | Verify block, `sill-pair/1` | At `.ready` |
|---|---|---|---|---|
| home | loopback, lan, direct; vpn and internet refused with no byte | paired, or Require pairing off | always | `sill/1`: the session (checked again); `sill-pair/1`: one kind 19 of `ask`, `qr` or `code` |
| remote | loopback, lan, vpn; internet only with internet access; direct never | paired | a window the remote door takes proofs for is open (was: any window) | as today: unpaired → refused; Remote Access off → goodbye `remoteOff`; 8 sessions → goodbye `busy`; `sill-pair/1`: `qr` or `code`, and `ask` answered `closed` without counting a try |

**The ask rule**, first match wins (§4.6 applies it):
1. the Mac is locked, or the console is another user's → `locked`;
2. on the cable, and no other key paired over this plug-in → `pairNow`;
3. a pairing window is open → `shown(opened: false)`;
4. this device's key or address is quiet (its last window was closed or expired within 10 minutes)
   → `openOnMac("quiet")`; 3 device-opened windows in the last 10 minutes → `openOnMac("often")`
   (the labels are the log's; the device only sees `openOnMac`);
5. otherwise → `shown(opened: true)`: a window opens for it.

#### 4.3 `CableLink.swift` (new; pure) and the IOKit read (`InterfaceSnapshot.swift`), `SessionLock.swift` (new)

```swift
/// Whether a connection came over the USB cable to an iPhone or iPad (docs/home-pairing-plan.md,
/// "The cable"). Pure: IOKit is read by InterfaceSnapshot, this judges what it read.
enum CableLink {
    /// One network interface's IOService ancestry, as far as the first IOUSBHostDevice.
    struct Ancestry: Equatable, Sendable {
        var ncm: Bool               // passes a CDC NCM IOUSBHostInterface (class 2, subclass 13)
        var vendor: Int?            // that device's idVendor
        var productName: String?    // "USB Product Name", else "kUSBProductString"
        var session: UInt64?        // its sessionID: one plug-in
    }
    static let appleVendor = 0x05AC
    static let products: Set<String> = ["iPhone", "iPad"]
    static func isPhoneOrPadCable(_ a: Ancestry?) -> Bool
    /// The plug-in a connection came over, or nil: arrived on such an interface, from a link-local
    /// source. Anything unread counts as no cable.
    static func plugIn(arrival: String?, sourceIsLinkLocal: Bool, cables: [String: Ancestry]) -> UInt64?
}
```

- **InterfaceSnapshot** (read on the network queue, cached 2 s as today) gains `cables: [String:
  CableLink.Ancestry]`: for each up interface that is not loopback, a tunnel or peer-to-peer Wi‑Fi,
  whatever its name (today en14 and anri0; a new name is judged the same way),
  `IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(…))`, then
  `IORegistryEntryGetParentEntry(…, kIOServicePlane, …)` upward: note an `IOUSBHostInterface` with
  `bInterfaceClass` 2 and `bInterfaceSubClass` 13, stop at the first `IOUSBHostDevice`
  (`IOObjectConformsTo`) and read `idVendor`, `USB Product Name` (else `kUSBProductString`) and
  `sessionID`. Under a millisecond an interface; read again only when the interface list changes.
  Nothing written, no permission needed (the probe ran from Terminal as a plain process).
- **SessionLock** (main actor): unlocked when `CGSessionCopyCurrentDictionary()` has
  `kCGSSessionOnConsoleKey` = 1 and no true `CGSSessionScreenIsLocked`; a nil dictionary counts as
  locked. Sill.app adds a second witness, the distributed notifications `com.apple.screenIsLocked`
  and `com.apple.screenIsUnlocked` (either saying locked wins), because the dictionary's lock key
  is undocumented and a rename would read as unlocked. The CLI has the dictionary only.
- **TEST ONLY**, honoured only by a host that does not advertise: `SILL_TEST_CABLE_INTERFACE=<if>`
  counts every interface of that name as a cable to an "iPad" (session 1), so a link-local client
  on the Mac's own `fe80::…%en0` stands in for a device on the cable, as
  `SILL_TEST_PEER_TO_PEER_INTERFACE` stands in for awdl0; `SILL_TEST_LOCKED=1` makes SessionLock
  say locked.

#### 4.4 `Door.swift` (new, from RemoteServer.swift) and `RemoteServer.swift`

- **`Door`** is RemoteServer's admission, moved: pending connections (8 in all, 2 a source), the
  10 s admission deadline, the origin check before start, the verify block (now
  `DoorPolicy.trusts`), `.ready` (`DoorPolicy.atReady`), reading the one kind 19, the backoff (5 of
  its own refusals in 60 s → 300 s; a paired key clears its source), `doorRefusals`, and the
  minute's summary. One class, two instances: `Door(.remote)` owned by RemoteServer and
  `Door(.home)` owned by StreamServer. Its outputs: `onSession(connection, route)` and
  `onPairAttempt(attempt, reply)`; a home attempt also carries the arrival interface, the origin
  and the cable plug-in (`CableLink.plugIn`, read at `.ready` from InterfaceSnapshot).
- **The home door's summary** (the plain door's line stays byte for byte for the CLI):
  "Home door refused N connections in the last minute: a unpaired, b through a VPN, c from the
  internet, d from an older Sill (not TLS), e over the limit." A home handshake that fails with
  -9858 or -9836 (not TLS, or not TLS 1.3) counts as "from an older Sill" and sets
  `olderDeviceAt` (§4.10).
- **RemoteServer** keeps its listener's life (port 7455, the 30 s retry, never another port) and
  its log lines byte for byte; its admission is `Door(.remote)`.

#### 4.5 `StreamServer.swift`

1. **`init(serviceType:advertise:home:)`**, `home: HomeDoorMode`:
   - `.plain`: today's door, byte for byte (the CLI without `--pairing`);
   - `.tls(HomeTLS)`: the identity's `sec_identity_t`, the trust box and the Door's outputs;
   - `.closed(String)`: no listener at all (Sill.app whose keychain failed, §6.1); the status says
     why.
2. **`makeListener(peerToPeer:port:)`** (:338) builds `RemoteTLS.parameters(tls:tcp:peerToPeer:)`
   in `.tls`, today's parameters in `.plain`. The Direct Wireless replacement is unchanged: it
   rebuilds the listener with the same mode.
3. **`accept(_:)`** (:591): `.plain` as today; `.tls` hands the connection to `homeDoor.accept`.
   An admitted session is registered through `serve(_:route:)` (:648), as the remote door's are,
   with `.home(origin, peer:)` and its link (ClientLink), read at registration as today.
4. **`ClientRoute.home`** gains the peer: `.home(OriginPolicy.Origin, peer: Peer?)` with `Peer {
   fingerprint: Data; name: String? }` (name nil for an unpaired key while Require pairing is off;
   no peer on the plain door). `fingerprint` and `pairedName` answer for both doors.
5. **The TXT record:** the coordinator's `txtRecord` returns `r` and `p`. New `updateService()`
   sets `listener.service` again on the queue for a `p` change; during a replacement it does
   nothing, since `settled` (:466) reads the current value.
6. **Ticks** (:138–150):
   ```swift
   // Over TLS every record costs CPU (H20): skip a tick right after anything else went out. The
   // link is busy anyway, so the device's radio stays awake exactly as before.
   if client.encrypted, now - client.lastSentAt < Self.tickInterval { continue }
   // The USB cable has no radio to keep awake.
   if client.encrypted, client.onCable { continue }
   ```
   `encrypted` is every TLS client (both doors; was: remote only); `onCable` is set at
   registration from `CableLink.plugIn`. The plain door keeps today's ticks byte for byte.
7. **`disconnectPeerToPeerClients`** (:487) also cancels the home door's pending connections on
   peer-to-peer Wi‑Fi (an ask or a proof in flight over awdl0). Its line and the rest are unchanged.
8. **Goodbyes:** `goodbye(_:to:)` and `sessions(where:)` serve the home door's sessions as they do
   the remote door's (Remove, Require pairing turned on).

#### 4.6 `RemoteAccess.swift` (it now owns pairing for both doors; the name stays)

- **`apply(config)`** also takes `requirePairing`: `publishTrust()`, `server.updateService()`, and
  when it turns on, every home session without a paired key gets goodbye `pairingRequired`, one
  line each: "Require pairing: disconnecting ‹name› at ‹endpoint›, which isn’t paired."
- **`judge(attempt)`** (:312): `ask` never reaches `PairingWindow.tryProof` (whose unknown methods
  count as wrong codes). On the remote door it is answered `closed`. On the home door,
  `DoorPolicy.ask(…)` with `SessionLock.unlocked()`, the attempt's plug-in, `window.isOpen`,
  `AskLimits` and the key's cable record:
  - `pairNow`: a `PairedDevice` with `method: "cable"` is saved first (a save that fails answers
    `openOnMac` and logs why), then the snapshot; the plug-in records the key; the line "Paired
    ‹name› (key ‹prefix›…) over the USB cable (‹endpoint›)."; `onCablePaired` (the app's notice, the
    CLI's line); kind 20 ok with `method: "cable"`, the Mac ID, name and recognition key.
  - `shown(opened: true)`: `openPairing(requestedBy: ‹name›, byDevice: (key, source, route))`; kind
    20 `shown`.
  - `shown(opened: false)`: kind 20 `shown`.
  - `openOnMac`, `locked`: `pairingRequest` set for the menu (§4.10); kind 20 with that reason.
  - Each ask logs one line (§4.11).
- **`openPairing(requestedBy:byDevice:)`** (:198): only some windows are the remote door's. A
  window opens the remote door (`updateDoor`, :420: `remoteAccess || (window.isOpen &&
  window.forRemote)`) and lets it take proofs (`publishTrust` sets `remotePairingOpen`) when the
  Mac's user opened it in Sill.app, or when the CLI runs with `--remote`; never a window a device
  opened, and never the CLI's with `--pairing` alone, whose always-open window would otherwise bind
  7455 beside Sill.app's. `PairingOffer` gains `byDevice`, and the app shows such an offer in front
  without taking the keyboard (§6.3). When a device-opened window closes cancelled or expired,
  `AskLimits` makes that key and address quiet for 10 minutes.
- **Kind 21** (`pairingWanted`, :244) opens a device-opened window too (a Pair This iPad… from an
  unpaired session while Require pairing is off).
- **`remove(fingerprint:)`** (:266) closes that key's home sessions as well as its remote ones,
  each with goodbye `removed`; the line counts both.
- **`sessionStarted(fingerprint:route:)`** records home sessions of paired keys too, with the home
  route's words: "over the USB cable" (CableLink), "over Wi‑Fi", "over Ethernet", "directly"
  (peer-to-peer Wi‑Fi), "on this Mac" (loopback), else "at home". Written at most once a minute per
  device, as today.
- **The cable's keys:** `cableKeys: [UInt64: Data]`, plug-in → the key paired over it; an entry
  goes when its plug-in leaves InterfaceSnapshot.
- **The CLI** (`reopensPairing`): its window is always open, so an ask is answered `shown` and the
  CLI prints the code again with who asked (§5).

#### 4.7 `PairingWindow.swift`

- `Open` gains `byDevice: DeviceAsk?` (the key's fingerprint and the source address), for the quiet
  rule and the window's copy, and `forRemote: Bool` (whether the remote door runs for it and takes
  its proofs, §4.6).
- **`AskLimits`** (new, pure, same file, checked with swiftc):
  ```swift
  struct AskLimits {
      static let quietFor: Double = 600      // after a device-opened window is closed or expires unused
      static let span: Double = 600          // at most `maxWindows` device-opened windows in this span
      static let maxWindows = 3
      func quiet(fingerprint: Data, source: String, now: Double) -> Bool
      func recentWindows(now: Double) -> Int
      mutating func opened(now: Double)
      mutating func closedUnused(fingerprint: Data, source: String, now: Double)
  }
  ```
  TEST ONLY `SILL_TEST_ASK_QUIET=<s>` replaces both 600 s on a host that does not advertise.

#### 4.8 `HostIdentity.swift`

- `PairedDevice.method`: "qr", "code" or, new, "cable" (M5 adds "icloud"). `displayMethod`: "with
  the QR code", "with a code", "over the USB cable".
- `TrustSnapshot` gains `requirePairing` and `remotePairingOpen`.

#### 4.9 `StreamCoordinator.swift`

- `init(config:synthetic:appKitLoop:remote:homePairing:)`: the server's home mode is `.plain`
  without `homePairing` (the CLI's default), else `.tls` with the remote identity, or `.closed`
  with its `identityProblem`.
- `onClientConnected`: a paired home session shows its paired name until its stats arrive, as a
  remote one does, and records `sessionStarted` for the pane's "last connected".
- `.pairingWanted` (:539): from a home session whose key is not paired (Require pairing off), not
  within 30 s of that connection's last one. A paired session's is ignored.
- `adopt`: `requirePairing` changed → `remote?.apply(next)`. No restart.

#### 4.10 `HostStatus.swift`

`RemoteStatus` (kept, one type for both doors' pairing) gains:
```swift
package enum HomeDoor: Equatable { case plain, pairingRequired, open, unavailable(String) }
package var homeDoor: HomeDoor
/// A device asked and no window shows its code (the Mac locked, or the limits), or a device-opened
/// window is open: for the menu's "‹device› Wants to Pair", 5 minutes after the ask.
package var pairingRequest: PairingRequest?     // name, at, reason: "showing" | "locked" | "limit"
/// The last connection the home door refused as not TLS (an older Sill), for the menu.
package var olderDeviceAt: Date?
```
- `Pairing.open(requestedBy:expiresAt:triesLeft:lastWrongFrom:)` gains `byDevice: Bool`.
- `PairedDeviceSummary.lastRoute` now holds home routes too.
- The code and the QR secret are still never in the status.

#### 4.11 Log lines (exact; each only when its event happens; never a code or a secret in Sill.app)

```
Home door: TLS, pairing required (2 paired).
Home door: TLS, pairing not required.
Home door unavailable: Sill couldn’t use its key in the keychain (‹error›).
Pairing: iPad (iPad14,1) at fe80::1c0f:2a:6e1:9b3%en0 asked to pair; showing the code.
Pairing: iPad (iPad14,1) at fe80::1c0f:2a:6e1:9b3%en0 asked to pair; the code is already showing.
Pairing: iPad (iPad14,1) at fe80::1c0f:2a:6e1:9b3%en0 asked to pair; not shown (this Mac is locked).
Pairing: iPad (iPad14,1) at fe80::1c0f:2a:6e1:9b3%en0 asked to pair; not shown (its last window was closed 3 minutes ago).
Pairing: iPad (iPad14,1) at fe80::1c0f:2a:6e1:9b3%en0 asked to pair; not shown (3 windows in 10 minutes).
Pairing window open for 5 minutes (asked by iPad (iPad14,1) on this network).
Paired iPad (iPad14,1) (key 5KD2Q7…) over the USB cable (fe80::18fe:abff:febb:459f%anri0).
Cable pairing: iPad (iPad14,1) at fe80::18fe:abff:febb:459f%anri0 not paired by itself (another key was paired over this cable since it was plugged in); showing the code.
Paired iPad (iPad14,1) (key 5KD2Q7…) from fe80::1c0f:2a:6e1:9b3%en0, with the QR code.
Require pairing: disconnecting iPhone (iPhone17,1) at 10.128.0.41:61022, which isn’t paired.
Removed iPad (iPad14,1); closed 1 connection.
Home door refused 7 connections in the last minute: 3 unpaired, 0 through a VPN, 0 from the internet, 4 from an older Sill (not TLS), 0 over the limit.
Settings: require pairing on → off
```

"Client connected: …", "Client left: …" and "Catalog → …" keep their exact text: tests grep for
them. The first two lines print once at start (Sill.app always; the CLI only with `--pairing`).

---

### 5. CLI (`Sources/SillHostCLI/main.swift`)

| Flag | Effect |
|---|---|
| none | Output byte-identical to `ba91136` (masked and sorted), idle and streaming, with and without `--direct-wireless` and `--remote`. Today's plain home door: no pairing, no `p` in any TXT record |
| `--pairing` | The home door speaks TLS with pairing required. A throwaway identity (`MemoryIdentityStore`; `SILL_TEST_REMOTE_DIR` on `--synthetic`), the same one `--remote` uses when both are given; the remote door runs only with `--remote`. A pairing window is always open (a fresh one after each use or expiry, as with `--remote`); its link carries the remote door's port and addresses as today, which a device pairing at home ignores. main.swift prints from the `onPairingOffer` hook: `Pairing required for this run (TLS on the home door). Pair with 4829 1355 7208 or sill://pair?v=1&…`, and on each ask `Pairing: iPad (iPad14,1) asked; code 4829 1355 7208 or sill://pair?v=1&…`. Over the cable the core's "Paired … over the USB cable (…)." line. With `--remote` too, each prints its own startup line and the pairing lines once |
| `--print-cable` | For each interface: `en14: the USB cable to an iPad (Apple, product 0x12AB, NCM, plug-in 4739806731214)`, `anri0: the USB cable to an iPad (…)`, `anpi0: not a cable (this Mac's own USB device port)`, `en0: not a cable (no USB device)`; then `This Mac: unlocked, your session on the console.` and exit 0. Read-only IOKit and CGSession, no listener, no permission. H5's live check with a device on the cable |

**Why the default stays plain.**
- The CLI is the development host. Its default output is the parity baseline every step of every
  plan checks; a pairing line or a warning line would change it for every gate from here on.
- Every existing headless gate, `sillclient.py` without `--tls`, and the simulator's
  `-SillConnect` tests (the moves, the wired fallback) talk to it plainly and keep working.
- Only a DEBUG device build dials a plain door (§7.3); a Release device never reaches it.
- Rejected: pairing required by default (a code line in every run, every gate rewritten for TLS);
  an open TLS door by default with a warning line (the baseline changes by that line, for nothing
  a development host needs).
- The README says: "SillHost without --pairing lets any device on your network connect, without
  encryption. Use it only while developing Sill."
- The code and the link go to the CLI's own stdout only, as with `--remote`; core code never
  prints them.

---

### 6. Sill.app (`Sources/SillMenuBar`)

Errors inline, never in alerts. Windows open from AppKit target/action, SwiftUI `Button` actions,
or, for a device's request, a main-actor hop that shows a window and runs no modal loop. Sill's
windows stay off the virtual display and out of every Desktop stream (PR #13).

#### 6.1 Settings › Devices (a new tab, after General)

`SettingsTab.devices`, titled "Devices", symbol `ipad.and.iphone`. New `DevicesPane.swift`, a
grouped Form 520 pt wide, following `HostStatus` live.

**Section 1**
- Toggle **"Require pairing"** (`$settings.config.requirePairing`).
- Footer while on: "Each iPhone or iPad pairs once: over the USB cable by itself, or on Wi‑Fi with
  a code this Mac shows when the device asks. Everything devices send and receive is encrypted."
- While off (orange, with its sign): "Any device on your network, or nearby with Direct Wireless
  Connection on, can see and control this Mac without pairing. Connections are still encrypted."
- The keychain unusable (orange): "Devices can’t connect: Sill couldn’t use its key in your
  keychain (‹error›). Quit Sill and open it again, and choose Always Allow if the keychain asks."

**Section 2 "Paired Devices"** (moved from Remote Access, the same rows)
- Detail: "Paired Sep 25 over the USB cable · last connected 2 minutes ago over Wi‑Fi", "Paired Sep
  24 with the QR code · last connected yesterday through Tailscale".
- Remove (no confirmation), rename (double-click), "iPad (iPad14,1) can no longer connect. To use
  it again, pair it again." and the keychain line after a failed Remove, as today.
- Empty: "No paired devices yet."
- **[Pair iPhone or iPad…]**
- Footer: "A paired device can see and control this Mac on your network, nearby, and from afar
  while Remote Access is on. If one is lost, remove it here."

#### 6.2 Settings › Remote Access

Its "Paired Devices" section becomes one row: "Paired devices" with the count and **[Show
Devices…]** (opens the Devices tab), footer "The devices you pair in Devices can connect from afar
while Remote Access is on." Everything else is unchanged.

#### 6.3 The pairing window (`PairDeviceWindow.swift`)

**Opened by a device** (an ask, or kind 21):

```
┌─ Pair iPhone or iPad ────────────────────────────────┐
│ iPad (iPad14,1) on this network asked to pair.       │   "…nearby asked to pair." over peer-to-peer
│ Point it at this code, or tap Enter Code Instead     │   Wi‑Fi; "…on this Mac…" over loopback
│ and type the code.                                   │
│                 ██▀▀▀▀██ ▄▀▄ ██▀▀▀▀██                │
│                 ██ ██ ██ ▀▄█ ██ ██ ██   (220 pt)     │
│                 ██▄▄▄▄██ █▀▄ ██▄▄▄▄██                │
│   Code      4829 1355 7208                           │
│ Works once, for the next 4:58.                       │
│ A paired device can see and control this Mac.        │
│ Didn’t ask for this? Click Cancel.                   │
│                                            [Cancel]  │
└──────────────────────────────────────────────────────┘
```

- No Address row (the device dials the door it asked on) and no Remote Access line. The device's
  name goes through SafeText (at most 64 characters, no control or bidi characters), as every
  device-supplied name does.
- Shown with `orderFrontRegardless()` and no `NSApp.activate()`: not `WindowPlacement.bringForward`
  (SettingsWindow.swift:133), which activates Sill. In front, off the virtual display, without the
  keyboard; `.fullScreenAuxiliary` so it shows over a full-screen app. A click makes it key.
- Its states (Pairing with…, Paired with…, a wrong code…, stopped, expired) are today's.

**Opened on the Mac** (the menu, a pane, New Code): as today, activating Sill, with the first line
"In Sill on your iPhone or iPad, tap this Mac, or tap Add a Mac… when you’re away, then point it at
this code." (was "…tap Add a Mac…, then point it at this code."). The Address row and the Remote
Access line stay: they are for pairing from away.

**The cable notice** (the same window, a new phase):

```
┌─ Paired over the USB Cable ──────────────────────────┐
│ ✓ iPad (iPad14,1) is paired with this Mac.           │
│ It paired by itself over the USB cable, and can      │
│ connect over Wi‑Fi and nearby from now on too.       │
│                                    [Remove]  [OK]    │
└──────────────────────────────────────────────────────┘
```

- One per pairing, never per connection; closes by itself after 10 s; shown like a device-opened
  window (in front, no keyboard). Remove is the Devices pane's Remove, with its keychain rule.
  VoiceOver announces its first line.

#### 6.4 Status menu and card (`StatusItemController.swift`, `StatusText.swift`)

New attention items (first group, orange):

| Title | Subtitle | While | Action |
|---|---|---|---|
| "iPad Wants to Pair" (the device's name) | "Showing a code" · "Show a Code…" · "Unlock this Mac, then tap it on the iPad again" | `pairingRequest`, 5 minutes from the ask: a device-opened window is open · an ask the limits kept from showing · the Mac was locked | brings the window forward, or opens one on the Mac "asked by" that device |
| "An iPhone or iPad Needs Sill Updated" | "It tried to connect with an older Sill." | 10 minutes from `olderDeviceAt` | none |
| "Devices Can’t Connect" | "Sill couldn’t use its key in your keychain." | `homeDoor == .unavailable` | Settings › Devices |

- The glyph shows attention for the first and the third (Sill needs its user); the second is only
  information.
- "Pair iPhone or iPad…" stays in the third group.
- The card: a paired device's row shows its paired name until its stats arrive, as remote ones do.

#### 6.5 Settings keys and wiring (`HostSettings.swift`, `AppModel.swift`)

- `requirePairing` (true), registered from `HostConfig.standard`, saved only when changed;
  `-requirePairing NO` overrides it for one run. An existing install has no key and comes up on.
- `remoteDevicesSeen` keeps its name and now also holds home sessions.
- AppModel: `StreamCoordinator(…, homePairing: true)`; `onCablePaired` shows the notice; the
  Devices pane gets the pair, remove and rename actions the Remote Access pane had; it observes the
  lock notifications for SessionLock (§4.3).
- StreamProtocol's HostSettings.swift header ("every place a new setting must go") adds require
  pairing to the Mac-only knobs that never enter StreamSettings, HostSettingsChange or
  DeviceSettings.accepted.

#### 6.6 DebugHooks and previews

- `-SillSetAfter` learns `requirePairing=0|1`.
- `-SillCancelPairingAfter <s>` closes the pairing window as Cancel does (the quiet rule).
- `-SillCableNoticeAfter <s>` shows the notice for a sample device.
- `-SillRenderPreviews` adds `pane-devices-{required,off,empty,unavailable}-{light,dark}.png`,
  `pairing-{asked,askednearby,cablenotice}-{light,dark}.png`, the Remote Access pane's samples with
  the list replaced by its line, and menu.txt's three attention items.

---

### 7. iOS client

#### 7.1 Files (a new file needs its four pbxproj entries, by hand)

| File | Change |
|---|---|
| `Sources/StreamProtocol/*` (shared) | Remote.swift (`ask`, the new reasons, `PairResult.method`, `pairingRequired`); Pairing.swift (`HomeDoorTXT`); RemoteTLS.swift (the parameters overload) |
| `iOSClient/DiscoveryPolicy.swift` | `homeDial`, `rowWord`, `onCable` (pure) |
| `iOSClient/SavedMacs.swift` | `homeTLS`, `revoked` (optional: older records decode) |
| `iOSClient/StreamClient.swift` | one TLS builder for every home dial; `p` from each result; the session gate at the first window list; revoked |
| `iOSClient/StreamClient+Remote.swift` | the ask; pairing through the row; the cable's ok; the goodbyes at home |
| `iOSClient/AddMacCard.swift` | a home mode: the scanner, or the code alone |
| `iOSClient/ContentView.swift` | row words and hints; the card for a row; the harness contract |
| `iOSClient/HostSettingsPanel.swift` | Away from home: "Paired"; Pair This ‹iPad›… only in an unpaired session |
| `iOSClient/MockCatalog.swift` | the new cases |
| PR #12's files, once merged | its `startMove(to:kind:fallback:)` and `reconnectNow` dial through the builder |

#### 7.2 One builder for every home connection

- **`HomeLink.parameters(identity:pin:peerToPeer:alpn:)`** replaces `connectionParameters(peerToPeer:)`
  (StreamClient.swift:867) for every connection to a Mac whose row carries `p`: `connect(to:)`
  (:763) with its wired dial and fallback, the automatic reconnect (through `dial`, :731), the move
  from AWDL (`startMove`, :935) and its fallback, PR #12's moves and `reconnectNow`, and the
  session after a pairing. The plain builder stays for plain doors (DEBUG only, §7.3).
- **The pin** is the saved Mac's fingerprint. For an unsaved Mac on an open door (`p=0`) the
  session's first connection takes any key, and every later connection of that session (a move,
  a PR #12 hop) pins the key the first one saw. `DeviceIdentity.loadOrCreate()` runs at the first
  TLS dial (today: at the first pairing).
- **A move's new connection** is read up to its first window list before it takes the session
  over (`probeMove`); over TLS that is also where the Mac's refusal of the key shows (a read error,
  -9825, right after `.ready`), and a refused move ends as a failed one does today. SessionLink's
  fences, holds and hand-overs are unchanged.
- **Connected at the first window list**, as the remote door's sessions are
  (`remoteSessionReady`): a TLS session is `.ready` before the Mac has judged the key.
  `connected`, `connectedAt`, `reconnect = nil` and "Connected to ‹Mac›" move there. The route word
  is still read at `.ready` (`setRoute(from:fresh:)`). PR #12's `reconnectNow` keeps the stream
  screen up as it does today; its new connection counts once its first window list arrives, like a
  move's.
- TCP as today on the device (no Nagle); `includePeerToPeer` for a Direct row only; the video
  service class.

#### 7.3 Discovery: the TXT record, rows and their words

- `recomputeMacs` (:575) reads `p` with `HomeDoorTXT.door` beside `r` (`tag(of:)`, :620), for
  both browsers. `FoundMac` gains `door: HomeDoorTXT.Door`.
- `SavedMac` gains `homeTLS: Bool?` (the Mac was seen with `p`, or a TLS home session with it ran)
  and `revoked: Bool?` (goodbye `removed`, or a pinned home dial refused with -9825 or -9829;
  cleared by the next pairing).

| Row (`DiscoveryPolicy.rowWord`) | Word | VoiceOver |
|---|---|---|
| a saved Mac, not revoked, on a TLS door | its method, as today: "Wired", "Wi‑Fi", "Direct" | as today |
| unsaved or revoked, `p=1`, not Wired | "Not paired" | "Mac mini, not paired"; hint "Pairs with a code Mac mini shows, then connects." |
| unsaved or revoked, `p=1`, Wired | "Wired" | "Mac mini, Wired"; hint "Pairs over the USB cable, then connects." |
| unsaved, `p=0` | its method | as today |
| no `p`, DEBUG, not `homeTLS` | its method (a plain door, as today) | as today |
| no `p`, Release; no `p` and `homeTLS` | "Update Sill" | hint "Mac mini’s Sill is too old for this ‹iPad›." |

- **No downgrade.** Once a saved Mac is `homeTLS`, its rows are dialed only over TLS, in DEBUG too;
  a row of it without `p` reads "Update Sill" (its own Sill never goes back to plain; someone may
  be replaying its tag). A Release build never dials plain at all.
- Remote rows are unchanged.

#### 7.4 A tap (`DiscoveryPolicy.homeDial`, pure)

| Row | A tap |
|---|---|
| saved, not revoked, TLS door | `sill/1` pinned to the saved key; connected at the first window list |
| saved and revoked; unsaved with `p=1` | the ask (§7.5) |
| unsaved, `p=0` | `sill/1` with any Mac key; nothing saved |
| no `p`, DEBUG, not `homeTLS` | plain, as today |
| no `p`, otherwise | nothing dialed; status "Mac mini runs an older Sill. Update Sill on the Mac to connect." |

- The automatic reconnect follows the same table, and never asks: an ask is a tap's.
- A Wired row's dial goes over the cable first (`wiredDial`, :748) with its fallback after
  `wiredWait`, for an ask as for a session.

#### 7.5 Pairing at home (`StreamClient+Remote.swift`)

1. **The ask.** A `sill-pair/1` connection to the row (its wired interface first for a Wired row)
   that takes any Mac key and remembers the one it saw (`askedKey`); kind 19 `ask`; kind 20 within
   15 s (`pairingReplyDeadline`). Status "Pairing with Mac mini…" ("…over the cable…" on a Wired
   row).
2. **Kind 20 ok with `method: "cable"`.** Accepted only when this connection runs over the cable
   as the device sees it (`DiscoveryPolicy.onCable`, pure): the Mac's address is link-local and
   scoped to a wired interface (the iPad saw it on en2, 2026-09-25), or it is IPv4 link-local
   (169.254/16) with this device's own address on a wired interface. Otherwise "Pairing didn’t
   finish…" and nothing is saved, so a look-alike on Wi‑Fi cannot make a device pin it without a
   code. Saved: `method "cable"`, the pin from this session, the recognition key, `homeTLS`, the
   Bonjour name. Then a pinned session on the row.
3. **`shown`.** The connect screen unfolds the home card for that row (§7.8): the scanner, or
   after Enter Code Instead the code alone.
   - A scanned link whose key is `askedKey`: a second `sill-pair/1` connection to the row, pinned
     to that key, kind 19 `qr` with the proof from the link's secret. A link with another key is
     another Mac's code: today's pairing through the link's addresses.
   - A typed code: `sill-pair/1` to the row pinned to `askedKey`, kind 19 `code` with the PBKDF2
     proof; the check digit is checked first, as today.
   - Kind 20 ok with proof_M checked and `macID == MacID(fp)`: saved as the remote path saves,
     plus `homeTLS` and the Bonjour name; then a pinned session on the row.
4. **`openOnMac`, `locked`:** the status line (§7.7); no card.
5. **`busy`:** one silent retry, as today. `closed`, `expired`, `stopped` on the second
   connection: §7.7's words; a tap on the row asks again.

- **An outside link** (`onOpenURL`, after its confirmation) goes the same way: to the row whose
  asked key it names, else through its addresses, as today.
- **Pair This ‹iPad›…** (the panel's overlay; now only in an unpaired session while Require
  pairing is off): kind 21, then scan or type, dialed on the session's row as above, never through
  kind 18's addresses (a device-opened window does not start the remote door).
- **Add a Mac…** (pairing from away) is unchanged.

#### 7.6 How a session at home ends

- **goodbye `removed`**, or -9825/-9829 right after `.ready` on a pinned home dial: the saved Mac is
  `revoked`; no automatic reconnect; status "Mac mini removed this ‹iPad›. Tap it to pair again.";
  its row reads "Not paired" (on the cable, "Wired").
- **goodbye `pairingRequired`:** status "Mac mini now asks devices to pair. Tap it to pair this
  ‹iPad›."; no automatic reconnect; the row reads "Not paired" once the new TXT record arrives.
- **-9808** on a pinned home dial (another key answers as that Mac): the remote copy, "This isn’t
  the Mac mini this ‹iPad› paired with. If Sill was set up again on it, forget it here and pair
  again."; never a plain retry.
- **The panel's Away from home group** (HostSettingsPanel.swift:303): the saved Mac's row reads
  "Paired" (was "Paired for remote access"); Pair This ‹iPad›… shows only in an unpaired session.

#### 7.7 Copy on the device (inline; VoiceOver announces each status line, as today)

**Connect screen**

| Where | Text |
|---|---|
| Row words | "Not paired", "Wired", "Update Sill" (§7.3) |
| Status | "Pairing with Mac mini…" · "Pairing with Mac mini over the cable…" · "Paired with Mac mini over the cable." · "Mac mini runs an older Sill. Update Sill on the Mac to connect." · "Mac mini removed this ‹iPad›. Tap it to pair again." · "Mac mini now asks devices to pair. Tap it to pair this ‹iPad›." |
| After an ask | `openOnMac`: "Mac mini didn’t show a code. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then tap Mac mini again." · `locked`: "Unlock Mac mini, then tap it again." |

**The home card**

| Where | Text |
|---|---|
| Title | "Pair with Mac mini" (a heading; VoiceOver focus moves to it) |
| Scan line | "Mac mini is showing a code. Point this ‹iPad› at it." |
| Viewfinder | Caption "Point at the code on Mac mini"; spoken "Camera. Point it at the code on Mac mini." |
| Typed | "Type the code Mac mini shows." Field "Code", placeholder "0000 0000 0000", the remote path's code keyboard; [Pair] |
| Links | "Enter Code Instead" / "Scan Code Instead" · "Cancel" |
| Errors, under the field | "A code has 12 digits." · "That code has a typo. Check it against your Mac." · "That code didn’t work. Check the code on your Mac. 4 tries left." · "Mac mini stopped pairing after too many wrong codes. Tap Mac mini for a new code." · "That code was used or has expired. Tap Mac mini for a new one." · "Pairing didn’t finish: Mac mini couldn’t show it knows the code. Tap it to try again." |

#### 7.8 Layout

The home card is AddMacCard in a home mode, with every layout rule of the remote plan §7.10: the
380 pt leading column, the viewfinder at the column's width × 230 pt, side by side under 520 pt
tall, the top half at 710×1000 (nothing crosses the crease), 48 pt fields, the column to the top
while the keyboard is up. Its typed path has the code field alone, so the collapsed line is "Type
the code Mac mini shows." Esc, Cancel or the escape gesture fold it back to the rows.

#### 7.9 Harness and DEBUG arguments (ContentView.swift's contract comment, and CLAUDE.md)

- `-SillConnectCase` gains `homerows` (a saved Wi‑Fi row, "Not paired", an unpaired "Wired",
  "Update Sill", a long name), `homecard`, `homecode`, `homecodeerror`, `homeasking`, `homelocked`,
  `homeopenonmac`, `homerevoked`, `homecabledone` and `pairingrequired`.
- `-SillSettingsCase` gains `paired` (Away from home's "Paired") and `openpair` (an unpaired
  session with Pair This iPad…).
- `-SillHomeDoor paired|open|plain`: what a `-SillConnect` address counts as, since an address has
  no TXT record. Default `plain`, today's behaviour, so every existing gate is unchanged.
- `-SillServiceType _silltest._tcp`: the browsers look for that type instead of `_sill._tcp`, so a
  test host registered with `SILL_TEST_SERVICE_TYPE` shows as a real row with its TXT record, and
  no real Mac is listed.
- `-SillCableTest 1`: this device's path counts as the cable for §7.5's check (the simulator has
  none). With the host's `SILL_TEST_CABLE_INTERFACE=en0` and `-SillConnect` to the Mac's own
  `fe80::…%en0`, the whole cable path runs in the simulator.

---

### 8. TLS on every home connection: what it costs, and the tick

- **The handshake**, once per connection (a tap, a reconnect, a move): 12–20 ms on loopback (the
  remote door, measured), plus one round trip of the link: about 1–2 ms on the cable, 5–10 ms on
  Wi‑Fi, about 75 ms over AWDL. The moves' budgets have room: the wired wait is 2.5 s and a move
  gets 5 s. PR #12's move down (the cable pulled) holds what the device sends until the Wi‑Fi
  connection is ready, so its hold grows by the handshake, some 15–30 ms on Wi‑Fi.
- **The bytes:** TLS 0.9 ms of CPU per MB at each end against 0.4 for plain TCP (the remote plan
  §3.3), so +0.5 ms per MB. At Balanced (15 Mbps, 1.9 MB/s): +1 ms a second, 0.1 % of a core. At
  Extreme over the cable (150 Mbps at 60 fps, 18.75 MB/s): +9 ms a second, about 0.9 %; at 120 fps
  about 1.9 %. The iPad pays the same per byte. A frame's last TLS record decrypts in
  microseconds, so frame age does not move.
- **The tick** exists for the device's Wi‑Fi power save: a downlink quiet for a moment lets the
  radio doze, and the next packet waits up to 300 ms (CLAUDE.md, trackpad stutter (1)). Over TLS
  each 14-byte tick is a record: the remote door measured +1.46 percentage points of host CPU with
  a tick every 30 ms, and 5.79 % (TLS, a tick skipped right after anything else went out) against
  6.08 % (the plain home door with every tick), 60 s at 60 fps (PR #13, step 3, H20). So:
  - every TLS client, home or remote, skips a tick when something went out within the last 30 ms
    (the remote rule, StreamServer.swift:146): the downlink is exactly as busy as before, and the
    radio stays awake;
  - a device on the USB cable gets no tick at all: there is no radio to keep awake;
  - over Wi‑Fi and Direct the tick stays;
  - the plain door (the CLI's default) keeps every tick, byte for byte.
- **Measured before it counts:** H0's probe P3 (per MB, per record), H9 (host CPU, frame age), P11
  (the `rtt m/M` maxima on a still window over Wi‑Fi as before; on the cable without ticks; Extreme
  at 120 fps over the cable as before).

---

### 9. Timeouts and limits (one table)

| What | Value |
|---|---|
| Home door: accept → admission (TLS, plus a pairing connection's one kind 19) | 10 s |
| Home door: pending connections | 8 in all, 2 per source; 5 of the door's own refusals in 60 s → refused for 300 s; a paired key clears its source |
| Device-opened pairing windows | one at a time; at most 3 in any 10 minutes; a device whose window was cancelled or expired opens none for 10 minutes (by key and by address) |
| Pairing window | 300 s, 5 wrong proofs, spacing 1/2/4/8 s, 5 s per source, single use (as today) |
| The ask: kind 20 on the device | within 15 s |
| The cable: keys paired by themselves per plug-in | 1 (the same key may pair again) |
| The cable notice | 10 s |
| The menu's "‹device› Wants to Pair" | 5 minutes after the ask |
| The menu's older-device item | 10 minutes after the last refused plain connection |
| Kind 21 | once per 30 s per unpaired connection |
| Ticks | 30 ms; skipped within 30 ms of a send for TLS clients; none on the USB cable |
| Home clients' eviction | unchanged: no drain for 4 s, after an 8 s grace |
| Pairing message; client message | 4 KiB; 1 MiB |

---

### 10. Edge cases

| Case | Behaviour |
|---|---|
| Noah's iPad, paired by QR for Tailscale on 2026-09-25 | Paired at home too: one trust list. After both updates it connects over TLS with no step (P1) |
| Sill deleted and installed again on the iPad | Its saved Macs went with the app (UserDefaults), though its key may still be in the Keychain; the rows read "Not paired" and a pairing replaces the Mac's record of that key. An ask from a key the Mac already trusts is still a normal ask: a proof-less answer off the cable would let a look-alike be pinned |
| The iPad restored from a backup | No key (`ThisDeviceOnly`), so its saved Macs are cleared at launch (`knownMissing`); it pairs again; the Mac lists the old key until it is removed |
| Sill set up again on the Mac (a new key and recognition key) | Its tag no longer names the saved Mac: its row is an unsaved "Not paired", the old record a Remote row. Pairing again gives "Mac mini" and "Mac mini (2)"; Forget the old one (as in the remote plan) |
| Remove while the device streams on the cable | Goodbye `removed`; the row reads "Wired"; a tap pairs it again over the cable, and the notice shows again. Unplug it to keep it out |
| Remove while it streams on Wi‑Fi | Goodbye `removed`; "Not paired"; a tap asks and the window opens |
| The Mac locked, the cable in | "Unlock Mac mini, then tap it again."; the menu's item |
| Another user's session on the console (fast user switching) | Counts as locked: nothing pairs by itself, no window opens (it could not be seen) |
| Two devices on the cable at once | Two plug-ins: each pairs by itself |
| A new key over the same plug-in (Sill deleted and installed again while plugged in, its key gone) | A second key: the code window. Unplug and plug in again to pair by itself |
| An iPad on a USB-C Ethernet adapter on the LAN | Its row says Wired; the ask arrives on the Mac's LAN interface, which has no iPhone or iPad above it: the window |
| An iPhone sharing its connection over USB (Personal Hotspot) | That iPhone is on the cable (link-local); its hotspot's other clients arrive routed, never link-local: never the cable |
| Another Mac over USB-C or Thunderbolt Bridge | No iPhone or iPad above the interface: never the cable |
| A stranger asking again and again | One window; after Cancel or expiry, 10 minutes of quiet per key and address; at most 3 windows in 10 minutes; never the keyboard; never while locked; the menu's item otherwise |
| A device-opened window while the Mac's screen is shared in a meeting | The code could be read. It works only at the home door (this Mac's network, or nearby), within 5 minutes, and only if the real device has not used it; `sharingType = .none` is best effort; "Didn’t ask for this? Click Cancel." |
| An ask while the Mac's user has a window open for pairing someone away | `shown`: the device scans that window's code; the first valid proof wins and the other gets `closed` and asks again |
| Direct Wireless turned off mid-pairing over AWDL | The home door's pending connections on peer-to-peer Wi‑Fi are cancelled with its sessions; the device pairs on the network, or with Direct Wireless on again |
| Require pairing turned on while unpaired devices are connected | Each gets goodbye `pairingRequired`; paired ones stream on; the TXT record says `p=1` |
| Require pairing turned off | Nothing ends; `p=0`; unpaired devices connect without a code, still encrypted |
| The keychain unusable at launch | No home listener: "Devices Can’t Connect", the Devices pane's line; Sill.app keeps running (fail closed) |
| An older device build | Refused at TLS; the Mac's menu says so; the device retries until it is updated (§3.4) |
| A local process over loopback | Needs pairing like any device while Require pairing is on: the confused deputy is closed |
| A session moved by PR #12 (cable ↔ Wi‑Fi) or from AWDL | Each new connection is TLS, pinned; the Mac admits it by its key; the fences as before |
| Tailscale on both at home | Bonjour lists the Mac: the home door, over TLS. Connect Remotely still tests the remote door |
| A remote session | Unchanged |
| The CLI without `--pairing` on the same network as Sill.app | Two rows. The CLI's is a plain door: DEBUG devices can dial it, a Release device shows "Update Sill" |

---

### 11. Test gates

**Hard rules for the implementing session:**
- Only synthetic hosts from `.build/release`, or the bare `SillMenuBar --synthetic` with
  `SILL_TEST_REMOTE_DIR`, started from Python with `start_new_session=True`, killed by PID, none
  left running. Never `/Applications/Sill.app`, the `me.saffer.sill.mac` domain, Noah's login
  keychain or his iPad. `defaults delete SillMenuBar` afterwards.
- A synthetic host that streams uses the Mac's hardware encoder. Before such a run, check that
  Noah's Sill.app is not streaming (the last `client …` line in `~/Library/Logs/Sill/Sill.log` is
  more than a minute old); keep streaming runs under 60 s; most pairing gates stop at the catalog.
  No XCUITest and no `simctl io recordVideo` (both drive the encoder at a higher priority than
  Sill's); photos with `simctl io screenshot` only.
- Registrations only under `_silltest._tcp`; in the simulator `-SillServiceType _silltest._tcp`, so
  no real Mac is ever a row to tap. AWDL-on tests under 20 s.
- `$T` is a fresh directory per gate; `sillclient.py --identity=$T/…` keeps its key there.

**Test tools.** `Scripts/sillclient.py` gains, each checked before it connects: `--pair-ask`
(kind 19 `ask`; prints kind 20), `--then-code=FILE` (after `shown`, reads the code from FILE and
pairs over the same door: the CLI's printed code saved by the harness, or the bare app's
`$SILL_TEST_REMOTE_DIR/pairing.code`), and `--expect-pair=ok|cable|shown|openOnMac|locked|closed`.
`--host=fe80::…%en0` (existing) reaches the stand-ins.

**Headless (H): no permissions needed.**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). The base's commit; `git archive` it to `$SP/base` and build it. Baselines: `SillHost --synthetic` idle 35 s; with `sillclient.py PORT 5 desktop`; both with `--direct-wireless`, and with `--remote`; the bare app's and the bundle's `-SillRenderPreviews`; the counts of the policy, ledger, fence, remote-rules, AddressList/PairingWindow, OriginPolicy and ClientLink checks. **Probes:** P1, a TLS NWListener registered as `_silltest._tcp` with TXT `r` and `p`: `dns-sd -L` reads both; setting its `service` again with `p` changed shows within 2 s with no "(2)"; the same with `includePeerToPeer` (under 20 s) leaves nothing on awdl0's index. P2, this plan's `cable-probe.swift` on the build machine: with a device on the cable the chain matches the Decision's table; without one no interface is a cable. P3, TLS against plain TCP on loopback through NWConnection: 200 MB each way, and 60 s of 14-byte records every 30 ms; CPU per MB and per record at both ends. P4, `ba91136`'s `sillclient.py` against a TLS listener: what bytes it gets and when it sees EOF | Files exist; every probe answers, or the plan changes first |
| H1 | Builds: `swift build -c release`; iOS Debug and Release for the simulator, Debug for the iPad (build only) | Only the known warnings |
| H2 | **The CLI byte for byte:** H0's runs on the new build, masked and sorted | Identical. `--pairing` adds exactly its two lines (§5, §4.11), plus one per ask; `--print-cable` exits 0 |
| H3 | **Pure checks**, each with mutants caught: `DoorPolicy` (every row of §4.2: both doors, each origin, each ALPN, Require pairing on and off, paired or not, a window or not, the ask rule's five steps in order); `CableLink` (fixtures: this Mac's en14 and anri0 → a cable; anpi0 and en4 (device mode), en1 (Thunderbolt), en0 (Wi‑Fi), bridge0 → not; a Realtek USB Ethernet adapter (0x0BDA) → not; Apple's USB Ethernet Adapter (0x05AC, "Apple USB Ethernet Adapter") → not; an iPhone (0x05AC, "iPhone") → a cable; another Mac in device mode → not; no product name, no NCM interface → not; a routed source on a cable interface → not); `AskLimits` (one window; 10 minutes of quiet by key and by address; 3 in 10 minutes; expiry counts as unused; the test override); `HomeDoorTXT` (build, parse, an unknown value → required); the device's `rowWord`, `homeDial` and `onCable` (every row of §7.3 and §7.4, DEBUG and Release, `homeTLS`, revoked; fe80 scoped to en2 or anpi0, IPv4 link-local with a wired local address, Wi‑Fi, AWDL, loopback); `SavedMacs` (the new fields; records without them decode) | All pass |
| H4 | **The home door up:** `SILL_TEST_SERVICE_TYPE=_silltest._tcp SillHost --synthetic --pairing` | Its two lines; `dns-sd -t 3 -L "Sill test <pid>" _silltest._tcp local` shows `r` and `p=1`; one listener (`lsof`), none on 7455; without `--pairing`, H2 holds |
| H5 | **Refusals at the home door:** `ba91136`'s `sillclient.py` (plain); `--tls` with an unpaired key on `sill/1`; `--tls` with another ALPN; `SILL_TEST_ORIGIN=vpn`. And `SillHost --print-cable` (read-only) with the iPad plugged in, if it is | Plain: closed within 100 ms with no Sill byte, counted "from an older Sill"; unpaired: ready, then a read error (-9825), no Sill byte; another ALPN: the handshake fails; vpn: closed before TLS; one summary line. `--print-cable` names en14 and anri0 as the iPad's cable |
| H6 | **Pairing at home:** `--pair-ask --then-code=…` with the printed code; again with `--pair-url`; then `sill/1` with the same identity | `shown`, and the CLI's ask line; ok with a valid proof_M, over the home door; the session's catalog 2, 16, 18, 4…, 5, 14 and frames. On the bare app with Remote Access off, a device-opened window starts nothing on 7455 (`lsof`) while `-SillPairAfter`'s does |
| H7 | **The cable, by its stand-in:** `SILL_TEST_CABLE_INTERFACE=en0`, the client on the Mac's own `fe80::…%en0` | `--pair-ask` → ok, `method "cable"`, the line, the notice hook; a second key over the same plug-in → `shown`; the first key again → ok; `SILL_TEST_LOCKED=1` → `locked`; a 127.0.0.1 client with the variable set → `shown` (not link-local) |
| H8 | **The ask's limits,** on the bare app with `-SillCancelPairingAfter` and `SILL_TEST_ASK_QUIET=5` | After a device-opened window is cancelled, that key and that address get `openOnMac` for 5 s, another key from another address a window; three windows opened and closed, then the fourth ask `openOnMac`; `pairingRequest` in the status; one line per ask |
| H9 | **TLS cost:** 60 s at 60 fps synthetic with `sillclient --stats`: the CLI's plain door; the TLS door with §8's tick rule; the TLS door without it | TLS with the rule within +0.5 percentage points of plain (host CPU, `ps`, release) and median frame age within 1 ms; the other run and P3's figures recorded in the Results |
| H10 | **Require pairing,** on the bare app with `SILL_TEST_SERVICE_TYPE`: `-SillSetAfter '3 requirePairing=0; 10 requirePairing=1'` | `p` 1 → 0 → 1 in `dns-sd -L`, no "(2)"; an unpaired `--tls` session admitted between 3 and 10 s, then goodbye `pairingRequired` and EOF within 1 s of 10 s; a paired session streams throughout; one Settings line each; the same port |
| H11 | **Remove:** a paired home session and a paired remote one (Remote Access on), then `-SillUnpairAfter` | Goodbye `removed` on both doors within 1 s; "Removed …; closed 2 connections."; the next `sill/1` refused in the handshake |
| H12 | **Direct Wireless over TLS:** `SILL_TEST_PEER_TO_PEER_INTERFACE=en0`, a paired TLS client and a pending ask from the Mac's `fe80::…%en0` | Direct Wireless off: the client disconnected with the existing line and the pending ask cancelled; `p` still in the TXT record after the replacement; the same port |
| H13 | **Fail closed:** the bare app with an unreadable `SILL_TEST_REMOTE_DIR` | No listener; `homeDoor` unavailable in the status; its log line |
| H14 | **The remote door, again:** the remote plan's H6–H13, H15 and H17 against this build (Remote Access on) | As before; `ask` there answered `closed` with no try counted |
| H15 | **Previews,** before and after | Only the Devices pane's samples, the Remote Access pane's line, the three pairing window samples and menu.txt's three items differ; look at each |
| H16 | **Hard rules** (grep and diff) | `requirePairing` in none of StreamSettings, HostSettingsChange, DeviceSettings; no `print` of a code or secret in Sources/SillHost; no `assumeIsolated` or `updateConfiguration` there; StreamServer's plain `accept` untouched |
| H17 | **Regression:** the policy, ledger, fence, remote-rules and ClientLink checks; the Direct Wireless swap fallbacks (`SILL_TEST_SWAP_FAIL`) on a TLS host | As before |

**Simulator (S):** an iPad simulator of its own (the iPad Pro 13" one is shared with other work),
launch arguments, `simctl io screenshot`, the iOS Simulator control tool's taps.

| # | Check |
|---|---|
| S1 | **The photo matrix:** every new connect case at 1000x710, 710x1000, 500x710, 710x500, 402x874, 874x402 and 375x667; the home card at the four Duo sizes and at `content_size accessibility-extra-large` (reset afterwards); the two settings cases at the Duo sizes. Nothing crosses y = 500 at 710x1000; "Not paired" and "Update Sill" are never truncated; the title never moves sideways; the card goes side by side under 520 pt. Send Noah the sheet |
| S2 | **A real row:** `SILL_TEST_SERVICE_TYPE=_silltest._tcp SillHost --synthetic --pairing` and the normal app with `-SillServiceType _silltest._tcp`: the row "Sill test ‹pid›" reads "Not paired"; a tap, and the CLI prints the ask's line; the printed code typed into the card → paired, streaming; relaunched, the row reads its method word and connects pinned, with no ask |
| S3 | **The cable:** the host with `SILL_TEST_CABLE_INTERFACE=en0 … --pairing`, the app with `-SillConnect fe80::…%en0:P -SillHomeDoor paired -SillCableTest 1`: paired with no card, "Paired with … over the cable.", streaming. Without `-SillCableTest`, the ok is refused ("Pairing didn’t finish…") and nothing is saved |
| S4 | **Moves over TLS:** `-SillMoveTest 1` and `to:` this Mac's `fe80::…%en0` with `-SillHomeDoor paired` (and PR #12's `-SillPathTest` cases once merged): each move's connection pinned, the fence as before; a key removed mid-session ends its move as a failed one |
| S5 | **The ends:** the bare app's `-SillUnpairAfter` while connected → "Mac mini removed this iPad. Tap it to pair again." and "Not paired"; `requirePairing` 0 → 1 with an unpaired session → "Mac mini now asks devices to pair…" |
| S6 | **Older hosts:** `ba91136`'s `SillHost --synthetic` from `$SP/base` with `-SillConnect` streams as today (DEBUG, plain); with `SILL_TEST_SERVICE_TYPE`, a Release build with `-SillServiceType` shows "Update Sill" and dials nothing |
| S7 | **Accessibility:** the labels, hints, headings, focus moves and announcements of §7.3 and §7.7, from the accessibility tree |

**Noah's devices (P):** the iPad mini, and the iPhone as the second device and the hotspot.

| # | Check |
|---|---|
| P1 | **The upgrade.** Install the iPad build first (Debug, the usual route), then Sill.app. The iPad, paired by QR on 2026-09-25, connects at home with no pairing step. The log: "Home door: TLS, pairing required (1 paired)." and "Client connected: …"; Settings › Devices lists the iPad, "last connected just now over Wi‑Fi" |
| P2 | **QR over Wi‑Fi.** Remove the iPad on the Mac; its row reads "Not paired". Typing in another app on the Mac, tap the row: the window comes up in front and the typing goes on. Scan: streaming. Time it (under 20 s) |
| P3 | **The code.** Remove again; tap; Enter Code Instead; the 12 digits: streaming |
| P4 | **The cable.** Remove; plug in; the row reads "Wired"; tap: streaming at once, no code; the Mac's notice; Devices says "over the USB cable". Pull the cable while streaming: the session goes on over Wi‑Fi (PR #12), still paired; plug it back: back on the cable |
| P5 | **Locked.** Remove; the cable in, lock the Mac (⌃⌘Q); tap: "Unlock Mac mini, then tap it again."; the menu's item; unlock, tap: paired |
| P6 | **Direct at the café.** Direct Wireless on, the iPad on the iPhone's hotspot, the Mac at home in range; Remove first. The Direct row reads "Not paired"; tap: the window; scan; the host logs `%awdl0`. Direct Wireless off: disconnected as before |
| P7 | **An older build.** The iPhone on main's build (or the iPad put back on it): the menu's "An iPhone or iPad Needs Sill Updated"; the device flickers and retries (the known limit); the new build fixes it |
| P8 | **Remove while streaming at home:** "Mac mini removed this iPad. Tap it to pair again."; the row "Not paired" (on the cable, "Wired") |
| P9 | **The moves:** plug and pull while streaming, and the move from AWDL to the network: every hop over TLS, a "Client connected" per hop, no connect screen |
| P10 | **A stranger's taps:** the unpaired iPhone taps the Mac; Cancel on the Mac; it taps again: "Mac mini didn’t show a code…" for 10 minutes; the menu's "iPhone Wants to Pair" opens the window on a click |
| P11 | **The cost:** five minutes on a still window over Wi‑Fi, the host's `rtt m/M` maxima as before (ticks still keep the radio awake); the same on the cable, now without ticks; Extreme at 120 fps over the cable, fps and frame age as before; Sill.app's CPU in Activity Monitor against the previous build |
| P12 | **Remote after a home pairing:** pair over the cable only, then away through Tailscale (Remote Access on): the remote session with no further step |
| P13 | **Require pairing off:** the pane's warning; the unpaired iPhone connects without a code; on again: it is disconnected with "Mac mini now asks devices to pair." |
| P14 | **VoiceOver** on the rows ("Mac mini, not paired"), the home card and the Mac's window |

---

### 12. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

0. **Preflight** (no commit): fetch; branch from origin/main once PR #12 (and #11) have merged,
   else from `ba91136` with a rebase before step 4; H0 and its probes.
1. **"Protocol: home pairing's values, the TXT key and the door policy"** — Remote.swift's `ask`,
   reasons, `PairResult.method` and `pairingRequired`; `HomeDoorTXT`; the RemoteTLS overload; the
   pure `DoorPolicy`, `CableLink` and `AskLimits` (host) and `rowWord`, `homeDial`, `onCable`
   (device); the SavedMacs fields. Gates: H1, H3, H17. About 500 lines, and 700 of checks.
2. **"Host: the home door speaks TLS, pairs at home and over the cable"** — `Door` out of
   RemoteServer; StreamServer's three modes; InterfaceSnapshot's IOKit read; SessionLock;
   RemoteAccess's ask, cable keys, limits, Require pairing, Remove on both doors, home "last
   connected"; the coordinator, HostConfig, HostStatus; the tick rule; the CLI's `--pairing` and
   `--print-cable`; `sillclient.py`'s flags. Gates, with the CLI and `sillclient.py`: H1, H2,
   H4, H5, H6 (the CLI's part), H7, H9, H12, H14, H16, H17. About 1,100 lines; the largest step.
3. **"Sill.app: Settings › Devices, device-opened windows, the cable notice and the menu"** — Gates,
   with the bare app: H1, H6 (the bare app's part), H8, H10, H11, H13, H15. About 550 lines, much of
   it moved from RemoteAccessPane.
4. **"iOS: TLS on every home connection, and pairing at home"** (the model) — the builder on every
   dial site, PR #12's included; `p` on rows; the session gate at the first list; revoked;
   `homeTLS`; the ask, the cable's ok, the two proofs through the row; the goodbyes. Gates: H1
   (iOS), H3 (device), S2–S6. About 700 lines.
5. **"iOS: rows, the home card and the panel"** (the UI) — Gates: S1, S7, S2 again. About 400 lines.
6. **"docs: Pairing at home"** — this plan's Results; CLAUDE.md (the Current step, Layout, Build and
   run: `--pairing`, `--print-cable`, the TEST ONLY variables `SILL_TEST_CABLE_INTERFACE`,
   `SILL_TEST_LOCKED`, `SILL_TEST_ASK_QUIET`, the harness lines); the README's Pairing section (at
   home, over the cable, Require pairing, the CLI's plain door, resetting).
7. **Review and hand-over.** Three lenses: security and protocol (the verify blocks, the cable rule,
   no proof-less ok off the cable, no downgrade, no secret in a log); listeners and concurrency
   (one `Door` behind two listeners, the swap with TLS, pending cancellation, the TXT update); the
   device UI and accessibility at every size. A "Review fixes" commit if needed; adversarial reruns
   of H5–H12 and S2–S5; then P1–P14 to Noah. **Stop there.**

**What lands first, so Noah's devices keep working through the branch:**
- Nothing reaches his devices until he installs a build. Sill.app changes only at step 3, the iOS
  app at steps 4–5, and the CLI's default door never changes, so every older gate and tool keeps
  working throughout.
- PR #12 first: step 4 must put the builder on its dial sites (`startMove(to:kind:fallback:)`,
  `reconnectNow`), which do not exist at `ba91136`. PR #11 touches StreamCoordinator, HostStatus and
  StatusText: a rebase. The `remote-pacing` fix touches only the remote branch of `broadcast`:
  either order.
- At the hand-over, **the iPad build first** (Debug): it still dials today's Sill.app plainly. Then
  Sill.app. His iPad is already paired, so P1 needs no step. If Sill.app goes first, the iPad on
  main's build cannot connect until it is updated, and the Mac's menu says so.

### 13. Hard rules (for every step)

- **Never `MainActor.assumeIsolated`** in core code. The verify blocks and admission read the
  lock-protected TrustSnapshot and never wait on the main actor; SessionLock runs on the main actor,
  where the ask is judged anyway.
- **Never reconfigure a running SCStream.**
- **The CLI's stdout stays byte for byte** without `--pairing` (masked and sorted), idle and
  streaming, with and without `--direct-wireless` and `--remote`.
- **Kinds 16 and 17 stay compatible both ways;** Require pairing is never device-writable; kinds 19,
  20 and 22 grow only by string values and one optional field.
- **A proof-less ok** (kind 20 with `method: "cable"`) is sent only for a connection the Mac judged
  to be on its cable, and accepted only for the device's own `ask` over its own cable.
- **No downgrade:** a Release device never dials plain; no device dials a `homeTLS` Mac plain.
- **Apple frameworks only:** Network, Security, CryptoKit, CommonCrypto, IOKit, CoreGraphics,
  SystemConfiguration. No PAKE package.
- **Secrets:** the code and the QR secret are never in a line of Sill.app's log, the status, kind 16
  or 18, or a TXT record. The trust list lives in the keychain (the app), memory (the CLI) or a 0700
  test directory, never in UserDefaults.
- **The modal-loop rule** in the app; errors inline; a device-opened window never activates Sill.
- **Tests never touch** Noah's Sill.app, `/Applications`, `me.saffer.sill.mac`, his login keychain or
  his iPad; no XCUITest or `recordVideo` while his Sill.app runs; TEST ONLY hooks are honoured only
  by hosts that do not advertise.
- **New iOS files** need their four pbxproj entries by hand. Swift 5 language mode.

### 14. What M5 inherits

- One trust list for every route, each record saying how it was trusted ("qr", "code", "cable", then
  "icloud"), with Remove.
- TLS and pins on the home door; `ask` as the one "pair me" request. M5 answers it `pairNow` for a key
  in the user's iCloud set, as the cable does today, and the Mac "just appears" again for
  same-account devices, which is BRIEF.md's M5 promise.
- The rotating tag and `p`.
- The remote plan's M5 note ("it probably puts the home network behind the same pairing") is done
  here. What remains for M5 is exchanging the keys through CloudKit.

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **Show the code by itself when a device asks (option A), with the limits?** Default: **yes.** The
   alternatives: a prompt first and the code on a click (A′), or only after Pair iPhone or iPad… on
   the Mac (B).
2. **The typed code stays 12 digits,** as for remote access. Default: **yes.** Six would need a PAKE
   that Apple's frameworks do not have.
3. **The cable pairs only while the Mac is unlocked** (and your session is on the console). Default:
   **yes.**
4. **One key per plug-in over the cable** (a second, different key gets the code window). Default:
   **yes.**
5. **A notice for every pairing over the cable** (10 s, with Remove). Default: **yes.**
6. **Require pairing off means TLS for anyone at home,** not today's plain door. Default: **yes.**
7. **The CLI's default door stays plain and open;** `--pairing` opts in. Default: **yes** (the
   parity baseline and every gate stay as they are).
8. **The 1.0 floor:** a Release device never dials a plain door; DEBUG builds do, until they have
   seen that Mac over TLS. Default: **yes.**
9. **A Devices tab** (General, Devices, Streaming, Virtual Display, Permissions, Remote Access), with
   the paired list moved out of Remote Access. Default: **yes.**
10. **Ticks:** every TLS client skips a tick right after a send, and a device on the USB cable gets
    none. Default: **yes**, checked by H9 and P11.
11. **A window a device opened never starts the remote door.** Default: **yes.**
12. **The keychain unusable → the home door closed** (fail closed, with the menu item). Default:
    **yes.** The alternative is a throwaway identity for the run, with pairings lost at quit.
13. **Pair over the cable without a tap,** as soon as the row appears. Default: **no.**
14. **No in-band message for older builds;** the Mac's menu says it. Default: **yes.**
15. **The words:** "Not paired" on an unpaired row; "Wired" on an unpaired Mac over the cable, since
    it pairs by itself. Default: **yes.**
