# Direct Wireless Connection: final plan

Judged 2026-09-24 against `direct-wireless` at 35a1238 (branched from `ipad-host-settings`), with the
repo read only. Two designs were judged: **host-protocol** (the wire, the host and a measured live
listener swap) and **discovery-ux** (the iPad's discovery and UI). This file stands alone: the
implementer should not need either design. Line numbers are at 35a1238; re-read each file before
editing it.

**Noah's decision (2026-09-24):** AWDL is off by default on both ends. An opt-in named "Direct
Wireless Connection" goes in the settings menus: the Mac app's Settings and the iPad's Settings
panel, as a host setting like the other five.

**Why (CLAUDE.md, trackpad stutter).** `includePeerToPeer = true` sits on the host's NWListener
(StreamServer.swift:109) and on the iPad's NWBrowser and NWConnection (StreamClient.swift:171 and
:223). It makes the kernel enable AWDL as `_sill._tcp` registers ("Enabling AWDL due to Mdns"). The
Mac's one radio then leaves its Wi‑Fi channel for up to ~97 ms every 524 ms: 17–33 % of packets
are delayed, and p90 is 48–67 ms against ~4 ms with AWDL off. On a shared network AWDL carries
none of Sill's data.

---

## Decision

**Winner: host-protocol.** It supplies the backbone: the wire field, the host seam, the measured
listener replacement, the CLI, persistence, the test hooks and most of the gates.

From discovery-ux, a trimmed version of the iPad's discovery:

- two browsers and a small pure policy;
- a Search Nearby offer;
- "Direct" rows on the connect screen;
- the panel row's placement and its header line;
- the ledger's rule 9;
- the status menu item;
- the copy style.

### Scores (0–10)

| Criterion | host-protocol | discovery-ux |
|---|---|---|
| Correctness (live listener swap races, kinds 16/17, default off on both ends) | 8 | 5 |
| CLI parity and hard rules | 9 | 7 |
| Native feel on Mac and iPad | 6 | 9 |
| Implementation risk (10 = lowest) | 8 | 4 |
| Fit with the remote-access step (VPN / public IP) | 7 | 7 |
| **Average** | **7.6** | **6.4** |

### Why host-protocol wins

**The swap is measured, not assumed** (experiments in `scratchpad/direct-wireless/exp`, re-read for
this judgement):

- `.cancelled` follows `cancel()` in 0–2 ms. Binding the same port before it fails with
  EADDRINUSE; right after it, it works 10/10, even while accepted connections hold the port. No
  `allowLocalEndpointReuse` is needed: Network.framework listeners already carry SO_REUSEADDR.
- Connections the old listener accepted carry data after it is cancelled.
- Re-registering the same Bonjour name within milliseconds of dropping an AWDL registration
  orphaned the awdl0 record in 5 of 5 runs. The phantom was still listed minutes after the process
  exited. A 0.25–1.5 s pause was clean in 6 of 6.
- So the design binds at once with no service and advertises 1.5 s later.

**Its state stays truthful.**

- The replacement always runs what the target says. If both binds fail, the existing
  listener-failure rule applies.
- So there's no new wire field, no new snapshot field and no second source of truth.
- Late callbacks from a replaced listener are inert (identity guard). The port is read through a
  lock. Requests coalesce, and the newest wins.

**The hard rules stay clean.**

- The test hooks live in StreamServer, behind environment variables that only a test sets.
- The CLI's default path prints nothing new.

**Its iOS side is minimal but has two holes**, which the grafts close:

1. **The first direct connection.** The iPad only ever learns the Mac's setting over a shared
   network, so the Mac can't be found the first time without one.
2. **A single browser that turns peer-to-peer on.** Such a browser can report a Mac at home as seen
   only over awdl0 for a moment, and a reconnect can take that path.

### Where discovery-ux goes wrong, or goes too far

- **The service is re-attached at once** on the replacement listener (its §6.3 step 3). That is
  exactly the measured orphan. Its failure path rebuilds with the previous flag, so the target and
  the running listener disagree, which then needs a `directWirelessNote` wire field, snapshot
  fields and UI.
- **Reconnect matching with the " (n)" suffix stripped would rejoin the wrong Mac.** Two Macs that
  share a computer name ("MacBook Pro" / "MacBook Pro (2)") are common in one household.
- **Test type and construction.** It passes the test type through a CLI flag and
  `-SillTestServiceType`. It also adds a second, advertising `StreamServer` construction in
  synthetic mode, right next to a hard rule.
- **Scope beyond the ask:**
  - NWPathMonitor, and the 10 s and 30 s timers;
  - a two-line status area and nine connect-screen cases;
  - converting the connect screen to Dynamic Type;
  - `Device.direct` with a card detail;
  - a disabled "Always on" row for older hosts (the only older hosts are Noah's dev builds).

### Grafts from discovery-ux (kept)

- **Two iPad browsers.** The network browser always runs with peer-to-peer off. The nearby browser
  is on demand and never runs while connected.
- **Merging their results.** A Mac the network lists is always a network row, so at home it is
  never reached over AWDL.
- **The gate for the nearby browser.** It starts only when a remembered Mac with the setting on is
  missing from the network after 3 s, or when the user taps Search Nearby.
- **`FoundMac`,** a constructible row type the harness can seed, and step 3's list can grow from.
- **The panel row** comes after the closing footer, whose "The stream restarts for a moment" is
  false for this setting. The SillHost sentence moves to the very end.
- **A "Connected directly" header line.**
- **Ledger rule 9:** a field the host did not report is never sent.
- **A status menu item.** It's situational: on in a café, off at home. And Noah said "menus".
- **Copy style:** typographic apostrophes, "Wi‑Fi" with U+2011 in UI strings, and the AirDrop
  comparison.

### Rejected from host-protocol

- **The single iOS browser, recreated with peer-to-peer.** Replaced by the two browsers above.
- **No menu item.** Rejected, as above.
- **"Pause for up to 100 ms about twice a second" in UI footers.** That precision goes in the log
  line and CLAUDE.md; the UI says streaming "can stutter".
- **`StreamServer(…, peerToPeer:)` at construction.** The coordinator keeps
  `StreamServer(advertise: !synthetic)` byte for byte and calls `setPeerToPeer` before `start()`.

---

## Final plan

### 0. Ground rules and hard rules (repeat them in every review)

**Where to work.**

- Worktree `/Users/noah/Downloads/winstream-ipad-settings`, branch `direct-wireless` only.
- Never touch `/Users/noah/Downloads/winstream` and never check out other branches.
- Never push.
- Never edit `docs/BRIEF.md`, `docs/ipad-host-settings-plan.md` or `docs/menu-bar-app-plan.md`.

**Commits.**

- One commit per step (§10).
- Each message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Swift and Apple frameworks only.
- Comments say why.

**Noah's running Sill.app** (PR #4, from /Applications, with the iPad connected):

- never kill it, and never touch `/Applications/Sill.app` or the `me.saffer.sill.mac` domain;
- never run `Scripts/make-app.sh --install/--open`;
- never run `tccutil`;
- never install anything on the iPad.

**Test hosts.**

- Only from `/Users/noah/Downloads/winstream-ipad-settings/.build/release`.
- Start them from Python with `start_new_session=True`, kill them by PID, and leave none running.
- Only `--synthetic` hosts; never select a real window on a `--virtual-display` host.
- Use the bare `SillMenuBar`, never the bundle's binary, which would use `me.saffer.sill.mac`. Its
  defaults domain is `SillMenuBar`; delete it afterwards.
- Nothing you launch gets a permission.

**Code rules.**

1. Never use `MainActor.assumeIsolated` in `Sources/SillHost`; hop with `Task { @MainActor in … }`.
2. Never call `SCStream.updateConfiguration`.
3. **The CLI's default-path stdout stays byte for byte** with no device connected. Check it
   masked and sorted against 35a1238.
   - "Advertising _sill._tcp on the local network." stays.
   - New lines appear only with `--direct-wireless`, with a `SILL_TEST_*` variable, or when a
     device sends kind 17.
   - No new `Stats.bump` key.
4. `server = try StreamServer(advertise: !synthetic)` stays byte for byte
   (StreamCoordinator.swift:129). A synthetic host never registers `_sill._tcp`.
5. **Off by default:**
   - the virtual display;
   - Direct Wireless (`HostConfig.standard`);
   - the iPad's peer-to-peer, which is used only when §6.1's policy says so.
6. Kinds 16 and 17 stay backward compatible:
   - one optional field in each direction;
   - no new kind and no new top-level field;
   - never rename or retype a field, and no enums.
7. Host code stays `package`, never `public`.
8. **Mac UI rules:**
   - Errors show inline, never in alerts.
   - Menu actions stay AppKit target/action (the modal-loop rule).
9. No third-party code and zero operating cost.

**Radio hygiene while testing.**

- AWDL-on checks use test service types only (`_silltest._tcp`), and each lasts under 20 s.
- A `dns-sd -includeAWDL -B` browse adds 1 to the kernel's AWDL service count while it runs, so
  never overlap one with a `ValidSvc` reading.
- **dns-sd options go before the command:** `dns-sd -includeAWDL -B …`. The suffix form
  (`… 45678 -includeAWDL`) registers a TXT record "-includeAWDL" and sets no flag.
- `log` is a zsh builtin: call `/usr/bin/log`, and add `process == "kernel"` to predicates.
- Get awdl0's interface index at run time, never hard-coded (it is 16 here):
  `python3 -c 'import socket; print(socket.if_nametoindex("awdl0"))'`.

**Paths.**

- `SP=/private/tmp/claude-501/-Users-noah-Downloads-winstream/8c347207-ca84-4178-90e4-157cc440b6d8/scratchpad/direct-wireless`
  (run `mkdir -p` on it first).
- `WT=/Users/noah/Downloads/winstream-ipad-settings`.
- Reusable tooling from the host-settings step is in `$SP/../ipad-settings-build/`:
  - `hostlib.py` starts and stops hosts by PID;
  - `ledgercheck/main.swift` is the ledger model check.

### 1. What changes, in one page

**The Mac.**

- A sixth host setting, `directWireless`, is **off** in `HostConfig.standard`. So the CLI and a
  fresh or updated Sill.app ask for no AWDL.
- On, the listener is built with `includePeerToPeer = true`, so its Bonjour registration includes
  AWDL. That is what turns the Mac's AWDL on.
- A change applies **live**. StreamServer replaces its listener:
  1. cancel the old one;
  2. wait for `.cancelled`;
  3. bind the **same port** at once, with no service;
  4. advertise it 1.5 s later.
- Devices already streaming keep streaming, and the stream never restarts for this setting.
- It is changed from Settings › General ("Direct wireless connection"), from the status menu
  ("Direct Wireless Connection"), from a device's panel, from `-SillSetAfter`, and from the CLI's
  `--direct-wireless` flag at launch.

**The iPad.**

- The **network browser** always runs with peer-to-peer off, and connections to the Macs it lists
  are network only.
- A **nearby browser** (peer-to-peer on) runs only while not connected, and only when:
  - a Mac this device last saw with the setting **on** is missing from the network 3 s after the
    connect screen began looking; or
  - the user tapped **Search Nearby**. That is offered when no Mac is listed after 3 s.
- A Mac found only over peer-to-peer interfaces shows as a "Direct" row. Only such a row is
  connected with `includePeerToPeer = true`.
- The panel gets a "Direct Wireless Connection" row as the last group.

### 2. Wire (`Sources/StreamProtocol/HostSettings.swift`)

```swift
public struct StreamSettings {
    …the five…
    /// Direct Wireless Connection: the host's listener and its Bonjour registration include
    /// peer-to-peer Wi‑Fi (AWDL), so devices with no network in common can find and reach it.
    /// Optional because it came sixth: nil is a host without the setting (the device shows no row
    /// and never sends it).
    public var directWireless: Bool?
    public init(maxFPS: Int, bitrate: Int, captureScale: Double, prioritizeSpeed: Bool,
                virtualDisplay: Bool, directWireless: Bool?)      // required: the host must say
}

public struct HostSettingsChange {
    …token and the five…
    public var directWireless: Bool?
    public init(token: Int? = nil, …, virtualDisplay: Bool? = nil, directWireless: Bool? = nil)
    // isEmpty: `&& directWireless == nil`. applied(to:): `if let v = directWireless { r.directWireless = v }`
}
```

**Other changes in the file.**

- `StreamSettings`' init takes `directWireless` with **no default**. Its two callers must pass it:
  `DeviceSettings.streamSettings` and `MockCatalog`. The compiler catches a host that forgets it.
- `SettingsChoices`: no change (it's a Bool).
- `HostSettingsState`: no change.
- The header comment:
  - "The five streaming settings" becomes "the settings a device sees and changes: five for the
    stream, and one (Direct Wireless) for how devices reach the Mac";
  - "All five setting fields nil" becomes "All setting fields nil";
  - add `DebugHooks.apply` (`-SillSetAfter`) to the Sill.app line of the "places a new setting
    goes" list;
  - add one rule: a field a host did not report is never sent (the device ledger's rule 9).

**On the wire.** The synthesized encoder leaves nil out.

```
change   {"token":12,"directWireless":true}
state    {"settings":{"maxFPS":120,"bitrate":15000000,"captureScale":2,"prioritizeSpeed":false,
          "virtualDisplay":false,"directWireless":true},"persistent":true,
          "virtualDisplayAvailable":true,"softwareEncoder":false,"stream":{…}}
answer   the same state plus "answering":12
old host the state has no "directWireless" key → the device decodes nil
```

**Compatibility.**

| | Device at 35a1238 (PR #4) or older | New device |
|---|---|---|
| **Host at 35a1238** (listener always peer-to-peer) | As today | `directWireless` is nil, so there's no row, and rule 9 means nothing is sent. The host is found on the LAN, because its registration covers infrastructure too. The memory is untouched. |
| **New host** | JSONDecoder ignores the key. That device still browses peer-to-peer (its own radio's cost until updated) and finds the Mac on the LAN, or over AWDL when the setting is on. | Full feature |

- An old host that somehow receives the key ignores it. Its answer lacks the field, and the ledger
  counts a refusal: correct feedback.
- A device may set `true` or `false` on every host (§3.1).

### 3. Host (`SillHostCore`)

#### 3.1 `HostConfig.swift` and `DeviceSettings.swift`

```swift
/// Direct Wireless Connection: peer-to-peer Wi‑Fi (AWDL) on the listener and its Bonjour
/// registration, so a device with no network in common can find and reach the Mac. Off by
/// default: while it is on the kernel keeps AWDL up and the Mac's one radio leaves its Wi‑Fi
/// channel up to ~97 ms every 524 ms (CLAUDE.md, trackpad stutter). The listener's, not the
/// pipeline's: a change replaces the listener (StreamServer.setPeerToPeer) and never restarts
/// the stream.
package var directWireless: Bool
```

**`HostConfig`**

- `init(maxFPS:captureScale:bitrate:prioritizeSpeed:virtualDisplay:directWireless:)`: the new
  parameter is **required**, so the compiler finds both call sites (`standard` and the app's
  `HostSettings.init`).
- `standard`: `directWireless: false`.
- `validated()`: no change.
- `changes(to:)` appends `"direct wireless \(onOff(directWireless)) → \(onOff(new.directWireless))"`.
  Also update its doc example.

**`DeviceSettings.swift`**

- `streamSettings` passes `directWireless: directWireless`.
- `applying` gains `if let v = change.directWireless { c.directWireless = v }`.
- `accepted` starts with
  `var ok = HostSettingsChange(prioritizeSpeed: c.prioritizeSpeed, directWireless: c.directWireless)`.
  It is always accepted, on every host, including the synthetic one, where it changes only which
  interfaces the listener accepts on.
- "these five knobs" becomes "these six".

#### 3.2 `StreamServer.swift`: the listener and its replacement

The listener's whole lifecycle becomes the network queue's: its creation after `init`, `start`,
replacement, and the port read. The doc comment, above the properties:

```swift
// MARK: The listener, and Direct Wireless (peer-to-peer Wi‑Fi)
//
// includePeerToPeer on the listener makes its Bonjour registration include AWDL, which is what
// turns the Mac's AWDL on: the kernel counts that registration as an AWDL service ("Enabling AWDL
// due to Mdns"); a peer-to-peer listener without a service counts as none. NWListener fixes its
// parameters at creation, so a change replaces the listener. Measured 2026-09-24: connections the
// old listener accepted are independent of it and keep streaming; `.cancelled` follows `cancel()`
// within 2 ms, and a new listener binds the same port right after it even while accepted
// connections hold the port (binding before it fails with EADDRINUSE); re-registering the same
// name within milliseconds of dropping an AWDL registration orphaned the awdl0 record for minutes
// (5 of 5), while 0.25 s and more removed it cleanly (6 of 6). So: cancel, wait for `.cancelled`,
// bind the same port at once without a service (a device connecting in those milliseconds is
// refused and retries), and advertise `advertiseDelay` later.
```

State, all on `queue` once `start()` has run:

```swift
private var listener: NWListener                 // replaced whole, never reconfigured
private let service: NWListener.Service?         // the Mac's name, the test type (§3.4), or nil (synthetic)
private let serviceIsTest: Bool                  // a test registration never reaches onServiceRegistered
private var peerToPeer = false                   // what `listener` was built with
private var wantedPeerToPeer = false             // the newest request
private enum Swap: Equatable { case idle, cancelling(Int), settling(Int) }
private var swap = Swap.idle
private var swapCount = 0
private var replacementPort: NWEndpoint.Port?    // the port the current replacement tried; nil = any port
private var started = false
private let portLock = NSLock()                  // `port` is read on the main actor
private var readyPort: UInt16?
private static let advertiseDelay: TimeInterval = 1.5   // 6× the shortest clean pause, past the ~1 s the old record's removal takes
private static let cancelTimeout: TimeInterval = 1.0
```

The code, in outline. Write it in this shape; every step is on `queue`.

```swift
init(serviceType: String = "_sill._tcp", advertise: Bool = true) throws {   // signature unchanged
    if advertise { service = .init(name: Host.current().localizedName ?? "Mac", type: serviceType); serviceIsTest = false }
    else if let t = Self.testServiceType { service = .init(name: "Sill test \(getpid())", type: t); serviceIsTest = true }
    else { service = nil; serviceIsTest = false }
    listener = try Self.makeListener(peerToPeer: false, port: nil)
    listener.service = service
    wire(listener)
}

/// Today's TCP options (noDelay, keepalive 5/2/3), `.interactiveVideo`, and the flag; `on: port` when given.
private static func makeListener(peerToPeer: Bool, port: NWEndpoint.Port?) throws -> NWListener

/// Before `start()`: the listener is built with it. After: the listener is replaced. Thread-safe,
/// returns at once; requests during a replacement coalesce and the newest wins.
func setPeerToPeer(_ on: Bool) { queue.async { [self] in wantedPeerToPeer = on; if started { beginSwap() } } }

func start() {
    queue.async { [self] in
        // Set before start (the setting at launch): build the listener with it, nothing to swap.
        if wantedPeerToPeer != peerToPeer, let l = try? Self.makeListener(peerToPeer: wantedPeerToPeer, port: nil) {
            l.service = service; wire(l); listener = l; peerToPeer = wantedPeerToPeer
        }
        started = true
        listener.start(queue: queue)
    }
}

var port: UInt16? { portLock.withLock { readyPort } }
```

**`wire(_ l:)`** (today's three handlers, moved here). Every handler first checks
`guard let self, let l, l === self.listener`, capturing `[weak self, weak l]`, so a replaced
listener's late callbacks are inert.

- **State handler.**
  - `.ready`: set `readyPort = l.port?.rawValue` under the lock.
  - `.failed(e)`, while `swap == .settling(n)`: `l.cancel()`, then `replacementFailed(e, swap: n)`,
    and return.
  - Any other `.failed(e)`: today's rule. `print("Listener failed: \(e)")`, then `onListenerFailed`,
    or `exit(1)` when unset (the CLI).
  - Then `onListenerState?(state)` as today.
- **Registration handler.**
  - A **test service** prints one line on `.add` and returns:
    `Test service registered as "Sill test 4242" (_silltest._tcp, peer-to-peer on); no device browses this type.`
    The on/off reads `l.parameters.includePeerToPeer`, the listener's parameters themselves.
  - Otherwise today's forwarding: `.add` → `onServiceRegistered(name)`, `.remove` →
    `onServiceRegistered(nil)`.
- **`newConnectionHandler`:** `accept(c)` as today, so `clients`, ticks and eviction don't change.

**`beginSwap()`**

1. Guard: `started`, `swap == .idle` and `wantedPeerToPeer != peerToPeer`.
2. `swapCount += 1`, `swap = .cancelling(n)`, and `let oldPort = listener.port`, which is nil for a
   failed listener.
3. On the old listener:
   - set `serviceRegistrationUpdateHandler = nil`;
   - replace its `stateUpdateHandler` with one that acts only on `.cancelled` while
     `swap == .cancelling(n)`, calling `bindReplacement(on: oldPort, swap: n)`;
   - call `cancel()`.
4. Arm a fallback `queue.asyncAfter(cancelTimeout)`. If `swap` is still `.cancelling(n)`, call
   `bindReplacement(on: nil, swap: n)`: the old socket may still hold the port.

**`bindReplacement(on port:, swap n:)`**

1. Set `swap = .settling(n)` and `replacementPort = port`.
2. **TEST ONLY:** if `testSwapFail` is `"port"` and `port != nil`, or it is `"all"`, call
   `replacementFailed(.posix(.EADDRINUSE), swap: n)` without binding, and return.
3. `let l = try? makeListener(peerToPeer: wantedPeerToPeer, port: port)`. On nil, call
   `replacementFailed(.posix(.EINVAL), swap: n)`.
4. `wire(l)`, set `listener = l` and `peerToPeer = wantedPeerToPeer`, then `l.start(queue:)`, with
   **no service**.
5. `queue.asyncAfter(advertiseDelay) { [weak self, weak l] in self?.settled(l, swap: n) }`.

**`settled(_ l:, swap n:)`**

1. Guard: `swap == .settling(n)` and `l === listener`. A retry or a newer swap makes it a no-op.
2. Set `swap = .idle`.
3. If `wantedPeerToPeer != peerToPeer`, call `beginSwap()` and return. That listener was never
   advertised, so the last registration dropped is already 1.5 s old.
4. Otherwise set `l.service = service` and print one line:
   - `Direct wireless on: listening on port 52344 again, advertised again.`
   - `off` for off;
   - with no service, the line ends at "again.".

**`replacementFailed(_ e:, swap n:)`**

1. Guard: `swap == .settling(n)`.
2. **If `replacementPort != nil`:** print
   `Direct wireless on: port 52344 unavailable (<e>); trying another port.`, then call
   `bindReplacement(on: nil, swap: n)`.
3. **Otherwise:**
   - Set `swap = .idle` and `peerToPeer = wantedPeerToPeer`. That way the next change, either way,
     replaces the dead listener, so a toggle doubles as a retry.
   - Apply the existing rule: `print("Listener failed: \(e)")`, then `onListenerFailed(e)` or
     `exit(1)`, then `onListenerState?(.failed(e))`.

A failed replacement never goes back to the old flag: the listener runs what the target says, or it
has visibly failed.

**What each party sees when the setting turns on while the iPad streams** (t = the change):

| t | Host | Devices |
|---|---|---|
| 0 | "Settings from iPad…: direct wireless off → on", publish, answer, then "Settings: direct wireless off → on" and `setPeerToPeer(true)` | The broadcast and the answer arrive first: they are queued on `sill.net` before the swap. |
| +0–2 ms | The old listener `.cancelled`; the new one bound on the same port | A connect in this window is refused, and the iOS client retries. Streaming connections are untouched. |
| ≈ +1 s | | Browsers drop the Mac (goodbye) |
| +1.5 s | Service set; the one "listening … again" line | |
| ≈ +2.2 s | `.add(name)`: the status is unchanged (same name). Kernel `ValidSvc` +2, and "Enabling AWDL due to Mdns" if AWDL was off. | Browsers list the Mac again, also on awdl0 |

Turning it off is the mirror image. The kernel disables AWDL about 3 s after the last AWDL service
leaves, "unless a socket on awdl0 is still active": that's from its log text, and W5 confirms it.

#### 3.3 `StreamCoordinator.swift`

**Construction (:129).** Leave the line exactly as it is, and add one line after it:

```swift
server = try StreamServer(advertise: !synthetic)   // the test pattern is for test clients, not devices
// Direct Wireless is the listener's: built with it at start, replaced when it changes (adopt).
server.setPeerToPeer(config.directWireless)
```

**`start()`,** right before `server.start()` (:283). This is the only new startup line, and it
appears only when the setting is on:

```swift
if config.directWireless {
    print("Direct wireless connection on: also advertised over peer-to-peer Wi-Fi (AWDL), which takes this Mac's Wi-Fi off its channel for up to ~100 ms twice a second.")
}
```

**`adopt(_:)` (:376),** right after `config = next`:

```swift
// The listener's, not the pipeline's: StreamServer replaces it and connected devices keep streaming.
if old.directWireless != next.directWireless { server.setPeerToPeer(next.directWireless) }
```

- A change to Direct Wireless alone reaches `adopt` straight from `applyPending`, because
  `restartNeeded` is false.
- A change mixed with a stream setting reaches it at `select`'s commit: one restart plus one swap.
- A change that lands mid-switch waits for that switch's commit, like every setting. The answer
  and the broadcast go out at once and carry the target.

**`restartNeeded` (:363):** no change. Add one comment line saying `directWireless` is deliberately
absent.

**Unchanged:** `settingsState` (the target already carries the field), `HostStatus`, the
`status.onChange` publishing, and `HostShutdown`.

#### 3.4 Test-only hooks (StreamServer only; off unless set; not in the README)

**`SILL_TEST_SERVICE_TYPE=_silltest._tcp`**

- It is honoured only when `advertise == false`, which means the `--synthetic` hosts: the CLI and
  the bare app.
- It accepts only a `_name._tcp` other than `_sill._tcp`.
- The listener then registers as "Sill test ‹pid›" under that type, with the listener's own
  peer-to-peer flag. So the registration follows Direct Wireless exactly as the real one would, and
  a `dns-sd` browse can check it.
- Devices browse only `_sill._tcp` (both Info.plists), so nothing ever sees it.
- The registration is never forwarded to `onServiceRegistered`, so the app's "Status: Test Pattern
  Mode — … port N" line stays.

**`SILL_TEST_SWAP_FAIL=port|all`**

- `port`: a replacement's same-port attempt fails as EADDRINUSE, without binding.
- `all`: the any-port attempt fails as well.
- It exercises the fallback and the exit rule without a real port conflict.

Read both once, into `private static let`s, with a `// TEST ONLY` comment saying why. List them in
StreamServer's doc comment and in CLAUDE.md's "Build and run".

### 4. CLI (`Sources/SillHostCLI/main.swift`)

Add this next to `--virtual-display` (:28-29):

```swift
// `SillHost --direct-wireless`: also advertise over, and accept connections from, peer-to-peer
// Wi-Fi (AWDL), so a device with no network in common can connect. Off by default: while it is on
// the Mac's radio leaves its Wi-Fi channel up to ~97 ms every 524 ms, which is the stutter in
// CLAUDE.md. A device can still turn it on or off; that lasts until SillHost quits.
config.directWireless = CommandLine.arguments.contains("--direct-wireless")
```

- **Output:**
  - Without the flag, nothing changes.
  - With it, the coordinator's one line from §3.3 prints.
  - "Advertising _sill._tcp on the local network." stays byte for byte in both cases.
- **A device's change** swaps live and lasts until the CLI quits (`persistent: false` already says
  so). It prints three lines: "Settings from …", "Settings: …", and the swap line.
- **Exit rule:** unchanged. It is reached only after a swap's same-port and any-port attempts have
  both failed. Under `--virtual-display`, `atexit` still restores a staged window.

### 5. Sill.app

**`HostSettings.swift`**

- `Key.directWireless = "directWireless"`.
- Registered from `standard` (false).
- Loaded with `defaults.bool(forKey:)` and passed to the now-required init parameter.
- Written in `save(changedFrom:)` only when it changed.
- What follows:
  - Existing installs have no key, so they come up with AWDL off after the update.
  - `-directWireless YES` overrides it for one run without saving.
  - A device's change arrives through `onDeviceSettingsChange`, is saved like a click and shows
    live.

**Settings › General (`SettingsPanes.swift`)**

- Change `case .general` (:16) to `GeneralPane(model: model, settings: model.settings)`.
- `GeneralPane` gains `@Bindable var settings: HostSettings`.
- Add a new `Section` directly after the "Visible on your network as" section (:91-107), because it
  is about how devices reach the Mac:

  ```swift
  Section {
      Toggle("Direct wireless connection", isOn: $settings.config.directWireless)
  } footer: {
      Footnote("Lets your iPhone and iPad connect when they’re near this Mac, even without a shared Wi‑Fi network, the way AirDrop does. While it’s on, this Mac’s Wi‑Fi keeps stepping away from your network, so streaming over Wi‑Fi can stutter. Anyone nearby with Sill can find and connect to this Mac.")
  }
  ```

- The label is sentence case, like the pane's other toggles. It stays enabled in `--synthetic`
  (it is saved, and changes the listener's flag).

**The status menu (`StatusItemController.swift`)**

- `MenuEntry.Action` gains `case setDirectWireless(Bool)`. It is absolute, under
  `setVirtualDisplay`'s comment, and for the same reason: a device can change it while the menu is
  open.
- `MenuBuilder` puts an item at the **top of the second group**, before `var loginNote` (:82). That
  group is about how Sill runs on this Mac, not about the picture:

  ```swift
  menu.append(MenuEntry(kind: .item, title: "Direct Wireless Connection",
                        subtitle: "No shared network needed; Wi‑Fi streams can stutter",
                        checked: config.directWireless, action: .setDirectWireless(!config.directWireless)))
  ```

- The handler (next to :242): `case .setDirectWireless(let on): model.settings.config.directWireless = on`.

**`DebugHooks.swift`**

- `apply` gains `case "directWireless": config.directWireless = flag`.
- The doc comment's key list (:12-15) gains `directWireless`.

**Unchanged:** `AppModel`, the card and `StatusText`.

### 6. iOS

#### 6.1 Discovery

**New file `iOSClient/DiscoveryPolicy.swift`.** Foundation only, so it can be checked with
`swiftc` (H13) the way the ledger is.

pbxproj entries (both IDs checked free):

- a `PBXBuildFile` `A1000001000000000000A014`;
- a `PBXFileReference` `A1000001000000000000F014`;
- a child of the main group `A1000001000000000000C001`;
- an entry in the Sources phase `A1000001000000000000B001`.

```swift
/// When the device also looks for Macs over peer-to-peer Wi‑Fi (AWDL), and how a nearby result is
/// told from a network one. AWDL takes the radio off its Wi‑Fi channel (CLAUDE.md, trackpad
/// stutter), so the device asks for it only when a Mac it has seen with Direct Wireless Connection
/// on is missing from the network, or when the user taps Search Nearby, and never while connected.
enum DiscoveryPolicy {
    /// A Mac on the LAN answers mDNS well within this: the network gets the first word, so at home
    /// the nearby search never starts.
    static let networkFirst = 3.0
    static let memoryCap = 16

    struct Input: Equatable {
        var now: Double                 // ProcessInfo.systemUptime
        var connected: Bool             // a connection is ready, either route
        var onNetwork: Set<String>      // names the network browser lists
        var remembered: Set<String>     // Macs whose last state said Direct Wireless is on
        var searchingSince: Double      // launch, or the last connection ending
        var askedNearby: Bool           // Search Nearby tapped since the last connection
        var nearbyRunning: Bool         // sticky until a connection is ready
        var listed: Int                 // rows on the connect screen
    }
    struct Output: Equatable {
        var browseNearby: Bool
        var showHint: Bool              // the hint sentence; its button only while !browseNearby
        var recheckAt: Double?
    }

    static func decide(_ i: Input) -> Output {
        if i.connected { return Output(browseNearby: false, showHint: false, recheckAt: nil) }
        let due = i.searchingSince + networkFirst
        let missing = !i.remembered.subtracting(i.onNetwork).isEmpty
        // Sticky once started: rows found nearby must not vanish because another Mac turned up.
        let browse = i.askedNearby || i.nearbyRunning || (missing && i.now >= due)
        return Output(browseNearby: browse, showHint: i.listed == 0 && i.now >= due,
                      recheckAt: i.now < due ? due : nil)
    }

    /// awdl0 and llw0 report the interface type .wifi like en0; only the name tells them apart.
    static func isPeerToPeer(_ interfaceName: String) -> Bool

    /// The connect screen's rows, in order: every network name (reached over the network even when
    /// the nearby browser sees it too), then each nearby name seen on peer-to-peer interfaces alone.
    /// A nearby result also on a network interface is left out: the network browser lists it a
    /// moment later.
    static func rows(network: [String], nearby: [(name: String, interfaces: [String])]) -> [(name: String, direct: Bool)]

    /// The memory after a state from `mac`: true moves it to the front, false removes it, nil (an
    /// older host) keeps the list; capped at memoryCap; an empty name changes nothing.
    static func remember(_ list: [String], mac: String, directWireless: Bool?) -> [String]
}
```

**`StreamClient.swift`**

- **Rows.** `hosts` (:12) is replaced by the constructible
  `struct FoundMac: Identifiable, Hashable { let name: String; let endpoint: NWEndpoint; let direct: Bool; var id: String { name } }`
  and `@Published var macs: [FoundMac] = []`. `NWBrowser.Result` has no public initializer, so the
  harness could not seed it.
- **New published state.** `@Published var searchingNearby = false`,
  `@Published var showsNearbyHint = false` and `@Published var connectedDirectly = false`. Their
  setters are internal, like `settings`, because MockCatalog seeds them.
- **New private state:**
  - `networkBrowser`, `nearbyBrowser`, `networkResults`, `nearbyResults`;
  - `searchingSince` (uptime), `askedNearby`, and `discoveryRecheck: DispatchWorkItem?`;
  - the memory, UserDefaults `"Sill.directWirelessMacs"` (`[String]`, most recent first).
- **`startBrowsing()` (:169):**
  - `searchingSince = now`.
  - Start the network browser with `NWParameters()`. Its `includePeerToPeer` is left at its default,
    false, and a comment says why. Results go to main.
  - Call `discoveryChanged()`.
- **`discoveryChanged()` (main):**
  1. `macs` = `DiscoveryPolicy.rows(…)`, each mapped to the endpoint from the browser that listed
     it.
  2. `updateDiscovery()`.
  3. `reconnectIfListed()`.
- **`updateDiscovery()` (main):**
  1. Run `decide` on the current inputs.
  2. Start the nearby browser (`includePeerToPeer = true`, same handler shape), or cancel it and
     clear `nearbyResults`.
  3. Set `searchingNearby` and `showsNearbyHint`.
  4. If `status` is one of the two idle texts, set the one that matches.
  5. Re-arm `discoveryRecheck` at `recheckAt`.
  6. A DEBUG `print("discovery: nearby search on|off")` on each change; S4 reads it.
- **`connect(to mac: FoundMac)`** replaces `connect(to result:)` (:203). It calls
  `connect(to: mac.endpoint, name: mac.name, peerToPeer: mac.direct)`.
- **`connect(to endpoint:name:peerToPeer: Bool = false)` (:210):**
  - `params.includePeerToPeer = peerToPeer`, replacing :223.
  - The status reads "Connecting to ‹Mac› directly…" when `peerToPeer` is set.
  - In the `.ready` case, on the network queue before hopping to main:
    `let direct = peerToPeer && Self.runsPeerToPeer(c.currentPath)`. That is true when
    `availableInterfaces` has an awdl/llw name, or the remote endpoint's scope is `%awdl…` or
    `%llw…`.
  - On main, next to `connected = true`: `connectedDirectly = direct; askedNearby = false; updateDiscovery()`.
    This stops the nearby browser; the network browser keeps running.
  - `-SillConnect` and everything else use the default, false.
- **`tearDown` (:302)** also sets:
  - `connectedDirectly = false`;
  - `searchingSince = now`;
  - `askedNearby = false`.

  Then the callers (`disconnect`, `connectionLost`) call `updateDiscovery()` after it.
- **`reconnectIfListed()`** replaces the browse handler's block (:176-184) and the timer's lookup
  (:291-299).
  - It picks `macs.first { $0.name == wanted && !$0.direct } ?? macs.first { $0.name == wanted }`.
  - Names match **exactly**, as today. Never strip " (n)": two Macs can share a computer name.
  - The status reads "Reconnecting to ‹Mac› directly…" for a direct row.
- **`searchNearby()`:** `askedNearby = true; updateDiscovery()`.
- **The memory.** In `receiveSettings` (:647), only when `connection != nil` (never the DEBUG
  mock's answers) and `macName` is not empty:
  - `let next = DiscoveryPolicy.remember(memory, mac: macName, directWireless: state.settings.directWireless)`;
  - if it changed, save it and call `updateDiscovery()`.

  Every state carries the field: on connect, broadcasts and answers.
  - The key is the window list's `macName`, as `windowOrder` uses. `sendCatalog` sends the list
    before the state.
  - The memory is a discovery hint only. The panel never reads it, so the ledger's rule 7 ("never
    persist a Mac's settings") holds.
  - Launch arguments seed it for one run: `-Sill.directWirelessMacs '("Mac mini")'`, or `'()'` to
    clear it.
- **DEBUG `mockDiscovery` flag,** set by MockCatalog's connect cases. While it is set,
  `searchNearby()` and `connect(to mac:)` only update the published state and status, and never
  touch the network.

#### 6.2 The connect screen (`ConnectScreen`, ContentView.swift:196-233)

Top to bottom, in the existing 380 pt column and fixed sizes:

1. The title, unchanged.
2. **`client.status`**, whose idle text now follows the nearby search.
3. **Rows:** `ForEach(client.macs)`.
   - A direct row passes `trailing: "Direct"` to `DrawerRow`.
   - It gets `.accessibilityHint("Connects without a shared Wi‑Fi network")`.
   - Its action is `client.connect(to: mac)`.
   - The title truncates and "Direct" never does. If S1 shows otherwise, give the trailing text
     `.fixedSize()`.
4. **When `showsNearbyHint`:**
   - the hint sentence (13 pt, muted, wrapping);
   - then, while `!searchingNearby`, a **Search Nearby** button:
     - accent text, 15 pt semibold;
     - leading-aligned, at least 44 pt tall, the column's width;
     - `.accessibilityHint("Also looks for a Mac with Direct Wireless Connection turned on, without a Wi‑Fi network.")`.
   - After a tap, the button goes and the status reads "…and nearby". It needs no spinner.

#### 6.3 The Settings panel row (`HostSettingsPanel.swift`)

- **Closing footer (:184).** It becomes only "Applies to every device streaming from \(mac). The
  stream restarts for a moment." Its SillHost sentence moves to the very end, as its own footnote.
- **The new group, after the closing footer.** It comes after the footer because this setting
  never restarts the stream. It is also the least-changed row with the longest footer, so it goes
  last on the 259 pt outer display. It shows only when `shown.directWireless != nil`:

  ```swift
  // Direct Wireless Connection: how devices reach the Mac, not how it streams; after the closing
  // footer, whose "the stream restarts" is not true of it.
  if let direct = shown.directWireless {
      Rows {
          Toggle(isOn: binding(direct) { HostSettingsChange(directWireless: $0) }) {
              RowTitle(title: "Direct Wireless Connection", since: client.settings.pendingSince(.directWireless))
          }
          .accessibilityHint(client.connectedDirectly ? "Turning this off can disconnect this \(device)." : "")
          .rowFrame()
      }
      Footnote(text: directFooter)   // §7
  }
  if !state.persistent { Footnote(text: "SillHost keeps these until it quits.") }
  ```

- **The toggle is never disabled.** Turning it off from a directly connected device is allowed:
  - the Mac is nearby by definition;
  - it's parity with the Mac;
  - the consequence is written beside the switch.
- **The header.** When `client.connectedDirectly`, add a line "Connected directly", in the style of
  "On the virtual display" (:98). `spokenReadout` gains a `direct` parameter and appends
  ", connected directly".
- **Pending, refused and timeout** go through the existing ledger unchanged. The answer comes before
  the swap, so the spinner (300 ms) normally never shows.

#### 6.4 The ledger (`HostSettingsLedger.swift`)

- `SettingsField` gains `directWireless`, appended last.
- `fields`, `only` and `adding` gain it.
- The comment "One of the five" becomes six.
- **Rule 9,** in `pick`'s loop, before the value compare: a field this Mac did not report is never
  sent. That makes "never sends to an older host" a property of the model, not of the view.

  ```swift
  if field == .directWireless, shown.directWireless == nil { continue }
  ```

- Add rule 9 to the numbered list in the doc comment.

#### 6.5 Harness (DEBUG; ContentView's contract comment at :51-90 and CLAUDE.md)

**`MockCatalog`**

- Every existing case seeds `directWireless: false`, so the row shows by default.
- New `SettingsCase`s:
  - `direct`: on;
  - `directlink`: on, plus `client.connectedDirectly = true`, which shows the header line and the
    footer's extra sentence;
  - `nodirect`: `directWireless: nil`, an older host, with no row.
- `mockAnswer` needs nothing: `applied(to:)` carries the field.

**`-SillConnectCase looking|hint|nearby`**

- `LayoutHarness.Spec.connectCase`. When it is set (and not `-SillLive`), the fake screen shows
  `ConnectScreen` on `MockCatalog.connectClient(case)`. That mock is not connected, never browses,
  and has `mockDiscovery` set.
- The cases:
  - `looking`: status "Looking for Macs on this network", no rows;
  - `hint`: no rows, `showsNearbyHint`, and the Search Nearby button;
  - `nearby`: status "…on this network and nearby"; rows "Studio" (network) and "Mac mini" with
    "Direct". The rows are built from `NWEndpoint.service(name:type:domain:interface:)`.

### 7. Copy

- In UI strings, "Wi‑Fi" is spelled with **U+2011** (a non-breaking hyphen) and apostrophes are
  typographic.
- Log lines are ASCII.
- "iPad" becomes "iPhone" by idiom, as the panel already does.

| Where | Text |
|---|---|
| Mac Settings › General, toggle | Direct wireless connection |
| Its footer | Lets your iPhone and iPad connect when they’re near this Mac, even without a shared Wi‑Fi network, the way AirDrop does. While it’s on, this Mac’s Wi‑Fi keeps stepping away from your network, so streaming over Wi‑Fi can stutter. Anyone nearby with Sill can find and connect to this Mac. |
| Mac status menu | **Direct Wireless Connection** — subtitle "No shared network needed; Wi‑Fi streams can stutter" |
| iPad panel row | Direct Wireless Connection |
| Its footer (`directFooter`) | Lets devices reach ‹Mac› without a shared Wi‑Fi network, the way AirDrop does. While it’s on, streaming over Wi‑Fi can stutter. |
| Footer addition when `connectedDirectly` | This iPad is connected directly: turning this off can disconnect it. |
| Toggle accessibility hint when `connectedDirectly` | Turning this off can disconnect this iPad. |
| Panel header line | Connected directly (spoken: “…, connected directly”) |
| Closing footer | Applies to every device streaming from ‹Mac›. The stream restarts for a moment. |
| Last footnote (`persistent == false`) | SillHost keeps these until it quits. |
| Connect status, idle | Looking for Macs on this network / Looking for Macs on this network and nearby |
| Connecting / reconnecting | Connecting to ‹Mac›… / Connecting to ‹Mac› directly… / Reconnecting to ‹Mac›… / Reconnecting to ‹Mac› directly… |
| Direct row trailing text / hint | Direct / Connects without a shared Wi‑Fi network |
| Hint sentence | Your Mac has to be on the same Wi‑Fi network as this iPad, or have Direct Wireless Connection turned on in Sill. |
| Button / hint | Search Nearby / Also looks for a Mac with Direct Wireless Connection turned on, without a Wi‑Fi network. |
| Log: startup, only when on | Direct wireless connection on: also advertised over peer-to-peer Wi-Fi (AWDL), which takes this Mac's Wi-Fi off its channel for up to ~100 ms twice a second. |
| Log: a change | Settings: direct wireless off → on (from `changes(to:)`; "Settings from ‹device›: …" as today) |
| Log: swap done | Direct wireless on: listening on port 52344 again, advertised again. |
| Log: same port refused | Direct wireless on: port 52344 unavailable (‹error›); trying another port. |
| Log: test registration | Test service registered as "Sill test 4242" (_silltest._tcp, peer-to-peer on); no device browses this type. |

### 8. Edge cases

| Case | Behaviour |
|---|---|
| Upgrade, key absent | Off (registered default): Sill stops asking for AWDL. |
| Toggle while streaming (Mac, menu or device) | No restart. The answer and broadcast come first, then the replacement on the same port. The Mac leaves browse results for ~2 s. Streaming devices are unaffected. |
| Rapid toggles (double tap, the menu and a device racing) | `setTarget` settles the target. `wantedPeerToPeer` coalesces the requests: at most one extra replacement, and the registration is made once the value has held for 1.5 s. |
| Mixed with a stream change | One restart for the stream and one replacement for the listener. |
| Lands mid-switch (virtual display staging) | Waits for that switch's commit, as any setting does. The answer is immediate. |
| A device connecting in the bind gap (ms) | Refused. The iOS client retries on its timer, or the user taps again. |
| `.cancelled` never arrives | After 1 s the replacement binds any port. |
| The same port is refused | It binds any port and logs it. Bonjour carries the new port; test clients re-read it with lsof. |
| Both binds fail | The existing rule: the app shows "Not Visible on the Network" and keeps running (a later toggle retries); the CLI exits 1. |
| The listener had already failed (app) | A toggle replaces it, so it doubles as a retry. |
| No network (`.waiting`) | The replacement waits like the first listener did, and the service registers when the network returns. |
| Turned off while a device is connected directly | That connection is left alone. The kernel should keep AWDL while a socket on it is active (W5). New direct connections are refused. The device's footer warns it "can disconnect". |
| Quit or Ctrl-C mid-replacement | The process exits and mDNSResponder drops the registration. Nothing to restore. |
| Name clash on re-registration | `.add("Mac (2)")` updates the status as today. Measured: the same name came back 10 of 10 times. |
| Quick relaunch with it on | The new process registers a second or more after the old one exited, past the measured danger window. W7 checks it. |
| The iPad remembers a Mac that has since turned it off | At home, nothing happens (the Mac is on the network). Away, a nearby search runs on the connect screen and finds nothing. The next state from that Mac corrects the memory; a reinstall forgets it. |
| Two Macs, one reachable only nearby and never seen with it on | Not offered while another Mac is listed (the hint needs an empty list). One connection over a shared network with the setting on teaches the device. |
| iPad at 35a1238 with the new host | Finds the Mac on the LAN. Its own always-on peer-to-peer browse still costs its radio until updated. |
| New iPad with the 35a1238 host | No row, the memory untouched, finds the host on the LAN. |
| Mac on Ethernet with Wi‑Fi off | On does nothing (no awdl0), and is harmless. |
| AirDrop, Sidecar, Universal Control | They can hold AWDL on regardless. Off means Sill doesn't ask for it. |
| The iOS simulator | Its browsers run in the Mac's mDNSResponder, so a nearby search there turns the **Mac's** AWDL on. Never measure latency with a simulator sitting on the connect screen. |
| Security | On, anyone within radio range running Sill can find and connect to the Mac, with no pairing until M5. Default off shrinks today's exposure (the flag has been on since the first commit). The host-settings plan's §9 payload-length cap matters more with it on; flag it as its own task. |

### 9. Test gates

The **H** gates are headless and need no permissions. The **S** gates are simulator gates on the
iPad Pro 13-inch, UDID 40522E9E-8B13-4676-BC94-D94FDD048471. The **W** gates are Noah's, on the
iPad mini and Sill.app, and are handed over.

Builds:

- Mac: `cd $WT && swift build -c release 2>&1 | grep -E "error|warning:|Build complete"`.
- iOS:
  `xcodebuild -project $WT/iOSClient/Sill.xcodeproj -scheme Sill -destination 'generic/platform=iOS Simulator' -derivedDataPath $SP/dd-ios CODE_SIGNING_ALLOWED=NO build`,
  plus `-configuration Release` for the Release check.

Throughout, `AWDL0` is awdl0's interface index, read at run time.

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight, before any edit.** `mkdir -p $SP/base && git -C $WT archive 35a1238 \| tar -x -C $SP/base`, then build it. Take the base logs: `SillHost --synthetic` idle 35 s (`base-idle.log`), and with `Scripts/sillclient.py PORT 5 desktop` (`base-client.log`). Take base previews: `defaults delete SillMenuBar; $SP/base/.build/release/SillMenuBar -SillRenderPreviews $SP/prev-base`, with md5s. Copy this plan to `$WT/docs/direct-wireless-plan.md` (untracked until step 6). Copy `hostlib.py` and `ledgercheck/` from `$SP/../ipad-settings-build/`. | The files exist |
| H1 | Builds | Mac: only the known CaptureProbe warning. iOS Debug and Release: only the known StreamClient ImplicitStrongCapture warning. |
| H2 | **CLI byte for byte.** H0's two runs on the new build. Normalise: drop `[1s]` lines, mask digits, sort. | The diffs against base are empty. "Advertising _sill._tcp on the local network." is present. sillclient's first kind 16 shows `dw=0`. |
| H3 | **Off by default, the registration.** `SILL_TEST_SERVICE_TYPE=_silltest._tcp .build/release/SillHost --synthetic`. Run `dns-sd -t 3 -includeAWDL -B _silltest._tcp local` twice, 3 s apart. | The test line says `peer-to-peer off`. "Sill test ‹pid›" is listed on other interfaces, **never** on `AWDL0`. |
| H4 | **On at launch.** The same with `--direct-wireless`. | The startup line appears, and the test line says `peer-to-peer on`. There is a row on `AWDL0` within ~2 s, and the first kind 16 says `dw=1`. After `kill`, a continuous browse shows `Rmv` on `AWDL0`, and a fresh browse 5 s later has no row: no orphan. |
| H5 | **Live on and off with a streaming client.** H3's host, plus a continuous `dns-sd -includeAWDL -B _silltest._tcp local` for 30 s, plus `sillclient.py PORT 20 desktop --stats --set=directWireless=1@4 --set=directWireless=0@12 --expect=directWireless=0`. | Each change gives "Settings from sillclient: …", "Settings: direct wireless …", and exactly one "Direct wireless on\|off: listening on port P again." about 1.5 s later. `lsof -nP -iTCP -sTCP:LISTEN -a -p PID` shows the same P at 2, 8 and 16 s. The client gets frames every second, no EOF, and parameter sets only at the start. The answers carry `answering=1` with dw=1 and `answering=2` with dw=0. The browse shows `Add` on `AWDL0` about 1.5–3 s after the 4 s change and `Rmv` within ~2 s of the 12 s one. After exit, a fresh browse shows no `AWDL0` row. |
| H6 | **Connecting during a swap.** Beside H5's client, a Python loop opens a connection to P every 5 ms from 3.9 to 4.3 s, reads 1 s, and closes. | At most 3 are refused. Every accepted one receives a kind 2 window list. H5's client is unaffected. |
| H7 | **Bursts and mixes.** `--set=directWireless=1@4 … =0@4.1 … =1@4.2 … =0@4.3 … =1@4.4 --expect=directWireless=1`. Then `--set=directWireless=1,bitrate=25000000@4`. | Five answers in token order, and at most two "listening … again" lines. The final registration is on `AWDL0`, and there's no orphan 10 s after exit. The mix gives one restart (one new parameter set) and one swap line. |
| H8 | **Fallbacks.** `SILL_TEST_SWAP_FAIL=port` with H5. Then `SILL_TEST_SWAP_FAIL=all` on the CLI with `--set=directWireless=1@4`. Then the same on the bare app. | `port`: "port P unavailable … trying another port", then "listening on port Q again" with Q ≠ P in lsof, and the client keeps streaming. `all` on the CLI: "Listener failed: …" and exit status 1. On the app: "Status: Not Visible on the Network — …"; the app keeps running and so does the client's stream. |
| H9 | **The app.** `defaults delete SillMenuBar`, then `SILL_TEST_SERVICE_TYPE=_silltest._tcp .build/release/SillMenuBar --synthetic -SillLogFile $SP/app.log -SillSetAfter '3 directWireless=1; 9 directWireless=0' -SillQuitAfter 14`. Then a run with `sillclient --set=directWireless=1@3 --expect=directWireless=1,persistent=1`. Then a relaunch. | The first run: one "Settings:" and one swap line per change, and `defaults read SillMenuBar directWireless` ends at 0. "Status: Test Pattern Mode — … port N" is printed once, with N unchanged. The sillclient run saves 1. The relaunch: the first kind 16 says dw=1, the startup line appears, and there's an `AWDL0` row from the start. Then `defaults delete SillMenuBar`. |
| H10 | **Compatibility.** (a) sillclient without the key. (b) `--raw17={"token":1,"directWireless":true}@3`. (c) Against `$SP/base/.build/release/SillHost --synthetic`: `--set=directWireless=1@3`. (d) A scratch `swiftc` decode check: the 35a1238 `HostSettings.swift` (from `git show`) decodes a new state and change; the new types decode a base state and change. | (a) Unchanged. (b) Accepted, dw=1. (c) The answer lacks the key (`dw=-`) and the host logs nothing about it. (d) All decode, with nil for the missing field. |
| H11 | **Previews.** `defaults delete SillMenuBar; .build/release/SillMenuBar -SillRenderPreviews $SP/prev-new` | Only `pane-general-{light,dark}.png` and `menu.txt` differ from base. `menu.txt` differs by exactly one unchecked "Direct Wireless Connection — No shared network needed; Wi‑Fi streams can stutter" line per sample. Look at both General panes. |
| H12 | **Ledger.** Extend `$SP/ledgercheck/main.swift`: the host's acceptance copy, and every `StreamSettings` construction gets the sixth field. Add these scenarios: a state without the key decodes as nil; `pick(directWireless: true)` against it returns nil (rule 9); on → off → on never shows off after the first answer; refusal and timeout for the field; `directWireless` in the random model's alphabet. Run with `swiftc -O $WT/Sources/StreamProtocol/HostSettings.swift $WT/iOSClient/HostSettingsLedger.swift $SP/ledgercheck/main.swift -o $SP/ledgercheck/ledgercheck && $SP/ledgercheck/ledgercheck 5000` | All pass, and both mutants are still caught |
| H13 | **Discovery policy.** `swiftc -O $WT/iOSClient/DiscoveryPolicy.swift $SP/policycheck/main.swift -o $SP/policycheck/check && $SP/policycheck/check`. Adapt the draft in `$SP/policycheck/` to this trimmed policy. | Every scenario passes. `decide`: home default never browses and never hints; home with memory and the Mac listed by 3 s never browses; a remembered Mac missing browses from exactly 3.0 s; first use hints at 3 s and never browses by itself; Search Nearby browses at once (the hint stays, the button goes); sticky; connected means never; two remembered Macs with one missing browses; `recheckAt` is the 3 s mark only before it. `rows`: a network name is never direct; nearby [awdl0] is direct; nearby [en0] is left out; nearby [] is left out; order. `remember`: true fronts, false removes, nil keeps, cap 16, empty name. `isPeerToPeer`: awdl0 and llw0 yes; en0 and utun3 no. |
| H14 | **Hard rules** | `git -C $WT diff 35a1238 -- Sources/SillHost` adds no `assumeIsolated` or `updateConfiguration`. `StreamServer(advertise: !synthetic)` is present byte for byte. `HostConfig.standard` has `virtualDisplay: false` and `directWireless: false`. `grep -rn "includePeerToPeer = true" Sources iOSClient` finds only the nearby browser; the listener (`makeListener`) and the connection take the flag as a variable. `git diff --stat 35a1238` lists none of the three protected docs. |
| H15 | **Host-settings regression** (spot run with the `ipad-settings-build` tooling) | A burst of three stream changes gives one restart. `virtualDisplay` on the `--virtual-display --synthetic` host gives no restart. Two clients changing different fields both stick. A reconnect gets a fresh kind 16. The menu's Virtual Display item still sets what it showed. |
| S1 | **Photo sheet.** Panel cases `default`, `direct`, `directlink`, `nodirect` and `cli` (`-SillSettings 1 -SillSettingsCase …`), with the middle swiped up where the new group sits below the fold. Connect cases `looking`, `hint` and `nearby` (`-SillConnectCase …`). Each at 1000x710, 710x500, 710x1000 and 500x710. Also `directlink` and `hint` at 500x710 with `xcrun simctl ui 40522E9E-8B13-4676-BC94-D94FDD048471 content_size accessibility-extra-large` (reset afterwards). Rotate quarter-turned shots back with `sips -r 270`. | Nothing clipped, and the header and foot pinned. The row and both footnotes read fully. "Connected directly" fits the header. "Direct" is never truncated beside a long name. The hint wraps and the button is ≥ 44 pt. Send Noah the sheet (SendUserFile). |
| S2 | **Harness taps** (inspect, then tap) | Panel `direct`: the switch moves at once and settles after 0.35 s. `nodirect`: no row. Connect `hint`: Search Nearby → the button goes and the status reads "…and nearby", with no browser started (mock). |
| S3 | **Live by address.** `SILL_TEST_SERVICE_TYPE=_silltest._tcp .build/release/SillHost --synthetic`, and the simulator with `-SillLayout 710x1000 -SillLive 1 -SillConnect 127.0.0.1:PORT -SillSettings 1`. Toggle from the simulator, then `sillclient --set=directWireless=0@5` from the Mac side. Repeat against the bare `SillMenuBar --synthetic`. | The host's three lines appear and the stream continues (screenshots before and after). The lsof port is unchanged. The panel follows the Mac-side change. The app saves it in `SillMenuBar`. Afterwards run `xcrun simctl spawn 40522E9E-8B13-4676-BC94-D94FDD048471 defaults delete me.saffer.sill Sill.directWirelessMacs` and `defaults delete SillMenuBar`. |
| S4 | **The browse policy, live.** Launch the normal app (not the harness) with `xcrun simctl launch --console-pty …` from Python, with a timeout, three times: with no memory, with `-Sill.directWirelessMacs '("Nowhere Mac")'`, and with `'()'`. **Never tap a row: Noah's Mac is listed.** | No memory: no "nearby search on", and Noah's Mac is a plain row. With the seed: "discovery: nearby search on" about 3 s after launch, and optionally the kernel's `ValidSvc` mode +1 over 20 s. `'()'`: back to none. |

**Noah's checks (handed over; they need the two installs).**

| # | Check |
|---|---|
| W1 | **The payoff, off by default.** Install both builds. Run `/usr/bin/log stream --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "abling AWDL" OR eventMessage CONTAINS "ValidSvc")'`. Expect "Disabling AWDL due to no services and no active sockets" soon after the old Sill quits (unless AirDrop, Sidecar or Universal Control hold it), and `BonJourTrig 0` while streaming. Five minutes on a still window with trackpad strokes: the host's `client iPad: … rtt m/M` maxima stay near the LAN's, with no ~100 ms spikes. |
| W2 | **A/B in one session.** Turn it on from the iPad panel while streaming. Expect no restart and one "listening on port N again" line (same N). The Mac's Settings toggle and the menu (on reopening) follow. `defaults read me.saffer.sill.mac directWireless` reads 1. "Enabling AWDL due to Mdns" appears and the rtt maxima rise. Two minutes later, turn it off from the status menu: the maxima fall back, and "Disabling AWDL…" follows within seconds. |
| W3 | **Direct, remembered.** With it on, put the iPad on another network (the iPhone's hotspot) and leave the Mac on home Wi‑Fi. Within about 3–5 s the connect screen shows the Mac with "Direct". Tap it: the host log shows "Client connected: [fe80::…%awdl0]…" and the panel header says "Connected directly". Note the frame age and rtt medians and maxima. |
| W4 | **First use.** Delete and reinstall the iPad app, and use café conditions. After 3 s the hint and Search Nearby appear. Tap it, and the Mac appears as Direct; connect. Relaunch in café conditions: it searches nearby by itself after 3 s. |
| W5 | **Off while connected directly (from the Mac).** Does the stream continue while the socket is active, and for how long? After disconnecting, the iPad no longer finds the Mac, as designed. Fix the footer's "can disconnect" wording to match what happened. |
| W6 | **Home → café while streaming, with it on.** Take the iPad off the home Wi‑Fi. It reconnects directly within about 5 s without a tap ("Reconnecting to ‹Mac› directly…"). |
| W7 | **Relaunch Sill.app with it on.** `dns-sd -t 3 -includeAWDL -B _sill._tcp local` shows one instance on awdl0's index, with no "(2)". The iPad reconnects. |
| W8 | **The CLI.** `swift run -c release SillHost --direct-wireless` prints the startup line, and the iPad connects directly (W3's setup). A toggle from the iPad lasts until quit. Without the flag, no AWDL (W1's log). |
| W9 | **Mixed builds and VoiceOver.** The PR #4 iPad build against the new host, and the new iPad build against PR #4's Sill.app (no row): both connect over the LAN. VoiceOver on the connect screen ("Mac mini, Direct", the hint, Search Nearby) and on the panel row. |

### 10. Implementation order (one commit per step, each passing its gates before the next)

0. **Preflight** (no commit): H0.
1. **"Direct Wireless Connection: the sixth setting, off by default on both ends"**
   - Protocol: the two fields, `isEmpty`, `applied(to:)`, the header comment.
   - Host:
     - `HostConfig` and `DeviceSettings`;
     - `StreamServer` with `listener` as a `var`, `makeListener`, `wire`, `setPeerToPeer` (before
       start only), `start()` on the queue, the lock-protected `port`, and
       `SILL_TEST_SERVICE_TYPE`;
     - the coordinator's `setPeerToPeer` after construction, the startup line, and `adopt`
       forwarding.
   - The CLI flag.
   - The app's `HostSettings` key and `DebugHooks.apply`.
   - iOS:
     - the browser and the connection lose `includePeerToPeer`;
     - the ledger field and rule 9;
     - `MockCatalog`'s `StreamSettings` init.
   - `sillclient.py`:
     - `SET_KEYS` and `BOOL_KEYS` gain `directWireless`, so `--expect` takes it too;
     - `describe` prints `dw=1|0|-`;
     - the docstring.
   - The commit message says that a change after launch lands at the next launch until step 2.
   - Gates: H1, H2, H3, H4, H10, H12, H14.
2. **"Host: Direct Wireless applies live by replacing the listener"**
   - `beginSwap`, `bindReplacement`, `settled`, `replacementFailed`, `SILL_TEST_SWAP_FAIL`.
   - Gates: H2 again, H5, H6, H7, H8, H9's first run, H15.
3. **"Sill.app: Direct wireless connection in Settings › General and the status menu"**
   - Gates: H1, H9 (all), H11, H15's menu item.
4. **"iOS: the connect screen looks nearby when Direct Wireless calls for it"**
   - `DiscoveryPolicy.swift` and its pbxproj entries.
   - StreamClient's discovery, memory, `connect(peerToPeer:)`, `connectedDirectly` and reconnect.
   - `ConnectScreen`, and `-SillConnectCase` with its mock.
   - Gates: H1 (iOS Debug and Release), H13, the connect half of S1 and S2, S4.
5. **"iOS: the Direct Wireless Connection row in the Settings panel"**
   - The row and footers, the moved SillHost sentence, the header line, the three mock cases.
   - Gates: H1 (iOS Debug and Release), H12 again, the panel half of S1 and S2, S3.
6. **"docs: Direct Wireless Connection"**
   - `docs/direct-wireless-plan.md` (this file).
   - **CLAUDE.md:**
     - a new "Current step" entry at the top;
     - the trackpad-stutter "Learned" paragraph's "The fix, not applied yet" becomes applied, with
       a pointer;
     - Layout: StreamServer's listener replacement, and `DiscoveryPolicy.swift` with the
       two-browser client;
     - Build and run:
       - `--direct-wireless`;
       - `directWireless` in the defaults keys list;
       - the two `SILL_TEST_*` variables;
       - the dns-sd and `/usr/bin/log` recipes, with the prefix-syntax warning;
       - `-SillConnectCase`, the new `-SillSettingsCase` values, and `-Sill.directWirelessMacs`;
     - "Untested, for Noah": W1–W9.
   - **README:**
     - a Direct Wireless Connection paragraph in the Sill.app section: what it is for, its cost,
       off by default, `defaults delete me.saffer.sill.mac directWireless`;
     - `--direct-wireless` in the command-line section;
     - "Run on a real device on the same Wi‑Fi (or turn on Direct Wireless Connection)".
7. **Review and hand-over**
   - Three lenses, all on Opus 5.5:
     1. wire compatibility and the hard rules;
     2. the replacement's concurrency: phases, late callbacks, the port lock, the 1 s and 1.5 s
        timers, the failure paths;
     3. the iPad UI and accessibility at the four sizes.
   - Then an adversarial re-run of H5–H8 and S1–S3.
   - Fixes go in one "Review fixes: …" commit.
   - Hand W1–W9 to Noah and send the photo sheet.

### 11. What step 3 (VPN / public IP) inherits

- **The listener factory and the in-place replacement.**
  - `makeListener` and the replacement are how step 3 changes listener parameters (a fixed port,
    later TLS) without dropping streams.
  - Once saved addresses depend on the port, the any-port fallback must become "retry the same
    port", because an ephemeral port would break them until the next launch.
- **`FoundMac` is the connect screen's list.** Step 3 adds saved "by address" rows to it. Those
  connections keep `includePeerToPeer = false`: a VPN or public IP never needs AWDL.
- **The memory's key** (`macName`) moves to the Mac `id` that step 3 adds for saved addresses.
- **Network exposure.** Direct Wireless is the first device-writable setting that widens it, which
  goes against the host-settings plan's §9 line ("a device sets stream quality, never network
  exposure"). Revisit it with pairing (M5), before any remote device can change it.
- **Security prerequisites.** §9's payload-length cap and the kind 17 rate limit matter more with it
  on.

---

## Open questions for Noah

Only decisions that change the work. Each gives the default the implementer uses if Noah doesn't
answer.

1. **Can a device turn Direct Wireless Connection on?**
   - **Default: yes**, full parity with the Mac, as decided.
   - The alternative: devices may only turn it off, and turning it on is Mac-only. A device's "on"
     would be refused with "Turn it on in Sill’s Settings on ‹Mac›".
   - This is the first device-writable setting that widens who can reach the Mac. The host-settings
     plan's §9 said devices set stream quality, never network exposure.
2. **How the iPad looks nearby.**
   - **Default:** it remembers Macs last seen with the setting on, and searches nearby when one is
     missing from the network for 3 s. It also offers Search Nearby on the connect screen when no
     Mac is listed after 3 s.
   - The alternative is memory only, with no connect-screen change. Then the first direct
     connection needs the iPad to have seen the setting on over a shared network once, which saves
     `DiscoveryPolicy`'s hint, the button and the three connect harness cases.
3. **The status menu item.**
   - **Default: yes**, "Direct Wireless Connection" at the top of the second group. It's a
     situational toggle (on in a café, off at home), and the menu is one click.
   - The alternative is the Settings window only, like Prioritize Speed.
4. **The security sentence in the Mac's footer.**
   - **Default:** it ends with "Anyone nearby with Sill can find and connect to this Mac."
   - The alternative drops it until pairing (M5) lands.
