# Pairing at home: Wi‑Fi, Direct and the cable — the plan

## Status and hand-off (2026-09-27 02:38)

Stopped by Noah at 99 % of the week's usage, at the end of build step 5 of 5 (§12), before the
review phase. Branch `home-pairing` (worktree `/Users/noah/Downloads/winstream-pairing`, main merged
in at 1f3072a) holds: the plan and its review (0f50d14, c3fbb8c), H0's probes (8ce57ab), step 1 the
protocol (21b5789), step 2 the host door (c0b22d7), step 3 Sill.app (47bbbb8), step 4 iOS (41caa8f),
and the commit after this one: step 5 as the interrupted agent left it, mid-verification (it had
rerun the pure checks and the home and device mutants and was building iOS Release and a device
build and sheeting the Settings cases at phone sizes; results in the session scratchpad,
home-pairing/5/, if it survives a reboot). Unreviewed.

2026-09-27 01:15: step 5 verified as 1b8de5f left it, with nothing to fix (Results, Step 5, "Verified
again"), by two sessions, the first interrupted at 00:22 with this written but not committed: the
builds, every pure check with its mutants, S1's photos and the Settings cases at the Duo and phone
sizes, S7, and S2 with S5's end live, 18 of 18, every test listener on loopback (the first session's
run; the second's found Noah's iPad streaming from Sill.app throughout).

2026-09-27 02:38: main merged in at cf05a78 (PRs #16–#28; d11aa60, one merge commit, not a rebase),
with the device gate in `Door` for both TLS doors and `DoorPolicy.afterGate`, `SillProtocol` 1
settled as this door's `sill/1`, and this branch's pure checks moved into `Tests/checks` and CI
(Results, "The merge with main"). Every check passes and every mutant of the checks the merge
touched is caught; the host gates of both plans that the merge could break pass live, on the
software encoder with every listener on loopback. Not pushed.

Next agent, in order: (1) verify step 5: done, above; (2) merge main and rerun every check: done,
above; (3) the security review the workflow planned (three lenses: the wire and TLS, pairing's
rules and limits, the device UI), fixes; (4) the docs of §12's step 6 that are still to write
(CLAUDE.md's Layout and Build and run for pairing at home's files, flags and TEST ONLY variables,
and the README's Pairing section; the merge wrote only CLAUDE.md's Current step entry, its
Compatibility floor and its Tests/checks and sillclient lines); (5) the PR with Noah's device
tests (§11) and the install order: the iPad build first, then Sill.app. Quote Noah's authorization
in the prompt: "Yes please lets add a pairing process for Wi-Fi/Direct connect, something easy to
do but still secure, similar to how Tailscale is being paired. Wired should still pair
automatically." (2026-09-25) and this resumption.


2026-09-25. It stands alone: the implementer needs no other design document, though it builds on
`docs/remote-access-plan.md` (PR #13) and names its sections as "the remote plan §…". Written from
a read-only survey of origin/main `ba91136` ("Merge pull request #13", remote access) in the
worktree `/Users/noah/Downloads/winstream-pairing` (branch `home-pairing`), and from read-only
probes of this Mac's interfaces while Noah's iPad mini was on the USB cable. This plan is the only
file written; no host was started. Line numbers are at `ba91136` unless they say otherwise. PR #11
(`encoder-recovery`, host) merged into origin/main after the survey (`b50e224`), and PR #12
(`follow-best-path`, iOS only) at 18:50 the same day (`cea195c`, origin/main now; its host sources
are `b50e224`'s); the `update-notice` branch is not merged: §12 says how they meet this work. An
adversarial review the same evening (the read-only probes re-run twice with the iPad on the cable,
Sill.log read, main's merged iOS code read, no host started) changed the cable rule, the ask, the
device's cable check, the backoff for older builds, what an ask from this Mac may do, the window a
device opened once the Mac's user opens one, where Require pairing is kept, which hosts honour test
hooks, and several gates; its findings are folded in where they apply.

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
the Mac is unlocked and both ends agree that the connection is the cable (never an app on the Mac
itself, never a network behind a USB adapter), the Mac pairs the device on the spot, at most one
key per device, and shows a notice. Everywhere else it
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
- A window opens only for a request from another device on this Mac's own networks or over
  peer-to-peer Wi‑Fi (the home door's origins, less this Mac itself: an ask over loopback or from
  one of its own addresses never opens one, §4.2 step 4). Never through a VPN or from the
  internet, never on the remote door.
- One window at a time. A request while one is open is told the code is showing.
- Never while the Mac is locked, or while another user's session is on the console: the device is
  told to unlock the Mac.
- When the Mac's user closes a window a device opened, or it stops after five wrong codes, that
  device (its key, and its address) opens no other for 10 minutes. At most 3 device-opened windows
  in any 10 minutes. Past either limit the device is told to use the Mac's menu, and the menu says
  "iPad Wants to Pair". (As first planned, a window that simply ran out quieted its device too; the
  security review, 2026-09-27, found the device's card promising "Tap Mac mini for a new one" then,
  while the Mac refused that tap for 10 minutes. A window that runs out, or that its device withdraws
  with its own Cancel, kind 19 "cancel", or by pairing over the cable, quiets nobody now; the 3 in
  10 minutes still bound how often one can come up.)
- The window comes to the front without taking the keyboard (`orderFrontRegardless`, no app
  activation), so a request can never swallow a password being typed in another app.
- Its code is the one pairing code there is: 12 digits, 5 tries, 5 minutes, single use. A window a
  device opened never starts the remote door, and the remote door takes no proof while only such a
  window is open: its code works at the home door alone, until the Mac's user opens a window over
  it, which makes it the remote door's too (§4.6).

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
`networksetup -listallhardwareports`, `system_profiler SPUSBHostDataType` (`SPUSBDataType`, the
old name, prints nothing on macOS 27), `ioreg`, and a small swiftc probe of SystemConfiguration,
IOKit, getifaddrs, NWPathMonitor and CGSession
(`scratchpad/home-pairing-plan/probe/cable-probe.swift`). The review re-ran every one of them the
same evening, the iPad on the cable again: the same chains after a new plug-in (en14 then had
169.254.177.140 and the device `sessionID` 4854277126715; the iPad linked at 480 Mb/s), and two
facts the rule below uses: the iPad's `IOUSBHostDevice` carries `USB Serial Number` (its UDID,
the same at every plug-in), and `net.inet.ip.check_interface` and `net.inet6.ip6.check_interface`
are 1 on this Mac. Run once more at 18:55 (the critique of this plan): the same, plus the iPad's
interfaces in order (PTP@0 6/1, Apple USB Multiplexor@1 255/254, NCM Control@2 2/13 → en14, NCM
Control@4 2/13 → anri0), its neighbours `fe80::18fe:abff:febb:459f%anri0` and
`fe80::18c2:af60:ec0d:47ea%en14`, and one interface's ancestry read in 0.17 ms (median of 50; at
most 0.73 ms).

| Witness | What it says about the cable's two Mac-side interfaces, `en14` and `anri0` | Usable? |
|---|---|---|
| `networksetup -listallhardwareports`, `SCNetworkInterfaceCopyAll` | Neither is listed: only en4–en6 "Ethernet Adapter", Thunderbolt Bridge, Wi‑Fi and Thunderbolt 1–3 | No |
| NWInterface type | wired Ethernet (as the iPad's anpi0 and en2 are), exactly what any Ethernet adapter says | No |
| getifaddrs | not point-to-point (`UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST`); anri0 has only `fe80::…`, en14 `fe80::…` and `169.254.222.62` | Only as a second condition |
| The client's address | `fe80::…%anri0` or `fe80::…%en14`: in Sill.log (it reaches back to 2026-09-23 17:07) all 41 of the iPad's sessions over the cable by 18:57 on 09-25 came so (25 on anri0, 16 on en14, each from the one address the iPad has there at every plug-in), none over IPv4. The only IPv4 link-local clients in it were the Simulator on this Mac, twice on 2026-09-24 from `169.254.178.234`, this Mac's own en14 address then: a process on the Mac that dials the Mac's own address on the cable interface arrives scoped to it, with that address as its source | The scope names the arrival interface; the source must not be this Mac's own |
| IOKit, the IOService plane | en14: `IOEthernetInterface ← AppleUSBNCM11Data ← AppleUSBNCM11Control ← IOUSBHostInterface "NCM Control@2" ← IOUSBHostDevice "iPad"` (idVendor 0x05AC, idProduct 0x12AB, `USB Product Name` and `kUSBProductString` "iPad", `USB Serial Number` (its UDID, the same at every plug-in), a `sessionID` per plug-in). anri0: `AppleUSBHostNCMRestrictedEthernetInterface ← …"NCM Control@4" ←` the same iPad. The iPad's configuration also has "Apple USB Multiplexor" (class 255, subclass 254) and PTP. This Mac's own anpi0–2 and en4–en6 hang off `AppleT8112USBXDCI` (the Mac as a USB *device*), en1–en3 off Thunderbolt, en0 off PCIe Wi‑Fi: none has a USB host device above it | **Yes** |
| CGSession | unlocked: `kCGSSessionOnConsoleKey` = 1 and no `CGSSessionScreenIsLocked` key | For the unlock rule |

**The rule** (`CableLink`, pure, over what IOKit read; §4.3). A connection is on the cable when all
three hold, and otherwise it is not:
1. its source is an IPv6 link-local address (fe80::/10) scoped to an interface that has above it,
   in the IOService plane, a CDC NCM interface (`IOUSBHostInterface`, class 2, subclass 13) of an
   `IOUSBHostDevice` whose idVendor is 0x05AC and whose product name (`USB Product Name`, else
   `kUSBProductString`) is "iPhone" or "iPad". The scope is the interface the kernel received the
   connection on, and link-local sources are never routed, so it is the device at the other end of
   the cable, never something behind it (the other clients of an iPhone's Personal Hotspot over
   USB). An IPv4 source never counts, 169.254/16 included: its arrival would only be inferred from
   the local address (OriginPolicy's fallback), which holds against a sender on another link only
   while the kernel's strong end-system check is on (`net.inet.ip.check_interface`: 1 here, but a
   sysctl), and the iPad never used IPv4 over the cable (the table);
2. that source is none of this Mac's own addresses (InterfaceSnapshot's owner table). A process on
   this Mac that dials the Mac's own address on the cable interface arrives scoped to that
   interface with that address as its source: the Simulator did so on 2026-09-24 (the table), and
   H7's stand-in works the same way. Without this rule any app on the Mac could pair itself while an
   iPhone or iPad is plugged in, then use Sill's Screen Recording and Accessibility over loopback:
   the confused deputy this plan closes;
3. anything unread or unexpected (no registry entry, a missing property, this Mac's own
   device-mode ports, Thunderbolt, an Ethernet adapter including Apple's own USB one, another Mac)
   means not the cable.

**Pairing by itself over the cable** also needs, at that moment:
- the Mac unlocked with the user's session on the console;
- the device's own ask saying it is on the cable (`PairRequest.cable`, §3.1). The device checks
  its end (§7.5); one that cannot tell, on a USB Ethernet adapter say, gets the code window rather
  than a pairing it would then refuse;
- no other key of that iPhone or iPad on the trust list. The Mac knows the device by a hash of its
  USB serial number (`PairedDevice.cableDevice`), saved with a key paired over the cable and
  learned for any paired key the first time one of its sessions runs over the cable. A different
  key from a device that has one gets the code window; the same key may pair again; Remove frees
  the device. Not per plug-in, as first drafted: Sill asks only while unpaired, so once it had
  paired, a per-plug-in place was free again at every later plug-in for whichever other app on
  the device asked first.

Each such pairing is logged, listed as "over the USB cable" and shown in a notice with Remove.

### The security argument, plainly

- **Wi‑Fi and Direct.** A device gets in only with a code or QR code the Mac showed on its own
  screen, bound to both keys by the remote path's proofs. A stranger on the network, within radio
  range (Direct) or a local process (loopback, or this Mac's own addresses) gets nothing, and
  everything is encrypted. An ask from this Mac itself never puts a code on the screen by itself
  and never lights the menu (§4.2, step 4), so an app on the Mac cannot simply ask and read its
  own code; one that can record the screen and can also ask from another address still can (What
  stays open). Nor can an app turn pairing off behind Sill's back: Require pairing is kept with the
  trust list, not in UserDefaults, and a Sill.app started with test hooks ignores them (§4.3, §6.5).
  This closes the three exposures the remote plan left open until M5: the café LAN,
  radio range, and the loopback confused deputy that could borrow Sill's Screen Recording and
  Accessibility grants, the last down to an app that already records the screen.
- **The cable.** Whoever plugs an iPhone or iPad into an unlocked Mac already has the Mac in hand.
  A locked Mac pairs nothing, an app on the Mac is never the cable (rule 2), and a look-alike Mac
  on the network cannot answer a device's ask with the proof-less ok the device takes (§7.5).
- **What stays open:**
  - another app on the plugged-in device, one with Local Network access that speaks Sill's
    protocol, can pair its own key over the cable while that device has no key on the list yet (a
    device paired only by QR code has none until one of its Sill sessions runs over the cable): at
    its first plug-in, whether or not anyone taps Sill. It names itself as Sill does ("iPad
    (iPad14,1)": iOS gives apps no other name), so only the notice and a second entry in the list
    show it, and Sill's own tap then gets the code window. App Attest would close it (§1, not in
    this step);
  - a code shown at a stranger's request could end up in a screen share (`sharingType = .none` on
    the window is best effort on macOS 15 and later); it would still work only at the home door,
    from this Mac's own network or nearby, within the window's 5 minutes, and only if the real
    device has not used it first;
  - an app on this Mac that can record the screen can read the code of any window while it is up:
    one the Mac's user opened, or one a device opened, including one it made come up itself by
    asking from an address that is not this Mac's own: a virtual machine it runs (the
    Virtualization framework's NAT puts one behind vmnet's `bridge100`, a network OriginPolicy
    counts as this Mac's own) or another device on the network. Step 4 stops only the direct ask.
    Showing a device-opened window's code only after a click on the Mac (option A′, open question
    1) would take that trigger away;
  - with Require pairing off, the home door is as open as it is today, but encrypted: to devices on
    the network or nearby, and to any app on this Mac (loopback, or this Mac's own addresses);
  - a device that has never paired can be lured to a look-alike row that advertises `p=0`: it pins
    and saves nothing, but a session there gets what it types. Over the cable an app on this Mac can
    go further: listening on the Mac's end of the cable (which the device cannot tell from Sill) and
    answering an ask with a proof-less ok, it is saved as a Mac and gets what that device types,
    never the Mac itself. A saved Mac's rows are always dialed pinned, so a paired device never is;
  - anyone who can reach the home door (this network, or radio range with Direct Wireless on) can
    connect and read the Mac's certificate: TLS 1.3 encrypts it on the wire, but a client that
    connects receives it, and its key is stable, so it names this Mac across networks, as the
    remote door's already does. The rotating tag still keeps listeners who do not connect from
    telling;
  - a stranger on the network can hold up pairing and the door without getting in: three asks in
    10 minutes use up the device-opened windows (the real device is then sent to the Mac's menu,
    whose "‹name› Wants to Pair" it can keep lit), five wrong codes stop any open window, and eight
    half-open connections (10 s each, two per address, and IPv6 gives it any number of addresses)
    fill the door's pending places, as they can at the remote door;
  - Remote Access's own switches (remote access, internet access, the port) and Direct Wireless
    stay in UserDefaults, where any process of this user can flip them: that widens who reaches a
    door, never lets an unpaired key in. Require pairing is the one switch that would, so it is
    kept with the trust list (§6.5);
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
3. **The cable pairs by itself:** the IOKit rule over an IPv6 link-local source that is none of
   this Mac's own, the device's own claim, the Mac unlocked, one key per iPhone or iPad, a notice.
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
                 │     ask  → on the cable (both ends agree), unlocked: paired now (kind 20 ok "cable") │
                 │          → else: the pairing window opens (kind 20 "shown"), or "openOnMac" (always  │
                 │            for an ask from this Mac itself), "locked"                                │
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
  `closed` without counting a try (it gets that far only while a window the Mac's user opened is
  up; otherwise its handshake refuses any pairing connection, as today); PairingWindow never sees
  it. An older host never receives one:
  the device sends it only to a Mac whose TXT record carries `p`.
- **Kind 19 `PairRequest.method`** also gains `"cancel"` (the security review, 2026-09-27): the
  device's Cancel after the Mac answered its ask `shown`, "I no longer need that code". The window
  that ask opened closes without keeping the device quiet (§4.6); the answer is `closed` whatever
  happened, with no try counted, and the remote door answers it `closed` too. Its `proof` is `""`.
- **Kind 19 `PairRequest.cable`**, a new optional field: `true` only in an `ask` sent over a
  connection the device itself judged to be the USB cable to the Mac (`DiscoveryPolicy.onCable`,
  §7.5), absent otherwise. The Mac pairs by itself only when its own rule agrees as well (§4.3), so
  the claim can only narrow what the Mac does. Its use: a device that cannot tell (a USB Ethernet
  adapter on the LAN, which iPadOS also types as wired) gets the code window, not a pairing it
  would refuse and the Mac would keep.
- **Kind 20 `PairResult`:**
  - `ok: true`, no `proof`, and a new optional field `method: "cable"`: paired over the cable.
    The device accepts an ok without a proof only as the answer to its own `ask` that said
    `cable: true` (§7.5).
  - New reasons: `"shown"` (the window shows a code now: scan it or type it), `"openOnMac"` (the
    Mac did not show one by itself: choose Pair iPhone or iPad… on the Mac), `"locked"` (the Mac is
    locked).
  - A new optional field `message` (the security review, 2026-09-27): the Mac's own words for a
    reason the device does not know, which it shows as they are (SafeText, one line, at most 300
    characters), as a goodbye's. This build sends none (every kind 20 here is byte for byte as
    before); a later host adds a reason only with one. The reasons a device words itself are
    `PairResult.knownReasons`: `code`, `closed`, `expired`, `stopped`, `busy`, `shown`,
    `openOnMac`, `locked`.
- **Kind 22 `Goodbye.reason`** gains `"pairingRequired"`: Require pairing was turned on while this
  unpaired device was connected.
- **Kind 21** (`pairingWanted`) is unchanged; only an unpaired session (Require pairing off) still
  has a reason to send it.
- **Constants:** none new. The 4 KiB pairing message and the 1 MiB client message caps apply to
  the home door as they do to the remote one.

```swift
// Remote.swift
public struct PairRequest: Codable, Sendable {
    …                                   // as today
    /// ask only: true when the device judged this connection to be the USB cable to the Mac.
    public var cable: Bool?
    public static let ask = "ask"
}
public struct PairResult: Codable, Sendable {
    …                                   // as today
    /// ok without a proof: how the Mac paired this device by itself. "cable"; nil otherwise.
    public var method: String?
    public static let shown = "shown", openOnMac = "openOnMac", locked = "locked"
}
extension Goodbye { public static let pairingRequired = "pairingRequired" }
```

**Examples as they cross the wire** (keys in no fixed order: JSONEncoder's follows the process's hash
seed, step 1's Results):

```json
// kind 19, a tap on an unpaired row; on a cable the device checked, with "cable":true
{"v":1,"method":"ask","proof":"","name":"iPad","model":"iPad14,1"}
{"v":1,"method":"ask","proof":"","name":"iPad","model":"iPad14,1","cable":true}
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
  a Direct Wireless replacement, left to its settle step, which reads the current value.
  NWListener updates the record in place (H0's P1, Results): with the same name and type and a new
  TXT record, no browser sees a removal or a "(2)", the listener's
  `serviceRegistrationUpdateHandler` reports nothing (so the status keeps its name), and the new
  record is on lo0, en0, the cable's en14 and anri0 and, with `includePeerToPeer`, awdl0 0.02 to
  1.0 s later, whether `r` is fresh or the same; cancelling the listener removed every copy, awdl0's
  included, within 1.1 s.

```swift
public enum HomeDoorTXT {
    public static let key = "p"
    public enum Door: Equatable, Sendable { case plain, pairingRequired, open }
    public static func value(requirePairing: Bool) -> String { requirePairing ? "1" : "0" }
    public static func door(_ txt: [String: String]) -> Door   // no "p": .plain; "0": .open; else .pairingRequired
    public static func door(_ record: NWTXTRecord) -> Door     // the same, entry by entry: a bare "p" reads as "1"
}
```
NWTXTRecord's `dictionary` and subscript leave out a key without a value (step 1's Results), so a
device reads `p` from the result's record with the second form.

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
without sending its certificate. Corrected by H0 (Results, P4 and P3): a plain Sill client,
whatever its first message (kinds 6 to 23 were tried), makes the server fail with -9836 within
2 ms of its first bytes, and gets a 7-byte TLS alert (`15 03 01 00 02 02 46`: fatal,
protocol_version) and then EOF; -9858 (no alert) is what an HTTP request gets, -9863 a TLS 1.3
client without a certificate, and -9836 a TLS 1.2 client too. TLS costs the sender about
0.67 ms of CPU per MB paced at 60 fps against 0.44 plain, the receiver 0.72 against 0.40 (§8);
the remote plan's 0.9 against 0.4 had both ends in one process.

#### 3.4 Compatibility

"Main" is origin/main at `ba91136` (PR #13), `b50e224` (PR #11 too, nothing a device sees) or
`cea195c` (PR #12 too: the moves between the cable and Wi‑Fi, plain like every home dial there);
"this" is a build from this plan.

| Device | Host | Result |
|---|---|---|
| main | this Sill.app (either setting) | The device dials plain. The door fails the handshake (-9836) within 2 ms of the first bytes (the viewport at once, or the first ping at 0.25 s) and closes; the device reads a 7-byte TLS alert and EOF (H0's P4), which its header read takes for the Mac gone. Because main sets `connected` at TCP `.ready`, it shows the stream screen for a moment, then "Mac mini disconnected…", and retries every 2 s. These refusals do not count toward the door's 300 s backoff (§4.4): that backoff is checked before any key is seen, so an update installed after a few of them would otherwise be refused for up to 5 minutes. The Mac counts it as "from an older Sill (not TLS)" and its menu says "An iPhone or iPad Needs Sill Updated" (§6.4). **Install the device build first.** |
| main | SillHost without `--pairing` | As today (plain) |
| this, DEBUG | main's Sill.app (plain door, TXT `r`, no `p`) | Plain, as today: saved Macs recognised by the tag, no pairing at home, remote access as PR #13. Until the device has seen that Mac with `p` (§7.3) |
| this, Release | main's Sill.app | The row says "Update Sill"; a tap says why; nothing is dialed |
| this | this Sill.app, `p=1` | TLS. A saved Mac: a pinned session. An unsaved one: "Not paired", a tap asks. On the cable, both ends agreeing (§4.3, §7.5): paired at once |
| this | this Sill.app, `p=0` | TLS. A saved Mac: pinned. An unsaved one: a session with any Mac key, nothing saved |
| this, DEBUG | SillHost without `--pairing` (no TXT record) | Plain, as today |
| this, Release | SillHost without `--pairing` | "Update Sill"; nothing dialed. The CLI is a development host |
| this | SillHost `--pairing` | As `p=1`; its window is always open and its code printed |
| this, DEBUG, having seen that Mac with `p` (`homeTLS`) | an older Sill.app installed again: a build of any branch cut before this change (`update-notice`, `encoder-two-in-flight`, `remote-bundle`, the pointer work) | "Update Sill"; nothing dialed (no downgrade, §7.3). Launch the device build once with `-SillForgetHomeTLS 1` (§7.9), or Forget that Mac on the device; over the cable it pairs again by itself once the new Sill.app is back |
| main's `sillclient.py` | this Sill.app's home door | Refused, as main's device. Every gate against the app uses `--tls` |
| main's `sillclient.py` | SillHost without `--pairing` | Unchanged |
| any | the remote door | Unchanged, except that `ask` there is answered `closed` |

**The floor for 1.0:** Sill.app and the iOS app both from this change on. A Release device never
speaks plain to anything. Nothing has shipped, so nobody but Noah meets the rows above with "main"
in them.

#### 3.5 Rules for later changes

HostSettings.swift's rules, as for every payload since PR #13: JSON only; new fields optional; no
enums on the wire (strings; an unknown value is skipped or, for `p`, read as "1"); never rename or
retype a field. A later generation goes in the ALPN (`sill/2`, beside `sill/1` and `sill-pair/1`,
which every host offers for good), with `SillProtocol.current` (Compatibility.swift, main's since the
update notice): protocol 1 is this door's `sill/1`, settled at the merge with main (Results, "The
merge with main"). Pairing's own generation is `PairRequest.v`: a host answers any other than 1
`closed` without counting a try (`DoorPolicy.pairing`), so a later method or proof format comes with
a later `v`, never as a new method at 1, which a first-build host would judge as a wrong code and use
up a try. `MacInfo.v` stays 1 and no device reads it: kind 18 changes additively. What the first
public build freezes of all this is CLAUDE.md's Compatibility floor, "Pairing as 1.0 does it" (the
security review, 2026-09-27).

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
- `standard`: `requirePairing: true`. The init keeps every knob required. In Sill.app the value
  comes from the identity store beside the trust list, never from UserDefaults or a launch argument
  (§4.8, §6.5).
- `changes(to:)`: "require pairing on → off".
- `adopt` hands it to `RemoteAccess.apply` (§4.6); no pipeline ever restarts for it.

#### 4.2 `DoorPolicy.swift` (new; pure, Foundation only, checked with swiftc)

Who each door admits, in one place, for both listeners (`Door`, §4.4). RemoteServer's rules move
here unchanged; the home door's are new.

```swift
enum DoorPolicy {
    enum Door: Equatable, Sendable { case home, remote }
    struct Trust: Equatable, Sendable {
        var hasKey: Bool            // a P-256 key (a fingerprint); without one nothing is trusted
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
        case pairing                         // read its one kind 19; `pairing(_:method:)` says how
        case goodbye(String)                 // "remoteOff", "busy"
        case refuse(String)                  // counted for the summary ("unpaired")
    }
    static func atReady(_ door: Door, alpn: String?, _ t: Trust, remoteSessions: Int) -> AtReady
    enum Pairing: Equatable, Sendable { case ask, window, closed }   // home ask → ask; remote ask → closed; else the window
    static func pairing(_ door: Door, method: String) -> Pairing
    enum Ask: Equatable, Sendable { case pairNow, shown(opened: Bool), openOnMac(String), locked }
    /// cableSeen: the Mac's rule (§4.3); cableClaimed: the ask's `cable: true`. fromThisMac:
    /// loopback, or a source that is one of this Mac's own addresses (`isFromThisMac`).
    static func ask(unlocked: Bool, cableSeen: Bool, cableClaimed: Bool, otherKeyOfDevice: Bool, windowOpen: Bool,
                    fromThisMac: Bool, quiet: Bool, recentDeviceWindows: Int) -> Ask
    // Also (step 1): refusalBeforeStart, handshakeRefusal (§4.4), reason, menuRequest (§4.10),
    // isFromThisMac, otherKeyOfDevice, isTestHost, testAsksAsDevice.
}
```

| Door | Before start (origin) | Verify block, `sill/1` | Verify block, `sill-pair/1` | At `.ready` |
|---|---|---|---|---|
| home | loopback, lan, direct; vpn and internet refused with no byte | paired, or Require pairing off | always | `sill/1`: the session (checked again); `sill-pair/1`: one kind 19 of `ask`, `qr` or `code` |
| remote | loopback, lan, vpn; internet only with internet access; direct never | paired | a window the remote door takes proofs for is open (was: any window) | as today: unpaired → refused; Remote Access off → goodbye `remoteOff`; 8 sessions → goodbye `busy`; `sill-pair/1`: `qr` or `code`, and `ask` answered `closed` without counting a try |

**The ask rule**, first match wins (§4.6 applies it):
1. the Mac is locked, or the console is another user's → `locked`;
2. on the cable by the Mac's rule (§4.3) and by the ask's `cable: true`, and no other key of that
   device (its USB serial's hash) on the trust list → `pairNow`;
3. a pairing window is open → `shown(opened: false)`;
4. from this Mac itself (loopback, or a source that is one of this Mac's own addresses: the
   Simulator, a local tool, any app) → `openOnMac("this Mac")`. Such an ask never opens a window by
   itself: an app that can record the screen would otherwise ask, read the code it put up and pair,
   turning Screen Recording into control of the Mac through Sill's Accessibility grant. It lights
   no menu item either (§6.4): "iPad Wants to Pair · Show a Code…" under a name the app chose is
   one click from the same code. An app that asks from a second address it controls gets past this
   step (What stays open). The Simulator pairs with a window the Mac's user opens (Pair iPhone or
   iPad…). TEST ONLY `SILL_TEST_ASK_FROM_THIS_MAC=1`, on a test host (§4.3), skips this step and
   its menu rule, so the gates' local clients (H6–H8) open windows and light the menu;
5. this device's key or address is quiet (its last window was cancelled on the Mac or stopped
   within 10 minutes; one that ran out or that it withdrew quiets nobody)
   → `openOnMac("quiet")`; 3 device-opened windows in the last 10 minutes → `openOnMac("often")`
   (the labels are the log's; the device only sees `openOnMac`);
6. otherwise → `shown(opened: true)`: a window opens for it.

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
        var serial: String?         // "USB Serial Number": the device itself, at every plug-in
        var session: UInt64?        // its sessionID: one plug-in (the log and --print-cable only)
    }
    static let appleVendor = 0x05AC
    static let products: Set<String> = ["iPhone", "iPad"]
    static func isPhoneOrPadCable(_ a: Ancestry?) -> Bool
    /// The device a connection came over, or nil: an IPv6 link-local source (16 bytes) scoped to
    /// such an interface, that is none of this Mac's own addresses. An IPv4 source, no scope, no
    /// serial, or anything else unread counts as no cable.
    static func device(source: [UInt8], scope: String?, ownAddresses: Set<[UInt8]>,
                       cables: [String: Ancestry]) -> Ancestry?
    /// What PairedDevice.cableDevice keeps: base64url of the first 16 bytes of
    /// SHA-256("sill-cable-v1" ‖ serial). Never the serial itself, in the list or in a log line.
    static func deviceID(serial: String) -> String
}
```

- **InterfaceSnapshot** (read on the network queue, cached 2 s as today) gains `cables: [String:
  CableLink.Ancestry]`: for each up interface that is not loopback, a tunnel or peer-to-peer Wi‑Fi,
  whatever its name (today en14 and anri0; a new name is judged the same way),
  `IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(…))`, then
  `IORegistryEntryGetParentEntry(…, kIOServicePlane, …)` upward: note an `IOUSBHostInterface` with
  `bInterfaceClass` 2 and `bInterfaceSubClass` 13, stop at the first `IOUSBHostDevice`
  (`IOObjectConformsTo`) and read `idVendor`, `USB Product Name` (else `kUSBProductString`),
  `USB Serial Number` and `sessionID`. Under a millisecond an interface; read again when the
  interface list changes, and afresh for the arrival interface of every ask (a device swapped for
  another between two reads keeps the interface's name; the tick rule may use the cache). As built
  (step 2): no cache at all. Every reader reads its one interface afresh (an ask, a session's
  registration; --print-cable reads them all), so `InterfaceSnapshot.readCable` returns plain
  values and Door makes the `CableLink.Ancestry`. Nothing
  written, no permission needed (the probe ran from Terminal as a plain process, and again from
  the review's shell).
- **SessionLock** (main actor): unlocked when `CGSessionCopyCurrentDictionary()` has
  `kCGSSessionOnConsoleKey` = 1 and no true `CGSSessionScreenIsLocked`; a nil dictionary counts as
  locked. Sill.app adds a second witness, the distributed notifications `com.apple.screenIsLocked`
  and `com.apple.screenIsUnlocked` (either saying locked wins), because the dictionary's lock key
  is undocumented and a rename would read as unlocked. The CLI has the dictionary only.
- **TEST ONLY**, honoured only by a test host (the next item): `SILL_TEST_CABLE_INTERFACE=<if>`
  counts a client scoped to that interface as one on the cable to an "iPad" (serial "TEST", session
  1), even when its source is this Mac's own address (rule 2 is the one rule the stand-in skips),
  so a link-local client on the Mac's own `fe80::…%en0` stands in for a device on the cable, as
  `SILL_TEST_PEER_TO_PEER_INTERFACE` stands in for awdl0; `SILL_TEST_LOCKED=1` makes SessionLock
  say locked; `SILL_TEST_ASK_FROM_THIS_MAC=1` skips the ask rule's step 4 (§4.2).
- **Which hosts honour test hooks.** "A host that does not advertise" is not enough any more. Any
  process of this user can start Sill.app's own executable with `open -n --env SILL_TEST_…=… -a
  Sill --args --synthetic …` (`open --env` exists on this Mac), and it then runs as its own
  responsible process with Sill's Screen Recording and Accessibility grants: a synthetic host
  still lists, captures and types into real windows (only its Desktop is a test pattern). With
  `SILL_TEST_REMOTE_DIR` it would trust a `paired.json` its caller wrote; with
  `SILL_TEST_CABLE_INTERFACE` or `SILL_TEST_ASK_FROM_THIS_MAC` it would pair its caller with no
  code. That is the confused deputy again, open today through `SILL_TEST_REMOTE_DIR` (its
  `paired.json`, or `pairing.code` next to it). So a test host is one that does not advertise and
  is not a `.app`'s executable: `isTestHost`, set from AppModel's existing `bundled` check (the CLI
  is never bundled, and TCC charges it to whatever launched it). Every hook that bears on who gets
  in or what pairing needs reads it: the doors' and pairing's variables (`SILL_TEST_REMOTE_DIR`,
  `SILL_TEST_ORIGIN`, `SILL_TEST_PAIRING_TTL`, `SILL_TEST_BACKOFF_SECONDS`, the Direct Wireless
  ones, and this plan's), which today go by "does not advertise" (or `--synthetic`) alone. The
  bundle, `.build/Sill.app`
  included (the same designated requirement, so the same grants), ignores them with one line each,
  and with `--synthetic` keeps its identity in memory, pairing required. The encoder's variables
  (`SILL_TEST_ENCODER_HANG`, `SILL_TEST_PROBE_*`, `SILL_TEST_RECHECK_SECONDS`,
  `SILL_TEST_SOFTWARE_ENCODER`) let nobody in and stay as they are: Noah runs the first on Sill.app
  itself.

#### 4.4 `Door.swift` (new, from RemoteServer.swift) and `RemoteServer.swift`

- **`Door`** is RemoteServer's admission, moved: pending connections (8 in all, 2 a source), the
  10 s admission deadline, the origin check before start, the verify block (now
  `DoorPolicy.trusts`), `.ready` (`DoorPolicy.atReady`), reading the one kind 19, the backoff (5 of
  its own refusals in 60 s → 300 s; a paired key clears its source), `doorRefusals`, and the
  minute's summary. One class, two instances: `Door(.remote)` owned by RemoteServer and
  `Door(.home)` owned by StreamServer. Its outputs: `onSession(connection, route)` and
  `onPairAttempt(attempt, reply)`; a home attempt also carries the arrival interface, the origin,
  whether its source is this Mac's own, and the cable device (`CableLink.device`, over the arrival
  interface's ancestry read afresh at `.ready`).
- **The home door's summary** (the plain door's line stays byte for byte for the CLI):
  "Home door refused N connections in the last minute: a unpaired, b through a VPN, c from the
  internet, d from an older Sill (not TLS), e over the limit." A home handshake that fails with
  -9836 counts as "from an older Sill" and, at a source's third within a minute, sets
  `olderDeviceAt` (§4.10): every plain Sill message
  gets it, whatever its kind (H0's P4), because the TLS record header's version bytes are the Sill
  header's first timestamp bytes, 0x41 0xD0 to 0xDF for any time from 2004 to 2038, never a TLS
  version. A TLS 1.2 client gets -9836 as well (no Sill build is one). So the menu's item waits for
  a source's third plain try within a minute (`DoorPolicy.olderSillTry`; the security review,
  2026-09-27: one `openssl s_client -tls1_2` lit it for 10 minutes): an older Sill tries again and
  again, a tap and then its reconnect every 2 to 10 s, while a scanner usually tries once. The
  summary counts every try. -9858 (an HTTP request, which the TLS stack tells
  apart) and the remote door's other refusals (`doorRefusals`: -9808, -9863, -9810) count as
  "unpaired", toward the backoff, as they do at the remote door. An older Sill's -9836 counts in
  the summary, not toward its source's backoff: the
  backoff is checked when a connection is accepted, before any key is seen (RemoteServer.swift:214),
  so an iPad that retried plainly every 2 s (5 refusals in 10 s) and was then updated would have
  its new build refused at once for up to 300 s; a plain connection costs the Mac nothing past its
  first bytes.
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
   with `.home(origin, peer:)` and its link (ClientLink), read at registration as today. `serve`
   also sets a home session's `pathUpdateHandler` (`onClientRouteChanged`), which `accept` sets
   today and `serve` does not, so the card's Wired, Wi‑Fi or Direct keeps following the path.
4. **`ClientRoute.home`** gains the peer: `.home(OriginPolicy.Origin, peer: Peer?)` with `Peer {
   fingerprint: Data; name: String? }` (name nil for an unpaired key while Require pairing is off;
   no peer on the plain door). `fingerprint` and `pairedName` answer for both doors.
5. **The TXT record:** the coordinator's `txtRecord` returns `r` and `p`. New `updateService()`
   sets `listener.service` again on the queue for a `p` change (the same name and type: an update
   in place, H0's P1, which fires no `onServiceRegistered`); during a replacement it does
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
   registration from `CableLink.device` (read afresh, step 2). The plain door keeps today's ticks
   byte for byte.
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
  `DoorPolicy.ask(…)` with `SessionLock.unlocked()`, the attempt's cable device and the request's
  `cable`, the trust list's `cableDevice`s, `window.isOpen`, whether the source is this Mac's own,
  and `AskLimits`:
  - `pairNow`: a `PairedDevice` with `method: "cable"` and `cableDevice` is saved first (a save
    that fails answers `openOnMac` and logs why), then the snapshot; the line "Paired
    ‹name› (key ‹prefix›…) over the USB cable (‹endpoint›)."; `onCablePaired` (the app's notice, the
    CLI's line); kind 20 ok with `method: "cable"`, the Mac ID, name and recognition key. A key
    already on the list gets the same ok with no line and no notice, and nothing saved but its
    `cableDevice` if it had none: a device that lost its saved Macs asks once more, and an app
    asking in a loop shows nothing.
  - `shown(opened: true)`: `openPairing(requestedBy: ‹name›, byDevice: (key, source, route))`; kind
    20 `shown`.
  - `shown(opened: false)`: kind 20 `shown`.
  - `openOnMac`, `locked`: `pairingRequest` set for the menu (§4.10), except for an ask from this
    Mac, which is logged and nothing more; kind 20 with that reason.
  - Each ask logs one line (§4.11), at most one a minute per source address: a stranger asking in
    a loop would otherwise fill Sill.log.
- **`openPairing(requestedBy:byDevice:)`** (:198): only some windows are the remote door's. A
  window opens the remote door (`updateDoor`, :420: `remoteAccess || (window.isOpen &&
  window.forRemote)`) and lets it take proofs (`publishTrust` sets `remotePairingOpen`) when the
  Mac's user opened it in Sill.app, or when the CLI runs with `--remote`; never a window a device
  opened, and never the CLI's with `--pairing` alone, whose always-open window would otherwise bind
  7455 beside Sill.app's. The watchers (`updateWatchers`, :425), the address list (`addresses()`,
  :476: kind 18 and the link) and the offer's wait for them (`deliverOfferIfReady`, :397, up to
  3 s) follow `forRemote` too, not `window.isOpen`: a home-only window starts no Reachability, its
  link carries no `a` (a QR code read off the screen names no Tailscale address), and its offer goes
  out at once, so the window is up when the device hears `shown`. On a plain home door (the CLI
  without `--pairing`, and Sill.app built at step 2, before step 3 turns its door to TLS) every
  window is `forRemote`, kind 21's included, as today: the plain door takes no proof, so the remote
  door must. `PairingOffer` gains `byDevice`, and the app shows such an offer in front
  without taking the keyboard (§6.3). The Mac's user opening a window (the menu, the pane, New
  Code, the menu's Show a Code…) while a device-opened one is up makes that window the remote
  door's too: the same code, `forRemote` set, the door and the watchers started, and the offer made
  again (`again: true`) once the addresses are known, so a device away can pair with it. Today's
  `openPairing` only offers the open window again, which would leave the remote door refusing its
  proofs and its QR code without addresses. A device's ask never takes `forRemote` away. When a
  device-opened window closes cancelled on the Mac or stopped (five wrong codes), `AskLimits` makes
  that key and address quiet for 10 minutes; when it runs out, or its device withdraws it, nobody.
- **Kind 19 "cancel"** (the security review, 2026-09-27): the device's Cancel on the home card, or a
  new tap elsewhere, after the Mac answered its ask "shown", tells the Mac on a `sill-pair/1`
  connection pinned to the key that answered. The window closes, withdrawn (no quiet, "Pairing:
  ‹name› at ‹address› no longer needs its code; the window closed."), only when that very key's ask
  opened it and it is still the home door's alone: a window the Mac's user opened, or opened over
  it, stays. Always answered `closed`, never judged by the window. A device that pairs over the
  cable withdraws its own device-opened window the same way (no line), so its code does not stay
  up for its 5 minutes beside the cable notice.
- **Kind 21** (`pairingWanted`, :244) opens a device-opened window too (a Pair This iPad… from an
  unpaired session while Require pairing is off), through the ask rule's steps 1 and 3–6 and
  `AskLimits` (never step 2: a session is no pairing connection).
- **`remove(fingerprint:)`** (:266) closes that key's home sessions as well as its remote ones,
  each with goodbye `removed`; the line counts both.
- **`sessionStarted(fingerprint:route:)`** records home sessions of paired keys too, with the home
  route's words: "over the USB cable" (CableLink), "over Wi‑Fi", "over Ethernet", "directly"
  (peer-to-peer Wi‑Fi), "on this Mac" (loopback), else "at home". Written at most once a minute per
  device, as today.
- **The cable's devices:** `PairedDevice.cableDevice` (§4.8) is set for a key paired over the
  cable, and for a paired key whose session registers over the cable without one
  (`sessionStarted`; one save per key, ever), so a device paired by QR code gets it the first time
  Sill streams over its cable. An ask over the cable from a device whose ID another key carries
  gets the window (step 2); Remove frees the device.
- **The CLI** (`reopensPairing`): its window is always open, so an ask is answered `shown` and the
  CLI prints the code again with who asked (§5).

#### 4.7 `PairingWindow.swift`

- `Open` gains `byDevice: DeviceAsk?` (the key's fingerprint and the source address), for the quiet
  rule and the window's copy, and `forRemote: Bool` (whether the remote door runs for it and takes
  its proofs, §4.6).
- **`AskLimits`** (new, pure, same file, checked with swiftc):
  ```swift
  struct AskLimits {
      static let quietFor: Double = 600      // after the Mac's user cancels a device-opened window, or it stops
      static let span: Double = 600          // at most `maxWindows` device-opened windows in this span
      static let maxWindows = 3
      func quiet(fingerprint: Data, source: String, now: Double) -> Bool
      func recentWindows(now: Double) -> Int
      mutating func opened(now: Double)
      mutating func closedUnused(fingerprint: Data, source: String, now: Double)
  }
  ```
  TEST ONLY `SILL_TEST_ASK_QUIET=<s>` replaces both 600 s on a test host (§4.3).

#### 4.8 `HostIdentity.swift`

- `PairedDevice.method`: "qr", "code" or, new, "cable" (M5 adds "icloud"). `displayMethod`: "with
  the QR code", "with a code", "over the USB cable".
- `PairedDevice.cableDevice: String?`, new and optional (older lists decode): `CableLink.deviceID`
  of the iPhone or iPad this key paired over, or ran a session over, by cable.
- `TrustSnapshot` gains `requirePairing` and `remotePairingOpen`.
- `IdentityStore` gains `loadRequirePairing() throws -> Bool` (true when never saved; a read that
  fails counts as true too, with the keychain line) and
  `saveRequirePairing(_:) throws`: in the keychain store a generic password beside the trust list
  (service `me.saffer.sill.remote`, account `require-pairing`, the same default access control,
  so another app gets the keychain's prompt; a missing item reads as on, so deleting it only turns
  pairing on), in the memory store a variable, in the test directory a file `require-pairing`.
  Its own item, not a field of `paired-devices`: an older Sill.app reading a changed trust list
  would call it damaged and lose its identity.

#### 4.9 `StreamCoordinator.swift`

- `init(config:synthetic:appKitLoop:remote:homePairing:testHooks:)`: the server's home mode is
  `.plain` without `homePairing` (the CLI's default), else `.tls` with the remote identity, or
  `.closed` with its `identityProblem`. `testHooks` is false for Sill.app's own executable (§4.3):
  StreamServer's `testHost` and RemoteAccess's become "does not advertise and `testHooks`", so
  every existing `SILL_TEST_*` read follows the new rule without being touched one by one.
- `onClientConnected`: a paired home session shows its paired name until its stats arrive, as a
  remote one does, and records `sessionStarted` for the pane's "last connected" and, over the
  cable, the key's `cableDevice` (§4.6).
- `.pairingWanted` (:539; :594 at `cea195c`): from a home session whose key is not paired
  (Require pairing off), not within 30 s of that connection's last one. A paired session's is
  ignored.
- `adopt`: `requirePairing` changed → `remote?.apply(next)`. No restart.

#### 4.10 `HostStatus.swift`

`RemoteStatus` (kept, one type for both doors' pairing) gains:
```swift
package enum HomeDoor: Equatable { case plain, pairingRequired, open, unavailable(String) }
package var homeDoor: HomeDoor
/// A device asked and no window shows its code (the Mac locked, or the limits), or a device-opened
/// window is open: for the menu's "‹device› Wants to Pair", 5 minutes after the ask.
package var pairingRequest: PairingRequest?     // name, at, reason: "showing" | "locked" | "limit" (quiet or often; never an ask from this Mac); ends when that device pairs
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
Cable pairing: iPad (iPad14,1) at fe80::18fe:abff:febb:459f%anri0 not paired by itself (another key of this iPad is paired); showing the code.
Cable pairing: iPad (iPad14,1) at fe80::18fe:abff:febb:459f%anri0 not paired by itself (it didn’t find the cable on its side); showing the code.
Pairing: iPad Pro 13-inch (M5) (iPad17,4) at 169.254.178.234 asked to pair; not shown (it asked from this Mac).
Paired iPad (iPad14,1) (key 5KD2Q7…) from fe80::1c0f:2a:6e1:9b3%en0, with the QR code.
Require pairing: disconnecting iPhone (iPhone17,1) at 10.128.0.41:61022, which isn’t paired.
Removed iPad (iPad14,1); closed 1 connection.
Home door refused 7 connections in the last minute: 3 unpaired, 0 through a VPN, 0 from the internet, 4 from an older Sill (not TLS), 0 over the limit.
Settings: require pairing on → off
```

A "Cable pairing: … not paired by itself (…)" line ends with what the rest of the ask rule gave:
"showing the code", "the code is already showing" or "not shown (…)". A home session admitted
through the door prints "Client connected: ‹endpoint›" as `accept` does today.

"Client connected: …", "Client left: …" and "Catalog → …" keep their exact text: tests grep for
them. The first two lines print once at start (Sill.app always; the CLI only with `--pairing`).

---

### 5. CLI (`Sources/SillHostCLI/main.swift`)

| Flag | Effect |
|---|---|
| none | Output byte-identical to the branch point's (masked and sorted; `cea195c` or later, whose host sources are `b50e224`'s, not `ba91136`'s: PR #11 changed the host's encoder lines), idle and streaming, with and without `--direct-wireless` and `--remote`. Today's plain home door: no pairing, no `p` in any TXT record |
| `--pairing` | The home door speaks TLS with pairing required. A throwaway identity (`MemoryIdentityStore`; `SILL_TEST_REMOTE_DIR` on `--synthetic`), the same one `--remote` uses when both are given; the remote door runs only with `--remote`. A pairing window is always open (a fresh one after each use or expiry, as with `--remote`); its link carries no addresses (a home-only window, §4.6), so its offer prints at once. main.swift prints from the `onPairingOffer` hook: `Pairing required for this run (TLS on the home door). Pair with 4829 1355 7208 or sill://pair?v=1&…`, and on each ask, after the core's ask line, `Pairing: iPad (iPad14,1) asked; code 4829 1355 7208 or sill://pair?v=1&…`. Over the cable the core's "Paired … over the USB cable (…)." line. With `--remote` too, each prints its own startup line and the pairing lines once |
| `--print-cable` | For each interface: `en14: the USB cable to an iPad (Apple, product 0x12AB, NCM, device 3QX7…, plug-in 4854277126715)` (device: the start of `CableLink.deviceID`, never the serial), `anri0: the USB cable to an iPad (…)`, `anpi0: not a cable (this Mac's own USB device port)`, `en0: not a cable (no USB device)`; then `This Mac: unlocked, your session on the console.` and exit 0. Read-only IOKit and CGSession, no listener, no permission. H5's live check with a device on the cable |

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
- Toggle **"Require pairing"**, through AppModel to `RemoteAccess` and the identity store (§6.5);
  a save that fails leaves it on for this run, with the keychain line under it.
- Footer while on: "Each iPhone or iPad pairs once: over the USB cable by itself, or on Wi‑Fi with
  a code this Mac shows when the device asks. Everything devices send and receive is encrypted."
- While off (orange, with its sign): "Any device on your network (or nearby, with Direct Wireless
  Connection on) and any app on this Mac can see and control it without pairing. Connections are
  still encrypted."
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
- The origin line says "nearby" over peer-to-peer Wi‑Fi and "on this network" otherwise. "On this
  Mac" (loopback, or one of this Mac's own addresses) shows only on test hosts: in Sill.app an ask
  from this Mac never opens a window (§4.2, step 4).
- Shown with `orderFrontRegardless()` and no `NSApp.activate()`: not `WindowPlacement.bringForward`
  (SettingsWindow.swift:133), which activates Sill. In front, off the virtual display, without the
  keyboard; `.fullScreenAuxiliary` so it shows over a full-screen app. A click makes it key.
- Its states (Pairing with…, Paired with…, a wrong code…, stopped, expired) are today's.
- VoiceOver announces its first line as it comes up (it has neither focus nor the keyboard, so it
  would otherwise say nothing), as the cable notice does; not again when the same window's offer is
  made again (the security review, 2026-09-27).

**Opened on the Mac** (the menu, a pane, New Code): as today, activating Sill, with the first line
"In Sill on your iPhone or iPad, tap this Mac, or tap Add a Mac… when you’re away, then point it at
this code." (was "…tap Add a Mac…, then point it at this code."). The Address row and the Remote
Access line stay: they are for pairing from away.

**The cable notice** (a window of its own in the pairing window's style; as built in step 3, not
the pairing window in a new phase: a pairing over the cable can happen while that window shows a
code, since the ask rule pairs a cable ask before it looks at an open window, and the notice must
not take the code off the screen):

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
| "iPad Wants to Pair" (the device's name) | "A code is showing." · "Click to show a code." · "Unlock this Mac, then tap it on the iPad again." | `pairingRequest`, 5 minutes from the ask: a device-opened window is open · an ask the limits kept from showing (never an ask from this Mac, §4.2 step 4) · the Mac was locked. It ends sooner when that device pairs, by any path (its key), and a window opened from the item takes it over ("A code is showing.", ending with that window) | brings the window forward, or opens one on the Mac "asked by" that device |
| "An iPhone or iPad Needs Sill Updated" | "It tried to connect with an older Sill." | 10 minutes from `olderDeviceAt`: a source's third plain try within a minute (one try, a TLS 1.2 scanner's, lights nothing) | none |
| "Devices Can’t Connect" | "Sill couldn’t use its key in your keychain." | `homeDoor == .unavailable` | Settings › Devices |

- The glyph shows attention for the first and the third (Sill needs its user); the second is only
  information.
- "Pair iPhone or iPad…" stays in the third group.
- The card: a paired device's row shows its paired name until its stats arrive, as remote ones do.

#### 6.5 Settings keys and wiring (`HostSettings.swift`, `AppModel.swift`)

- `requirePairing` is not a UserDefaults key. Any process of this user can write
  `me.saffer.sill.mac` (`defaults write me.saffer.sill.mac requirePairing -bool NO`) and start a
  Sill.app with arguments (`open -n -a Sill --args -requirePairing NO`, a second instance beside
  the first: nothing stops one), and either would open the home door to every app on this Mac
  without a code, the confused deputy this plan closes; that is why the trust list is kept out of
  UserDefaults (HostIdentity.swift). So AppModel reads it from the identity store at launch into
  `settings.config` and writes it only from the Devices pane's toggle (`saveRequirePairing`, then
  `RemoteAccess.apply`). The bundle takes no argument for it; the bare binary takes
  `-requirePairing NO` and `-SillSetAfter requirePairing=0|1`, saved in its own store (memory, or
  the test directory). An existing install has no item and comes up on.
- `remoteDevicesSeen` keeps its name and now also holds home sessions.
- AppModel: `StreamCoordinator(…, homePairing: true)`; `onCablePaired` shows the notice; the
  Devices pane gets the pair, remove and rename actions the Remote Access pane had; it observes the
  lock notifications for SessionLock (§4.3).
- StreamProtocol's HostSettings.swift header ("every place a new setting must go") adds require
  pairing to the Mac-only knobs that never enter StreamSettings, HostSettingsChange or
  DeviceSettings.accepted.

#### 6.6 DebugHooks and previews

- `-SillSetAfter` learns `requirePairing=0|1` (the bare binary only, like every hook below).
- **In the bundle** every `-Sill…After` hook (`-SillSetAfter`, `-SillPairAfter`, `-SillUnpairAfter`,
  `-SillCancelPairingAfter`, `-SillCableNoticeAfter`, `-SillMenuAfter` and, as built in step 3,
  `-SillQuitAfter` too), `-requirePairing` and `SILL_TEST_REMOTE_DIR` are ignored with one line
  each: they open, answer or remove pairings, or change what the doors admit, and any process can
  pass them (§4.3, "Which hosts honour test hooks"). `-SillRenderPreviews` (no identity, no
  listener) and `-SillLogFile` stay.
- `-SillCancelPairingAfter '<s>[; <s> …]'` closes the pairing window as Cancel does (the quiet rule).
- `-SillCableNoticeAfter <s>` shows the notice for a sample device.
- `-SillMenuAfter '<s>[; <s> …]'` (added in step 3) prints the status menu as menu.txt shows it, one
  "SillMenuAfter ‹s› s: " line per line: the gates' view of the status (the request, the older
  device, the closed door).
- `-SillRenderPreviews` adds `pane-devices-{required,off,empty,unavailable}-{light,dark}.png`,
  `pairing-{asked,askednearby,cablenotice}-{light,dark}.png`, the Remote Access pane's samples with
  the list replaced by its line, and menu.txt's three attention items.

---

### 7. iOS client

#### 7.1 Files (a new file needs its four pbxproj entries, by hand)

| File | Change |
|---|---|
| `Sources/StreamProtocol/*` (shared) | Remote.swift (`ask`, `PairRequest.cable`, the new reasons, `PairResult.method`, `pairingRequired`); Pairing.swift (`HomeDoorTXT`); RemoteTLS.swift (the parameters overload) |
| `iOSClient/DiscoveryPolicy.swift` | `homeDial`, `rowWord`, `onCable` (pure) |
| `iOSClient/SavedMacs.swift` | `homeTLS`, `revoked` (optional: older records decode) |
| `iOSClient/StreamClient.swift` | one TLS builder for every home dial; `p` from each result; the session gate at the first window list; revoked |
| `iOSClient/StreamClient+Remote.swift` | the ask; pairing through the row; the cable's ok; the goodbyes at home. As built (step 4): these live in a new `iOSClient/StreamClient+Home.swift` (`DeviceTLS`, `HomeDialer`, `HomeAsk`, the ask, the proofs at the home door, the session gate, how a home session ends); +Remote routes its scanner, outside links and ends to it |
| `iOSClient/Info-Debug.plist` (new, step 4) | the Debug configuration's Info.plist: Info.plist plus `_silltest._tcp` (§7.9) |
| `iOSClient/AddMacCard.swift` | a home mode: the scanner, or the code alone (as built, step 5: `home`, the row's name) |
| `iOSClient/ContentView.swift` | row words and hints; the card for a row; the harness contract |
| `iOSClient/HostSettingsPanel.swift` | Away from home: "Paired"; Pair This ‹iPad›… only in an unpaired session (as built, step 5: `DiscoveryPolicy.awayFromHome`, pure) |
| `iOSClient/CodeScanner.swift` (step 5) | the viewfinder's caption and spoken label name the home card's Mac |
| `iOSClient/StreamScreen.swift` (step 5) | `DrawerRow`'s trailing word keeps its whole width ("Not paired" and "Update Sill" hold a space): the title truncates instead |
| `iOSClient/MockCatalog.swift` | the new cases |
| PR #12's code (merged, `cea195c`) | its dial sites go through the builder: at `cea195c`, StreamClient.swift's `connect(to:…)` :867 (the connection at :887; the wired dial's fallback, `dialUnconstrained` :972, calls it again) and `startMove(to:kind:fallback:)` :1059, which every move uses: from AWDL, up to the cable, down to Wi‑Fi, and `reconnectNow` :1465 and `rescue` :1505 through it; `connectionParameters` :985 is the plain builder. A remote dial's `adopt` :1865 takes RemoteConnector's connection, already TLS |

#### 7.2 One builder for every home connection

- **`HomeLink.parameters(identity:pin:peerToPeer:alpn:)`** replaces `connectionParameters(peerToPeer:)`
  (StreamClient.swift:867; :985 at `cea195c`) for every connection to a Mac whose row carries `p`:
  `connect(to:)` (:763; :867) with its wired dial and fallback, the automatic reconnect (through
  `dial`, :731; :815), the move from AWDL (`startMove`, :935; :1059) and its fallback, PR #12's
  moves and `reconnectNow`, and the session after a pairing. The plain builder stays for plain
  doors (DEBUG only, §7.3).
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

- `recomputeMacs` (:575; :648 at `cea195c`) reads `p` with `HomeDoorTXT.door` (the result's
  NWTXTRecord, entry by entry, §3.2) beside `r`
  (`tag(of:)`, :620; :704), for
  both browsers. `FoundMac` gains `door: HomeDoorTXT.Door`.
- `SavedMac` gains `homeTLS: Bool?` (the Mac was seen with `p`, or a TLS home session with it ran)
  and `revoked: Bool?` (goodbye `removed`, or a pinned home dial refused with -9825 or -9829;
  cleared by the next pairing).

| Row (`DiscoveryPolicy.rowWord`) | Word | VoiceOver |
|---|---|---|
| a saved Mac, not revoked, on a TLS door | its method, as today: "Wired", "Wi‑Fi", "Direct" | as today |
| unsaved or revoked, `p=1`, not over a cable | "Not paired" | "Mac mini, not paired"; hint "Pairs with a code Mac mini shows, then connects." |
| unsaved or revoked, `p=1`, Wired over a cable (its wired interface carries only link-local addresses, §7.5) | "Wired" | "Mac mini, Wired"; hint "Pairs over the USB cable, then connects." |
| unsaved, `p=0` | "Not paired" (`openDoor`; the security review, 2026-09-27: it read its method, "Wi‑Fi", exactly as a paired Mac's row does) | "Mac mini, not paired"; hint "Connects without pairing: Mac mini lets any device in." |
| no `p`, DEBUG, not `homeTLS` | its method (a plain door, as today) | as today |
| no `p`, Release; no `p` and `homeTLS` | "Update Sill" | hint "Mac mini’s Sill is too old for this ‹iPad›." |

- A Wired row whose wired interface also carries a routable address (a USB Ethernet adapter on
  the LAN) is no cable: it reads "Not paired", and its tap asks without `cable`.
- **No downgrade.** Once a saved Mac is `homeTLS`, its rows are dialed only over TLS, in DEBUG too;
  a row of it without `p` reads "Update Sill" (its own Sill never goes back to plain; someone may
  be replaying its tag). A Release build never dials plain at all.
- A row whose tag names no saved Mac, under the Bonjour name a saved Mac was last reached by,
  counts as that saved Mac for these rules (`DiscoveryPolicy.rowMac`, `FoundMac.savedByName`),
  for the automatic reconnect (#13's `reconnectIfListed` matches by name when the row has no Mac
  ID) and, since the security review (2026-09-27), for a tap too: its word is that Mac's, it is
  dialed pinned to its key, and not at all without `p` once it is `homeTLS`, in DEBUG too. (A tap
  used to dial such a row with any key, or plain in DEBUG, while it read exactly like the paired
  Mac's: a look-alike advertising a saved Mac's name without its tag got a session and all it was
  sent.) A same-named Mac that is not it then fails the pin (-9808): the reconnect skips it from
  then on (`pinRefusedRows`) without the "This isn’t the Mac mini…" copy, which is for a row its
  tag named, and a tap, after the Mac's other rows, says that copy (the user asked for that Mac).
  The price: another Mac of the same name, reached only while the saved one is not listed, cannot
  be tapped until the saved one is forgotten (its Remote row's menu).
- Remote rows are unchanged.

#### 7.4 A tap (`DiscoveryPolicy.homeDial`, pure)

| Row | A tap |
|---|---|
| saved, not revoked, TLS door | `sill/1` pinned to the saved key; connected at the first window list |
| saved and revoked; unsaved with `p=1` | the ask (§7.5) |
| unsaved, `p=0` | `sill/1` with any Mac key; nothing saved (the row reads "Not paired", §7.3) |
| no `p`, DEBUG, not `homeTLS` | plain, as today |
| no `p`, otherwise | nothing dialed; status "Mac mini runs an older Sill. Update Sill on the Mac to connect." |

- The automatic reconnect follows the same table, and never asks: an ask is a tap's.
- A Wired row's dial goes over the cable first (`wiredDial`, :748; :832 at `cea195c`) with its
  fallback after `wiredWait`, for an ask as for a session.

#### 7.5 Pairing at home (`StreamClient+Remote.swift`)

1. **The ask.** A `sill-pair/1` connection to the row (its wired interface first for a Wired row,
   over IPv6 only: `NWProtocolIP.Options.version = .v6` on that dial, since the cable counts only
   over IPv6 link-local at both ends, and 41 of 41 sessions over the cable already were).
   For a saved, revoked Mac it pins the saved key (`askedKey` is that key): the Mac's key has not
   changed, only its trust in this device, so no look-alike can answer and a typed code goes only
   to the real Mac. For an unsaved Mac it takes any key and remembers the one it saw (`askedKey`).
   Kind 19 `ask`, with `cable: true` when `DiscoveryPolicy.onCable` holds for this connection at
   `.ready` (item 2); kind 20 within 15 s (`pairingReplyDeadline`). Status "Pairing with Mac mini…"
   ("…over the cable…" on a Wired row).
2. **Kind 20 ok with `method: "cable"`.** Accepted only as the answer to an ask that said `cable:
   true`, with `macID == MacID(fp)` of this session's Mac key and a 32-byte recognition key, as the
   remote path checks. The device says `cable: true` only when this connection runs over the cable
   as it sees it (`DiscoveryPolicy.onCable`, pure, over the path and `getifaddrs`), all of:
   - the Mac's address is IPv6 link-local and scoped to a wired interface (the iPad saw it on en2,
     2026-09-25); an IPv4 address never counts, as on the Mac (§4.3);
   - it is none of this device's own addresses: another app on the device, listening on the
     device's own en2 address behind a look-alike row, would otherwise be "the Mac";
   - that interface carries no address but link-local ones (fe80::/10, 169.254/16). The USB link
     to a Mac has only those; a USB Ethernet adapter on the LAN, which iPadOS also types as wired
     Ethernet and whose row also says "Wired", has the network's DHCP or SLAAC address, and a
     look-alike Mac on that LAN could otherwise make the device pin it without a code.
   Otherwise the ask goes without `cable`, the Mac shows its window, and a proof-less ok is refused
   ("Pairing didn’t finish…", nothing saved). The DEBUG console says what the check read ("cable:
   yes, en2 carries only link-local addresses"; "cable: no, en3 has 10.128.0.52"). Saved:
   `method "cable"`, the pin from this session, the recognition key, `homeTLS`, the Bonjour name.
   Then a pinned session on the row.
3. **`shown`.** The connect screen unfolds the home card for that row (§7.8): the scanner, or
   after Enter Code Instead the code alone.
   - A scanned link whose key is `askedKey`: a second `sill-pair/1` connection to the row, pinned
     to that key, kind 19 `qr` with the proof from the link's secret. A link with another key: the
     home rows with `p`, each dialed pinned to the link's key, one at a time (the Mac whose code it
     is answers; a look-alike that answered the ask cannot, so the scan still pairs the real Mac),
     then, none answering, today's pairing through the link's addresses. A device-opened window's
     link has none: "Nothing answered…".
   - A typed code: `sill-pair/1` to the row pinned to `askedKey`, kind 19 `code` with the PBKDF2
     proof; the check digit is checked first, as today.
   - Kind 20 ok with proof_M checked and `macID == MacID(fp)`: saved as the remote path saves,
     plus `homeTLS` and the Bonjour name; then a pinned session on the row.
4. **`openOnMac`, `locked`:** the status line (§7.7); no card.
5. **`busy`:** one silent retry, as today. `closed`, `expired`, `stopped` on the second
   connection: §7.7's words; a tap on the row asks again.

- **An outside link** (`onOpenURL`, after its confirmation) goes the same way: to the row whose
  asked key it names, else the home rows pinned to its key, then its addresses, as today.
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
- **-9825 or -9829 on an unsaved `p=0` session** (its TXT record was stale: Require pairing is on
  again): as `pairingRequired`, and the row reads "Not paired".
- **-9808** on a pinned home dial (another key answers as that Mac): first every other row
  recognised as the same saved Mac is dialed, pinned (a stranger replaying the Mac's tag makes a row
  that looks like it, and the copy below would tell the user to forget the real Mac); only when none
  answers with the saved key, the remote copy, "This isn’t the Mac mini this ‹iPad› paired with. If
  Sill was set up again on it, forget it here and pair again."; never a plain retry. A row taken by
  the saved Mac's Bonjour name alone (§7.3) is skipped by the reconnect from then on
  (`pinRefusedRows`) without that copy; after a tap, which asked for that Mac, the copy follows the
  Mac's other rows as for a row its tag named.
- **Kind 18 speaks for the session's Mac only when the key of the connection it came on signed it**
  (`DiscoveryPolicy.macInfoNamesSession`, the security review, 2026-09-27): a Mac sends its kind 18
  to every session, an open door's included (and in plaintext at a plain door), so another Mac can
  replay it on a connection of its own. Before, a kind 18 whose signature checked named any session
  as that saved Mac: the panel said "Paired", the record was refreshed and took the look-alike's
  Bonjour name, and a goodbye `removed` from that session then revoked the real Mac. Now such a kind
  18 is shown as an unverified one is, and names, refreshes and renames nothing; over a plain
  connection (DEBUG) nothing is ever named. A goodbye `removed` (and -9825/-9829 on a pinned dial)
  revokes a saved Mac only from a session pinned to that Mac's key, at home or through the remote
  door (`removalRevokes`), never from a plain one or an open one that saw another key.
- **The panel's Away from home group** (HostSettingsPanel.swift:303; :305 at `cea195c`): the
  saved Mac's row reads "Paired" (was "Paired for remote access"); Pair This ‹iPad›… shows only in
  an unpaired session. As built (step 5, `DiscoveryPolicy.awayFromHome`, pure): under "Paired",
  "Connected through Tailscale." on a remote session, "Away from home, Sill reaches Mac mini through
  Tailscale (…)." with Remote Access on, else "To reach Mac mini away from home, turn on Remote Access
  in Sill’s Settings on the Mac." (a Mac paired at home with Remote Access off). An unpaired session
  at home over TLS (there is one only while Require pairing is off) offers Pair This ‹iPad›… whatever
  Remote Access says, since it pairs at the session's own door: "Mac mini lets devices connect without
  pairing. Pair this iPad once to keep connecting if that changes, and to reach Mac mini away from
  home while Remote Access is on. Mac mini shows a code; scan it with this iPad." Over a plain door
  (DEBUG), as before: Pair This ‹iPad›… with Remote Access on, the Remote Access footnote without it.

#### 7.7 Copy on the device (inline; VoiceOver announces each status line, as today)

**Connect screen**

| Where | Text |
|---|---|
| Row words | "Not paired", "Wired", "Update Sill" (§7.3) |
| Status | "Pairing with Mac mini…" · "Pairing with Mac mini over the cable…" · "Paired with Mac mini over the cable." · "Mac mini runs an older Sill. Update Sill on the Mac to connect." · "Mac mini removed this ‹iPad›. Tap it to pair again." · "Mac mini now asks devices to pair. Tap it to pair this ‹iPad›." |
| After an ask | `openOnMac`: "Mac mini didn’t show a code. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then tap Mac mini again." · `locked`: "Unlock Mac mini, then tap it again." · `shown` (as built, step 4, while the card is up): "Mac mini is showing a code. Point this ‹iPad› at it." · nothing answered the ask or a proof (step 4): "Mac mini didn’t answer. Check that Sill is open on it, then tap it again." |

**The home card**

| Where | Text |
|---|---|
| Title | "Pair with Mac mini" (a heading; VoiceOver focus moves to it) |
| Scan line | "Mac mini is showing a code. Point this ‹iPad› at it." |
| Viewfinder | Caption "Point at the code on Mac mini"; spoken "Camera. Point it at the code on Mac mini." |
| Typed | "Type the code Mac mini shows." Field "Code", placeholder "0000 0000 0000", the remote path's code keyboard; [Pair] |
| Links | "Enter Code Instead" / "Scan Code Instead" · "Cancel" |
| Errors, under the field | "A code has 12 digits." · "That code has a typo. Check it against your Mac." · "That code didn’t work. Check the code on your Mac. 4 tries left." · "Mac mini stopped pairing after too many wrong codes. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then tap Mac mini again." · "That code expired. Tap Mac mini for a new one." · "That code no longer works. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then tap Mac mini again." · "Pairing didn’t finish: Mac mini couldn’t show it knows the code. Tap it to try again." (the security review, 2026-09-27: after a stop, or a code closed by the Mac's Cancel, the Mac keeps the device quiet for 10 minutes, so the words send the person to its menu first; "Tap … for a new one" only after an expiry, which quiets nobody; a reason the device does not know shows the Mac's own `message`) |

As built (step 5): the row a tap's ask is waiting on is lit (the app drawer's highlight) while
"Pairing with…" shows; Cancel, Esc or the escape gesture stops the ask or the proof and puts the idle
status line back; the card stays up through "Paired with Mac mini." until the session after it comes
(or its 10 s run out: "Mac mini is saved. Tap it to connect."), and a session that connects leaves no
ask behind. Pair This ‹iPad›… over a stream at home has no row to tap, so its errors are not the
card's: a refused code in the remote path's words ("Mac mini stopped pairing after too many wrong
codes. Choose Pair iPhone or iPad… on your Mac for a new code.", "This code expired. Choose Pair
iPhone or iPad… on your Mac for a new one.", "Mac mini isn’t pairing right now. On your Mac, choose
Pair iPhone or iPad… first."), and "Pairing didn’t finish: Mac mini couldn’t show it knows the
code." · "Mac mini didn’t answer. Try again."

#### 7.8 Layout

The home card is AddMacCard in a home mode, with every layout rule of the remote plan §7.10: the
380 pt leading column, the viewfinder at the column's width × 230 pt, side by side under 520 pt
tall, the top half at 710×1000 (nothing crosses the crease), 48 pt fields, the column to the top
while the keyboard is up. Its typed path has the code field alone, so the collapsed line is "Type
the code Mac mini shows." Esc, Cancel or the escape gesture fold it back to the rows.

#### 7.9 Harness and DEBUG arguments (ContentView.swift's contract comment, and CLAUDE.md)

- `-SillConnectCase` gains `homerows` (a saved Wi‑Fi row, "Not paired", an open door's "Not paired" (since the security review), an unpaired "Wired", a
  Wired row through a USB Ethernet adapter reading "Not paired", "Update Sill", a long name), `homecard`, `homecode`, `homecodeerror`, `homeasking`, `homelocked`,
  `homeopenonmac`, `homerevoked`, `homecabledone` and `pairingrequired`; and, as built (step 5),
  `homeolder` (a tap on an "Update Sill" row: "Mac mini runs an older Sill…").
- `-SillSettingsCase` gains `paired` (Away from home's "Paired") and `openpair` (an unpaired
  session with Pair This iPad…); and, as built (step 5), `pairedoff` (paired, Remote Access off).
- `-SillHomeDoor paired|open|plain`: what a `-SillConnect` address counts as, since an address has
  no TXT record. Default `plain`, today's behaviour, so every existing gate is unchanged. With
  `paired` the address is the one saved Mac when exactly one is saved (dialed pinned, as its row
  would be; a later launch, a move's `to:` address and PR #12's `-SillPathTest` addresses too),
  else an unsaved Mac on a `p=1` door (a tap asks).
- `-SillForgetHomeTLS 1`: clears `homeTLS` on every saved Mac at launch, so the device dials an
  older Sill.app (another branch's build) plainly again (§3.4). DEBUG only, like every argument
  here.
- `-SillServiceType _silltest._tcp`: the browsers look for that type instead of `_sill._tcp`, so a
  test host registered with `SILL_TEST_SERVICE_TYPE` shows as a real row with its TXT record, and
  no real Mac is listed. The simulator enforces NSBonjourServices (H0's P5: a browse for a type
  the Info.plist does not declare fails with -65555 NoAuth, on every launch but the first after an
  install), so the Debug configuration's Info.plist declares `_silltest._tcp` beside `_sill._tcp`
  (a per-configuration plist or a Debug-only build step), and Release's declares `_sill._tcp`
  alone: H1 prints `NSBonjourServices` from both products.
- `-SillCableTest 1`: this device's path counts as the cable for §7.5's check. The simulator has
  no cable of its own: its interfaces and addresses are this Mac's, so without the argument its
  check never passes, even over en14 while a device is plugged into the Mac. With the host's
  `SILL_TEST_CABLE_INTERFACE=en0` (which also lets this Mac's own address through, §4.3) and
  `-SillConnect` to the Mac's own `fe80::…%en0`, the whole cable path runs in the simulator.
- Added in step 4, because the gates drive no UI (no XCUITest; the Simulator tool's taps would ask
  for a device permission a headless session cannot give): `-SillTapRow <name prefix>` taps the
  first network or Direct row so named, once, as soon as it is listed; `-SillHomeCode <digits>` and
  `-SillHomeLink <sill://pair…>` type the code into, or scan the link with, the home card once the
  Mac answers the ask `shown`; `-SillOverlayCode <digits>` runs Pair This ‹iPad›… (kind 21, then
  the code typed) once, on a session at home over TLS. The move and path tests' rows count as the
  one saved Mac under `-SillHomeDoor` (they carry no TXT tag).

---

### 8. TLS on every home connection: what it costs, and the tick

- **The handshake**, once per connection (a tap, a reconnect, a move): 12–20 ms on loopback (the
  remote door, measured), plus one round trip of the link: about 1–2 ms on the cable, 5–10 ms on
  Wi‑Fi, about 75 ms over AWDL. The moves' budgets have room: the wired wait is 2.5 s and a move
  gets 5 s. PR #12's move down (the cable pulled) holds what the device sends until the Wi‑Fi
  connection's first window list (`probeMove`, then `finishMove`), so its hold grows by the
  handshake, some 15–30 ms on Wi‑Fi.
- **The bytes** (H0's P3, Results: NWConnection on loopback with the home door's options, each end
  its own process): paced at 60 fps with 320 KB frames, the Mac pays 0.67 ms of CPU per MB over
  TLS against 0.44 plain, the device 0.72 against 0.40. So Extreme over the cable (150 Mbps at
  60 fps) costs the Mac +0.44 percentage points of a core (1.29 % against 0.85 %) and the device
  +0.61; at 120 fps +1.1 and +1.3; at Balanced (15 Mbps) the difference is below the runs' noise.
  This section first said +0.5 ms per MB and 0.9 % at Extreme, from the remote plan's figure with
  both ends in one process. A frame's last TLS record decrypts in microseconds, so frame age does
  not move.
- **The tick** exists for the device's Wi‑Fi power save: a downlink quiet for a moment lets the
  radio doze, and the next packet waits up to 300 ms (CLAUDE.md, trackpad stutter (1)). Over TLS
  each 14-byte tick is a record of its own. The remote door measured +1.46 percentage points of
  host CPU with a tick every 30 ms, and 5.79 % (TLS, a tick skipped right after anything else went
  out) against 6.08 % (the plain home door with every tick), 60 s at 60 fps (PR #13, step 3, H20).
  H0's P3 finds the record itself cheap: alone, a tick costs the Mac 90 µs over TLS against 75 µs
  plain (the device 68 against 53), 0.05 % of a core more at 33 a second; beside a 60 fps Balanced
  stream every tick together costs about 0.19 percentage points over TLS and 0.17 plain, and
  skipping them brings TLS to 0.76 % against plain's 0.69 % with every tick. So the rule below
  saves about 0.2 points, not 1.5, and H9 measures the whole host. The rules stay:
  - every TLS client, home or remote, skips a tick when something went out within the last 30 ms
    (the remote rule, StreamServer.swift:146): the downlink is exactly as busy as before, and the
    radio stays awake;
  - a device on the USB cable gets no tick at all: there is no radio to keep awake;
  - over Wi‑Fi and Direct the tick stays;
  - the plain door (the CLI's default) keeps every tick, byte for byte.
- **Measured before it counts:** H0's probe P3 (per MB, per record: done, Results), H9 (host CPU,
  frame age), P11 (the `rtt m/M` maxima on a still window over Wi‑Fi as before; on the cable
  without ticks; Extreme at 120 fps over the cable as before).

---

### 9. Timeouts and limits (one table)

| What | Value |
|---|---|
| Home door: accept → admission (TLS, plus a pairing connection's one kind 19) | 10 s |
| Home door: pending connections | 8 in all, 2 per source; 5 of the door's own refusals in 60 s → refused for 300 s (an older Sill's plain tries do not count, §4.4); a paired key clears its source |
| Device-opened pairing windows | one at a time; at most 3 in any 10 minutes; a device whose window was cancelled on the Mac or stopped opens none for 10 minutes (by key and by address); a window that ran out, or that its device withdrew, quiets nobody |
| Pairing window | 300 s, 5 wrong proofs, spacing 1/2/4/8 s, 5 s per source, single use (as today) |
| The ask: kind 20 on the device | within 15 s |
| The cable: keys paired by themselves per iPhone or iPad (a hash of its USB serial number) | 1 while that key stays paired (the same key may pair again; Remove frees the device) |
| Ask lines in the log | at most one a minute per source address |
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
| The iPad restored from a backup | No key (`ThisDeviceOnly`), so its saved Macs are cleared at launch (`knownMissing`); it pairs again, with the code, or over the cable once the old key is removed if that key ever ran a session over the cable (it carries this iPad's serial); the Mac lists the old key until it is removed |
| Sill set up again on the Mac (a new key and recognition key) | Its tag no longer names the saved Mac: its row is an unsaved "Not paired", the old record a Remote row. Pairing again gives "Mac mini" and "Mac mini (2)"; Forget the old one (as in the remote plan) |
| Remove while the device streams on the cable | Goodbye `removed`; the row reads "Wired"; a tap pairs it again over the cable, and the notice shows again. Unplug it to keep it out |
| Remove while it streams on Wi‑Fi | Goodbye `removed`; "Not paired"; a tap asks and the window opens |
| The Mac locked, the cable in | "Unlock Mac mini, then tap it again."; the menu's item |
| Another user's session on the console (fast user switching) | Counts as locked: nothing pairs by itself, no window opens (it could not be seen) |
| Two devices on the cable at once | Two serial numbers: each pairs by itself |
| A new key from an iPhone or iPad that already has one on the list (Sill deleted and installed again with its key gone) | The code window; or Remove the old entry in Settings › Devices, then tap again to pair by itself. Unplugging does not help: the device, not the plug-in, holds the place |
| An iPad on a USB-C Ethernet adapter on the LAN | Its wired interface carries the LAN's address, so its row reads "Not paired" and its ask goes without `cable`; the ask arrives on the Mac's LAN interface, which has no iPhone or iPad above it: the window. A look-alike on that LAN cannot get a proof-less pin. On a link with no DHCP or router the adapter has only link-local addresses too, so the device takes it for the cable: a look-alike on such a link can be pinned as a new Mac (never in place of a saved one, whose rows are dialed pinned), and the real Mac still shows its window |
| An iPhone sharing its connection over USB (Personal Hotspot), or a Mac sharing its own over the cable (Internet Sharing) | The device's end of the cable carries a routable address (172.20.10.1, or the Mac's DHCP one), so it does not claim the cable: the code window. The hotspot's other clients arrive routed, never link-local: never the cable |
| An app on this Mac, or the Simulator, dialing this Mac's own address on the cable interface (the Simulator browses through this Mac's mDNSResponder, so while a device is plugged in its row for the Mac says "Wired"; Sill.log has it at 169.254.178.234 twice on 2026-09-24) | Never the cable: its source is this Mac's own address (§4.3, rule 2), and an IPv4 one never counts. Its ask is from this Mac: `openOnMac` in Sill.app and no menu item, unless a window the Mac's user opened is up |
| Another Mac over USB-C or Thunderbolt Bridge | No iPhone or iPad above the interface: never the cable |
| A stranger asking again and again | One window; after Cancel, expiry or five wrong codes, 10 minutes of quiet per key and address; at most 3 windows in 10 minutes; never the keyboard; never while locked; the menu's item otherwise; one log line a minute per address |
| A device-opened window while the Mac's screen is shared in a meeting | The code could be read. It works only at the home door (this Mac's network, or nearby), within 5 minutes, and only if the real device has not used it; `sharingType = .none` is best effort; "Didn’t ask for this? Click Cancel." |
| An ask while the Mac's user has a window open for pairing someone away | `shown`: the device scans that window's code; the first valid proof wins and the other gets `closed` and asks again |
| Direct Wireless turned off mid-pairing over AWDL | The home door's pending connections on peer-to-peer Wi‑Fi are cancelled with its sessions; the device pairs on the network, or with Direct Wireless on again |
| Require pairing turned on while unpaired devices are connected | Each gets goodbye `pairingRequired`; paired ones stream on; the TXT record says `p=1` |
| Require pairing turned off | Nothing ends; `p=0`; unpaired devices connect without a code, still encrypted |
| The keychain unusable at launch | No home listener: "Devices Can’t Connect", the Devices pane's line; Sill.app keeps running (fail closed) |
| An older device build | Refused at TLS; the Mac's menu says so; the device retries until it is updated (§3.4) |
| A local process over loopback, or dialing one of this Mac's own addresses | Needs pairing like any device while Require pairing is on, is never the cable, and its ask never opens a window or lights the menu by itself (§4.2, step 4). The confused deputy is closed to an app that cannot record the screen; one that can reads the code of any window that is up, and can make one come up by asking from a second address (What stays open). With Require pairing off it is open again |
| A virtual machine on this Mac (the Virtualization framework's NAT, UTM, Docker: vmnet's `bridge100`) | A device on this Mac's network: its ask opens a window (the limits apply); never the cable |
| The Mac's user opens a window (Pair iPhone or iPad…, New Code, Show a Code…) while one a device opened is up | The same window and code become the remote door's too (§4.6): the door starts, the QR code gets its addresses, and a device away can pair; the device that asked at home pairs as before |
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
- Every host pushes one probe frame through the Mac's hardware encoder at start (`EncoderProbe`,
  in the coordinator's `start`), streaming or not, and a host that streams uses it throughout. So
  every host but H2's parity runs and H9 starts with `SILL_TEST_SOFTWARE_ENCODER=1` (the pointer
  plan's §4.10 hook: a `--synthetic` host skips `EncoderProbe` and starts on the software encoder;
  step 2 adds it if that plan has not landed), and the pairing gates never touch the hardware
  encoder. Before H2's and H9's runs, check that Noah's Sill.app is not streaming (the last
  `client …` line in `~/Library/Logs/Sill/Sill.log` is more than a minute old) and keep them under
  60 s; most pairing gates stop at the catalog. No XCUITest, no `simctl io recordVideo`, and never
  the iOS Simulator control tool's `attach` (each records or drives the screen at a higher priority
  than Sill's encoder); photos with `simctl io screenshot` only, taps and text through that tool
  without its panel.
- Registrations only under `_silltest._tcp`; in the simulator `-SillServiceType _silltest._tcp` on
  every launch, `-SillConnect` ones included, so no real Mac is ever a row to tap or to reconnect
  to. AWDL-on tests (H0's P1) under 20 s, and only after the same Sill.log check: AWDL takes the
  Mac's radio off its channel while it is on.
- The door's backoff (5 of its refusals in 60 s → 300 s) now runs at the home door too: every
  gate starts its own host, and those that refuse on purpose (H5) run with
  `SILL_TEST_BACKOFF_SECONDS=5` (existing; `Door` honours it for both doors on a test host).
- Noah's Sill.app runs with Remote Access on and holds port 7455 (`lsof`, 2026-09-25): every test
  host takes any remote port (`SillHost --remote` without a port; the bare app with
  `-remotePort 0`), and every `lsof` check goes by the host's PID, never by port 7455.
- `$T` is a fresh directory per gate; `sillclient.py --identity=$T/…` keeps its key there.

**Test tools.** `Scripts/sillclient.py` gains, each checked before it connects: `--pair-ask[=cable]`
(kind 19 `ask`, with `cable: true` given `=cable`; prints kind 20), `--then-code=FILE` (after `shown`, reads the code from FILE and
pairs over the same door: the CLI's printed code saved by the harness, or the bare app's
`$SILL_TEST_REMOTE_DIR/pairing.code`), `--pair-hold=S` (a `sill-pair/1` connection that sends
nothing for S seconds: a pairing connection still pending) and
`--expect-pair=ok|cable|shown|openOnMac|locked|closed`. `--host=fe80::…%en0` (existing) reaches the
stand-ins.

**Headless (H): no permissions needed.**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). The base's commit (origin/main at the branch point: `cea195c` or later; its host sources are `b50e224`'s); `git archive` it to `$SP/base` and build it. Baselines: `SillHost --synthetic` idle 35 s; with `sillclient.py PORT 5 desktop`; both with `--direct-wireless`, and with `--remote`; the bare app's and the bundle's `-SillRenderPreviews`; the counts of the policy, ledger, fence, remote-rules, AddressList/PairingWindow, OriginPolicy and ClientLink checks. **Probes:** P1, a TLS NWListener registered as `_silltest._tcp` with TXT `r` and `p`: `dns-sd -L` reads both; setting its `service` again with `p` changed shows within 2 s with no "(2)"; the same with `includePeerToPeer` (under 20 s) leaves nothing on awdl0's index. P2, this plan's `cable-probe.swift` on the build machine: with a device on the cable the chain matches the Decision's table; without one no interface is a cable. P3, TLS against plain TCP on loopback through NWConnection: 200 MB each way, and 60 s of 14-byte records every 30 ms; CPU per MB and per record at both ends. P4, the base's `sillclient.py` against a TLS listener: what bytes it gets and when it sees EOF. P5, the simulator app with `-SillServiceType _silltest._tcp` lists a test registration (its Info.plist declares only `_sill._tcp` in NSBonjourServices; should the simulator enforce that, a DEBUG-only declaration, never in Release's plist). P6, `sysctl net.inet.ip.check_interface` recorded (1 on 2026-09-25; the cable rule no longer leans on it) | Files exist; every probe answers, or the plan changes first |
| H1 | Builds: `swift build -c release`; iOS Debug and Release for the simulator, Debug for the iPad (build only) | Only the known warnings |
| H2 | **The CLI byte for byte:** H0's runs on the new build, masked and sorted | Identical. `--pairing` adds exactly its two lines (§5, §4.11), plus two per ask (the core's ask line and the CLI's code line); `--print-cable` exits 0 |
| H3 | **Pure checks**, each with mutants caught: `DoorPolicy` (every row of §4.2: both doors, each origin, each ALPN, Require pairing on and off, paired or not, a window or not, the ask rule's six steps in order: step 2 only with the Mac's rule, `cable: true` and no other key of the device, step 4 for loopback and every one of this Mac's own addresses, and the TEST ONLY skip only on a test host, §4.3); `CableLink` (fixtures: this Mac's en14 and anri0 → a cable; anpi0 and en4 (device mode), en1 (Thunderbolt), en0 (Wi‑Fi), bridge0 → not; a Realtek USB Ethernet adapter (0x0BDA) → not; Apple's USB Ethernet Adapter (0x05AC, "Apple USB Ethernet Adapter") → not; an iPhone (0x05AC, "iPhone") → a cable; another Mac in device mode → not; no product name, no NCM interface → not; a routed source on a cable interface → not; a source that is one of this Mac's own addresses on en14, fe80 or 169.254 (the Simulator's, 2026-09-24) → not; any IPv4 source → not; no serial → not; `deviceID` stable, 22 characters, never the serial); `AskLimits` (one window; 10 minutes of quiet by key and by address; 3 in 10 minutes; expiry and a stop count as unused; the test override); `HomeDoorTXT` (build, parse, an unknown value → required); the device's `rowWord`, `homeDial` and `onCable` (every row of §7.3 and §7.4, DEBUG and Release, `homeTLS`, revoked; fe80 scoped to en2 or anpi0 carrying only link-local addresses → the cable; the same interface with a DHCP or SLAAC address (a USB Ethernet adapter) → not, and its row "Not paired"; the Mac's address one of this device's own → not; IPv4 link-local, Wi‑Fi, AWDL, loopback → not); `SavedMacs` and `PairedDevice` (the new fields; records without them decode) | All pass |
| H4 | **The home door up:** `SILL_TEST_SERVICE_TYPE=_silltest._tcp SillHost --synthetic --pairing` | Its two lines; `dns-sd -t 3 -L "Sill test <pid>" _silltest._tcp local` shows `r` and `p=1`; one listener for its PID (`lsof -p`), no remote door; without `--pairing`, H2 holds |
| H5 | **Refusals at the home door:** the base's `sillclient.py` (plain); `--tls` with an unpaired key on `sill/1`; `--tls` with another ALPN; `SILL_TEST_ORIGIN=vpn`. And `SillHost --print-cable` (read-only) with the iPad plugged in, if it is | Plain: closed within 100 ms, the 7-byte TLS alert and EOF, no Sill byte (H0's P4), counted "from an older Sill"; an HTTP request (`curl http://127.0.0.1:PORT/`): counted "unpaired", no menu item; five plain tries from one address in 10 s, then a paired `--tls` session from it: admitted at once (no backoff, §4.4); unpaired: ready, then a read error (-9825), no Sill byte; another ALPN: the handshake fails; vpn: closed before TLS; one summary line. `--print-cable` names en14 and anri0 as the iPad's cable |
| H6 | **Pairing at home:** `--pair-ask --then-code=…` with the printed code; again with `--pair-url`; then `sill/1` with the same identity | `shown`, and the CLI's ask line; ok with a valid proof_M, over the home door; the session's catalog 2, 16, 18, 4…, 5, 14 and frames. On the bare app with Remote Access off, `-remotePort 0` and `SILL_TEST_ASK_FROM_THIS_MAC=1`, a device-opened window adds no listener to its PID, its `pairing.url` has no `a`, and `pairing.code` is written within 0.5 s of the ask, while `-SillPairAfter`'s window adds the remote door; without the variable the same ask gets `openOnMac` (it comes from this Mac) and no `pairingRequest` in the status. With a device-opened window up, `-SillPairAfter` makes it the remote door's: the remote door's listener appears for the PID, `pairing.url` is written again with the same secret and an `a`, and `--pair-url` over the remote door pairs |
| H7 | **The cable, by its stand-in:** `SILL_TEST_CABLE_INTERFACE=en0` and `SILL_TEST_ASK_FROM_THIS_MAC=1`, the client on the Mac's own `fe80::…%en0` | `--pair-ask=cable` → ok, `method "cable"`, the line, the notice hook, `cableDevice` in `paired.json`; `--pair-ask` without `cable` → `shown`; a second key → `shown` (the same device, serial TEST); the first key again → ok; on the bare app, the first removed (`-SillUnpairAfter`), then the second → ok; `SILL_TEST_LOCKED=1` → `locked`; a 127.0.0.1 client → `shown` (not link-local); without `SILL_TEST_CABLE_INTERFACE`, the same `fe80::…%en0` client → `shown` (this Mac's own address) |
| H7b | **The real rule against this Mac's own addresses**, only while an iPhone or iPad is on the cable (`SillHost --print-cable` says so; skipped and recorded otherwise): `SILL_TEST_SERVICE_TYPE=_silltest._tcp SillHost --synthetic --pairing`, no TEST ONLY variable; `--pair-ask=cable` from this Mac's own `fe80::…%en14` (or `%anri0`) and from its 169.254 address on en14 | `shown` both (the CLI's window is open), never ok, nothing in `paired.json`: what the Simulator and any app on the Mac get. The connections stay inside this Mac; nothing crosses the cable |
| H8 | **The ask's limits,** on the bare app with `-SillCancelPairingAfter`, `SILL_TEST_ASK_QUIET=5` and `SILL_TEST_ASK_FROM_THIS_MAC=1` (its clients are on this Mac), from two sources: `127.0.0.1` and this Mac's `fe80::…%en0` | After a device-opened window is cancelled, that key and that address get `openOnMac` for 5 s, another key from the other address a window; a window stopped by five wrong codes quiets its asker the same way; three windows opened and closed, then the fourth ask `openOnMac`; `pairingRequest` in the status; one line per ask |
| H9 | **TLS cost:** 45 s at 60 fps synthetic (the 60 s rule above) with `sillclient --stats`: the CLI's plain door; the TLS door with §8's tick rule; the TLS door without it | TLS with the rule within +0.5 percentage points of plain (host CPU, `ps`, release) and median frame age within 1 ms; the other run and P3's figures recorded in the Results |
| H10 | **Require pairing,** on the bare app with `SILL_TEST_SERVICE_TYPE`: `-SillSetAfter '3 requirePairing=0; 10 requirePairing=1'` | `p` 1 → 0 → 1 in `dns-sd -L`, no "(2)"; an unpaired `--tls` session admitted between 3 and 10 s, then goodbye `pairingRequired` and EOF within 1 s of 10 s; a paired session streams throughout; one Settings line each; the same port |
| H11 | **Remove:** a paired home session and a paired remote one (the bare app with `-remoteAccess YES -remotePort 0`), then `-SillUnpairAfter` | Goodbye `removed` on both doors within 1 s; "Removed …; closed 2 connections."; the next `sill/1` refused in the handshake |
| H12 | **Direct Wireless over TLS:** `SILL_TEST_PEER_TO_PEER_INTERFACE=en0`, a paired TLS client and a pending pairing connection (`--pair-hold=8`) from the Mac's `fe80::…%en0` | Direct Wireless off: the client disconnected with the existing line and the pending pairing connection cancelled; `p` still in the TXT record after the replacement; the same port |
| H13 | **Fail closed:** the bare app with `SILL_TEST_REMOTE_DIR` holding a damaged `paired.json` (an unreadable directory is only ignored: AppModel falls back to an in-memory identity, and FileIdentityStore sets 0700 again) | No listener; `homeDoor` unavailable in the status; its log line |
| H14 | **The remote door, again:** the remote plan's H6–H13, H15 and H17 against this build (Remote Access on; the bare app with `-remotePort 0`) | As before; with a window the Mac's user opened, an `ask` there is answered `closed` with no try counted (without one the remote door refuses every pairing connection in its handshake, as today) |
| H15 | **Previews,** before and after | Only the Devices pane's samples, the Remote Access pane's line, the three pairing window samples and menu.txt's three items differ (and the samples of a window the Mac's user opened, by §6.3's new first line); look at each |
| H16 | **Hard rules** (grep and diff) | `requirePairing` in none of StreamSettings, HostSettingsChange, DeviceSettings, nor among HostSettings' UserDefaults keys; every door and pairing `SILL_TEST_` read behind `isTestHost`; no `print` of a code or secret in Sources/SillHost; no `assumeIsolated` or `updateConfiguration` there; StreamServer's plain `accept` untouched |
| H17 | **Regression:** the policy, ledger, fence, remote-rules and ClientLink checks; the Direct Wireless swap fallbacks (`SILL_TEST_SWAP_FAIL`) on a TLS host | As before |
| H18 | **The bundle takes no door or pairing hook:** a copy of `.build/Sill.app` whose Info.plist names `me.saffer.sill.h18`, signed ad hoc (so it shares neither the `me.saffer.sill.mac` defaults nor Noah's grants), its executable started from Python with `--synthetic -SillLogFile $T/log -SillQuitAfter 6 -SillPairAfter 1 -SillSetAfter '1 requirePairing=0' -requirePairing NO` and `SILL_TEST_REMOTE_DIR=$T/dir`, `SILL_TEST_CABLE_INTERFACE=en0`, `SILL_TEST_ASK_FROM_THIS_MAC=1` and `SILL_TEST_SOFTWARE_ENCODER=1` (an encoder hook, still honoured) in its environment; `--pair-ask=cable` from this Mac's `fe80::…%en0` to the port in its log meanwhile; `defaults delete me.saffer.sill.h18` afterwards | One "ignored" line per door or pairing variable and per hook; the software encoder in use; nothing written in `$T/dir`; no pairing window; `requirePairing` on in the status; the ask answered `openOnMac` (`locked` while the Mac is locked), never ok |

**Simulator (S):** an iPad simulator of its own (the iPad Pro 13" one is shared with other work),
launch arguments, `simctl io screenshot`, the iOS Simulator control tool's taps and text (never
its `attach`).

| # | Check |
|---|---|
| S1 | **The photo matrix:** every new connect case at 1000x710, 710x1000, 500x710, 710x500, 402x874, 874x402 and 375x667; the home card at the four Duo sizes and at `content_size accessibility-extra-large` (reset afterwards); the two settings cases at the Duo sizes. Nothing crosses y = 500 at 710x1000; "Not paired" and "Update Sill" are never truncated; the title never moves sideways; the card goes side by side under 520 pt. Send Noah the sheet |
| S2 | **A real row:** `SILL_TEST_SERVICE_TYPE=_silltest._tcp SillHost --synthetic --pairing` and the normal app with `-SillServiceType _silltest._tcp`: the row "Sill test ‹pid›" reads "Not paired"; a tap, and the CLI prints the ask's line; the printed code typed into the card → paired, streaming; relaunched, the row reads its method word and connects pinned, with no ask. With an iPhone or iPad on the Mac's cable the row reads "Wired" (the simulator sees this Mac's en14) and the tap still gets the card, never a pairing by itself |
| S3 | **The cable:** the host with `SILL_TEST_CABLE_INTERFACE=en0 … --pairing`, the app with `-SillConnect fe80::…%en0:P -SillHomeDoor paired -SillCableTest 1`: paired with no card, "Paired with … over the cable.", streaming. Without `-SillCableTest` the device asks without `cable` and gets the card (the CLI's window is open), never a pairing by itself: the Mac pairs by itself only for an ask that claims the cable (§4.2). The device's own refusal of a proof-less ok it did not ask for needs a Mac that sends one: a stand-in (a swiftc tool over `RemoteTLS.options` in the server role, on a test port, answering every ask with ok and `method: "cable"`), without `-SillCableTest`: "Pairing didn’t finish…", nothing saved |
| S4 | **Moves over TLS,** after S3's pairing (the one saved Mac, §7.9): `-SillMoveTest 1` and `to:` this Mac's `fe80::…%en0`, and PR #12's `-SillPathTest` cases (merged: up to the cable at this Mac's `fe80::…%en14` while a device is plugged in, down to Wi‑Fi, the connection cut, a loose cable), with `-SillHomeDoor paired`: each move's connection pinned, "Client connected" per hop on the host, the fence and the hold as before; a key removed mid-session ends its move as a failed one |
| S5 | **The ends:** the bare app's `-SillUnpairAfter` while connected → "Mac mini removed this iPad. Tap it to pair again." and "Not paired"; `requirePairing` 0 → 1 with an unpaired session → "Mac mini now asks devices to pair…" |
| S6 | **Older hosts:** the base's `SillHost --synthetic` from `$SP/base` with `-SillConnect` streams as today (DEBUG, plain). The "Update Sill" rows (every plain door in Release; a `homeTLS` Mac's in DEBUG) are H3's pure `rowWord` and `homeDial` checks and S1's `homerows` photo: the harness arguments exist only in DEBUG builds, and a base host is never a Mac the device saw with `p` |
| S7 | **Accessibility, without XCUITest** (the hard rules forbid it; the remote plan ran its S6 as XCUITests): the labels, hints and announced status lines of §7.3 and §7.7 are strings built by the pure functions H3 checks, so H3 checks them too; the headings and focus moves are read in the SwiftUI source at the review and heard with VoiceOver on the iPad (P14) |

**Noah's devices (P):** the iPad mini, and the iPhone as the second device and the hotspot.

| # | Check |
|---|---|
| P1 | **The upgrade.** Install the iPad build first (Debug, the usual route), then Sill.app. The iPad, paired by QR on 2026-09-25, connects at home with no pairing step. The log: "Home door: TLS, pairing required (1 paired)." and "Client connected: …"; Settings › Devices lists the iPad, "last connected just now over Wi‑Fi" |
| P2 | **QR over Wi‑Fi.** Remove the iPad on the Mac; its row reads "Not paired". Typing in another app on the Mac, tap the row: the window comes up in front and the typing goes on. Scan: streaming. Time it (under 20 s) |
| P3 | **The code.** Remove again; tap; Enter Code Instead; the 12 digits: streaming |
| P4 | **The cable.** Remove; plug in; the row reads "Wired"; tap: streaming at once, no code; the Mac's notice; Devices says "over the USB cable"; the iPad's console says what its cable check read ("cable: yes, …") and the host's line names `%anri0` or `%en14`. Pull the cable while streaming: the session goes on over Wi‑Fi (PR #12), still paired; plug it back: back on the cable |
| P5 | **Locked.** Remove; the cable in, lock the Mac (⌃⌘Q); tap: "Unlock Mac mini, then tap it again."; the menu's item; unlock, tap: paired |
| P6 | **Direct at the café.** Direct Wireless on, the iPad on the iPhone's hotspot, the Mac at home in range; Remove first. The Direct row reads "Not paired"; tap: the window; scan; the host logs `%awdl0`. Direct Wireless off: disconnected as before |
| P7 | **An older build.** The iPhone on main's build (or the iPad put back on it): the menu's "An iPhone or iPad Needs Sill Updated"; the device flickers and retries (the known limit); the new build connects at once (its plain tries started no backoff, §4.4) |
| P8 | **Remove while streaming at home:** "Mac mini removed this iPad. Tap it to pair again."; the row "Not paired" (on the cable, "Wired") |
| P9 | **The moves:** plug and pull while streaming, and the move from AWDL to the network: every hop over TLS, a "Client connected" per hop, no connect screen |
| P10 | **A stranger's taps:** the unpaired iPhone taps the Mac; Cancel on the Mac; it taps again: "Mac mini didn’t show a code…" for 10 minutes; the menu's "iPhone Wants to Pair" opens the window on a click |
| P11 | **The cost:** five minutes on a still window over Wi‑Fi, the host's `rtt m/M` maxima as before (ticks still keep the radio awake); the same on the cable, now without ticks; Extreme at 120 fps over the cable, fps and frame age as before; Sill.app's CPU in Activity Monitor against the previous build |
| P12 | **Remote after a home pairing:** pair over the cable only, then away through Tailscale (Remote Access on): the remote session with no further step |
| P13 | **Require pairing off:** the pane's warning; the unpaired iPhone connects without a code; on again: it is disconnected with "Mac mini now asks devices to pair." |
| P14 | **VoiceOver** on the rows ("Mac mini, not paired"), the home card and the Mac's window |
| P15 | **A USB Ethernet adapter**, if one is at hand: Remove first; the iPad on the adapter, on the home LAN, Wi‑Fi off: the row reads "Not paired", a tap gets the code window, and the console says "cable: no, … has 10.128.0.…" |
| P16 | **The iPhone's hotspot over USB:** the iPhone plugged into the Mac sharing its connection, the iPad (removed first) on the iPhone's Wi‑Fi: the iPad's ask arrives routed (a 172.20.10.… or global source, never `fe80`) and gets the code window; the iPhone's own ask claims no cable (its end carries 172.20.10.1) and gets it too |

---

### 12. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

0. **Preflight** (no commit): fetch; branch from origin/main, `cea195c` or later: PR #11
   (`b50e224`) and PR #12 (`cea195c`) merged the day this plan was written. The parity baseline is
   that base's output, not `ba91136`'s (PR #11 changed the host's encoder lines; PR #12 changed no
   host file). H0 and its probes.
1. **"Protocol: home pairing's values, the TXT key and the door policy"** — Remote.swift's `ask`,
   `PairRequest.cable`, reasons, `PairResult.method` and `pairingRequired`; `HomeDoorTXT`; the RemoteTLS overload; the
   pure `DoorPolicy`, `CableLink` and `AskLimits` (host) and `rowWord`, `homeDial`, `onCable`
   (device); the SavedMacs fields. Gates: H1, H3, H17. About 500 lines, and 700 of checks.
2. **"Host: the home door speaks TLS, pairs at home and over the cable"** — `Door` out of
   RemoteServer; StreamServer's three modes; InterfaceSnapshot's IOKit read; SessionLock;
   RemoteAccess's ask, the cable's devices, limits, Require pairing, Remove on both doors, home "last
   connected"; the coordinator, HostConfig, HostStatus; the tick rule; the CLI's `--pairing` and
   `--print-cable`; `sillclient.py`'s flags; `SILL_TEST_SOFTWARE_ENCODER` unless the pointer work
   has landed it. Gates, with the CLI and `sillclient.py`: H1, H2, H4, H5, H6 (the CLI's part),
   H7, H7b, H9, H12, H14, H16, H17. About 1,100 lines; the largest step. Sill.app built here
   keeps a plain door (AppModel passes `homePairing: true` only at step 3), and on a plain door
   kind 21's windows stay the remote door's (§4.6), so it behaves as main's.
3. **"Sill.app: Settings › Devices, device-opened windows, the cable notice and the menu"** — with
   Require pairing in the identity store and the bundle's refusal of test hooks (§4.3, §6.5, §6.6).
   Gates, with the bare app: H1, H6 (the bare app's part), H7 (Remove frees the device), H8, H10,
   H11, H13, H15, H18. About 550 lines, much of it moved from RemoteAccessPane.
4. **"iOS: TLS on every home connection, and pairing at home"** (the model) — the builder on every
   dial site, PR #12's included; `p` on rows; the session gate at the first list; revoked;
   `homeTLS`; the ask, the cable's ok, the two proofs through the row; the goodbyes. Gates: H1
   (iOS), H3 (device), S2–S6. About 700 lines.
5. **"iOS: rows, the home card and the panel"** (the UI) — Gates: S1, S7, S2 again. About 400 lines.
6. **"docs: Pairing at home"** — this plan's Results; CLAUDE.md (the Current step, Layout, Build and
   run: `--pairing`, `--print-cable`, the TEST ONLY variables `SILL_TEST_CABLE_INTERFACE`,
   `SILL_TEST_LOCKED`, `SILL_TEST_ASK_QUIET`, `SILL_TEST_ASK_FROM_THIS_MAC` (and
   `SILL_TEST_SOFTWARE_ENCODER` if step 2 added it), the harness lines, `-SillForgetHomeTLS`, and
   that Sill.app itself takes no door or pairing hook); the README's Pairing section (at home, over
   the cable,
   Require pairing, the CLI's plain door, resetting).
7. **Review and hand-over.** Three lenses: security and protocol (the verify blocks, the cable rule,
   no proof-less ok off the cable, no downgrade, no secret in a log, which hosts honour test hooks,
   where Require pairing is kept); listeners and concurrency (one `Door` behind two listeners, the
   swap with TLS, pending cancellation, the TXT update); the device UI and accessibility at every
   size. A "Review fixes" commit if needed; adversarial reruns of H5–H12 (H7b included), H18 and
   S2–S5; then P1–P16 to Noah. **Stop there.**

**What lands first, so Noah's devices keep working through the branch:**
- Nothing reaches his devices until he installs a build. Sill.app's door changes only at step 3
  (step 2's core keeps a plain door's kind 21 as today, §4.6), the iOS app at steps 4–5, and the
  CLI's default door never changes, so every older gate and tool keeps working throughout.
- PR #12 is in (`cea195c`): step 4 puts the builder on its dial sites (§7.1). PR #11 is in too:
  the line numbers here, at `ba91136`, have moved in StreamCoordinator (`.pairingWanted` is at
  :594), HostStatus and StatusText, and in StreamClient, SessionLink and DiscoveryPolicy (§7.1 and
  §7.2 give PR #12's). The `remote-pacing` fix touches only the remote branch of `broadcast`:
  either order.
- Branches cut before this change (`update-notice`, `encoder-two-in-flight`, `remote-bundle`, the
  pointer work) build a Sill.app with a plain home door. Once his iPad has seen Sill.app with `p`,
  such a build reads "Update Sill" on it (§3.4): merge this change into a branch before installing
  its Sill.app, or launch the iPad build once with `-SillForgetHomeTLS 1`.
- `update-notice` (main's since PR #18): its DeviceGate holds a ready connection at both doors until
  the device's hello (kind 23). Whichever lands second puts the gate inside `Door`, one place for
  both doors; the hello goes first on every TLS session connection and never on a pairing
  connection, as that branch already has it at the remote door. Builds from before either change
  nothing here: they cannot speak TLS at home, so no goodbye, `update` or `pairingRequired`, ever
  reaches them. This branch landed second: the merge with main put the gate in `Door` (Results,
  "The merge with main").
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
  20 and 22 grow only by string values and two optional fields (`PairRequest.cable`,
  `PairResult.method`).
- **A proof-less ok** (kind 20 with `method: "cable"`) is sent only for a connection the Mac judged
  to be on its cable (an IPv6 link-local source under an iPhone or iPad, never one of the Mac's
  own addresses) whose ask said `cable: true`, and accepted only for the device's own such ask.
- **An ask from this Mac itself** (loopback, or one of its own addresses) never opens a window
  and never lights the menu.
- **No downgrade:** a Release device never dials plain; no device dials a `homeTLS` Mac plain.
- **Apple frameworks only:** Network, Security, CryptoKit, CommonCrypto, IOKit, CoreGraphics,
  SystemConfiguration. No PAKE package.
- **Secrets:** the code and the QR secret are never in a line of Sill.app's log, the status, kind 16
  or 18, or a TXT record. The trust list lives in the keychain (the app), memory (the CLI) or a 0700
  test directory, never in UserDefaults.
- **The modal-loop rule** in the app; errors inline; a device-opened window never activates Sill.
- **Tests never touch** Noah's Sill.app, `/Applications`, `me.saffer.sill.mac`, his login keychain or
  his iPad; no XCUITest, `recordVideo` or Simulator-tool `attach`; TEST ONLY hooks that bear on the
  doors or pairing are honoured only by test hosts: not advertising and not a `.app`'s executable
  (§4.3).
- **Require pairing lives with the trust list** (the identity store), never in UserDefaults, and
  the bundle takes no argument or hook that changes it.
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
   the Mac (B). With A an app on this Mac that records the screen can make a code come up by
   asking from a virtual machine it runs, or from another device, and read it (What stays open);
   A′ or B take that away, for one more click whenever a device pairs over Wi‑Fi.
2. **The typed code stays 12 digits,** as for remote access. Default: **yes.** Six would need a PAKE
   that Apple's frameworks do not have.
3. **The cable pairs only while the Mac is unlocked** (and your session is on the console). Default:
   **yes.**
4. **One key per iPhone or iPad over the cable** (by a hash of its USB serial number, learned from a
   pairing or a session over the cable): a different key from the same device gets the code window
   until the first is removed. Default: **yes.** Per plug-in, as first drafted, freed the place at
   every plug-in, and Sill never asks again once paired, so whichever other app on the device
   asked first would pair itself.
5. **A notice for every pairing over the cable** (10 s, with Remove). Default: **yes.**
6. **Require pairing off means TLS for anyone at home** (and for any app on this Mac), not today's
   plain door. Default: **yes.**
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
    it pairs by itself (a Wired row through a USB Ethernet adapter says "Not paired"). Default:
    **yes.**
16. **An ask from this Mac itself never opens a window or lights the menu by itself** (the
    Simulator and local tools pair with a window you open from the Sill menu), so an app that can
    record the screen cannot simply ask, read the code and take control of the Mac through Sill; it
    would need a second address (question 1). Default: **yes.**
17. **The device claims the cable only when its end carries nothing but link-local addresses,** so
    an iPhone sharing its connection over USB, or an iPad on a Mac that shares its own, gets the
    code window instead. Default: **yes.**
18. **Require pairing is kept with the trust list, and Sill.app itself takes no test hook that
    bears on the doors or pairing** (`SILL_TEST_REMOTE_DIR` and the like, `-SillSetAfter`,
    `-SillPairAfter`): any app could otherwise turn pairing off, or pair itself, through a Sill.app
    it starts. Tests use the bare binary and the CLI, as they already do; the encoder's test
    variables still work on Sill.app. Default: **yes.**

---

## Results (implementation, 2026-09-25, branch `home-pairing`)

`$SP` below is `scratchpad/home-pairing/0` in the implementing session's scratchpad; every script,
log and photo named here is there.

### Step 0: the merge and H0

**The merge.** origin/main `1f3072a` (PRs #11, #12, #14 and #15) merged into this branch with no
conflict: the branch had only this plan. The base is therefore `1f3072a` (the plan allowed
`cea195c` or later): its host sources equal `b50e224`'s, and its iOS sources are `cea195c`'s plus
PR #14's connect-screen footer
(`SillLinks.swift`, the privacy manifest, `ITSAppUsesNonExemptEncryption`). `swift build -c
release` passes with only the old CaptureProbe warning, and the iOS Debug build for the simulator
with only the old `StreamClient` capture warning.

**Baselines** (the base is `git archive 1f3072a` in `$SP/base`, built there):
- The CLI (`$SP/baseline/baseline.py`; raw, timestamped and masked-and-sorted logs in
  `$SP/baseline/logs`): `SillHost --synthetic` idle 35 s and with `sillclient.py PORT 5 desktop`,
  each plain, with `--direct-wireless` and with `--remote` (any port). Noah's Sill.log was read
  before every host and every 2 s while it ran: idle throughout. This branch's merged build gives
  the same output, masked and sorted: idle identical; with the client identical but for the last
  `[1s]` line, which has a `net.tick` count or not by whether a tick fell in the last partial
  second, so H2 compares without the `[Ns]` lines too. `--remote` prints a fresh code and link per
  run: the `.masked` files replace the link with `<link>` and mask digits.
- Previews: the bare binary copied to a fixed path, `$SP/previews/bin/SillMenuBar`, because the
  General pane shows where it runs from; and the bundle as a copy of make-app.sh's
  `.build/Sill.app` with `CFBundleIdentifier` `me.saffer.sill.h0previews` and `CFBundleVersion`
  `H0`, signed ad hoc, at `$SP/previews/Sill-h0.app`, so no run reads `me.saffer.sill.mac` and
  the General pane's build number never differs. 80 files each (`bare-base`, `bundle-base`, with
  their `shasum` lists); the merged build's bare 80, rendered from the same path, equal the
  base's byte for byte. H15 renders its "after" from the same two paths.
- The pure checks (`$SP/checks/run.sh WT OUT`: the newest harness of each, as the
  `github-actions` session collected them for `Tests/checks/`, unchanged), against the merged
  tree: the discovery policy 286, the ledger 90, the fence 14 of 14 modes, remote-rules 64,
  AddressList and PairingWindow 41, OriginPolicy 66, ClientLink 89; also the pairing window's
  address rule 80 and the protocol 188 plus its 8 cross-checks. All pass.

**P1, the TXT record** (`$SP/probe`: one swiftc tool over StreamProtocol's own RemoteTLS,
RemoteIdentity and StreamMessage; `$SP/p1`). A TLS 1.3 NWListener with RemoteTLS's server options
over the home door's TCP options, registered as `_silltest._tcp` "Sill probe ‹pid›" with TXT `r`
and `p=1`; 3 s after ready its `service` is set again with `p=0` and a fresh `r`, 4 s later with
`p=1` and the same `r`; cancelled at 11 s.
- The update is in place. `dns-sd -B` saw one Add per interface at the start and one Rmv per
  interface after the cancel (1.1 s later), nothing in between, and never a "(2)". The listener's
  `serviceRegistrationUpdateHandler` reported the first registration and nothing for either
  update.
- `dns-sd -i ‹if› -L` on lo0, en0, en14 and anri0 saw each new record 1.00 s after the set; fresh
  one-shot lookups on each interface read whichever record was current, and after the cancel
  found nothing.
- With `includePeerToPeer` (after the Sill.log check; AWDL on for 19.3 s by the kernel's own
  lines, its tail included): the registration also on awdl0 (index 16); the updates reached awdl0
  0.02 s and 1.0 s after the sets; the cancel removed the awdl0 copy with the others, and a fresh
  `dns-sd -t 3 -includeAWDL -B` found nothing. The kernel counted ValidSvc 0 → 1 (the browse) → 3
  (the registration) → 1 → 0, with "Enabling AWDL due to Mdns" and "Disabling AWDL due to no
  services and no active sockets"; nothing left behind.

**P2, the cable** (the plan's `cable-probe.swift`, `probe2.swift` and `timing.swift`, unchanged,
read-only; `$SP/p2`). The iPad was still on the cable, the same plug-in as the review's (sessionID
4854277126715): en14 `IOEthernetInterface ← AppleUSBNCM11Data ← AppleUSBNCM11Control ←
IOUSBHostInterface (class 2/13) ← IOUSBHostDevice "iPad"` (0x05AC, 0x12AB, the serial present,
24 characters), anri0 the same through `AppleUSBHostNCMRestrictedEthernetInterface`; the iPad's
interfaces PTP@0, Apple USB Multiplexor@1, NCM Control@2 and Data@3, NCM Control@4 and Data@5;
its neighbours `fe80::18fe:abff:febb:459f%anri0` and `fe80::18c2:af60:ec0d:47ea%en14`; this Mac's
anpi0–2 and en4–en6 under `AppleT8112USBXDCI`, en1–en3 under Thunderbolt, en0 under PCIe: no USB
host device. One interface's ancestry read takes 0.165 ms (median of 50; at most 0.60 ms). The
session is unlocked (`kCGSSessionOnConsoleKey` 1, no lock key). NWPathMonitor's default path
listed only en0 and utun6, the default route's, never the cable. Not run: the half of P2 with
nothing plugged in (unplugging the iPad is Noah's).

**P3, what TLS costs** (`$SP/probe` in `serve` and `dial` modes, each end its own process, CPU from
`getrusage` between `.ready` and the last byte; `$SP/p3`, `summary.txt`). Loopback, the home door's
TCP options and service class on the Mac's side, the device's on the other, RemoteTLS's options on
both; the receiver reads a 14-byte header, then its payload, as the device does. MB = 10⁶ bytes;
medians of 3 (bulk) or 2 (paced).

| Run | Mac TLS | Mac plain | Device TLS | Device plain |
|---|---|---|---|---|
| 200 MiB Mac → device, unpaced, 32 KiB messages (ms per MB) | 0.73 | 0.44 | 1.33 | 1.06 |
| the same, 320 kB messages | 0.39 | 0.25 | 0.45 | 0.24 |
| 200 MiB device → Mac, 32 KiB (the Mac receives) | 1.38 | 1.03 | 0.73 | 0.33 |
| the same, 320 kB | 0.47 | 0.22 | 0.40 | 0.21 |
| Extreme: 320 kB at 60 fps for 20 s (ms per MB; % of a core) | 0.67; 1.29 % | 0.44; 0.85 % | 0.72; 1.39 % | 0.40; 0.78 % |
| Extreme at 120 fps for 10 s (% of a core) | 2.59 % | 1.49 % | 2.73 % | 1.40 % |
| Balanced: 32 KiB at 60 fps for 20 s (% of a core) | 0.47 % | 0.53 % | 0.48 % | 0.53 % |
| 2,000 ticks (14 bytes) every 30 ms, nothing else (µs per tick) | 90 | 75 | 68 | 53 |
| Balanced at 60 fps and a tick every 30 ms, 30 s (% of a core) | 0.95 % | 0.69 % | 0.95 % | 0.69 % |
| the same, a tick skipped within 30 ms of a send (all were) | 0.76 % | 0.52 % | 0.81 % | 0.53 % |

At Balanced the two runs of each kind disagreed by more than TLS's share, so there it is below
the noise. The plan's §8 said +0.9 % at Extreme and 1.9 % at 120 fps from the remote plan's figure;
measured: +0.44 and +1.1 points on the Mac, +0.61 and +1.33 on the device. A tick record costs
15 µs more over TLS at each end; the remote door's +1.46 points for ticks (H20) is not their own
cost. §8 now says so; its rules are unchanged, and H9 still measures the whole host.

**P4, an older build at a TLS door** (`$SP/p4`: `p4.py` and `p4b.py` against the probe's TLS
listener with the home door's options, which fails and cancels a connection as RemoteServer does;
main's `sillclient.py` from `1f3072a`, and a raw client that sends what main's device sends).

| Client (plain unless named) | The door | The client |
|---|---|---|
| main's `sillclient.py PORT 5 desktop` (kind 6 first), also with `--stats --fps=60` | `.failed(-9836)` 0.4–0.7 ms after the accept, cancelled | 7 bytes, `15 03 01 00 02 02 46` (a TLS alert: fatal, protocol_version), then EOF; it prints "EOF from host at 0.00s", 0 frames, exit 0 |
| main's device: its viewport (kind 9) at once | -9836 | the same 7 bytes 0.7 ms after its send, EOF 0.3 ms later |
| main's device before its viewport: its first ping (kind 10) at 0.25 s | nothing until the ping, then -9836 | the same, 0.1 ms after the ping, then EOF |
| kinds 8, 12, 15, 17, 19, 21 or 23 (the update-notice hello) first | -9836 within 2 ms of the accept | the same 7 bytes and EOF, within 5 ms of its send (one at 11 ms) |
| sends nothing | waits; `-9816` only when the client closes (3 s here) | nothing; the Door's 10 s admission deadline bounds it |
| an HTTP request | -9858 | nothing, EOF |
| TLS 1.2 only | -9836 | the protocol_version alert |
| TLS 1.3 without a client certificate | -9863 | the handshake ends, then the certificate_required alert |

Main's device reads the 7 bytes and EOF as its 14-byte header read ending short with
`isComplete`, which is `connectionLost`: the Mac gone, the 2 s retry. §3.3, §3.4 and H5 now say
so, and §4.4 counts only -9836 as "from an older Sill" (-9858 is never a Sill build).

**P5, the simulator and NSBonjourServices** (`$SP/p5`). The `-SillServiceType` argument does not
exist before step 4, so a scratch copy of this branch's iOS app browsed `_silltest._tcp` in place of
`_sill._tcp`, its Info.plist unchanged (only `_sill._tcp`), on a simulator of its own ("iPad
home-pairing H0", `8E83D7DE-94BD-4608-BEAB-8E8C66D28EC0`, iOS 27.0, shut down after), while the
probe registered "Sill probe ‹pid›". The first launch after each of two installs listed it
("Sill probe 15413 … Wired, seen on anri0, lo0, en0, en14": the simulator browses through this
Mac, so the iPad on the cable makes it "Wired"); both later launches got "Browse failed: -65555:
NoAuth" and no row (`connect.png` and `connect4.png` with the row, `connect2.png` and
`connect3.png` without). The simulator enforces it, so §7.9 now puts `_silltest._tcp` in the Debug
configuration's NSBonjourServices only.

**P6.** `net.inet.ip.check_interface` 1 and `net.inet6.ip6.check_interface` 1 (macOS 27.0,
26A428), as on 2026-09-25 afternoon; the cable rule does not lean on them.

**What H0 changed in this plan:** §3.2 and §4.5 (5) (the update is in place and fires no
registration callback), §3.3 (what a plain client and other clients get; the cost), §3.4 (the
first row), §4.4 (only -9836 is an older Sill; -9858 counts as unpaired), §7.9 (the Debug-only
NSBonjourServices entry), §8 (the measured cost of the bytes and the tick) and H5 (the alert, and
an HTTP request).

### Step 1: the protocol and the pure policies

`$SP` here is `scratchpad/home-pairing/1`: the checks are in `$SP/checks` (`run.sh` runs every one,
its mutants, the wire probe and step 0's checks; outputs in `$SP/out`). No host was started.

**What landed.** StreamProtocol: `PairRequest.ask` and `.cable`, `PairResult`'s reasons `shown`,
`openOnMac` and `locked`, `.method` and its one value `PairResult.cable`, `Goodbye.pairingRequired`
(Remote.swift); `HomeDoorTXT` (Pairing.swift); `RemoteTLS.parameters(tls:tcp:peerToPeer:)`, which
the remote door's builder now calls with its own TCP options and no peer-to-peer, as before. The
host: `DoorPolicy.swift`, `CableLink.swift`, `AskLimits` (PairingWindow.swift), `IPBytes.unmapped`
and `.unscoped` (OriginPolicy.swift), `PairedDevice.cableDevice` and `.displayMethod`. The device:
`DiscoveryPolicy`'s `rowWord`, `homeDial`, `onCable` and `carriesOnlyLinkLocal`; `SavedMac.homeTLS`
and `.revoked`, and `SavedMacs.adding` keeping `homeTLS`. Nothing calls the new rules yet (step 2
wires the host, step 4 the device), so nothing a device or the CLI sees has changed.

**H1.** `swift build -c release` from an empty scratch path: only the old CaptureProbe warning.
iOS Debug and Release for the simulator and Debug for `generic/platform=iOS` (build only,
unsigned; the iPad was not touched): only the old `StreamClient` capture warning.

**H3**, each check with its mutants (`$SP/out`): DoorPolicy 104 checks and 41 of 41 mutants
caught (both doors × each origin; both doors × 7 ALPNs × every trust, 1,792 verify-block and
7,168 `.ready` combinations against §4.2's table; the ask rule's 768 combinations against its six
steps; the -9836 rule; the menu never lit from this Mac; every one of a fixture Mac's own
addresses, v4-mapped and with the kernel's embedded scope; the test hooks only on a test host);
CableLink 40 and 20 of 20 (this Mac's en14 and anri0 from H0's P2, an iPhone, device-mode
ports, Thunderbolt, Wi-Fi, bridges, Realtek and Apple USB Ethernet adapters, another Mac, no NCM,
no name, no serial, routed and IPv4 sources, this Mac's own fe80 and 169.254 on en14 (the
Simulator's), the stand-in; `deviceID` against Python's hashlib, 22 characters, never the serial);
AskLimits 27 and 15 of 15; the records 20 and 10 of 10 (a trust list and saved Macs from before
the fields decode and re-encode byte for byte; 1f3072a's types read the new records); the device's
rules 61 and 31 of 31 (all 384 `rowWord` and 96 `homeDial` combinations against §7.3 and §7.4,
the word agreeing with what a tap does in all 384, no reconnect ever asking, no Release or
`homeTLS` plain dial, the cable check's cases, the VoiceOver labels and hints); the protocol's
new values 39 and 19 of 19: 291 checks, 136 of 136 mutants.

**H17.** Step 0's checks against this tree, unchanged: the discovery policy 286, the ledger 90, the
fence 14 of 14 modes, remote-rules 64, AddressList and PairingWindow 41, the pairing window's
address rule 80, OriginPolicy 66, ClientLink 89, the protocol 188 and its 8 cross-checks.

**The wire** (`$SP/checks/wire`). Every payload of kinds 18–22 as it goes out today, the pairing
link, the tag, both proofs and a framed goodbye, built against 1f3072a's StreamProtocol and this
one: 50 lines byte for byte identical with `SWIFT_DETERMINISTIC_HASHING=1`, and identical in
canonical form in runs with random hash seeds; `{"reason":"quit"}` is `{"reason":"quit"}`.
1f3072a's types read every new message (an ask with and without `cable`, the cable's ok, `shown`,
`openOnMac`, `locked`, `pairingRequired`) as this build does, the new key ignored.

**Learned.**
- JSONEncoder (`Wire.encode`) writes an object's keys in an order that follows the process's hash
  seed: `pairResult ok` came out in 3 orders in 3 runs. The plan's examples (§3.1) show the keys,
  not their order; the checks compare JSON canonically, and the probe with deterministic hashing.
- NWTXTRecord's `dictionary`, and its subscript, leave out a key without a value (DNS-SD's boolean
  attribute): `HomeDoorTXT.door(_: [String: String])` would read a bare `p` as a plain door.
  `HomeDoorTXT.door(_: NWTXTRecord)` reads the entry (a bare or empty `p` reads as "1"); step 4's
  rows read `p` through it. Its subscript is case-insensitive; the dictionary form takes `p`, else
  `P`.

**Deviations from the sketches (the rules are §4.2's, §4.7's and §7's).**
- `DoorPolicy.ask` takes the Mac's rule and the ask's claim as two arguments (`cableSeen`,
  `cableClaimed`) where §4.2 had `onCable`, so H3 checks "step 2 only with both".
- `AtReady.pairing` carries no set of methods: `DoorPolicy.pairing(_:method:)` says how the one
  kind 19 is treated (home: `ask` → the ask rule; remote: `ask` → `closed`, no try counted; `qr`,
  `code` and any other method → the window, which counts an unknown one as a wrong proof, as the
  remote door always has).
- `Trust.hasKey`: RemoteServer's "no fingerprint, no trust" moved into the policy, so a peer
  without a P-256 key is refused at home even with Require pairing off.
- Added, as pure functions of the plan's rules so the checks reach them: `refusalBeforeStart`,
  `handshakeRefusal` (§4.4), `reason`, `menuRequest` (§4.10), `isFromThisMac`, `otherKeyOfDevice`,
  `isTestHost` and the readers of `SILL_TEST_ASK_FROM_THIS_MAC`, `SILL_TEST_CABLE_INTERFACE` and
  `SILL_TEST_ASK_QUIET`, each honoured only with `testHost`; `AskLimits.quietSince` (the log's
  "closed 3 minutes ago") and `.quiets`; `RowWord`'s labels and hints (§7.3, S7),
  `updateSillStatus` (§7.4), `HomeDial.waitForTap` (a reconnect never asks),
  `carriesOnlyLinkLocal` (the row's cable), `SavedMacs.adding` keeping `homeTLS` (a pairing from
  away after a removal must not undo "no downgrade"), `HomeDoorTXT.door(_: NWTXTRecord)` (above).
- `DoorPolicy.maxRemoteSessions` repeats RemoteServer's 8 until step 2's Door uses it.
- `SILL_TEST_SOFTWARE_ENCODER` stays step 2's, as §12 orders; step 1 started no host.

**What step 1 changed in this plan:** §3.1 (the examples' key order), §3.2 (the record reader),
§4.2 (the sketch: `Trust.hasKey`, `AtReady.pairing`, `pairing(_:method:)`, the ask's two cable
arguments and the helpers) and §7.3 (`p` read from the record).

### Step 2: the host

`$SP` here is `scratchpad/home-pairing/2`: the gates (`gates.py`, `h2.py`, `h9.py`, `harness.py`, and
`remote-gates/` with PR #13's scripts), their logs (`logs/`, `h2/`) and the checks (`checks/`,
`checks-full/`, `regression/`). Every host but H2's and H9's (and H15's home half) ran with
`SILL_TEST_SOFTWARE_ENCODER=1`; H2, H9 and H15's home half ran on the hardware encoder only while
Noah's Sill.log said idle and no other session's host ran, re-checked every 2 s. One host of this
step at a time, each started after any other session's host had ended (another session's parity
batch ran beside this work and aborts a run when a host starts beside it).

**What landed.**
- `Door` (Door.swift): RemoteServer's admission, moved and shared: `Door(.remote)` owned by
  RemoteServer, `Door(.home)` by StreamServer, both driven by DoorPolicy (the origin before start,
  the verify block, `.ready`, the one kind 19, handshake refusals). The home door's summary line;
  -9836 counts "from an older Sill" and marks `olderDeviceAt`, never toward the backoff. A home
  attempt carries its address with its scope, whether it comes from this Mac itself (getifaddrs
  read afresh), and its cable device (CableLink over the arrival interface's IOKit ancestry, read
  afresh). RemoteServer keeps the listener's life (the port, the 30 s retry) and its lines.
- StreamServer: `HomeDoorMode` `.plain` (as before), `.tls` (the Door's TLS options over the home
  door's own TCP; a Direct Wireless replacement rebuilds the same mode), `.closed` (no listener, one
  line; the CLI exits 1 as when its listener fails). `serve` registers a TLS home session with its
  link, which then follows the path; `ClientRoute.home(origin, peer:)`; the tick rule (a TLS client
  skips a tick within 30 ms of a send, and one on the cable gets none); `updateService()` for `p`;
  Direct Wireless off also cancels the home door's pending connections on peer-to-peer Wi-Fi;
  `closeSessions` over both doors (Remove, Require pairing).
- InterfaceSnapshot: `readCable` (read-only IOKit), `cableCandidates`, `ownAddresses`. SessionLock
  (CGSession; `watchNotifications()` for the app; SILL_TEST_LOCKED). CableReport (`--print-cable`).
  TestHooks: one "… ignored" line for each door or pairing variable set on a host that does not
  honour them (the test-host rule now also gates SILL_TEST_SERVICE_TYPE).
- RemoteAccess: the ask (the rule, its line at most once a minute per address, the menu's request,
  5 minutes, a "showing" one ending with its window); pairing by itself over the cable (saved first,
  the line, `onCablePaired`; a key already on the list gets the ok with nothing else); windows a
  device opened (the home door's alone: no remote door, no address in the link, offered at once;
  AskLimits when one closes unused; the Mac's user opening a window over one makes it the remote
  door's too, offered again with addresses); kind 21 at a TLS door through the ask rule's steps 1
  and 3–6; Require pairing (`p` in place, goodbye `pairingRequired` to the unpaired sessions); Remove
  on both doors; "last connected" at home; the cable's device learned once from a session; the
  status's `homeDoor`, `pairingRequest`, `olderDeviceAt` and `Pairing.open(byDevice:)`;
  `storedRequirePairing()` and `saveRequirePairing(_:)` for step 3.
- HostConfig `requirePairing` (on in `standard`; absent from the wire and DeviceSettings);
  IdentityStore's `loadRequirePairing()` and `saveRequirePairing(_:)` (the keychain's
  `require-pairing` item, memory, the test directory's `require-pairing` file); TrustSnapshot's
  `requirePairing` and `remotePairingOpen`; the coordinator's `homePairing` and `testHooks` (their
  defaults keep Sill.app's call as it was); `SILL_TEST_SOFTWARE_ENCODER` (the pointer plan's §4.10
  hook and lines; it also keeps the re-check off, so the hardware is never touched).
- The CLI: `--pairing` and `--print-cable`. `sillclient.py`: `--pair-ask[=cable]`, `--then-code=FILE`,
  `--pair-hold=S`, `--expect-pair=R`.
- Sill.app: only what the core's new values need to compile (its HostSettings passes
  `requirePairing`, the pairing window's `.open` pattern and samples). Its home door stays plain
  until step 3.

**H1.** `swift build -c release` from an empty scratch path: only the CaptureProbe warning. iOS Debug
and Release for the simulator and Debug for a generic device (build only, unsigned; the iPad was not
touched): only the `StreamClient` capture warning. No iOS file changed, and StreamProtocol by one
comment.

**H2** (`h2.py`). Idle 35 s and with the base's `sillclient.py PORT 5 desktop`, plain, with
`--direct-wireless` and with `--remote`: identical to step 0's base logs, masked and sorted, without
the `[1s]` lines, and in full but for client-dw's last partial second (a `net.tick` count, as step 0
found). `--pairing` adds exactly "Home door: TLS, pairing required (N paired)." and "Pairing
required for this run (TLS on the home door). Pair with N N N or sill://pair?<link>".
`--print-cable` exits 0.

**H4.** Its two lines; `dns-sd -L` reads `r` and `p=1` on every interface; one listener for its
PID; no code in any core line.

**H5.** (a) A plain Sill message: `15 03 01 00 02 02 46` 1.5 ms after it, then EOF, no Sill byte;
the base's `sillclient.py` reads EOF at once, 0 frames; "1 from an older Sill (not TLS)". (b)
`curl http://127.0.0.1:PORT/`: 000 in 1.7 ms, "1 unpaired". (c) Five plain tries from 127.0.0.1,
each the alert, then the ask, the code and a session from the same address, admitted at once with
the real 300 s backoff. (d) An unpaired key on `sill/1`: TLS up, then certificate_unknown on the
first read, no Sill message, "1 unpaired". (e) ALPN `h2`: the handshake fails, "1 unpaired". (f)
`SILL_TEST_ORIGIN=vpn`: closed with no byte in 0.9 ms, "1 through a VPN". One summary line each.
`--print-cable` names en14 and anri0 as the cable to the iPad (plug-in 4854277126715).

**H6** (the CLI's part). The ask → `shown`; the code → ok with a proof_M that checks; the core's
ask line and the CLI's "Pairing: H6 iPad (sillclient) asked; code …"; "Paired … from 127.0.0.1,
with the code."; the same by the link (`--pair-url`, pinned to `k`); then `sill/1` with the first
identity: pinned, catalog `2 16 18 4×119 5 16 2 14`, 330 frames in 6 s; the codes and QR secrets
only in main.swift's offer lines.

**H7** (the stand-in: `SILL_TEST_CABLE_INTERFACE=en0`, `SILL_TEST_ASK_FROM_THIS_MAC=1`, the client on
this Mac's `fe80::…%en0`). `--pair-ask=cable` → ok, `method` "cable", no proof, the Mac ID and a
32-byte recognition key; "Paired Cable iPad (sillclient) (key …) over the USB cable
(fe80::…%en0)."; `paired.json` method "cable" and `cableDevice` = deviceID("TEST"), no serial;
then a pinned session that got no tick. Without `cable` → `shown`; a second key claiming it →
`shown`; the first key again → ok, with no second line; a 127.0.0.1 client claiming it → `shown`;
the line "Cable pairing: … not paired by itself (it didn’t find the cable on its side); the code is
already showing."; `SILL_TEST_LOCKED=1` → `locked` and its line, nothing saved; without the stand-in
the same `fe80::…%en0` client → `shown`, nothing saved.

**H7b** (the iPad on the cable). `--pair-ask=cable` from this Mac's own `fe80::…%en14` and from
169.254.177.140 (en14): `shown` both, nothing saved; the host's line names `%en14` and is a plain
"Pairing: … asked to pair" line (rule 2: this Mac's own address), never "Cable pairing".

**H9** (`h9.py`, two rounds, 45 s at 60 fps, CPU over 40 s after a 4 s settle). Plain 3.59 % (3.60,
3.57); TLS with §8's tick rule 3.26 % (3.40, 3.12): −0.32 points; median frame age 0.20 against
0.17 ms. TLS without the rule (a scratch build with its two lines out) 3.45 % (3.52, 3.37): +0.19
over the rule, as P3 estimated. Ticks received: 1,500 plain, none over TLS with the rule (a 60 fps
stream always sent something within 30 ms).

**H12.** `--pairing --direct-wireless` with `SILL_TEST_PEER_TO_PEER_INTERFACE=en0`: a paired TLS
session from `fe80::…%en0` turned it off (kind 17): "Direct wireless off: disconnecting Direct iPad
at fe80::…%en0.N, which was connected over peer-to-peer Wi-Fi; …" and EOF; a pending pairing
connection (`--pair-hold=8`) closed 3.96 s into its hold (the replacement's settle); the same port.
With `SILL_TEST_SERVICE_TYPE`, after the Sill.log check (AWDL on for 3.4 s): `p=1` after the
replacement.

**H14.** PR #13's scripts from `remote-access-build`, unchanged but for the helpers' paths:
`h6_h13.py` (the remote plan's H6–H10 and H13), `h11_h15.py` (H11, H12, H15), `h17_h23.py H17`
(after the Sill.log check), `goodbyes.py` (busy, quit) and `h16_h19.py` (H16 and H19 on the bare
app, its SillMenuBar domain deleted after): all pass. On the software encoder three frame counts
were lowered (H7 more than 30 frames in 6 s, H8 and H9 more than 20; it gave 330, 230 and 225 here),
and H6's comparison leaves out the two encoder lines, the base's "Hardware encoder probe: …" and
the hook's "Test encoder: …". H15's home half needs the hardware encoder (the software encoder's
~7 kB/s never fills the loopback buffers within 60 s) and ran on it under the rule: "Client not
draining for 4 s" 26.0 s in (the base: 27.7–30.5 s). With a window the Mac's user opened (the CLI's
`--remote` window) an ask at the remote door is answered `closed`, the next wrong code still leaves
4 tries, and no ask line is printed.

**H16.** `requirePairing` in no wire type, not in DeviceSettings, not a UserDefaults key (the app
passes the standard value to HostConfig's init). Every door and pairing `SILL_TEST_` read is behind
the test-host rule. No print of a code, secret, link or serial added under Sources/SillHost; no
`assumeIsolated` added (HostShutdown's is the base's) and no `updateConfiguration`. The plain
`accept`: one line that hands a TLS door's connection to its Door, and `.home(origin, peer: nil)`.

**H17.** Step 0's checks unchanged (the discovery policy 286, the ledger 90, the fence 14 of 14
modes, remote-rules 64, AddressList and PairingWindow 41, the pairing window's address rule 80,
OriginPolicy 66, ClientLink 89, the protocol 188). Step 1's checks unchanged (DoorPolicy 104,
CableLink 40, AskLimits 27, the records 20, the device 61, the protocol's new values 39) with
136 of 136 mutants caught, and the wire probe's 50 lines byte for byte (`$SP/checks-full`). The swap's fallbacks on a TLS host: `SILL_TEST_SWAP_FAIL=port` → another port, the
session on the old listener streams on, and the new listener speaks TLS (a pinned session, the alert
for a plain message); `=all` → "Listener failed", exit 1.

**Beyond step 2's gates.** A scratch-only build of the CLI (`$SP/harness/tree`, never committed)
reads SILLH_* variables: Require pairing's starting value and a flip after S seconds, no window at
start, the app's window rules (a window's own line, its expiry), the Mac's user opening a window,
the Mac user's windows running the remote door, the remote port, Remove, the notice hook, the
status, and SILLH_UNLOCKED, since this Mac was locked by then (an ask there was answered `locked`,
which is the rule). The same build, with SILLH_UNLOCKED alone, also reran H5, H6, H7, H12 and the
swap's fallbacks on the final code: all pass. Run ahead of step 3's bare-app gates:
- HA (H10's core): off at start, "Home door: TLS, pairing not required.", `p=0`; an unpaired key's
  session admitted and streaming; the flip at 10 s: goodbye `pairingRequired` 0.08 s after it and
  EOF, one "Require pairing: disconnecting Stranger at 127.0.0.1:N, which isn’t paired." line and
  one "Settings: require pairing off → on", `p=1`, the same port, no "(2)"; a paired session
  streams throughout.
- HB (H8's core, `SILL_TEST_PAIRING_TTL=1`, `SILL_TEST_ASK_QUIET=12`): an ask opens a window (one
  listener, a link with no address, "Pairing window open for 1 s (asked by K1 (sillclient) on this
  Mac)."); after it expired the same key and address get `openOnMac`; another key from ::1 a
  window, a third from `fe80::…%en0`, then a fourth from the LAN address `openOnMac` with "not
  shown (3 windows in 12 s)"; the status's request "K4 (sillclient)/limit".
- HC: a device-opened window, then the Mac's user's: the same code, the remote door's listener
  appears, the offer again with addresses, and its link pairs at the remote door.
- HD: kind 21 from an unpaired session opens a device-opened window (home only, "showing" in the
  status); without `SILL_TEST_ASK_FROM_THIS_MAC` the same kind 21 from this Mac opens nothing, lights
  no menu, and its line says "not shown (it asked from this Mac)".
- HE: with Remote Access on and only a device-opened window, the remote door refuses a pairing
  connection in its handshake; the same link pairs at the home door.
- HF: `onCablePaired` once per pairing (not for the same key asking again); a key paired by code
  gets `cableDevice` the first time its session runs over the (stand-in) cable, then another key's
  cable ask gets the window with "another key of this iPad is paired"; its "last connected" reads
  "over the USB cable".
- HG: a plain Sill message sets the status's `olderDeviceAt`; an HTTP request does not.
- HH (H11's core, `--pairing --remote`): Remove sends goodbye `removed` to the key's home session
  and its remote one, "Removed Both (sillclient); closed 2 connections.", and its next `sill/1` is
  refused in the handshake.
- The CLI with `--pairing` and a damaged `paired.json` in `SILL_TEST_REMOTE_DIR`: "Home door
  unavailable: Sill couldn’t use its key in the test directory … (… is damaged).", no listener,
  exit 1.
- Pure checks (`$SP/checks`): SessionLock's rule 15 checks, 6 of 6 mutants; Require pairing's bytes
  and its memory and file stores 19. The bare app's 80 previews, rendered from one fixed path by
  1f3072a's binary and by this one: identical byte for byte.

**Deviations from the plan's sketches.**
- No cable cache in InterfaceSnapshot (§4.3, §4.5 (6) now say so): each reader reads its one
  interface afresh. `readCable` returns plain values, so InterfaceSnapshot still compiles on its own
  with OriginPolicy (step 0's origin check); Door makes the `CableLink.Ancestry`.
- One key per iPhone or iPad over the cable, by a hash of its USB serial number, as the amended plan
  says (not per plug-in).
- `Door.PairAttempt` carries `display` (the address with its scope at home, the old `source` at the
  remote door, whose lines are unchanged) and no endpoint.
- A "Cable pairing" line whose ask both lacks the claim and comes from a device with another key on
  the list names the Mac's own reason ("another key of this iPad is paired").
- The ask's line is at most one a minute per source address (§4.6): step 3's H8 reads kind 20 for
  asks that repeat an address within a minute, or uses a fresh address per ask.
- Turning Remote Access off closes only a window the remote door runs for; a device-opened window
  at home stays up. On a plain home door every window is the remote door's, so nothing changed there.
- A home-only window's link names the configured remote port, else 7455: the link needs a port, and
  its device dials the door it asked on.
- A closed home door's line names where the key lives ("in the keychain" for the app, the store's
  own words otherwise), and the CLI exits 1 after it, as when its listener fails; the status says
  `homeDoor == .unavailable` and the network state is left to step 3's presentation.
- The core prints the "… ignored" line for each door or pairing variable a host does not honour
  (TestHooks); step 3 adds SILL_TEST_REMOTE_DIR's and the `-Sill…After` hooks' in the app.
- The coordinator's `homePairing` and `testHooks` have defaults (false, true) so Sill.app's call is
  unchanged until step 3 passes them; `SessionLock.watchNotifications()` is there for step 3 to call.

**What step 2 changed in this plan:** §4.3 and §4.5 (6) (no cable cache).

### Step 3: Sill.app

`$SP` here is `scratchpad/home-pairing/3`: the gates (`gates3.py`: H6, H7, H8, H10, H11, H13 and two
more on the bare app; `h18.py`; `h2.py`, step 2's; `hostlib.py`, step 2's with an `AppHost` for the
bare binary), their logs (`logs/`), the previews (`previews/`), a window probe (`winprobe/`: a
process's on-screen windows and the frontmost app), a pixel diff (`pixdiff/`), the toolbar check
(`toolbar/`) and the pure checks (`checks-full/`). Every bare-app and bundle host ran with
`SILL_TEST_SOFTWARE_ENCODER=1`, one at a time, stopped by its PID; `defaults delete SillMenuBar` and
`defaults delete me.saffer.sill.h18` afterwards. The bare app shows its windows on this Mac's screen
(a device-opened pairing window, the notice; `-SillPairAfter`'s window activates it).

**What landed.**
- Sill.app's home door speaks TLS: `StreamCoordinator(…, homePairing: true, testHooks: !bundled)`.
  Require pairing comes from the identity store at launch (`storedRequirePairing`, before the
  coordinator, so the first TXT record and the startup line carry it) and goes back to it from the
  Devices pane (`AppModel.setRequirePairing`: saved first; off only once saved, on always; the
  keychain line in the pane when a save fails). The lock notifications are watched
  (`SessionLock.watchNotifications`).
- Settings › Devices (`DevicesPane.swift`, after General, `ipad.and.iphone`): Require pairing, its
  two footers and the keychain line; the paired devices, moved from Remote Access, each with how it
  paired and how it last connected (at home too); Remove, rename, Pair iPhone or iPad…. Remote
  Access's section is one row: the count and Show Devices….
- The pairing window: one a device opened (`offer.byDevice`) says who asked and from where, has no
  Address row and no Remote Access line, never shows the remote door's port trouble, closes itself
  3 s after a pairing, and comes to the front without activating Sill (`WindowPlacement.showInFront`:
  `orderFrontRegardless`, off the virtual display; `.fullScreenAuxiliary` on both windows); one the
  Mac's user opened activates Sill as before, with §6.3's first line, and "‹device› asked to pair."
  when a device's request led to it. The core offers a device-opened window the Mac's user has since
  opened over as theirs (`byDevice` false once it is the remote door's), so it then shows the
  Address row; Pair iPhone or iPad… brings a window that is up forward at once.
- The cable notice ("Paired over the USB Cable", Remove and OK, 10 s, VoiceOver's announcement of
  its first line).
- The menu: "‹device› Wants to Pair" (Showing a code · Show a Code… · Unlock this Mac, then tap it on
  the ‹device› again; the window forward, or one opened on the Mac asked by that device), "An iPhone
  or iPad Needs Sill Updated" (10 minutes, information only), "Devices Can’t Connect" (Settings ›
  Devices); the attention glyph for the first and the third; while the home door is closed the card
  says "Not Visible on the Network" with the keychain line.
- Hooks: `-SillSetAfter requirePairing=0|1`, `-requirePairing YES|NO`, `-SillCancelPairingAfter`,
  `-SillCableNoticeAfter` and `-SillMenuAfter` on the bare binary; Sill.app itself ignores every
  `-Sill…After` hook, `-requirePairing` and `SILL_TEST_REMOTE_DIR`, one line each.
- Previews: `pane-devices-{required,off,empty,unavailable}`, `pairing-{asked,askednearby,cablenotice}`
  and five menu samples (`wants-to-pair`, `-limit`, `-locked`, `older-device`,
  `devices-cant-connect`: their cards and menu.txt).

**H1.** `swift build -c release` into an empty scratch path: only the CaptureProbe warning. No iOS or
StreamProtocol file changed in this step (`git diff c0b22d7 -- iOSClient Sources/StreamProtocol` is
empty), so the iOS builds were not run again.

**H6** (the bare app, `-remotePort 0`, Remote Access off). With `SILL_TEST_ASK_FROM_THIS_MAC=1`: the
ask → `shown`; still one listener for the PID; `pairing.code` written 0.055 s after the ask and
`pairing.url` with no `a`; the window (440×508) on screen while the frontmost app stayed the same;
`-SillMenuAfter`: "⚠ H6 iPad Wants to Pair — Showing a code". `-SillPairAfter` over it: the remote
door's listener appeared for the PID, `pairing.url` was written again with the same `s` and five
`a`, and `--pair-url` over the remote door paired. The lines "Pairing: H6 iPad (sillclient) at
127.0.0.1 asked to pair; showing the code." and "Pairing window open for 5 minutes (asked by …)";
neither the code nor the secret in the log. Without the variable: `openOnMac`, no "Wants to Pair" in
the menu, no window, "… not shown (it asked from this Mac)."; `-SillPairAfter`'s window then added the
remote door.

**H7** (`SILL_TEST_CABLE_INTERFACE=en0`, `SILL_TEST_ASK_FROM_THIS_MAC=1`, the client on this Mac's
`fe80::…%en0`). The first key → ok, `method` "cable", `paired.json` with its `cableDevice`; the notice
on screen ("Paired over the USB Cable", 440×164) with the frontmost app unchanged; a second key →
`shown` ("another key of this iPad is paired"); `-SillUnpairAfter` removed the first; the second key
then → ok over the cable.

**H8** (`-SillCancelPairingAfter '5; 10; 13'`, `SILL_TEST_ASK_FROM_THIS_MAC=1`, quiet and span 14 s,
not 5: slack between the app's timers and the script's asks). K1 from 127.0.0.1 opened a window;
after the cancel, K1 from there, K2 from there and K1 from `fe80::…%en0` all got `openOnMac`; K3 from
`fe80::…%en0` a window; K4 from `::1` a third; then K5 from this Mac's LAN address `openOnMac`, "not
shown (3 windows in 14 s)", and the menu "⚠ K5 Wants to Pair — Show a Code…". Each cancel closed
the window on screen; one line per address (four lines for seven asks). A second run (quiet 40 s):
five wrong codes from three other sources stopped K1's window (4, 3, 2, 1 tries left, then
`stopped`, with the window's `busy` spacing between), after which K1 from 127.0.0.1 and K2 from
`fe80::…%en0` got `openOnMac` and K3 from `::1` a window.

**H10** (`SILL_TEST_SERVICE_TYPE`, `-SillSetAfter '8 requirePairing=0; 16 requirePairing=1'`, at 8
and 16 s rather than 3 and 10, to pair a key with `-SillPairAfter`'s code first). `p` 1 → 0 → 1 in
`dns-sd -L` (the last answer of each lookup: one lookup that began within a second of a change read
the cached record first), the same port, no "(2)"; the test directory's `require-pairing` "0", then
"1"; an unpaired session admitted while off, goodbye `pairingRequired` and EOF 0.09 to 0.14 s after
16 s; the paired session streamed throughout; "Settings: require pairing on → off" and "… off → on"
once each, and one "Require pairing: disconnecting Stranger at 127.0.0.1:…, which isn’t paired.".

**H11** (`-remoteAccess YES -remotePort 0`). Goodbye `removed` on the home and the remote session,
0.11 s after `-SillUnpairAfter`, then EOF; "Removed Both (sillclient); closed 2 connections."; the
next `sill/1` refused in the handshake.

**H13** (a damaged `paired.json`). No listener for the PID and the app still running; "Home door
unavailable: Sill couldn’t use its key in the test directory … (… is damaged)."; the menu: the card
"Not Visible on the Network" and "⚠ Devices Can’t Connect".

**Beyond the list.** The older-device item on the bare app: shown after a plain Sill message, not
after an HTTP request. `-SillCableNoticeAfter`: the notice in front with the frontmost app
unchanged, still up 9 s after it appeared, gone by 11.5 s. The toolbar: a scratch tab controller
with the six tabs at 520 pt, built with this SDK, keeps all six visible.

**H15.** The base (step 0's copies of `1f3072a`'s bare binary and bundle) rendered again from this
step's fixed paths (`$SP/previews/bin/SillMenuBar` and `$SP/previews/Sill-h0.app`, the bundle as
before: CFBundleIdentifier `me.saffer.sill.h0previews`, CFBundleVersion `H0`, signed ad hoc) equals
step 0's but for pane-general, which shows the path. This build's, from the same paths: 80 → 104
files for each. 41 identical; 24 new (the four Devices samples, the three pairing samples and the
five new cards, each light and dark); 39 differ: the 18 Remote Access samples (the list replaced by
its row), the 20 samples of a window the Mac's user opened (the pixel diff bounds every difference
to the rows of the first line, y 43–103 of 2×, and `requested` also to its headline, to y 163) and
menu.txt (180 lines added, none changed; the bare and the bundle's are identical). Looked at: every
Devices sample, `asked`, `askednearby`, the notice, `requested`, the Remote Access samples and the
new cards.

**Hard rules** (grep). `requirePairing` is no UserDefaults key of HostSettings and in no wire type;
only the bare binary takes it from its arguments (Sill.app looks only to say it ignores it); the
app's one `SILL_TEST_` read (`SILL_TEST_REMOTE_DIR`) is honoured only by a test host; no code, link or
secret printed; no `assumeIsolated` or `updateConfiguration` added to Sources/SillHost.

**H17.** Step 1's checks and mutants (DoorPolicy 104, CableLink 40, AskLimits 27, the records 20,
the device 61, the protocol's values 39; 136 of 136 mutants caught), the wire probe's 50 lines byte
for byte, step 0's checks (the policy 286, the ledger 90, the fence 14 of 14 modes, remote-rules 64,
addresses 41, the pairing address 80, origin 66, ClientLink 89, the protocol 188 and its 8
cross-checks) and step 2's (SessionLock 15, the stored Require pairing 19): all pass.

**H2, again** (step 2's `h2.py`: this step touched the core's pairing offers). The CLI's runs on the
hardware encoder while Noah's Sill.log said idle (re-read every 2 s): idle and with a client, plain,
with `--direct-wireless` and with `--remote`, identical to step 0's base logs masked and sorted
without the `[1s]` lines (in full too but for client-dw's last partial second, as before);
`--pairing` adds exactly its two lines.

**H18.** `.build/Sill.app` (make-app.sh, not installed) copied with CFBundleIdentifier
`me.saffer.sill.h18`, signed ad hoc, started with `--synthetic -SillLogFile … -SillQuitAfter 6
-SillPairAfter 1 -SillSetAfter '1 requirePairing=0' -requirePairing NO` and `SILL_TEST_REMOTE_DIR`,
`SILL_TEST_CABLE_INTERFACE=en0`, `SILL_TEST_ASK_FROM_THIS_MAC=1`, `SILL_TEST_SOFTWARE_ENCODER=1`: one
"ignored" line for each of the three hooks, the three variables and `requirePairing`; "Test encoder:
software only"; nothing in the test directory; no window, no hook ran; "Home door: TLS, pairing
required (0 paired)." and no Settings line; the ask claiming the cable from `fe80::…%en0` answered
`openOnMac`, "… not shown (it asked from this Mac)."; still running at 8 s (its `-SillQuitAfter`
ignored too), stopped by its PID (143). The window probe found no system prompt on screen after it
(TCC attributed the copy to the process that started it).

**Not verified.** The real Sill.app (Noah's, in /Applications) and its keychain store's
`require-pairing` item under Sill's own signature; the live menu and Settings window clicked through
(no UI automation here: the previews and `-SillMenuAfter` stand in), so "‹device› Wants to Pair"'s
action, the Devices pane's switch and Remove, and the notice's Remove ran only as code paths the
gates reach otherwise; VoiceOver's announcement; a device-opened window over a full-screen app;
Noah's devices (P1–P16).

**Deviations from the plan's sketches.**
- The cable notice is a window of its own, not the pairing window in a new phase (§6.3 now says so).
- Sill.app ignores `-SillQuitAfter` too, where §6.6 kept it: this step's brief made every `-Sill…After`
  argument a hard rule for the bundle (§6.6 now says so; H18 stops the bundle by its PID).
- `-SillMenuAfter` is new (the bare binary only): the gates' "in the status" is the menu it prints.
- The card's header while the home door is closed: "Not Visible on the Network" and the keychain
  line (step 2 left the network state to this step).
- A window the Mac's user opened for a device's request says "‹device› asked to pair." without "on
  this network": the request does not say where the device was, and it may have been nearby.
- The core's `PairingOffer.byDevice` (and the status's `Pairing.open(byDevice:)`) is true only while
  the window is the home door's alone, so the window a device opened and the Mac's user then opened
  over shows as theirs.
- The Devices pane with the keychain unusable says "Your paired devices show here once Sill can use
  its key again." instead of "No paired devices yet." (the list is unread, not empty).
- H8's quiet and span were 14 s (and 40 s for the stop), not 5; H10's changes at 8 and 16 s, not 3
  and 10.
- H15's list left out the samples of a window the Mac's user opened, which §6.3's first line changes
  (H15 now says so).
- Commits end with this session's attribution line, as steps 0 to 2 did.

**What step 3 changed in this plan:** §6.3 (the notice's own window), §6.6 (the bundle ignores
`-SillQuitAfter` too; `-SillMenuAfter`) and H15.

### Step 4: the iOS model

`$SP` here is `scratchpad/home-pairing/4`: the checks (`checks/`: step 1's harness with the device and
records checks grown and a new `home` check; step 0's policy, rf2 remote-rules and fence harnesses with
step 4's sections and their mutant drivers pointed at this tree), the simulator gates (`sgates.py`,
`simlib.py`), the stand-in Mac (`standin/`), their consoles and host logs (`t-s2` … `t-s6`,
`sgates-final.out`) and the builds' logs. Every host ran with `SILL_TEST_SOFTWARE_ENCODER=1` but the
base's (S6, which has no such hook), which ran on the hardware encoder only while Noah's Sill.log said
idle; one host at a time, each under 90 s, stopped by its PID. The simulator is this plan's own ("iPad
home-pairing H0"); the app browsed only `_silltest._tcp`; photos with `simctl io screenshot` only, and no
tap, UI test, recording or panel.

**What landed.**
- One TLS builder, `DeviceTLS` (the new StreamClient+Home.swift): every connection to a Mac takes its
  client options (RemoteTLS, this device's certificate, the pin or any P-256 key): a tap's session, its
  wired dial and the fallback, the automatic reconnect, the move from AWDL, PR #12's moves up and down
  and its reconnect over the cable (`rescue`), the session after a pairing, every pairing connection at
  home (`HomeDialer`), and RemoteConnector's dials and pairings from afar. Plain TCP remains for a plain
  door only, which `homeDial` gives a DEBUG build alone, and only for a Mac never seen with `p`. A move
  of a TLS session is pinned as the session is (`moveParameters`; parameters that never connect should
  the key be unreadable, so nothing goes out plain). `DeviceIdentity.loadOrCreate()` runs at the first
  TLS dial.
- `p` on every row: `FoundMac.door` (HomeDoorTXT.door over the result's record, both browsers) and
  `homeWord` (`rowWord`: "Not paired", "Wired" for an unpaired Mac over the cable, "Update Sill"; the
  cable bit from getifaddrs), which `word` shows. A saved Mac seen with `p` is marked `homeTLS` before
  the rows are built, so a plain row of it reads "Update Sill" at once.
- Taps and the reconnect go by `homeDial`: pinned, any key (an open door), the ask (a tap's only), plain
  (DEBUG), or nothing ("‹Mac› runs an older Sill…"). The reconnect never asks, and skips a row it took by
  Bonjour name whose key was another's (`pinRefusedRows`).
- The session gate: a TLS session is connected at its first window list (`homeSessionReady`:
  `connected`, `connectedAt`, `reconnect = nil`, "Connected to …", the DEBUG move and path tests, the
  moves), with a remote session's 10 s first-list deadline; the route word is read at `.ready`. An open
  door's session pins the key its first connection saw for every later hop (`trust(_:readyWith:)`). A TLS
  error while connecting ends the dial at once.
- How a home session ends (`homeEnd`): goodbye `removed`, or -9825/-9829 on a saved Mac's dial → the
  record `revoked`, "‹Mac› removed this ‹iPad›. Tap it to pair again.", no reconnect; goodbye
  `pairingRequired`, or a refused key on an open session → "‹Mac› now asks devices to pair. Tap it to
  pair this ‹iPad›.", no reconnect; -9808 on a pinned dial → the other rows the tag names, pinned, then
  the remote path's wrong-Mac words (none for a row taken by name alone). A goodbye `removed` on a remote
  session revokes the record too.
- The ask: `sill-pair/1` to the row as a tap dials it (its wired interface first, IPv6 only, then the
  row as listed after 2.5 s or at once), pinned to a revoked Mac's saved key, else any key; the device's
  cable check at `.ready` (`onCable` over the path's address, its scope and getifaddrs; the DEBUG
  console's "home: cable: …"); kind 19 `ask` with `cable: true` only then; kind 20 within 15 s, judged by
  the new pure `askAnswer`: the cable's proof-less ok only for an ask that claimed it, naming the key the
  connection saw, with a 32-byte recognition key (saved with method "cable", `homeTLS`, the Bonjour name;
  then a pinned session); `shown` → `homeAsk` (the home card's state for step 5: the asked key and the
  endpoint that answered); `openOnMac`, `locked` and the rest in §7.7's words; `busy` one silent retry;
  any other ok "Pairing didn’t finish…".
- Proofs at the home door (`homeProof`): the home card's code (`pairHome`), its scanner and an outside
  link (`pairLinkAtHome`: the connection the ask reached when the link names its key, else every row
  with `p` pinned to the link's key, then the link's addresses), and Pair This ‹iPad›… over a TLS session
  (`pairOverlayTyped`, and its scanner: the session's own row, pinned to the key it saw). proof_M
  checked; saved as the remote path saves plus `homeTLS` and the Bonjour name; then a pinned session on
  the row, or over a stream the session goes on with a saved Mac. The home card's errors are new
  `PairingProblem` cases.
- Pure: DiscoveryPolicy's `HomeTrust`, `pin`, `sessionTrust`, `trust(_:readyWith:)`, `homeEnd`,
  `nextPinnedRow`, `askAnswer`, `linkRows` and `HomeCopy`; SavedMacs' `seenOverTLS`, `revoking` and
  `forgettingHomeTLS`.
- DEBUG: `-SillServiceType`, with `_silltest._tcp` declared in the Debug configuration's own
  `Info-Debug.plist` (Release's Info.plist declares `_sill._tcp` alone); `-SillHomeDoor`,
  `-SillForgetHomeTLS`, `-SillCableTest`; and for the gates, which drive no UI, `-SillTapRow`,
  `-SillHomeCode`, `-SillHomeLink`, `-SillOverlayCode` (§7.9).

**H1.** iOS Debug for the simulator (signed ad hoc, for its keychain), Release for the simulator and
Debug for `generic/platform=iOS` (build only, unsigned; the iPad was not touched): only the old
`StreamClient` capture warning. `NSBonjourServices`: Debug `_sill._tcp`, `_silltest._tcp` (simulator and
device products); Release `_sill._tcp`. No package source changed (`swift build -c release`: nothing to
do).

**H3 (device)**, each check with its mutants (`$SP/out`, `$SP/out-ext`): the device check 111 (61 + 50:
the pin of each hop, `sessionTrust` over all 192 `homeDial` answers, `homeEnd` over 360 combinations,
`askAnswer` over 10,240 with the proof-less ok taken in exactly one shape, `linkRows`, `nextPinnedRow`,
§7.7's words) and 66 of 66 mutants (31 + 35); the records 30 (20 + 10) and 16 of 16 (10 + 6); a new
`home` check, 34 (the literals DiscoveryPolicy spells against Goodbye's and PairResult's, real kind 20
JSON, and pairing at home walked end to end: unpaired, the cable's ok, the pinned session, removed,
paired again, an older Sill.app, `-SillForgetHomeTLS`, an open door, a look-alike, links) and 11 of 11;
the policy check grown to 336 (286 + the same 50) with 105 of 105 mutants (step 0's 70, still caught
against this tree, and 35); the rf2 remote check grown to 102 (64 + the home model and the saved Macs'
home fields) with 52 of 52 mutants (step 0's 35, still caught against this tree, and 17: the home
model's 11 and the saved Macs' 6); the fence check, whose SessionLink this step does not touch, 14 of 14
modes and 19 of 19 of its mutants (step 0's, against this tree).

**H17.** Step 1's checks (DoorPolicy 104, CableLink 40, AskLimits 27, HomeDoorTXT 39) and their
mutants (41, 20, 15 and 19, all caught); the wire probe's 50 lines byte for byte; step 0's (the policy
286, the ledger 90, the fence 14 of 14 modes, remote-rules 64, addresses 41, the pairing address 80,
origin 66, ClientLink 89, the protocol 188 and its 8 cross-checks): all pass. Step 2's host checks were
not rerun: no host file changed.

**S (simulator, `sgates-final.out`: 60 of 60 on the final build).**
- S2: `SILL_TEST_SERVICE_TYPE=_silltest._tcp SillHost --synthetic --pairing` listed as "Sill test ‹pid›"
  (p=1); with Noah's iPad on this Mac's cable the simulator sees the Mac on anri0 and en14 too, so the
  unpaired row read "Wired", as S2 says it would (`notpaired.png`); the tap asked over anri0, the
  device's check said "cable: no, fe80::… is this device’s own address", the CLI printed its ask and code
  lines ("asked to pair; the code is already showing."), the code typed paired at the home door ("…
  with the code."), and a pinned session was connected at its first list and streamed. Saved: method
  "code", `homeTLS`, the Bonjour name. Relaunched, the row listed again (the Debug plist: no -65555) with
  its method word and connected pinned, with no ask.
- S2b (added): the host gone and back with the same identity under a new Bonjour name: the reconnect
  found it by its tag and dialed it pinned, no ask.
- S3: `SILL_TEST_CABLE_INTERFACE=en0 … --pairing`, the app at this Mac's `fe80::…%en0` with
  `-SillHomeDoor paired -SillCableTest 1`: the ask claimed the cable, the host paired it by itself
  ("Paired … over the USB cable (fe80::…%en0)."), the device took the ok ("Paired with … over the
  cable."), no card, a pinned session streaming; saved with method "cable" and `homeTLS`; the host's
  `paired.json` with the method and a `cableDevice`. S3b: without `-SillCableTest` the device's check
  said no (en0 is Wi-Fi), the ask claimed nothing, the host answered `shown` ("Cable pairing: … not paired
  by itself (it didn’t find the cable on its side)"), nothing saved; the stand-in (a swiftc tool over
  RemoteTLS's server options) answered an unclaimed ask with a proof-less ok and the device refused it
  ("Pairing didn’t finish: … couldn’t show it knows the code…"), nothing saved.
- S4, after S3's pairing (its host identity kept in a test directory): `-SillMoveTest 1` (dialed pinned,
  the move's connection read to its first list, the fence down, "Client connected" per connection, no
  ask and no refused plain connection on the host) and `to:` this Mac's `fe80::…%en0` (the route word
  Wi-Fi at the hand-over); `-SillPathTest` with this Mac's own `fe80::…%en14` as the cable (the iPad
  plugged in): up to the cable, down to Wi-Fi when its path went, up again, the connection cut and
  carried on over Wi-Fi at once, every hop pinned, the host seeing `%en14` and `%en0`; and a move to a
  stand-in that presents the Mac's key and refuses this device's (a key removed on the Mac) ended as a
  failed move while the session streamed on.
- S5 (the bare app): paired with `-SillPairAfter`'s code at the home door, then `-SillUnpairAfter`:
  "… removed this iPad. Tap it to pair again.", the record revoked, and the next dial the ask pinned to
  the saved key (answered `openOnMac`: no window, from this Mac); `-requirePairing NO` then
  `requirePairing=1` with an unsaved session on the open door: "… now asks devices to pair. Tap it to
  pair this iPad.", no reconnect. S5c (added): Pair This ‹iPad›… over that open session with
  `-SillPairAfter`'s code went to the session's own row, pinned ("this session's Mac"), never the remote
  door; saved; Require pairing turned on then left the now paired session streaming.
- S6: the base's (1f3072a) `SillHost --synthetic` and this CLI without `--pairing`, with `-SillConnect`:
  plain, connected at `.ready`, streaming, as before.

**Not verified.** The home card, the rows' VoiceOver labels and hints, the panel's Away from home
(step 5); "Not paired" on a live row (only with no device on this Mac's cable; the pure checks and step
5's photos cover it); the real cable at both ends: the simulator is this Mac, so its check always finds
the Mac's address its own, and S3 ran on the host's stand-in and `-SillCableTest`; a Direct row's ask and
session over AWDL (no AWDL-on test here); an outside link from `simctl openurl`; Noah's devices (P1–P16).

**Deviations from the plan's sketches.**
- The device's home code is a new file, `StreamClient+Home.swift` (§7.1 now says so), and the Debug
  configuration's `NSBonjourServices` comes from its own `Info-Debug.plist` (§7.9's "a
  per-configuration plist").
- DEBUG arguments beyond §7.9's for the gates, which drive no UI: `-SillTapRow`, `-SillHomeCode`,
  `-SillHomeLink`, `-SillOverlayCode` (§7.9 now lists them); the move and path tests' rows count as the
  one saved Mac under `-SillHomeDoor`.
- A TLS session at home has a remote session's 10 s first-list deadline; a TLS error while connecting
  ends a dial at once rather than after `.waiting`'s 5 s.
- A goodbye `removed` on a remote session revokes the saved Mac too (one trust list).
- Copy §7.7 did not have: after `shown`, the status line is "‹Mac› is showing a code. Point this ‹iPad›
  at it." (the card's scan line), and an ask or a proof nothing answered says "‹Mac› didn’t answer.
  Check that Sill is open on it, then tap it again." (§7.7 now lists both).
- RemoteConnector builds its TLS options through `DeviceTLS` (the same verify rule as before).
- `HomeDoor` and `RowWord` are Hashable (FoundMac is).
- Commits end with this session's attribution line, as steps 0 to 3 did.

**What step 4 changed in this plan:** §7.1 (the new file and the Debug plist), §7.7 (two lines) and
§7.9 (the gates' arguments).

### Step 5: the iOS UI

`$SP` here is `scratchpad/home-pairing/5`: the photos (`before/` and `after/`, the regression set on
step 4's build and on this one; `new/`, this step's cases; `fix/`; `sheets/`), their tools
(`photos.py`, which launches the harness and crops each `simctl io screenshot` to the fake screen;
`imgtool.swift`, CoreGraphics only: crop, pixel diff, lit rows, sheets; `compare.py`), the checks
(`checks/`: step 4's, with the device check's step-5 section and its mutants), the live gates
(`sgates5.py`, `simlib.py`, `t-s2ui/`, `t-s5ui/`) and the builds' logs. Photos on this plan's own
simulator ("iPad home-pairing H0", an iPad Pro 13"), with `simctl io screenshot` only: no tap, UI
test, recording or panel; the harness draws each size inside it (so its words say "iPad" at the
phone sizes too). Content size set with `simctl ui … content_size` and put back to `large`.

**What landed.**
- The rows. Each network or Direct row ends in its home word (step 4's `FoundMac.word`: "Not
  paired", "Wired" for an unpaired Mac over the cable, "Update Sill", or how it is reached), and
  VoiceOver reads `RowWord`'s label and hint ("Mac mini, not paired" · "Pairs with a code Mac mini
  shows, then connects."; over the cable "Pairs over the USB cable, then connects."; "Mac mini’s Sill
  is too old for this iPad."). The row a tap's ask is waiting on is lit, as the app drawer lights the
  app on screen, while the status line says "Pairing with Mac mini…". `DrawerRow`'s trailing word
  keeps its whole width (`fixedSize`): the title truncates, never "Not paired" or "Update Sill".
- The home card: `AddMacCard`'s home mode (`home`, the row's name), unfolded in the rows' place when
  the Mac answers the ask `shown` (`ConnectScreen.homeCard`, from `homeAsk`). Its title "Pair with Mac
  mini" is a heading and VoiceOver's focus moves to it; the scanner under "Mac mini is showing a code.
  Point this iPad at it.", its caption "Point at the code on Mac mini" (spoken "Camera. Point it at
  the code on Mac mini."), or after Enter Code Instead "Type the code Mac mini shows." and the code
  field alone, whose Pair and Return call `pairHome`; the errors under the field or in its place, in
  §7.7's words; Cancel, Esc and the escape gesture fold it (the ask or proof stops, the idle status
  line comes back). It stays through "Paired with Mac mini." until the session comes; side by side
  under 520 pt; in the top half at 710×1000; on the typed path where there is no scanner (the
  simulator), as Add a Mac is.
- The panel's Away from home (`DiscoveryPolicy.awayFromHome`, pure; §7.6 as built): "Paired" (was
  "Paired for remote access"), with "Connected through …", "Away from home, Sill reaches …" or, Remote
  Access off, how to turn it on; Pair This ‹iPad›… only in an unpaired session: at home over TLS
  (Require pairing off) whatever Remote Access says, with its own footnote; over a plain door as
  before.
- Pair This ‹iPad›… over a stream at home says what to do there, never "Tap Mac mini": a refused
  code in the remote path's words (`problem(for:mac:)`, now shared), "Pairing didn’t finish: Mac mini
  couldn’t show it knows the code." and "Mac mini didn’t answer. Try again." (`PairingProblem`'s
  `proofFailedOverStream` and `noAnswerOverStream`, words in `HomeCopy`).
- "That code didn’t work. Check the code on your Mac. 4 tries left." keeps "4 tries" together (a
  no-break space): at 380 pt it wrapped as "…your Mac. 4" / "tries left.", on Add a Mac's card too.
- Model hooks for the UI: `cancelHomeAsk` puts the idle status line back after the ask's own ("Pairing
  with…", "… is showing a code…"); a session that connects (`markConnected`, `remoteSessionReady`)
  clears any ask, so the card never comes back for one (a pairing that ended through a link's
  addresses left it); Add a Mac… cancels an ask still waiting; `sessionAtHomeOverTLS`; a DEBUG console
  line for each pairing failure ("pairing: …", for the gates).
- The harness: `-SillConnectCase` `homerows`, `homeasking`, `homecard`, `homecode`, `homecodeerror`,
  `homelocked`, `homeopenonmac`, `homerevoked`, `homecabledone`, `homeolder` and `pairingrequired`;
  `-SillSettingsCase` `paired`, `pairedoff` and `openpair` (`mockHomeTLS`); each row's word comes from
  `rowWord` itself. ContentView's contract names them, `-SillSettingsEnd` and §7.9's arguments.

**H1.** iOS Debug for the simulator (signed ad hoc), Release for the simulator and Debug for
`generic/platform=iOS` (unsigned, build only; the iPad was not touched): only the old `StreamClient`
capture warning (now StreamClient.swift:2449). `NSBonjourServices`: Release `_sill._tcp`; Debug
`_sill._tcp` and `_silltest._tcp`. `swift build -c release`: nothing to do (no package source changed).

**H3 and S7** (`$SP/out`). The device check 111 → 128: the panel's Away from home over all 16 inputs
(a saved Mac always "Paired", Pair This ‹iPad›… only unpaired, never at a home door for a remote
session) and each of its rows, the card's title, typed line, viewfinder caption and spoken label, the
scan line, the open door's footnote, and the overlay's words at home, which never say "Tap"; its
mutants 66 → 79, all caught (13 new: `awayFromHome`'s branches, and the words). Against the final tree,
with no mutant pattern gone ambiguous: the policy check 336 and 105 of 105 mutants, the rf2 remote
check 102 and 52 of 52, the home check 34 and 11 of 11 (a first run lost one mutant to a compiler
crash while the disk was full; run again, 11 of 11), the records 30. The labels, hints and announced
status lines are those pure strings; the headings and focus moves were read in the source
(ConnectScreen's title for either card, the card's escape action and Esc key, ProblemLine's
announcements), not heard.

**S1** (`$SP/new`, 162 photos). The 11 connect cases at 1000×710, 710×1000, 500×710, 710×500,
402×874, 874×402 and 375×667, and at `accessibility-extra-large` at the four Duo sizes and 402×874;
the three settings cases at those five sizes, both text sizes, scrolled to their end. Measured on all
162 (`compare.py`): at 710×1000 nothing of the column lies below 500 pt (the lowest, `homerows`' seven
rows, ends at 488 pt; the card at 404 pt); the title's leading edge is the same in every case at each
size (1000×710: 642 or 643 px, the first glyph's side bearing, "C" or "P"). Read by eye, one by one
or on sheets, about 50 of them: "Not paired" and "Update Sill" whole at every size down to 375×667,
the long names truncated instead; the card side by side at 710×500 and 874×402, stacked elsewhere, in
the top half at 710×1000; the status lines wrap and never truncate; the footer follows the larger
text and the column keeps its fixed sizes, as before; the panel's Paired, Pair This ‹iPad›… and
their footnotes at every size. The sheets are `$SP/sheets` (sent to Noah).

**Regression** (`$SP/before`, `$SP/after`): 117 photos of the existing cases (every connect case at
the four Duo sizes; every settings case at 1000×710, and scrolled to its end at 1000×710 and 500×710;
the drawer), step 4's build (`git archive` of 41caa8f) against this one: 107 identical pixel for
pixel. The other 10: the three `pairing` photos and `pending` (their spinners caught in other frames)
and the six remote cases scrolled to Away from home ("Paired", was "Paired for remote access"). Then,
with the no-break space, `addcodeerror` at the four Duo sizes differs in its error line alone ("…your
Mac." / "4 tries left.").

**S2 again, with the UI, and S5's end** (`sgates5.py`, `sgates5.out`: 16 of 16; the CLI host and the
bare app on the software encoder, each under 90 s, Noah's Sill.log idle). The CLI's row read "Not
paired" (no device on this Mac's cable this time); a tap asked ("Pairing with Sill test ‹pid›…") and
the Mac's `shown` brought up the card, photographed: "Pair with Sill test ‹pid›", "Type the code …
shows." (the simulator has no scanner), Pair and Cancel; a wrong code with a valid check digit came
back "That code didn’t work. Check the code on your Mac. 4 tries left." on the card, photographed,
nothing saved; the right code paired at the home door, then a pinned session streamed (the host's
`[1s]` lines with the client); a second host with the same identity under another name: the row read
"Wi‑Fi", and a tap connected pinned with no ask. The bare app: paired by its row with its own window's
code, then `-SillUnpairAfter`: "… removed this iPad. Tap it to pair again." and the row "Not paired",
photographed.

**Not verified.** VoiceOver on a device (P14); any tap in the UI (no UI automation here: Enter Code
Instead, Cancel, Esc, the escape gesture, the field; the gates type the code through
`-SillHomeCode`); the live scanner (the card's scanner is the harness's drawn viewfinder;
`-SillHomeLink` was not run in this step); "this iPhone" in a photo (the harness draws the phone
sizes on the iPad, so its words say iPad; the words' device argument is pure-checked with iPhone); Pair
This ‹iPad›…'s new error words in a live run (only their strings are checked); an unpaired row over a
real cable ("Wired") live, and a Direct row's "Not paired"; Noah's devices (P1–P16).

**Deviations from the plan's sketches.**
- Beyond §7.7's copy: the row a tap's ask waits on is lit; Pair This ‹iPad›…'s errors over a stream
  at home (the plan was silent, and step 4's said "Tap Mac mini", with no row to tap); the Away from
  home footnotes of §7.6's new states (the plan named only "Paired"); "4 tries" kept together, which
  changes Add a Mac's card too. §7.6 and §7.7 now say so.
- Harness cases beyond §7.9's: `homeolder` and `pairedoff`, and a seventh row in `homerows` (a second
  long name, reading "Update Sill"). §7.9 now lists them.
- Small model changes for the UI in StreamClient: the ask's status line cleared on Cancel, an ask
  cleared when a session connects, Add a Mac… cancelling a waiting ask, and a DEBUG console line per
  pairing failure.
- Commits end with this session's attribution line, as steps 0 to 4 did.

**What step 5 changed in this plan:** §7.1 (two rows new, two amended), §7.6 (the panel as built), §7.7 (the UI's
additions) and §7.9 (two cases).

**Verified again (2026-09-27, two sessions; `scratchpad/home-pairing-finish`, the second's in its
`verify/`).** Step 5 as 1b8de5f holds it (74cd925's code; 1b8de5f added only the hand-off), checked from
scratch after the interrupted verification, by a session that was itself interrupted at 00:22 (this
section written, nothing committed, its simulator still booted), then by the next, 00:39–01:15, which
ran everything again but the live gates. Nothing failed and no code changed.
- Builds, both sessions: `swift build -c release` in the worktree (nothing to do) and clean from `git
  archive` of 1b8de5f (29–30 s, only the CaptureProbe warning); iOS Debug for the simulator (signed ad
  hoc), Release for the simulator and Debug for `generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO`,
  each with its own fresh DerivedData (the second session built them from the archive, so nothing was
  built in the worktree): only the old `StreamClient.swift:2449` capture warning. `NSBonjourServices`:
  Debug `_sill._tcp` and `_silltest._tcp`, Release `_sill._tcp`; all three with
  `ITSAppUsesNonExemptEncryption` false and `PrivacyInfo.xcprivacy`. None of the harness's arguments
  or cases (`SillConnectCase`, `SillHomeCode`, `SillTapRow`, `mockHomeTLS`, …) is in the Release binary.
- H3, H17 and S7's strings, both sessions with the same counts: step 5's checks copied and run against
  the tree, each with its mutants: the device check 128 (79 of 79), home 34 (11 of 11), the policy
  check 336 (105 of 105), rf2 remote-rules 102 (52 of 52), records 30 (16 of 16), DoorPolicy 104 (41 of
  41), CableLink 40 (20 of 20), AskLimits 27 (15 of 15), HomeDoorTXT 39 (19 of 19), the fence check's 14
  modes (19 of 19); the wire probe's 50 lines byte for byte against the base; step 0's policy 286,
  ledger 90, fence 14 modes, remote-rules 64, addresses 41, pairing address 80, origin 66, ClientLink 89,
  the protocol 188 and its 8 cross-checks. S7's headings and focus moves read in the source again: the
  title is a heading under either card and takes VoiceOver's focus as a card unfolds or folds, the
  card's escape action and Esc key fold it (`fold`, which cancels the ask or the proof), ProblemLine
  announces its words, each status line is announced but the idle ones.
- S1. The first session, on a simulator of its own ("Sill home-pairing", an iPad Pro 13"), 192 photos:
  the 11 connect cases at the seven sizes and at `accessibility-extra-large` at the Duo sizes and
  402×874, the Settings cases `paired`, `pairedoff` and `openpair` scrolled to their end at the four
  Duo sizes, 402×874, 874×402 and 375×667, both text sizes, and at their top at 1000×710, 402×874 and
  874×402, with `remote`, `remotepair` and `remoteoff` scrolled to their end at the phone sizes beside
  them. The second deleted that simulator, made a fresh one of the same kind (deleted after) and took
  225: the same 192, pixel for pixel the first session's, the 162 of them step 5 took pixel for pixel
  step 5's own, and 33 more, the three Settings cases at their top at every other Duo and phone size
  and text size. At 710×1000 nothing of the column lies below 488 pt; each size's title edge is one
  within 1 px ("C" or "P"); the card is side by side at 710×500 and 874×402, stacked elsewhere; "Not
  paired" and "Update Sill" whole at every size, the long names truncated. The Settings panel's scroll
  area is small where the stream shares a phone's screen (two rows at 375×667), so scrolled to its end
  `openpair`'s five-line footnote puts Pair This ‹iPad›… partly or wholly under the header at 500×710
  and 375×667, and at the larger text at 402×874 and 874×402 too; `remotepair`'s shorter one only
  tucks the button's top under the header at 375×667. The panel's scrolling, as before, not step 5's:
  at their top every case shows its first rows.
- S2 again with S5's end, the first session (`sgates.py`, `live/`: 18 of 18, 00:14–00:19), under the rule
  that test listeners bind to loopback only: each host (the CLI with `--pairing`, the bare app) ran with
  an interposer (`loopback/loopback.dylib`, `DYLD_INSERT_LIBRARIES`) that binds its listeners to `::1`
  and refuses a listen anywhere else, `lsof` by its PID said `[::1]` alone before anything connected,
  and the app dialed the real `_silltest._tcp` row's wired-test address (`-SillWiredTest ::1:PORT`), the
  way a Wired row dials its cable. With Noah's iPad on this Mac's cable the unpaired row read "Wired";
  the tap asked, the card came up on `shown`, a wrong code gave "That code didn’t work… 4 tries left."
  and saved nothing, the right one paired at the home door and a pinned session streamed; a second
  host with the same identity listed as the saved Mac ("(p=1)", no home word) and a tap connected
  pinned with no ask; the bare app's window paired the row, and `-SillUnpairAfter` gave "… removed this
  iPad. Tap it to pair again." with the row reading "Wired" again (an unpaired Mac on the cable). Each
  host under 90 s, on the software encoder, Noah's Sill.log idle before each. The second session did
  not run them again: Noah's iPad streamed from Sill.app over the cable from 00:38 to past its end, and
  the gates start a host only while `no-device.sh` finds no device connected (their hosts use the
  software encoder, but a stream beside his is load he did not ask for). Its interposer, rebuilt from
  the same source, kept an `NWListener` on `::1` again.
- Found on the way, none of them step 5's code: the launch-argument domain drops a value that starts
  with "[" (`-SillWiredTest '[::1]:P'` or `-SillConnect '[::1]:P'` arrive as nothing, checked again with
  a probe of `UserDefaults`; `::1:P`, or the value quoted as `'"[::1]:P"'`, arrive), which
  `address(argument:)`'s comment does not say (StreamClient's `init` says it of `-Sill.savedMacs`);
  `-SillMoveTest to:[::1]:P` and `-SillPathTest` specs are unaffected. Under the wired test the ask is
  answered at an address, so the saved Mac has no Bonjour name (a real row's answer is its service).
  Step 5's own gate (`sgates5.py`) matched the row's word anywhere in the console, so with the iPad on
  the cable ("Wired" either way) two of its checks could pass without a pairing; the first session's
  read the saved Mac's "(p=1)" and the row after the removal.
- Not verified, as before: taps, VoiceOver, the live scanner, the real cable at both ends, Noah's
  devices (P1–P16).

### The merge with main (2026-09-27)

`$SP` here is `scratchpad/home-pairing-finish/merge` in the session's scratchpad: the host gates
(`gates.py`, their logs in `gates/`, the last run's output in `gates-final.out`), the CLI's parity
(`parity.py`, `parity/`), the rig's source (`rig/`: `GateRig-main.swift`, one more executable target
in `Package.swift`, built in a scratch copy of the tree, never committed), the previews
(`previews/`) and the builds' and mutants' logs (`logs/`). The copies built from `git archive` (the
rig's tree, both parents, the final tree's clean build) and every DerivedData were deleted after. Main was at cf05a78, about 100 commits ahead of this branch's base (1f3072a): PRs #16
(the best path's follow-ups), #17 (GitHub Actions, `Tests/checks`), #18 (the update notice: kind 23's
hello, `DeviceGate`, kind 22's new fields, the update check), #19 (iOS 1.0), #20 (the 33 fps plateau),
#21, #22 (CI's fence fix), #23 (TestFlight tooling), #24 and #25 (the public sweep), #26, #27 (the App
Store address) and #28. One merge commit (d11aa60), not a rebase; git stopped in 13 files, each
resolved by reading both sides.

**What landed.**
- The device gate in `Door`, one place for both TLS doors, as CLAUDE.md's Compatibility floor had
  it for whichever of update-notice and this branch landed second. Once `.ready` admits a `sill/1`
  key (`DoorPolicy.atReady`), `Door.admitSession` hands the connection to `StreamServer.gate`: with
  the floor at "0" (every build) it registers at once, as before; above it the first message inside
  TLS must be a hello the floor admits, and any other device gets kind 22 "update" and is never
  registered (main's gate, its Refused and count lines and its loop slowdown unchanged, counted per
  source across every door). Then `serve(_:route:hello:admitted:)` registers the session, prints the
  door's line ("Client connected", "Remote client connected") and then the hello's; `serve` runs no
  gate of its own now. The plain home door (the CLI without `--pairing`) keeps main's gate at
  `.ready`. A pairing connection never meets the gate: pairing is not refused for age.
- `DoorPolicy.afterGate` (pure): what changed while the gate held a session (up to 2 s, neither
  pending nor a client, so no `closeSessions` reached it) is judged again from the snapshot as the
  gate admits it: at the remote door main's `stillAdmits` (removed, remoteOff, internetOff for an
  origin the internet switch now refuses, busy at 8 sessions, in that order); at home a key paired at
  `.ready` and removed since ("removed", with Require pairing on or off) or an unpaired key once
  Require pairing is on ("pairingRequired"); a key paired meanwhile is admitted. `Door` sends that
  goodbye with the line that change's own close prints ("Removed ‹name›: disconnecting it at …",
  "Require pairing: disconnecting … which isn’t paired.", "Remote access off: …", "Internet access
  off: …"; busy counted in the minute's summary), with main's `closeWithGoodbye` (a FIN and a drain,
  never a reset before the goodbye). At home it also drops a connection accepted over peer-to-peer
  Wi-Fi when Direct Wireless went off meanwhile (`droppedForDirectWireless`, main's rule, now shared
  by both kinds of home door; `Door.accept` takes the accepting listener's flag). `readyArrived`'s
  own goodbyes (remoteOff, busy) close the same way, as main's remote door did.
- The test hooks: `SILL_TEST_MIN_DEVICE_VERSION` and `SILL_TEST_GOODBYE` follow this branch's test
  host (`DoorPolicy.isTestHost`: not advertising and not Sill.app's own executable), and TestHooks
  prints one "ignored" line for each elsewhere, beside the door's other hooks.
- `Goodbye` has main's fields and "update" beside "pairingRequired". GoodbyePolicy (main's) knows
  "pairingRequired" (its words as `HomeCopy.pairingRequired`, no reconnect, not a notice), so a TLS
  home session that hears it still ends through `homeSessionEnded`; main's goodbye check had used
  "pairingRequired" as its example of a reason the device does not know.
- The device's hello, first on every session connection, over TLS at a TLS door: `connect(to:)`
  (this branch's session parameters: TLS pinned, or plain for a plain door in DEBUG), `startMove`
  (`moveParameters`) and `adopt`. A send made before `.ready` waits for the handshake, so the hello
  is the first message inside TLS. Main's `connectionParameters` is gone (`DeviceTLS.plain` is the
  same). `sessionEnded`: main's notice first (GoodbyePolicy), then a remote dial's failure, then
  `homeSessionEnded` (removed, pairingRequired, another key), then GoodbyePolicy's outcome, with this
  branch's revoking of a saved Mac after "removed".
- `project.pbxproj`: both sides had taken A01E/F01E, for GoodbyePolicy.swift and
  StreamClient+Home.swift; the auto-merge kept both, and the build lost GoodbyePolicy.
  StreamClient+Home.swift is A301/F301 now (a block of its own, as App Store readiness took A201);
  A601/F601 since the review fixes (2026-09-27), as branch pointer-visibility has A301/F301 for its
  own file and no open branch has A601.
- Sill.app: `StreamCoordinator(…, homePairing:, testHooks:, hostVersion:)`; both sides' settings
  notes, panes (General's update section beside the Devices tab), menu entries and debug hooks;
  main's `-SillPrintMenuAfter` is among the timed hooks Sill.app itself ignores, while the update
  check's feed, version, interval and check-now arguments stay in the app (they bear on no door).
- `SillProtocol` settled (Compatibility.swift, CLAUDE.md, docs/update-notice-plan.md §3.2, §4.6 and
  open question 14): protocol 1 is 1.0's TLS home door with ALPN `sill/1`, as the remote door is;
  pairing on the home door is no longer an example of what raises it; a later generation raises
  both: `sill/2` is offered beside `sill/1` and `sill-pair/1`, which a host offers for good
  (`RemoteTLS.serverALPNs`), never instead of them. (As first written here, "offered beside
  `sill/1` while older peers are served": the security review's reading, 2026-09-27, was that it
  lets a later host drop `sill/1` exactly when its floor refuses 1.0 devices, and a 1.0 device
  hears kind 22 "update" only inside a `sill/1` session; without it, a failed handshake, -9838,
  "disconnected" and a redial for ever. Reworded, with the protocol check's case.)
- This branch's pure checks in `Tests/checks`, and in CI's mutants matrix: `door`, `cable`,
  `asklimits`, `records`, `device`, `hometxt` and `home` are `door-policy`, `cable-link`,
  `ask-limits`, `home-records`, `home-device`, `home-txt` and `home-model`, built by
  `Tests/checks/module.py` (the scratch folder's `lib.py`) from each folder's `module.txt`; the
  step-4 additions to `policy` and `remote-rules` are each folder's `home.swift`. `door-policy`
  gained `afterGate`'s cases (a 10,240-case grid against an oracle, the order of the remote changes,
  and that it admits exactly what `.ready` and the origin gate would admit now) and 8 mutants.
- `sillclient.py --hello-delay=S`: the hello S seconds after the connection is up, for a change made
  while a host's gate holds it.

**Verified** (2026-09-27, 01:20–02:38). A device streamed from Noah's Sill.app throughout
(`no-device.sh`: "1 client" every second), so nothing here used the hardware encoder: every host ran with
`SILL_TEST_SOFTWARE_ENCODER=1` (never probed) and started no stream (the clients picked nothing),
and every listener was on `::1` (`loopback.dylib`, `lsof` by the host's PID before any client), one
host at a time, another session's host waited for first.
- Builds: `swift build -c release` (only the old CaptureProbe warning in a clean build of the final
  tree from `git archive`); iOS Debug and Release for the simulator (signed ad hoc) and Debug for
  `generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO`, each with fresh DerivedData: only the old
  `StreamClient` capture warning (`StreamClient.swift:2572` now). The built Info.plists: Debug
  `_sill._tcp` and `_silltest._tcp`, Release `_sill._tcp`, all with `ITSAppUsesNonExemptEncryption`
  false, version 0.5 (main's) and `PrivacyInfo.xcprivacy`; none of the harness's arguments is in the
  Release binary. The first iOS build of the merge failed on the pbxproj IDs above.
- `Tests/checks/run-all.sh`: all 22 pass: addresses 41, ask-limits 27, cable-link 40, clientlink
  89, compatibility 75, device-gate 58, door-policy 116, encoder-mailbox 38,256, encoder-slowstate
  1,207, fence 14 modes, goodbye 45, home-device 128, home-model 34, home-records 30, home-txt 39,
  ledger 90, origin 66, pairing-address 80, policy 336, protocol 188 and its 8 cross-checks,
  remote-rules 102, update-policy 124. Before its update, goodbye failed 2 of 42: its later reason
  was "pairingRequired".
- The mutants of every check whose sources the merge changed from either side, every one caught:
  addresses 15, ask-limits 15, cable-link 20, compatibility 13, device-gate 14, door-policy 49 (41
  and afterGate's 8), goodbye 18 (16 and pairingRequired's 2), home-device 79, home-model 11,
  home-records 16, home-txt 19, origin 10, pairing-address 35, policy 105, protocol 20,
  remote-rules 52, update-policy 18. Not run again: clientlink, encoder-mailbox,
  encoder-slowstate and fence, whose sources (ClientLink, EncoderMailbox, EncoderSlowState,
  SessionLink, StreamMessage) are main's byte for byte, and ledger, which has none.
- The host gates (`gates.py`, 47 of 47, on the final build): G1, the plain home door at floor "0":
  a hello logged after "Client connected", a device without one served. G2, the plain door at floor
  1.2: an older hello, no hello, and a hello later than 2 s each hear kind 22 "update" (the message
  names the device and the Mac, `"minimumVersion":"1.2"`, `"reconnect":false`) and are never
  registered; one at the floor is served. G3, the TLS home door (`--pairing`, floor "0"): pairing by
  the link, a pinned session, pairing by an ask (the window open: `shown`) and the code, the hello
  logged inside TLS, a plain device refused in the handshake with no goodbye. G4, both TLS doors at
  floor 1.2: pairing is not refused for age; an older pinned session hears "update" inside TLS at
  home and at the remote door, with its Refused line and no connected line; the key paired at home
  is served at the remote door; nine remote sessions whose hellos the gate held at once: 8 served,
  the 9th "busy" (`afterGate`), counted once in the remote door's minute; one "Client left" per
  session served, none for the refused. G5 and G6, the rig (the merged host with the Mac's changes
  on stdin, `sillclient --hello-delay` holding the hello): at home, Require pairing turned on while
  an unpaired key's hello is held gives "pairingRequired" and "Require pairing: disconnecting iPad
  (iPad14,1) at …, which isn’t paired."; a paired key removed meanwhile gives "removed" and "Removed
  …: disconnecting it at …", and its next session is refused in the handshake; at the remote door
  (loopback counted as the internet) internet access off, Remote Access off and Remove each give
  their goodbye and line, never "Remote client connected". Direct Wireless turned off during a hold
  was not run: its stand-in client must be on en0, beyond loopback.
- The CLI's stdout without `--pairing` (`parity.py`) against this branch before the merge (1215f9b
  from `git archive`), each number masked, sorted: idle for 35 s identical (6 lines); with a client
  (a hello, picking nothing) identical but for main's "Client hello: …" line. Main's own CLI was not
  run: its launch probe uses the hardware encoder.
- Sill.app's previews (the bare binary's `-SillRenderPreviews`, each build run from the same path)
  against both parents from `git archive`: 124 files, the union of home-pairing's 104 and main's 100
  (80 names shared); 39 equal to both, 60 to this branch's, 22 to main's; three to neither, as
  expected: `menu.txt` (this branch's samples with main's `update-available` added) and the
  `pairing-longname` pair (this branch's window words with main's made-up Tailscale name).
- Found after the merge commit and fixed: the harness's `notice` case and the compatibility check
  used "pairingRequired" as a reason the device does not know; both use "pairAgain" now (the case
  would have shown pairing at home's own words, not a Mac's message).
- Not run: the simulator (S1–S7) and Noah's devices (P1–P16); main's parity and hardware gates
  (V1–V7, the encoder's) that need the hardware encoder or his devices.
