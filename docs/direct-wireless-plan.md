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

---

## As built (2026-09-24)

Implemented in the order of §10, one commit per step. Where the code departs from the plan above:

- **The plan was committed in step 0** (the orchestrating workflow asked for it), not left untracked
  until step 6.
- **A replaced listener's `newConnectionHandler` still accepts.** Its state and registration
  handlers are inert, as planned, but a connection it delivers late is a real client and no longer
  depends on the listener, so it is served rather than dropped.
- **`start()` never silently drops the setting.** If the peer-to-peer listener cannot be built at
  launch, it says so in one line and runs the other way; `setPeerToPeer` before `start()` only
  records the value, as planned.
- **The test type is validated** (`_name._tcp`, name 1–15 letters, digits or hyphens, never
  `_sill._tcp`); anything else is ignored with one line. **`SILL_TEST_SWAP_FAIL` is honoured only
  by a host that does not advertise**, like the test type (review): a stray variable can never
  break a real host's listener.
- **`startBrowsing()` starts the network browser once.** SwiftUI can run `onAppear` again, and a
  second browser would have replaced the first without cancelling it.
- **"Reconnecting to ‹Mac›…" is now visible.** It used to be overwritten at once by `connect`'s
  "Connecting to ‹Mac›…"; `reconnectIfListed` sets it after `connect`.
- **The connect screen's column is anchored leading** (`.frame(width: 380, alignment: .leading)`).
  With no rows the column shrank to its text and was centred, so the title jumped ~90 pt left when
  the hint or the first row appeared.
- **Harness.** The `nearby` connect case has a third row with a 43-character name, to show that
  "Direct" never truncates. The stream-screen mock sets `mockDiscovery` too, so the harness never
  browses even after the panel's Disconnect.
- **"Connected directly" lives in the header's readout block**, as §6.3 describes, so a direct
  connection to a host without settings (no state) shows no such line.

Test notes: H6 saw no refusal at all (55 of 55 accepted; ≤ 3 allowed). H11 renders both builds'
previews from one copied path, because the General pane shows the binary's own path. S2 and S3
tapped by coordinates read from screenshots (the simulator tool's inspect was unavailable), with a
0.15 s press: an instantaneous synthetic tap on a switch inside the panel's scroll view was taken
by the scroll view. S3's Mac-side test client picks the Desktop on connecting, which restarts that
pipeline once by itself; the setting's own changes never did.

### Review fixes (second review, 2026-09-24)

These supersede the parts of §6–§9 they name.

- **An automatic reconnect takes a Direct row only after 3 s.** The row must have stayed Direct,
  with no network row of that name, for `networkFirst` (`DiscoveryPolicy.directSince` and
  `reconnectRow`); a network row is still taken at once. The reason: a Mac coming back to the
  shared network (Sill relaunched, the Mac awake) registers there and over AWDL together, and while
  the nearby browser runs (a remembered Mac missing for 3 s turns it on) it can report awdl0 before
  the network browser reports the Wi‑Fi record. The old reconnect took that Direct row, and the
  whole home session ran over AWDL. A tap on a Direct row is not held back. Cost: a direct reconnect
  (W6) takes about 8 s instead of 5.
- **The memory is keyed by the Bonjour name the connection was made to** (the connection's service
  endpoint), not the window list's `macName`, which §6.1 and §11 named. `decide` compares the memory
  with the browsers' instance names, and Bonjour renames a clashing registration ("Mac (2)") while the
  window list still says "Mac", so that Mac looked missing at every launch and the nearby search ran
  at home. A connection by address (`-SillConnect`) teaches nothing.
- **Search Nearby turns into a muted "Also looking nearby"** of the button's 44 pt, whatever the
  status line says, and VoiceOver announces it. Before, the only feedback was the idle status's
  "…and nearby", which a disconnect's message ("Mac mini disconnected…") or "Browse failed" never
  showed. Under the hint the idle status now stays "Looking for Macs on this network", since the line
  says the rest; it adds "and nearby" when no hint shows (rows listed). §6.2's "the status reads
  '…and nearby'" and S2's expectation change accordingly. The tap moves nothing: the title stays at
  293.0 pt at 1000×710.
- **Local Network access denied** (the network browser waits with `PolicyDenied`, TN3179): the
  status reads "To find your Mac, allow Local Network for Sill in Settings.", with no hint and no
  nearby search, which would be refused as well (`DiscoveryPolicy.Input.localNetworkDenied`). When
  the browser is ready again, the network gets its 3 s afresh. The harness case is
  `-SillConnectCase denied`. The simulator does not enforce Local Network access, so only a device
  shows the real path (W4).
- **The panel's warning** (the footer's "turning this off can disconnect it" and the switch's
  accessibility hint) shows only while the switch shows on. §7 tied it to `connectedDirectly` alone.
- **Copy:** Settings › Permissions says frames go "straight to your devices" (no "on this network":
  a direct device shares none), so H11 now also expects `pane-permissions-{light,dark}.png` to differ
  from the base. The README's menu list gains the item and says only a streaming setting restarts
  the stream; its Direct Wireless paragraph says turning it off can disconnect a directly connected
  device. In CLAUDE.md, the connect screen's title no longer jumps *sideways*: the column is still
  centred vertically, so the hint moves it up 44 pt.
- **Not changed:** the trackpad-stutter paragraph's present-tense "Sill turns AWDL on itself" stays.
  It sits in a dated "Learned" paragraph and is still true with the setting on; only the device-side
  clause was added. Sill.app's Local Network alert text (`Packaging/Info.plist`, "on the same
  network") was outside the findings and is unchanged.

Checks for these fixes: H1 (a clean Mac build and iOS Debug and Release, each with only its known
warning); H2 again (identical, masked and sorted); H11 (only the two Permissions panes differ from the
previous step); H12 (unchanged, 44 passes); H13 grown to 68 checks, all passing, including replays of
the home race (awdl0 at 0 s, the network row at 0.8 s or 2.9 s: the network row taken), the café case
(taken at exactly 3 s), a flapping row, exact names and the denied state; six mutants of the new code,
all caught. A replay of the status rule, extracted verbatim from `updateDiscovery` and run against the
real policy: 13 states, including the finding's disconnect-then-tap sequence. H14 again. Simulator:
the connect cases (looking, hint, nearby, denied) at the four sizes; Search Nearby tapped at the four
sizes (the line in its place, status unchanged, title unmoved); the `directlink` switch tapped off
(the warning goes, "Connected directly" stays) and on again (it returns); the normal app connected by
address to `SillHost --synthetic --direct-wireless` wrote no memory; unconnected with no memory, it
started no nearby search and showed the real Mac as a plain row.

### Fixes after Noah's first sessions (2026-09-24, branch `direct-wireless-fixes`)

These supersede the parts of §3.2, §6, §7, §8 and the review fixes they name. Line numbers without a
commit are at a9cc248 (the merge of PR #5), the tree Sill.app build 40 ran.

**What the sessions showed** (Sill.app build 40, the iPad mini on the home Wi‑Fi, 40 Mbps; Sill.log
and the kernel's "…abling AWDL" lines):

- 15:34:20 on from the iPad: the swap at 15:34:21.9, "Enabling AWDL due to Mdns" at 15:34:22, and the
  rtt maxima went from ~9 ms to 85–103 ms. 15:35:22 off from the iPad: the swap at 15:35:24, "Disabling
  AWDL due to no services and no active sockets" at 15:35:51, and maxima of 7–24 ms from 15:35:52. So
  off works when no socket uses AWDL, with a ~30 s kernel lag.
- 15:36:29 on again. At 15:37:02 the host evicted the iPad on en0 ("not draining for 4 s"); at 15:37:25
  it came back over `%awdl0` while still on the home Wi‑Fi. 15:38:43 off from the Mac: the swap, but
  no "Disabling AWDL", and the iPad stayed on awdl0. The same at 15:43:05/15:43:17 (evicted on en0,
  back over awdl0) and 15:44:45 (off from the iPad, still connected). Noah then turned the iPad's Wi‑Fi
  off in Control Center and was *still* connected: Control Center's switch leaves the radio on for
  AirDrop and AWDL.
- Over awdl0 the device reported rtt ~75 ms typical, the worst of each report ~265 ms typical and up to
  2.4 s (frame age up to 2.1 s); on the LAN with AWDL off ~7 ms and ~11 ms; on en0 with AWDL on
  ~10 ms and ~91 ms.

**Why.**

- *Gap A, host.* `setPeerToPeer` (StreamServer.swift:254) → `beginSwap` (:263) drops the old
  registration's handler (:272) and cancels only the listener (:277); `bindReplacement` (:287) binds
  the new one. `clients` (:34) is never touched, by design: accepted connections are independent of
  the listener (the MARK at :115; `newConnectionHandler`, :248). The coordinator's `adopt`
  (StreamCoordinator.swift:389) is the only caller. So a connection accepted over awdl0 while it was on
  outlives off, and the kernel keeps AWDL up for its socket. §8's row "That connection is left alone"
  described exactly this; the footer's "can disconnect" never happened.
- *Knowing a client's route.* The accepted connection's `endpoint` is the device's address, which the
  log already prints (`Client connected:`, :376): `fe80::8425:bdff:fe62:8930%awdl0.63101` at 15:37:25,
  `…%en0.55690` at 15:34:05, `…%anri0.61390` (the USB cable) at 15:33:01. AWDL carries IPv6 link-local
  addresses only, and those always carry their interface. A local probe gave the same name through
  `IPv6Address.interface` (en0, type `.wifi`; awdl0 reports `.wifi` too, so only the name tells), while
  `currentPath.availableInterfaces` listed en0 *and* lo0 for one connection: a weaker witness.
- *Gap B, iOS.* `reconnectRow` (DiscoveryPolicy.swift:100) took a Direct row once it had stayed Direct
  for `networkFirst`, 3 s (:103), with no memory of the network row. And `reconnectIfListed`
  (StreamClient.swift:403) returns at once while connected (:406), so once on AWDL nothing looked at the
  network browser again, although it keeps running (`decide` stops only the nearby one,
  DiscoveryPolicy.swift:51; the network results still reach `discoveryChanged`, StreamClient.swift:241
  and :299). During a swap the old registration goes at `cancel()` (StreamServer.swift:272–277) and the
  new one is made 1.5 s later (`settled`, :319; `advertiseDelay`, :146): browsers drop the Mac about 1 s
  in and list it again about 2.2 s in (§3.2's table; H5 measured 1.3 s and 2.6 s for the awdl0
  record), longer when an announcement is lost.
- *What the log does not show.* The evictions behind the 15:37 and 15:43 reconnects came 32 s and
  3 min after the last swap (15:36:30.6, 15:40:06.9), not inside a blink, and the reconnects 23 s and
  12 s after them. A reconnect takes a network row at once, so the network browser must have
  lacked the Mac for longer than a blink: most likely mDNS lost while both radios left the channel. A
  stricter reconnect alone would not have caught them; moving back to the network does.

**What changed.**

1. **Host: off disconnects the devices on peer-to-peer Wi‑Fi** (commit "Host: turning Direct Wireless
   off disconnects…"). Once a replacement with it off is advertised (`settled`), or has failed for good
   while turning it off (`replacementFailed`, the app keeps running), StreamServer cancels every client
   whose connection runs over awdl or llw, one line each: `Direct wireless off: disconnecting iPad
   (iPad14,1) at fe80::…%awdl0.63101, which was connected over peer-to-peer Wi-Fi; it can reconnect over
   the network.` (the device's name from its last ClientStats; the endpoint alone before one). Then
   "Client left" as for any close. The replacement refuses peer-to-peer, so a device that shares a
   network with the Mac comes back over it; one that shares none cannot, which is what off means. A
   burst that ends where it started (off, then on again within the 1.5 s) disconnects nobody.
   `ClientLink` (new, Foundation only) decides from the endpoint's text: the scope decides when it names
   an interface; without one, the path's interfaces, only when every one is peer-to-peer. "Client
   connected" is unchanged for every client. TEST ONLY `SILL_TEST_PEER_TO_PEER_INTERFACE=en0` (honoured
   only by the hosts that do not advertise, like the other two) counts a client scoped to that interface
   as peer-to-peer, so a link-local test client on en0 stands in for awdl0. `HostStatus` has no
   per-device route, so nothing there changed.
2. **iOS: the reconnect waits out the network's blinks** (`DiscoveryPolicy.reconnectRow`). A network row
   is still taken at once. A Direct row only once it has stayed Direct for `directWait`, 6 s (was 3), and
   the network last listed that Mac `networkGrace`, 10 s, ago or more (`NetworkSightings.leftAt`, kept per
   Bonjour name from the network browser's results). Never listed there (the café): only the 6 s.
3. **iOS: a session over AWDL moves to the network** (`DiscoveryPolicy.moveToNetwork`,
   `StreamClient.moveToNetworkIfListed`). While connected directly, once the network browser has listed the
   same Mac (exact Bonjour name) for `moveAfter`, 2 s, without a break, the client opens a network
   connection beside the direct one and hands the session over when it is ready, closing the direct one
   0.5 s later. Make before break, so the Mac never drops to zero devices: it never stops the stream or
   sends a staged window home, and the new connection gets the running stream (no connect screen, no
   Desktop restart). As on any new connection, the ledger starts afresh (rule 7), the Desktop rule starts
   over, the panel gives the first state its two seconds, and the viewport (this device's rate) goes out
   on the new connection before the old one closes. A network connection that fails or is not ready in
   5 s changes nothing; the next try waits `moveRetry`, 10 s. The status reads "Switching to Wi‑Fi…"
   meanwhile, which only the connect screen shows, so in practice the move is seen in the host's log
   (a second "Client connected", then "Client left" for the `%awdl0` one) and in the panel's header
   losing "Connected directly". A plain reconnect was the first idea: it would have dropped the Mac to
   zero devices, stopped the stream (and sent a staged window home) and restarted it on the Desktop.
4. **Copy.** The panel's footer and the switch's hint: "This iPad is connected directly: turning this off
   disconnects it." / "Turning this off disconnects this iPad." (§7's "can disconnect" rows). With the
   move, a device still connected directly shares no network the Mac is listed on, so it stays
   disconnected until it does. README and CLAUDE.md follow.

**W5, answered.** Turned off while a device is connected directly (from the Mac or the device), the
stream did not stop and never would have: the awdl0 socket stayed open and kept AWDL up for as long as it
lasted (15:38:43 and 15:44:45, no "Disabling AWDL" after). Now the host disconnects that device 1.5 s
after the change, and the kernel should release AWDL about 30 s after the last registration and socket
are gone, as it did at 15:35:51 when no socket held it ("Disabling AWDL due to no services and no active
sockets"); W5 again below confirms it with a socket. The device reconnects over the network when it
shares one: the host's state said off first, which drops the Mac from the device's memory, so no nearby
search starts and no Direct row can be taken. A reconnect takes AWDL at home only if the network browser
has said nothing of the Mac for 10 s, and the move then brings the session back within 2 s of the network
listing it again. **Control Center's Wi‑Fi switch keeps AWDL alive**: it disconnects from the network but
leaves the radio on for AirDrop, so a direct session survives it. The real test for "no shared network"
is Settings › Wi‑Fi off, or another network.

**Checks** (headless, simulator, no permissions; Noah's running Sill.app untouched):

- Builds: the package clean (only the old CaptureProbe warning), iOS Debug and Release with only the old
  ImplicitStrongCapture warning.
- CLI byte for byte against 22209db (masked and sorted; idle 35 s, and a 5 s client): identical, first
  kind 16 `dw=0`.
- `ClientLink` on its own: 40 checks (the three endpoints from Sill.log verbatim, bracketed, numeric and
  empty scopes, IPv4, loopback, the scope deciding over the path, the stand-in rule); five mutants
  caught.
- Gap A end to end with the stand-in: `SILL_TEST_PEER_TO_PEER_INTERFACE=en0 SillHost --synthetic
  --direct-wireless`, a client on the Mac's own en0 link-local address and one on 127.0.0.1 that sets it
  off at 3 s: "…listening on port P again." then the disconnect line for the en0 client (by name), its
  EOF 1.5 s after the change, and the loopback client streaming to the end. Without the variable, the
  same en0 client (a real `%en0` endpoint) stays. Off then on within 0.3 s: one "on: listening…" line,
  nobody disconnected. The bare app with `SILL_TEST_SWAP_FAIL=all`: "Listener failed", the disconnect
  line, the app running on.
- `DiscoveryPolicy` check at 98: the constants; `reconnectRow` with and without a recent network row;
  `sightings`; `moveToNetwork`; a model of StreamClient's glue stepped every 50 ms: the network row
  blinking off for 1.5 s, 4 s and 7 s beside a Direct row goes back over the network at 1.5, 4.0 and
  7.0 s and never Direct; absent for good, Direct at exactly 10.0 s; connected directly, the network row
  from 5 s moves at exactly 7.0 s, a blink at 6–6.3 s moves it at 8.3 s, a failed move retries at 17.0 s,
  another Mac or "Studio (2)" never moves it; the café takes Direct 6 s after its row appeared; the home
  race (Sill relaunched, awdl0 first) takes the network row at 0.8, 2.9 and 5.9 s, and at 6.1 s takes
  Direct at 6.0 and moves at 8.1; a replay of 15:43 goes Direct at 10 s and back to the network at 22 s.
  Seven mutants of the new code caught.
- Simulator (iPad Pro 13-inch) against `SillHost --synthetic` with `-SillConnect … -SillMoveTest 1`: the
  host logs a second "Client connected" and "Client left" for the first, 1 → 2 → 1 clients with frames
  every second, one "Streaming" line in all (no Desktop restart); screenshots before and after show the
  test pattern moving; after the move the panel shows the Mac's state and a Prioritize Encoding Speed tap
  is answered ("Settings from iPad Pro 13-inch (M5)…: speed off → on"). `-SillMoveTest refused`: two tries
  given up after 5 s each, 10 s apart, the session streaming on one connection throughout. The
  `directlink` panel at 500×710 reads the new footer in full.

**Not changed:** the bitrate for direct clients (Noah has not decided); kinds 16 and 17; the default,
off on both ends; `StreamServer(advertise: !synthetic)`; the CLI's default output.

**For Noah** (both builds installed; the kernel's lines with `/usr/bin/log stream --style compact
--predicate 'process == "kernel" AND eventMessage CONTAINS "abling AWDL"'`):

- *W5 again.* Connected directly (the iPad on the iPhone's hotspot, the Mac at home), turn it off from
  the Mac: the disconnect line within ~2 s, the iPad on its connect screen, "Disabling AWDL…" about 30 s
  later. From the iPad's panel: the same, and the footer said so beforehand.
- *W6 again.* Home → café while streaming with it on: back over AWDL in about 10 s without a tap (was
  ~8 s: the 10 s since the network last listed the Mac). Café → home (rejoin the home Wi‑Fi while
  streaming directly): within a few seconds of the network listing the Mac, the host logs a second
  "Client connected" on `%en0` and "Client left" for the `%awdl0` one, the picture never stops, and the
  panel loses "Connected directly".
- *The blink.* At home with it on and the iPad streaming, quit Sill.app and open it again a few times,
  sometimes at once and sometimes after 15 s (its registration leaves and comes back on both routes at
  once, as in a swap, and the iPad reconnects by itself): the host logs the iPad on `%en0`. Only if the
  network takes over 6 s to list the Mac again may it come back on `%awdl0`, and then it moves to `%en0`
  about 2 s after the network lists it. Turning it off and on from the menu while the iPad streams
  never touches its connection at all.
- *Control Center.* Connected directly with Wi‑Fi off in Control Center, the session goes on over AWDL
  (as at 15:44); turning Direct Wireless off on the Mac now ends it within ~2 s and the iPad stays on its
  connect screen until Wi‑Fi is back. Streaming over the network at home with it on, Control Center's
  Wi‑Fi off drops the network connection and the iPad comes back over AWDL after ~10 s (W6's path).

### Review fixes of the move (2026-09-24, branch `direct-wireless-fixes`)

A review of the three commits above confirmed three findings, all in the iOS move from AWDL to the
network (`StreamClient.finishMove` and its neighbours at 386e6e8). These supersede the parts of "What
changed" 3 they name.

- **The hand-over could reorder what the device sends (medium).** `finishMove` pointed every send at the
  network connection as soon as it was ready, while earlier input and picks were still in flight on the
  direct one. The Mac reads each connection in arrival order on one queue and never orders one against the
  other, and over AWDL a round trip was ~75 ms typical and up to 2.4 s against ~10 ms on the network. So a
  release sent after the hand-over could land before its press (InputInjector then keeps the button down,
  and every later pointer move posts as a drag), keystrokes could swap, and a key could stay held. Now
  `SessionLink` (new, Foundation and Network only) holds the session's connection and is the one door every
  message to the Mac goes out of, each send under its lock. The hand-over makes the network connection the
  one read at once, but holds everything the device sends until a fence ping, sent on the direct connection
  under the same lock after everything else sent there, comes back: the host echoes a ping from its receive
  loop only after delivering all that came before it on that connection. Then the held messages go out on
  the network connection, in order, ahead of anything later; the viewport is the first of them, and the
  direct connection closes half a second after the fence is down. The fence's payload is 8 random bytes, so
  the pong of a regular ping still in flight cannot pass for it. The direct connection's read loop runs on
  until the fence's pong (the same loop, so no message is split between two readers) and only looks for it.
  If the direct connection closes first, what it had not delivered never will, and the held messages go at
  once; with no pong in 3 s (past the worst direct round trip of the sessions) they go anyway. The finding's
  first suggestion, waiting for a quiet spell longer than the worst rtt, was not taken: it guesses, and it
  leaves the network connection unread meanwhile, so the video would jump back when it takes over.
- **A move given up at 5 s could still be adopted (low).** The timer cancelled the network connection
  without ending the move, and a `.ready` can be delivered after `cancel()` returns (38 of 3000 in the
  review's experiment), so `finishMove` could make a dead connection the session's and tear it down, taking
  the Mac to zero devices. Now the timer ends the move (`moveEnded`) before it cancels, so the identity
  check turns a late `.ready` away, and the step that hands over also requires `c.state == .ready`, which
  catches a connection that failed after it was ready.
- **The move matched the Mac by Bonjour name alone (low).** Two Macs that share no link keep the same name
  (mDNS renames only within a link), so a session over AWDL to one "MacBook Pro" could move to another
  "MacBook Pro" on the network. The finding's suggestion, comparing the window list's `macName`, cannot tell
  them apart either: it is the same `Host.current().localizedName`. Now each host picks a random
  `launchID` at launch and puts it in every window list (`WindowList.launchID`, optional: an older device
  ignores the key, an older host sends none). A move reads the network connection up to its first window
  list, keeping every message it read for the session to replay, and hands over only when that list's
  launch ID equals the direct session's (`DiscoveryPolicy.sameHost`; two hosts without one go by the name,
  as before). A listing found to be another Mac is not tried again while it lasts
  (`moveToNetwork(refusedListing:)`): each try would connect to that Mac and fetch its whole catalog. A move
  also waits for the direct session's first window list, which names its host. Per launch, not per install:
  the move only needs to know that both connections reach the same running host, and nothing is stored. A
  reconnect still goes by the name (the host may have relaunched); pairing (M5) is the fix for that.

Also: `-SillMoveTest other:PORT` lists another port of the same address as the Mac's network row (another
synthetic host, refused; or the same host's own port behind a delay proxy, moved).

**Checks** (headless and on the simulator, no permissions; Noah's running Sill.app untouched):

- Builds: the package from a fresh copy with only the old CaptureProbe warning; iOS Debug and Release with
  only the old ImplicitStrongCapture warning.
- CLI byte for byte against 22209db (masked and sorted; idle 35 s and a 5 s client): identical, first kind
  16 `dw=0`.
- `SessionLink` against a stand-in Mac on loopback (the fence check: one serial queue reading every
  connection in arrival order and echoing pings, as StreamServer does; the first connection's messages each
  delivered 120 ms late, in order; 20 KB of frames every 10 ms on each; 600 numbered inputs from two senders
  on two threads; regular pings every 30 ms): all 600 in order with the fence down 122 ms after the
  hand-over (85 held); the old hand-over (switch at once) reordered 64; with the direct connection muted at
  the hand-over, released by the caller's timeout, everything sent after the hand-over in order; with it
  closed during the fence, released 31 ms after, in order. Five mutants caught: sends ignoring the fence
  (60 inversions), any pong ending it (ended after 29 ms by a regular ping's pong, 48 inversions), the held
  messages dropped (84 missing), the direct connection not read on (released only by the timeout), the fence
  ping sent on the new connection (the same).
- `DiscoveryPolicy` check at 111 (the 98 above, plus `sameHost` and the refused listing: another Mac named
  Studio is tried once at 7.0 s and never again to 40 s; after its row blinks at 20–20.3 s, tried at 22.3 s
  and refused again; when this Mac takes the name at 20.3 s, moved at 22.3 s; hosts without IDs move at
  7.0 s by name; an ID against none is refused). Five mutants caught.
- Simulator (iPad Pro 13-inch, Debug) against `SillHost --synthetic`: `-SillMoveTest 1` moves with the
  fence down in 2 ms holding the viewport, the host streaming throughout (one "Streaming" line) and five
  device reports arriving over the new connection; in the harness with the panel open, the panel shows the
  Mac's state after the move. `other:PORT` against a second synthetic host: one try, "move to the network
  refused", that host accepts one connection in 24 s ("Client connected" once), and the first host streams
  to one device throughout. Behind a proxy delaying each direction 150 ms (the direct session's rtt 302 ms),
  with the network row on the host's own port: the fence down after 301 ms, then rtt 1 ms and frame age
  0 ms. `refused`: tries 10 s apart, each ended once by its 5 s timer, the session streaming on.

**For Noah**, with W6: rejoin the home Wi-Fi while streaming directly and keep dragging on the trackpad or
typing through the move a few times: no button stays down, no letters swap, and the host logs the
`%awdl0` connection leaving about half a second after the `%en0` one arrives, plus one direct round trip.
