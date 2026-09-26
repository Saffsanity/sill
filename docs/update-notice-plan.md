# Update check and device notice — the plan

2026-09-25. Two items Noah added to the list of things the first public builds cannot get
afterwards. It stands alone: the implementer needs no other design document. Written from a survey
of the `update-notice` worktree (`/Users/noah/Downloads/winstream-update`, branch `update-notice`
from `remote-access` at cb0ec55, PR #13); line numbers are at cb0ec55. Nothing but this file was
written in the repository. Run for it, and nothing else: three unauthenticated GETs to
api.github.com, and two probes built with swiftc in the scratchpad (a URLSession probe against a
local fake feed, and the payloads' JSON; §6.2, §3.5). No host was started and no encoder was used.

**Noah's request (2026-09-25):**
> An update check in Sill.app. Apple frameworks only, so a check of the GitHub Releases feed rather
> than Sparkle.
>
> A host-to-device notice, so a future Mac can tell an old device to update instead of silently
> failing.

**Reading of it.** These are findings 2 and 4 of the App Store audit's versioning lens (session
scratchpad `appstore-result.json`): Sill.app cannot learn that it is out of date, and a host cannot
tell a device that it is. Finding 3 (pairing on the home network) is not part of this step; Noah did
not include it, and §14 says how this step prepares for it. The details below (the menu item's
words, the settings key, the log rules, the goodbye's fields) follow the task that commissioned this
plan; where the plan departs from it, it says so and why (open questions 1 and 3).

---

## Decision

### Why now: the first public builds set the floor

- iOS updates itself (automatic updates); Sill.app does not, and nothing tells its user that a new
  one exists. So after launch the likely mismatch is a newer device with an older Mac, and a Mac
  that never updates stays in the field for years.
- A device can stay old too: automatic updates off, or an iOS the next version no longer supports
  (`IPHONEOS_DEPLOYMENT_TARGET` 17.0).
- Today neither end can say "update". A Mac cannot tell a device to update, and a device cannot
  tell which Sill a Mac runs. On this branch a goodbye whose reason the device does not know shows
  "‹Mac› disconnected…" and reconnects at once (§7.3): against a Mac that refuses it, a loop.
- So the update check (feature 1) makes old Macs rarer; the notice (feature 2) turns every future
  refusal of an old device into one clear message; and the hello and the Mac's version on the wire
  give both ends the facts to decide. CLAUDE.md records the floor (§13).

### How a host learns a device's version: a hello of its own (kind 23)

The task suggested the Viewport or the first ClientStats. Neither is the device's first message:
- The Viewport goes out when the stream screen has measured its panel (StreamScreen.swift:170-174,
  or 0.25 s later, :187 and :205-217). At home that is just after `.ready`. On a remote session it
  is only after the first window list, because the session counts as connected only then
  (StreamClient+Remote.swift:326-350).
- ClientStats go out once a second while connected (DiagnosticsHUD.swift:33-42), the first about a
  second in.
- On a remote session the first message is a ping, 0.25 s after `.ready`
  (StreamClient.swift:1696-1720, :1793): 8 binary bytes.

A host that has to judge a device before sending it anything would wait for a Viewport that, on the
remote door, the device sends only after the host's window list. So the version goes in a message
of its own, the first thing on every session connection: kind 23, `Hello`. It carries the two
fields asked for (`appVersion`, `protocol`) and two more: `build`, and `device`, which the refusal's
wording and its log line need before any ClientStats. Every build skips a kind it does not know
(StreamMessage.swift:89-98; StreamCoordinator.swift:587; StreamClient.swift:1687), so older hosts
ignore it. It costs about 90 bytes per connection.

### A check, not an updater

Sill.app finds out, says so, and opens the release page; the person downloads the notarized zip and
replaces the app. §6.1 says why that is enough for a free, open-source Developer ID app with no
servers, and what Sparkle would add.

### The base, and the merge order

- Branch `update-notice` from `remote-access` (cb0ec55, PR #13): kind 22 and `Goodbye` live there.
- The PR is stacked on #13 (base `remote-access`) while #13 is open, and targets main once #13
  merges.
- If the first public build ships from main before #13 merges (the audit's recommendation), steps
  1, 3 and 4 have to reach main too. From #13 they need only kind 22, `Goodbye` and the goodbye
  handling in `sessionEnded`; the protocol step then brings those along (open question 11). Step 5
  (the update check) needs nothing from #13 but its neighbours in the menu and the pane.
- #11 (encoder-recovery: StreamCoordinator, HostStatus, StatusText) and #12 (follow-best-path:
  StreamClient, SessionLink, DiscoveryPolicy) touch files this plan touches. Re-read them before
  editing, and rebase after whichever merges first.

### Not in this step

- Pairing on the home network (the audit's finding 3; M5).
- Downloading or installing anything, with Sparkle or otherwise; "Skip This Version"; release notes
  inside the app.
- A floor above "0": this build refuses no device.
- A device refusing an older Mac (a device-side floor): §14.
- Anything in the Mac's device list or Remote Access pane about a refused device: the log only.
- The Mac's version anywhere on the device's screen: it is stored for later (§7.6).

---

## Final plan

### 1. Scope

**In this step:**

1. **Kind 23, the hello.** Every session connection a device makes starts with
   `Hello {appVersion, build, protocol, device}`.
2. **The host's version** in every window list (`hostVersion`, `protocol`).
3. **The device floor on the host:** `DeviceGate.minimumDeviceVersion`, "0" in this build.
   - Above "0", a host judges each device by its first message before sending it anything.
   - One below the floor gets kind 22 `{"reason":"update", message, minimumVersion,
     "reconnect":false}`, and is closed.
   - A TEST ONLY variable raises the floor on a synthetic host, so the path is tested now.
4. **Goodbyes on the device:**
   - "update" shows the host's message word for word, with an App Store link, and does not
     reconnect;
   - a reason the device does not know shows its message (or a generic line) and reconnects only
     when told to;
   - today's loop on an unknown reason is fixed.
5. **The update check in Sill.app:**
   - 30 s after launch when due, then every 24 hours;
   - GitHub's latest release against CFBundleShortVersionString;
   - a newer one adds "Sill 0.4 Is Available…" to the status menu;
   - Settings › General gets "Check for updates automatically" and Check Now with an inline result.
6. **The release rule:** a release's tag is `v` + the Sill.app version it carries, and
   `make-app.sh --release` builds only such a commit.
7. **Docs:** the compatibility floor in CLAUDE.md, the privacy policy's line, the release
   checklist's lines.

**Not in this step:** see Decision.

### 2. The design on one page

```
 ┌───────────── Sill.app ─────────────┐                           ┌───────── GitHub ─────────┐
 │ UpdateChecker                      │ GET …/releases/latest     │ api.github.com           │
 │ 30 s after launch if due, then     │ ───────────────────────▶  │ 200 {tag_name, html_url, │
 │ every 24 h; Check Now at any time  │ User-Agent Sill/0.3.0     │      draft, prerelease}  │
 │ newer tag → "Sill 0.4 Is           │ If-None-Match             │ 304 · 404 · 403 · 429    │
 │ Available…" → the browser          │ ◀───────────────────────  │                          │
 └────────────────────────────────────┘                           └──────────────────────────┘

 device                                          Mac (Sill.app or SillHost; either door)
 .ready ── kind 23 Hello {appVersion, build, protocol, device} ──▶   first, before anything else
          floor "0" (this build): registered at .ready as today; the hello is logged
          floor above the device's version (a later host), or no hello at all:
        ◀── kind 22 {"reason":"update", "message":"Update Sill on your iPad to keep using Mac mini.
                     It needs version 1.2 or later.", "minimumVersion":"1.2", "reconnect":false}
            then closed. Nothing else was ever sent to it.
 connect screen: the message as its status line, spoken; "Update Sill in the App Store"; no reconnect

        ◀── every window list now also carries "hostVersion":"0.4.0" and "protocol":1 (for later devices)
```

**Only a build raises the floor.** It is a constant, not a setting: a floor lower than the host
needs would serve a device something it cannot use, which is what the notice exists to prevent.

### 3. Wire protocol

#### 3.1 Kind 23, the hello (`Sources/StreamProtocol/Compatibility.swift`, new)

StreamMessage.swift, continuing the enum:

```swift
case hello = 23          // device → host: JSON Hello (Compatibility.swift) — who the device is. The first message of
                         // every session connection, before anything else, so a host can judge the device before it
                         // sends anything (DeviceGate). Never on a pairing connection. Older hosts skip it
```

```swift
/// Kind 23: the first message of every session connection a device makes (home door, remote door,
/// a move's network connection), written straight to that connection before anything else. Never
/// on a pairing connection, whose one message is kind 19. HostSettings.swift's rules apply.
public struct Hello: Codable, Sendable {
    /// CFBundleShortVersionString: "1.0" (the iOS project's MARKETING_VERSION, 0.1 today and 1.0
    /// at the first submission). What a host's floor compares (DeviceGate).
    public var appVersion: String?
    /// CFBundleVersion: "42". Logged only.
    public var build: String?
    /// SillProtocol.current: 1. Logged only in this build (§3.2).
    public var `protocol`: Int?
    /// "iPad (iPad14,1)", as ClientStats.device. The host cleans it (SafeText.label).
    public var device: String?
}
```

- All four are optional: `{}` decodes (checked), so a host never fails on a thin hello.
- The JSON keys are the property names. `protocol` is a keyword: backticks in Swift, "protocol" on
  the wire (checked).

#### 3.2 `SillVersion` and `SillProtocol` (same file; pure, Foundation only, checked with swiftc)

```swift
/// The wire's generation. 1: the 14-byte header, kinds 0–23 and the JSON rules of HostSettings.swift.
/// Raised only by a change an older peer cannot skip (a new transport, pairing required on the home
/// door); an additive change never raises it. When it rises, the host's floor rises too (§4.6).
public enum SillProtocol { public static let current = 1 }

/// A version as tags, bundles and the wire write it: "v0.4.0", "0.4.0", "0.4", "1.2.3-beta.1".
public struct SillVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let components: [Int]        // trailing zeros dropped, so "0.4" == "0.4.0"; [] is 0
    public init?(_ text: String)
    public static let zero: SillVersion
    public var description: String      // "0.4", "1.0", "1.2.3"
}
```

**Parsing:**
1. Trim whitespace, then drop one leading `v` or `V`.
2. Keep the longest prefix of digits and dots, and drop the dots at its end.
3. It must start with a digit. Split it on "."; each part has 1–9 digits, and there are at most 8
   parts. Anything else is nil.
4. What follows the prefix is ignored: "1.2.3-beta.1" is 1.2.3. A prerelease is GitHub's flag, not
   the tag's suffix (§6.4), and App Store versions are numeric.

**Comparing:** part by part, a missing part counting as 0: "0.10" > "0.9", "1.0.1" > "1.0",
"v0.4.0" == "0.4".

**Showing:** at least two parts, and trailing zeros beyond two dropped: 0.4.0 → "0.4", 1 → "1.0",
1.0.1 → "1.0.1", 0 → "0.0".

The check (H3) covers at least: "v0.4.0", "V0.4", " 0.4.0 ", "1.2.3-beta.1", "01.2" (1.2), "1..2"
(nil), "1." (1), "" (nil), "dev" (nil), "v" (nil), "1234567890" (nil: 10 digits), nine parts (nil).

#### 3.3 Kind 22's new fields and the reason "update" (`Remote.swift`)

```swift
/// Kind 22: why the host is about to close this session, and what the device should do then.
public struct Goodbye: Codable, Sendable {
    /// "removed", "remoteOff", "internetOff", "quit", "busy" or "update". Always sent: a device from
    /// before 2026-09-25 decodes nothing without it. A device from then on treats a reason it does not
    /// know by `message` and `reconnect`, so a later host can tell it anything (GoodbyePolicy).
    public var reason: String
    /// Shown word for word as the connect screen's status line (after SafeText.label, at most 300
    /// characters). "update" always carries one, and a new reason should. Nil: the device's own words.
    public var message: String?
    /// With "update": the oldest device version this host serves, as SillVersion shows it ("1.2").
    public var minimumVersion: String?
    /// Whether the device reconnects by itself. Nil is false for "update" and for a reason the device
    /// does not know; the older reasons keep their own rules. A refusal always sends false.
    public var reconnect: Bool?

    public static let removed = "removed", remoteOff = "remoteOff", internetOff = "internetOff", quit = "quit", busy = "busy"
    public static let update = "update"
}
```

- Nil fields are left out of the JSON, so every goodbye this branch sends today is still, byte for
  byte, `{"reason":"quit"}` and the like (checked).
- A device from before this change decodes `reason` and ignores the rest (checked with the old
  struct).

#### 3.4 The host's version in the window list (`Switcher.swift`)

`WindowList` gains, after `launchID`:

```swift
/// The host's version: Sill.app's CFBundleShortVersionString ("0.4.0"); nil from SillHost (no bundle)
/// and from hosts before 2026-09-25. For later devices: which Mac to update, and to what (§14).
public var hostVersion: String?
/// The host's SillProtocol.current; nil from hosts before 2026-09-25, which speak 1.
public var `protocol`: Int?
```

Every list carries them, as it carries `launchID` (about 35 bytes). An older device ignores both.

#### 3.5 Examples as they cross the wire

```json
// kind 23, the device's first message
{"appVersion":"1.0","build":"42","device":"iPad (iPad14,1)","protocol":1}
// kind 2, as today plus two keys
{"macName":"Mac mini","windows":[],"active":{"desktop":{}},"launchID":"6F1C…","hostVersion":"0.4.0","protocol":1}
// kind 22, a refusal (a later host; SILL_TEST_MIN_DEVICE_VERSION in this build)
{"message":"Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later.","minimumVersion":"1.2","reason":"update","reconnect":false}
// kind 22 as this branch already sends it: unchanged
{"reason":"quit"}
// kind 22 from a later host, with a reason this build does not know (SILL_TEST_GOODBYE in the tests)
{"reason":"pairingRequired","message":"Pair this iPad with Mac mini again: choose Pair iPhone or iPad… on the Mac.","reconnect":false}
```

The first, third and fourth were encoded by the probe (sorted keys); an old `{reason}` struct read
the third as "update", and the new struct read the fourth with every new field nil.

#### 3.6 Compatibility

| Device | Host | Result |
|---|---|---|
| From before this change (PR #13's, main's) | This host (floor "0") | As today: it sends no hello, and a floor of "0" never waits for one. It ignores `hostVersion` and `protocol` |
| This device | An older host (PR #13's Sill.app, main's, the CLI before this change) | As today: the hello is skipped (`default: break`); `hostVersion` is nil |
| This device | This host | One "Client hello: …" line on the Mac; nothing else changes |
| This device | A later host whose floor is above this device's version | Kind 22 "update" before anything else: the message, the App Store link, no reconnect (§7.4) |
| From before this change | A later host with a floor above "0" | Refused as "an older Sill" (no hello). It cannot show the message: main's build shows "…disconnected. It will reconnect when the Mac is back." and redials; PR #13's the same, at once when the Mac's row is listed. Only development and TestFlight builds are that old; the host slows them and logs them in two lines a minute (§4.2) |
| `sillclient.py` from cb0ec55 | This host | Unchanged |

#### 3.7 Rules for later changes

HostSettings.swift's rules (JSON only; new fields optional; no enums on the wire; never rename or
retype), with three more, written into Compatibility.swift's header:
- A device's first message on a session connection is its hello. A host never assumes one arrives:
  older devices send none.
- `Goodbye.reason` is always sent. A new reason carries a `message` that a device from 2026-09-25 on
  can show as it is, and `reconnect`.
- A refusal is kind 22 "update" with `"reconnect":false`, and nothing is sent before it.

### 4. Host (`SillHostCore`, folder `Sources/SillHost`)

Nothing becomes `public`: new types are `package` or internal. Hops to the main actor use
`Task { @MainActor }`, never `MainActor.assumeIsolated`.

#### 4.1 `DeviceGate.swift` (new; pure: Foundation and StreamProtocol; checked with swiftc)

```swift
package enum DeviceGate {
    /// The oldest Sill for iPhone and iPad this host serves. "0" admits every device, those that send
    /// no hello included. Raised only by the rule in docs/update-notice-plan.md §4.6.
    package static let minimumDeviceVersion = "0"
    /// A device's version: its hello's `appVersion`, else 0 (no hello: a device from before
    /// 2026-09-25; or a version that does not parse).
    package static func version(_ hello: Hello?) -> SillVersion
    package static func admits(_ hello: Hello?, floor: SillVersion) -> Bool
    /// {"reason":"update", message, "minimumVersion": the floor's description, "reconnect":false}.
    package static func refusal(_ hello: Hello?, floor: SillVersion, macName: String) -> Goodbye
    /// "iPad", "iPhone" or "device", from the hello's name.
    package static func deviceWord(_ hello: Hello?) -> String
    /// The Refused line (§4.5).
    package static func refusedLine(_ hello: Hello?, endpoint: String, floor: SillVersion) -> String
}
```

**The message, exactly:** "Update Sill on your ‹iPad› to keep using ‹Mac›. It needs version ‹floor›
or later."
- ‹iPad›: "iPhone" when the hello's cleaned device name starts with "iPhone", "iPad" when it starts
  with "iPad", else "device".
- ‹Mac›: the Mac's name, the window list's `macName` (`Host.current().localizedName`). The task's
  "this Mac" reads as the iPad itself on the iPad's screen, above a list of Macs (open question 3).
- ‹floor›: `SillVersion.description` ("1.2").

The swiftc check asserts that the shipped constant parses.

#### 4.2 `StreamServer.swift`: the gate, the hello, the goodbye

1. **The floor.**
   - `let deviceFloor: SillVersion`, read in `init` from `DeviceGate.minimumDeviceVersion`.
   - TEST ONLY: `SILL_TEST_MIN_DEVICE_VERSION=1.2` replaces it, honoured only when the host does not
     advertise, like the other test variables (StreamServer.swift:8-20). A value that does not
     parse prints "SILL_TEST_MIN_DEVICE_VERSION=abc ignored: not a version." and keeps the constant.
   - `var macName = "Mac"`, set by the coordinator before `start()`.
2. **Floor "0" (every build that ships now): nothing waits.** `accept` registers at `.ready` exactly
   as today (StreamServer.swift:591-633), and so does `serve` (:648-666). Nothing is read ahead,
   nothing new is printed, and the CLI's output is the base's.
3. **Floor above "0": the gate,** on both doors, after the origin gate and before `register`:
   - The connection is held unregistered: no broadcast, tick, catalog, keyframe request, device row,
     "Client connected" line or count change.
   - It reads one message, header (the 1 MB cap applies) and payload, within 2 s of `.ready`.
   - **A hello** that decodes and `admits`: `register`, "Client connected: …" (the home door) or the
     remote door's line (§4.3), `receiveLoop`, `onClientConnected`, then the hello as item 4 says.
   - **Anything else is refused:** a hello below the floor; and, each counting as version 0, a hello
     that does not decode, any other kind first (an older device's viewport, pick or ping), EOF, or
     nothing within 2 s.
   - **Refused:** `sayGoodbye` with `DeviceGate.refusal(…)` (:685-691: cancelled once the send is
     processed, or after 250 ms), and the Refused line (§4.5). It was never registered: no "Client
     connected" and no "Client left" for it.
   - **Slowing a loop:** a source address refused 5 times within 60 s gets its next refusals 2 s
     after its first message instead of at once. A device from before this change redials at once
     and cannot read the notice; a device from 2026-09-25 on sees the message 2 s later, on its
     sixth try in a minute.
   - TEST ONLY: `SILL_TEST_GOODBYE='<JSON>'`, with the floor variable, on a host that does not
     advertise: the refusal sends this payload instead. It must decode as a `Goodbye`; otherwise
     the host prints "SILL_TEST_GOODBYE ignored: not a Goodbye." and sends the usual refusal. It
     shows the simulator a reason it does not know (§10, S4).
4. **The hello in the receive loop** (:783-854), whatever the floor: kind 23 is the server's, as kind
   12 is.
   - Decoded; only the first per connection counts (a second is skipped without a line).
   - `client.device` = `SafeText.label(device)` when that is not empty and no stats have named the
     client yet.
   - One "Client hello: …" line (§4.5).
   - `onClientHello?(connection, hello)`, on the network queue.
   - It never refuses: with floor "0" every device is admitted, and above it the gate has already
     judged the device.
5. **Goodbyes carry a `Goodbye`.** `goodbye`, `sayGoodbye` and `goodbyeAll` (:676-708) take a value
   instead of a reason string. The five existing callers pass `Goodbye(reason: …)`, so their JSON is
   unchanged.

#### 4.3 `RemoteServer.swift`

- `admitSession` (RemoteServer.swift:292-318) calls `server.serve(c, route:, admitted:)`.
- "Remote client connected: ‹name› ‹label› (‹endpoint›)" moves into `admitted`, which the server
  calls once the gate admits: at once with floor "0", so the line comes where it does today.
- A remote device refused by the gate gets the update goodbye and the Refused line, never "Remote
  client connected".
- (Review fix.) While the gate reads, the session is neither pending nor a client, so
  `closeSessions` and the session count cannot see it: `serve` takes a `recheck`, and the door
  answers it from the trust snapshot as the gate admits (`stillAdmits`: removed, Remote Access or
  internet access off, the limit; the goodbye, closeSessions' line). The home door does the same
  for Direct Wireless turned off meanwhile. The door's own refusals at admission (remoteOff, busy)
  close like the gate's (`closeWithGoodbye`).
- Pairing (:320-359) is not gated: a device too old for this Mac's sessions can still pair, and it
  hears the notice when it connects (open question 5).

#### 4.4 `StreamCoordinator.swift`, `HostStatus.swift`

- **init** gains `hostVersion: String? = nil`: Sill.app passes its CFBundleShortVersionString when
  it parses (the bare binary's "dev" does not); the CLI passes nothing. It also sets
  `server.macName = macName` before `start()`.
- **listMessage** (:1297-1300): `WindowList(macName:windows:active:launchID:hostVersion:
  hostVersion, protocol: SillProtocol.current)`.
- **onClientHello** hops to the main actor. The device's row takes the hello's cleaned name while it
  has none, so the card shows "iPad (iPad14,1)" from the first moment instead of an address for a
  second; the stats replace it, as today.
- Nothing else: the floor is the server's, and a refused device never reaches the coordinator.

#### 4.5 Log lines (exact; each appears only when its event happens)

```
Client hello: iPad (iPad14,1), Sill 1.0 (42), protocol 1 (192.168.1.23:52344)
Client hello: 192.168.1.23:52344, no version                            (a hello with nothing in it)
Refused iPad (iPad14,1) (Sill 1.0): needs 1.2 or later.
Refused 192.168.1.23:52344 (an older Sill): needs 1.2 or later.         (no hello, or one that does not decode)
Refused 14 more connections from 192.168.1.23 in the last minute: too old for this Mac (needs 1.2 or later).
SILL_TEST_MIN_DEVICE_VERSION=abc ignored: not a version.
SILL_TEST_GOODBYE ignored: not a Goodbye.
```

- The hello line: the cleaned name, else the endpoint; "Sill ‹appVersion› (‹build›)", without the
  build when there is none, or "no version"; ", protocol ‹p›" when sent; the endpoint in parentheses
  when a name came first.
- The CLI prints a hello line too. None of the baseline runs sends a hello (H2).
- At most one Refused line per source address a minute; the rest are counted and printed in one line
  when the minute is up, as RefusalSummary does for the origin gate.
- "Client connected: …" and "Catalog → …" keep their text: tests grep for them.

#### 4.6 Raising the floor later (the rule)

`DeviceGate.minimumDeviceVersion` stays "0" until a host can no longer serve older devices
correctly. Then, in that host's own step:

1. **Only for a requirement, never as a nudge.** Raise it only when the host needs something older
   devices cannot do: pairing on the home door, a new transport, a kind they cannot skip. Everything
   else stays additive (§3.7), and older devices keep working.
2. **To a version people can get.** The floor is the first iOS version that has what the host
   needs, live on the App Store with its phased release finished before the host ships. It runs on
   every iOS the refused versions ran on (17.0 today), or the host's release notes say which
   devices it leaves behind.
3. **With the protocol.** A requirement older peers cannot skip raises `SillProtocol.current` in the
   same step.
4. **Words that stand alone.** The message is the host's (§4.1): a device from 2026-09-25 on shows it
   as it is and cannot learn new words. One or two sentences, at most 200 characters, naming the
   device, the Mac and the version.
5. **Said everywhere.** That Sill.app's GitHub release notes say "Needs Sill ‹floor› or later on
   iPhone and iPad.", and so does the README's requirements line.
6. **Tested first.** H6 with `SILL_TEST_MIN_DEVICE_VERSION` at the new floor, and V3 on a device
   below it, before the release.
7. **Never lowered again** in a later build without Noah: devices that updated because of it gain
   nothing, and devices still below it would meet a host that half works.

### 5. CLI (`Sources/SillHostCLI/main.swift`)

- No change. It never checks for updates: the check lives in Sill.app (Sources/SillMenuBar) only,
  and the core has no URLSession (H10).
- Its window lists carry `protocol` and no `hostVersion` (it has no bundle).
- With `--synthetic` (which does not advertise) it honours the two TEST ONLY variables.
- Its default stdout stays the base's byte for byte, masked and sorted, idle and streaming, with and
  without `--direct-wireless` (H2).

### 6. Sill.app: the update check

#### 6.1 A check, not an updater: why that is enough, and what Sparkle would add

**What happens:** Sill.app learns that a newer release exists, says so in its menu and Settings, and
opens the release's page on GitHub. The person downloads the notarized zip, quits Sill and replaces
the app in Applications.

**Why that is enough here:**
- **The download is already safe.** The zip holds a Developer ID signed, notarized and stapled app
  (app-store-readiness's `Scripts/release.sh`). The browser quarantines it, and Gatekeeper checks it
  at first launch, offline too thanks to the stapled ticket. A second check inside Sill would repeat
  Apple's.
- **Permissions survive.** Between Developer ID builds the designated requirement names the bundle
  ID and the team (`certificate leaf[subject.OU] = "‹team›"`, the form read from a Developer ID app
  on this Mac on 2026-09-25), so a new version keeps Screen Recording and Accessibility; V6
  confirms it on the first two notarized builds. The one loss is at the switch from Apple
  Development to Developer ID (README, Distribution).
- **Zero cost, zero servers.** GitHub hosts the releases, their notes and the feed.
- **Nothing surprising.** No background download, no privileged installer, no relaunch while a
  device streams (an install would cut the session), no new code path that could break the app.
- **Mac releases will be rare,** and an item in a menu the person opens anyway is enough of a nudge.

**What Sparkle would add:**
- the download and the install inside the app, with a restart;
- an EdDSA signature over each archive, checked before installing;
- delta updates;
- release notes in a window;
- "Skip This Version" and "Remind Me Later";
- silent automatic installs;
- staged rollouts through its appcast, an XML feed Sill would publish (on GitHub Pages, say).

**What it would cost:**
- a third-party framework, against "Apple frameworks only" (a BRIEF.md decision first);
- an EdDSA private key to keep safe for the life of the app;
- an appcast to publish with every release;
- Sparkle's helper services inside the bundle, signed and notarized with it.

For a free app that updates a few times a year, one drag to Applications does not pay for that. If
it ever does, the settings key and the menu item carry over.

#### 6.2 The request

```
GET https://api.github.com/repos/Saffsanity/sill/releases/latest
User-Agent: Sill/0.3.0
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
If-None-Match: W/"fd09…"          (only with a stored ETag and a stored release)
```

- **The session:** `URLSessionConfiguration.ephemeral`, with:
  - `timeoutIntervalForRequest = 10`, `timeoutIntervalForResource = 10`;
  - `httpCookieAcceptPolicy = .never`, `httpShouldSetCookies = false`, `httpCookieStorage = nil`;
  - `urlCache = nil`, `requestCachePolicy = .reloadIgnoringLocalCacheData`;
  - `waitsForConnectivity = false`;
  - the three fixed headers in `httpAdditionalHeaders`.
- **Never** an Authorization header, a token, an identifier, or any header but these.
- **Redirects** are followed only to `https://api.github.com/` (a renamed repository answers 301
  there). Any other is refused, and counts as "not a release".
- **The body** is read up to 1 MB; more is "not a release".
- **One request at a time.**

**Measured on 2026-09-25:**
- **This repository, private today:** HTTP 404 `{"message":"Not Found",…}`, no ETag,
  `x-ratelimit-limit: 60`. Every check gets this until the repository is public and has a release.
- **A public repository's latest release:** HTTP 200, 6.4 KB, `etag: W/"…"`, `cache-control:
  public, max-age=60`, and the four fields used here (`tag_name`, `html_url`, `draft`,
  `prerelease`). The same request with `If-None-Match` got 304 with no body, and
  `x-ratelimit-used` still went from 2 to 3: without a token a 304 saves bytes, not quota. The quota
  is 60 an hour per IP address, shared by every Mac behind it.
- **A bare swiftc binary with this configuration** (no Info.plist, so App Transport Security's
  defaults):
  - plain http to 127.0.0.1 and to localhost works, so the tests' fake feed needs no exception;
  - the manual `If-None-Match` got its 304 delivered;
  - no Cookie header went out after a `Set-Cookie`;
  - the User-Agent went out as set;
  - a closed port failed with -1004 in 6 ms, and a server that never answers with -1001 after
    10.0 s.

#### 6.3 When it checks

- **Automatic checks** run when all of these hold:
  - "Check for updates automatically" is on (`updateCheck`, on by default);
  - the running version parses (the bare binary's "dev" does not);
  - the app is not in test pattern mode, unless `-SillUpdateFeed` points at a feed on this Mac
    (§6.9).
- **Due:** `updateLastCheck` is unset, 24 hours old or more, or in the future (the clock went back).
- **At launch:** 30 s after the host has started, if due. Otherwise a one-shot run-loop Timer at
  `updateLastCheck` + 24 h + the jitter. Never before the host is up, and never blocking anything.
  If the host could not start, the checker starts anyway: a newer Sill may be the fix.
- **After each check** the next one is 24 hours later plus a random 0–30 minutes, so Macs behind one
  address drift apart. After a failure with no HTTP answer it is 1 hour later instead (in memory;
  `updateLastCheck` does not move).
- **Wake:** `NSWorkspace.didWakeNotification` re-arms the timer; a check that fell due during sleep
  runs 30 s after the wake.
- **Check Now** (and `-SillUpdateNow 1`) checks at once, whatever the setting and the 24-hour rule.
  A click during an automatic check joins it: the line shows "Checking…" and then its result, and it
  logs as a manual check.
- **Turning automatic checks on** schedules by the rule (if due, 30 s later). Off stops the
  scheduling; a check in flight finishes. What was found stays in the menu and the pane either way
  (open question 6).
- **No storm:** at most one request in flight; at most one an hour while network errors last; one a
  day otherwise; never a retry of a 404, 403, 429 or 5xx before the next day.

#### 6.4 What an answer means

`running` is CFBundleShortVersionString (`-SillUpdateVersion` in tests). The stored release is
`updateLatestTag` with `updateLatestURL`. A release is **published** when it decodes with a string
`tag_name` that parses (§3.2), `draft` and `prerelease` both false (GitHub's endpoint already skips
both), and an `html_url` on `https://github.com/` (with a test feed, any http or https URL). It is
**newer** when its tag's version is greater than `running`'s.

| Answer | Stored afterwards | Log, automatic | Log, Check Now | The pane's line after Check Now | Next automatic |
|---|---|---|---|---|---|
| 200, published, newer | `updateLastCheck`, `updateETag`, the tag, the URL | Update check: Sill 0.4 is available (this is 0.3.0): ‹html_url› | the same | Sill 0.4 is available. | 24 h |
| 200, published, not newer | the same | nothing | Update check: up to date (this is 0.3.0; the latest release is v0.3.0). | Sill is up to date. | 24 h |
| 304, with a stored release | `updateLastCheck` | as for the stored release, newer or not | as for the stored release | as for the stored release | 24 h |
| 404 | `updateLastCheck`; the ETag, tag and URL cleared (a withdrawn release stops being offered) | Update check failed: GitHub has no release of Sill (HTTP 404). | the same | Couldn’t check: GitHub has no release of Sill yet. | 24 h |
| 403 or 429 | `updateLastCheck` | Update check failed: GitHub is limiting requests from this network (HTTP 403; it resets at 15:42). | the same | Couldn’t check: GitHub is limiting requests from this network. Try again after 15:42. | 24 h |
| Any other HTTP status | `updateLastCheck` | Update check failed: HTTP 502. | the same | Couldn’t check: GitHub answered with an error (HTTP 502). | 24 h |
| A 200 that is not a published release; a 304 with no stored release | `updateLastCheck` | Update check failed: the answer is not a published release (‹why›). | the same | Couldn’t check: GitHub’s answer wasn’t a release Sill understands. | 24 h |
| No connection: URLError -1009, -1005, -1004, -1003, -1006, -1020, -1018, or TLS -1200 to -1206 | nothing | Update check failed: no connection (‹code›: ‹description›); trying again in 1 hour. | the same, without "trying again…" | Couldn’t check: this Mac isn’t connected to the internet. (TLS errors: Couldn’t check: ‹description›) | 1 h |
| Timeout, -1001 | nothing | Update check failed: no answer in 10 s; trying again in 1 hour. | the same, without "trying again…" | Couldn’t check: GitHub didn’t answer within 10 seconds. | 1 h |
| Any other URLError | nothing | Update check failed: ‹description› (‹code›); trying again in 1 hour. | the same, without "trying again…" | Couldn’t check: ‹description› | 1 h |

- ‹why› is one of: "no tag_name", "the tag “nightly” is not a version", "a draft", "a prerelease",
  "html_url is not on github.com", "a 304 before any release", "more than 1 MB", "a redirect to
  ‹host›".
- 15:42 is `X-RateLimit-Reset` in the Mac's short time format. Without that header: "…(HTTP 403)."
  and "Try again in an hour."
- A 200 without an ETag clears the stored one, so the next request sends none.
- Log lines give the running version and the tag as written ("this is 0.3.0", "v0.3.0"), and the
  offered version as the menu does ("Sill 0.4"). The menu and the pane show every version as
  SillVersion does ("0.3", "0.4").
- An automatic check that finds nothing new prints nothing: a quiet log, once a day.

**What is offered** is the stored release, whenever its version is newer than `running`. So:
- the menu item is there at launch without a request;
- it goes by itself once the new version runs (no refetch);
- it comes back after a downgrade.

At launch, when one is offered, one line (Sill.app only): "Update: Sill 0.4 is available (found by
an earlier check)."

#### 6.5 Versions, tags and the release

- **Sill.app's version** is Packaging/Info.plist's CFBundleShortVersionString (0.3.0 today,
  :23-24), and its build number is the commit count (make-app.sh:57-58). A release bumps the version
  by hand.
- **The rule:** a release's tag is `v` + that version (`v0.4.0` for 0.4.0), and its GitHub release
  is published (not a draft, not a prerelease) with the notarized zip attached. The check compares
  exactly that tag with the running version.
- **`make-app.sh --release`** refuses to build unless HEAD carries that tag (open question 9). In
  the pre-check at :32-38, with `git describe --tags --exact-match HEAD`:
  ```
  error: --release builds only a commit tagged v0.4.0 (HEAD is tagged 'nothing'): the update check compares the release's tag with this version.
  ```
- **docs/release-checklist.md** (app-store-readiness) gains, in order:
  - bump CFBundleShortVersionString in Packaging/Info.plist, and commit;
  - `git tag v‹version›`;
  - `make-app.sh --release` (through `release.sh`);
  - publish the GitHub release for that tag, with the zip;
  - within a day every older Sill.app offers it.

  If that branch has not merged when step 6 runs, the lines go into this PR's body, for it.

#### 6.6 The status menu (`StatusItemController.swift`)

- `MenuBuilder.entries(…, update: UpdateOffer?)` (:55-126).
- With an offer: one item right after the card and any attention items, before the first
  separator:
  ```
    Sill 0.4 Is Available…  — You have 0.3; opens its download page
  ```
  - `MenuEntry.Action.openUpdate` opens the offer's URL with `NSWorkspace.shared.open` from the
    item's target/action. That runs no modal loop.
  - The title in title case, the subtitle in sentence case, like the menu's other items.
- **The glyph does not change.** The attention glyph means that Sill needs the person before it can
  work at all (a permission, a failed listener, a port in use). An update needs nothing, and a menu
  bar icon that stays orange for days until someone updates teaches people to ignore it. The item is
  in front of the person at every open of the menu, and Settings says it too.
- No tooltip change; the card is unchanged.

#### 6.7 Settings › General (`SettingsPanes.swift`, GeneralPane :59-135)

A section before the Log section (:119-127):

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Check for updates automatically                                        [on]  │
│ Sill 0.4 is available.                      [Open Release Page…] [Check Now] │
└──────────────────────────────────────────────────────────────────────────────┘
  Once a day, Sill asks GitHub whether a newer version is out. GitHub sees this
  Mac’s IP address and which version of Sill it has; nothing else is sent. Sill
  never downloads or installs anything by itself: a new version opens its page
  on GitHub, where you download it.
```

- The toggle **"Check for updates automatically"** (`$settings.updateCheck`).
- The line, then the buttons: **[Open Release Page…]** only while an offer exists; **[Check Now]**,
  disabled while a check runs.
- The line, first match wins:

| State | Line |
|---|---|
| A check is running | Checking… |
| After Check Now in this run, until GitHub answers an automatic check | Its result (§6.4): "Sill is up to date.", "Sill 0.4 is available.", or "Couldn’t check: …" in orange |
| An update is offered | Sill 0.4 is available. |
| Checked before | Last checked ‹the date abbreviated, the time short›. |
| Never checked | Not checked yet. |
| No version (the bare binary) | This build of Sill has no version number, so it can’t check. (Check Now disabled) |
| Test pattern mode without a test feed | Sill doesn’t check for updates in test pattern mode. (Check Now disabled) |

- VoiceOver hears a Check Now result: `AccessibilityNotification.Announcement(line).post()` when it
  arrives.
- No alert anywhere: a failure is this line and one log line.
- The footer uses the pane's `Footnote`. The version footer at the bottom stays "Sill 0.3.0 (85).
  Free and open source."

#### 6.8 Settings keys and persistence

In `me.saffer.sill.mac` (the bare binary's domain is `SillMenuBar`):

| Key | Type | Written by | Meaning |
|---|---|---|---|
| `updateCheck` | Bool, registered default true | HostSettings (the toggle, `-SillSetAfter`) | Automatic checks. `-updateCheck 0` overrides it for one run |
| `updateLastCheck` | Double, seconds since 1970 | UpdateChecker | GitHub's last answer, of any HTTP status |
| `updateETag` | String | UpdateChecker | The last 200's ETag, sent back as If-None-Match |
| `updateLatestTag` | String | UpdateChecker | The last published release's tag, as GitHub wrote it ("v0.4.0") |
| `updateLatestURL` | String | UpdateChecker | Its html_url |

- `updateCheck` is not in HostConfig: it moves no listener and no pipeline. HostSettings gets its
  key, its registered default, and a property whose didSet saves it, calls `onUpdateCheckChange`,
  and logs "Update check: automatic checks off." or "Update check: automatic checks on.".
- The other four are the checker's own: read at start, written after each answer, in the same
  `UserDefaults`. Together they are "the version last offered" the task asked to keep: the stored
  release, offered whenever it is newer than what runs.
- To make the next launch check after 30 s, delete `updateLastCheck` (README, §13).

#### 6.9 Files, and the test arguments

| File | What |
|---|---|
| `Sources/SillMenuBar/UpdatePolicy.swift` (new; pure: Foundation and StreamProtocol's SillVersion; checked with swiftc) | The feed's URL; the release's decoding and the published and newer rules; `interpret(answer, stored:, running:, anyReleaseURL:) -> (Outcome, Stored)`; the due rule and the next date; every text of §6.4, §6.6 and §6.7 |
| `Sources/SillMenuBar/UpdateChecker.swift` (new; main actor, `@Observable`; Foundation and Observation only, so it compiles on its own with swiftc for H7 and needs no host) | The session; the timers (run-loop Timers, as DebugHooks uses); the one request in flight; the stored state; `offer`, `phase`, the Check Now line; `start()`, `checkNow()`, `systemDidWake()` |
| `AppModel.swift` | Owns `updates` (the defaults, the running version, the feed, the schedule); starts it once the host has started, or failed to (:52-86); forwards `updateCheck` changes; observes wake; passes `hostVersion` to the coordinator |
| `HostSettings.swift` | `updateCheck` |
| `StatusItemController.swift` | The item and `.openUpdate` |
| `SettingsPanes.swift` | The section, as `UpdatesSection(view: UpdatesView, actions:)`, which takes plain values so the previews can draw every state |
| `DebugHooks.swift` | The arguments below, and the previews |
| `Scripts/sillfeed.py` (new; Python's standard library) | A fake releases endpoint for the tests (§10) |

**Test arguments** (in release builds too, like the others; each does nothing unless passed):
- `-SillUpdateFeed <url>`: check this feed instead of GitHub. Only `http(s)://127.0.0.1…`,
  `http(s)://[::1]…` or `http(s)://localhost…`. Anything else prints "SillUpdateFeed ignored: only a
  feed on this Mac (127.0.0.1, ::1 or localhost) is allowed." With it, any http or https `html_url`
  counts as published, and test pattern mode checks.
- `-SillUpdateNow 1`: one check right after the host starts, as Check Now (so it logs "up to date"
  too). In test pattern mode without a feed: "SillUpdateNow ignored: test pattern mode checks only a
  test feed (-SillUpdateFeed)."
- `-SillUpdateVersion <v>`: the running version the check compares, for the bare binary, which has
  none.
- `-SillUpdateInterval <s>`: the 24 hours become s seconds, the hour's retry s/24 (at least 1 s),
  the launch delay min(30, s) seconds, and there is no jitter.
- `-SillSetAfter '<s> updateCheck=0'` (or `=1`): as a click on the toggle.

**Previews** (`-SillRenderPreviews`):
- `pane-general-*`, with the section fixed at "Not checked yet.", so the render does not depend on
  what an earlier run stored;
- `pane-updates-{never,last,checking,uptodate,available,norelease,limited,offline,noversion,testpattern}-{light,dark}.png`,
  the section alone at 520 pt;
- menu.txt's new sample `update-available`: the idle menu with the item.

#### 6.10 Privacy, and the policy's line

- **What a check sends GitHub:** the Mac's IP address (every request does), the User-Agent, which
  is Sill's version ("Sill/0.3.0"), the fixed headers above, and TLS's own metadata.
- **What it never sends:** an identifier, a cookie, a token, the Mac's name or model, anything about
  devices or streams.
- **Where it goes:** GitHub's logs, under GitHub's privacy statement. The developer receives nothing:
  there is no server of ours.
- **Opening the release page** is an ordinary visit to github.com in the person's browser.
- **The device's hello** (§3.1) goes only to the Mac it connects to, on whatever carries the
  session: the home network, the cable, Direct Wireless, or with Remote Access the person's own VPN
  or forwarded port.

**The line for `site/privacy.html` (app-store-readiness), as written:**

> **Update check (Mac).** Sill for Mac checks for updates. Unless you turn off “Check for updates
> automatically” in Sill’s Settings › General, once a day it asks GitHub (api.github.com) whether a
> newer version of Sill has been released, and again whenever you click Check Now. Like any visit to
> a website, that request shows GitHub your Mac’s IP address, and it says which version of Sill you
> have (for example “Sill/1.0”). Sill sends nothing else: no identifiers, no cookies, nothing about
> your devices or what you stream. We receive nothing from these checks; GitHub’s privacy statement
> covers what GitHub keeps. Sill never downloads or installs anything by itself. The iPhone and iPad
> app checks for nothing: the App Store updates it. It does tell your Mac which version of Sill it
> runs when it connects, so that your Mac can say when the app needs an update to keep working with
> it.

The iOS app's App Privacy answer stays "Data Not Collected": the device sends its version only to
the person's own Mac.

### 7. iOS client

#### 7.1 Files (a new iOS file needs its four pbxproj entries by hand; StreamProtocol's files reach the app through the package)

| File | Change |
|---|---|
| `Sources/StreamProtocol/Compatibility.swift` (new), `StreamMessage.swift`, `Remote.swift`, `Switcher.swift` | §3 |
| `iOSClient/GoodbyePolicy.swift` (new; pure: Foundation and StreamProtocol; checked with swiftc) | §7.3 |
| `iOSClient/SillLinks.swift` (new; or app-store-readiness's, if it has merged: `appStore` goes there) | §7.5 |
| `iOSClient/StreamClient.swift` | The hello (§7.2); `goodbye: Goodbye?` in place of `goodbyeReason` (:404, :1679-1686); `notice`; `hostVersion` and `hostProtocol` |
| `iOSClient/StreamClient+Remote.swift` | `sessionEnded` (:392-444) through GoodbyePolicy |
| `iOSClient/ContentView.swift` | The link under the status line (:360-366); the contract comment |
| `iOSClient/MockCatalog.swift` | The harness cases; `failureCopy`'s goodbye lines from GoodbyePolicy |
| `iOSClient/SessionLink.swift` | Its doc comment: pings and the hello go out on their own connection |

#### 7.2 The hello

- `StreamClient.helloMessage`, built once: `Hello(appVersion: CFBundleShortVersionString, build:
  CFBundleVersion, protocol: SillProtocol.current, device: ClientStatsReporter.deviceName)`. DEBUG
  `-SillHelloVersion <v>` replaces `appVersion`, for the gate's tests.
- It is the first call on each session connection, written straight to it (`c.send`), never through
  `SessionLink`:
  - `connect(to:…)`: first thing in `.ready` (:786), before `startMeasuring` starts the pings. A
    wired dial and its unconstrained fallback each send their own.
  - `startMove`: first thing in `.ready` (:943), before `probeMove`. The hand-over's fence does not
    hold it.
  - `adopt` (:1268): before `connection = c`, since a remote winner is `.ready` when it is handed
    over.
- Never on a pairing connection (RemoteConnector's `.pairing` dials), whose one message is kind 19.
- DEBUG console: "hello: sent Sill 0.1 (1), protocol 1".

#### 7.3 Goodbyes (`GoodbyePolicy.swift`, new; pure): today's loop, fixed

**What this branch does today** (cb0ec55) with a reason it does not know:
- A home session shows "‹Mac› disconnected. It will reconnect when the Mac is back." and reconnects:
  `reconnectIfListed` dials the Mac's network row at once (StreamClient+Remote.swift:424-444, :456).
- A remote dial before its first window list reads `.goodbye(_)` as `.refused`
  (RemoteDialPolicy.swift:175): "‹Mac› answered, but Sill isn’t accepting remote connections there…",
  and an automatic dial redials after 2, 4, 8, then every 10 s for 120 s.
- So it never drops silently. But against a Mac that refuses it, it loops (at home as fast as the
  connections go), and says the wrong thing.

**The rule** is one pure function, `GoodbyePolicy.outcome(goodbye, mac:, device:, saved:) ->
Outcome` (`text`, `reconnect`, `remoteAllowed`, `storeLink`, `isNotice`), for every route, whether or
not a window list came:

| Goodbye | Status line | Reconnects by itself | Remote dial in that reconnect | Link |
|---|---|---|---|---|
| None (the connection just ended) | A saved Mac: "‹Mac› disconnected. Sill will reconnect when it can reach it." Else: "‹Mac› disconnected. It will reconnect when the Mac is back." | yes | a saved Mac | — |
| quit | "‹Mac› quit Sill. This ‹iPad› reconnects when it’s back." | yes | a saved Mac | — |
| removed | "‹Mac› removed this ‹iPad›. To use it again, pair it again." | no | — | — |
| remoteOff | "‹Mac› turned off Remote Access." | yes | no | — |
| internetOff | "‹Mac› stopped accepting connections from the internet. Connect through your VPN." | yes | no | — |
| busy | "‹Mac› is already serving 8 devices." | yes | a saved Mac | — |
| update | `message`. Without one: "Update Sill on this ‹iPad› to keep using ‹Mac›.", plus " It needs version ‹minimumVersion› or later." when that parses | only with `"reconnect":true` | a saved Mac | the App Store |
| Any other reason, and a kind 22 that does not decode (reason "") | `message`. Without one: "‹Mac› closed the connection. Tap it to try again.", or with `"reconnect":true` "‹Mac› closed the connection. Sill will reconnect when it can." | only with `"reconnect":true` | a saved Mac | — |

- The first six rows are today's words and behaviour, moved, not changed.
- `message` is shown after `SafeText.label(message, limit: 300)`: one line, without control or
  bidirectional characters. Empty after cleaning counts as absent. The status line is
  `Text(client.status)`, which SwiftUI shows verbatim for a String: no Markdown, and no link from
  the host.
- **"update" and unknown reasons are notices.** `sessionEnded` looks at them first, before the
  remote dial-failure branch (:397-407). A remote session refused before its first window list
  shows the notice, never "isn’t accepting remote connections", and `remoteDialFailed` never retries
  it. The connect screen never left in that case, so `tearDown(status:restartSearch: false)` keeps
  its Remote rows; an after-pairing dial's watch is cancelled and its card goes idle.
- The known reasons keep their paths: a remote dial's removed, remoteOff and busy still go through
  `RemoteDialPolicy.classify`.
- No reconnect means `reconnect = nil` and nothing scheduled. Nothing dials that Mac until the person
  taps its row, or relaunches the app and taps it (the device never dials by itself at launch).
- DEBUG console: "session: the Mac said goodbye (update): “…”; not reconnecting", or
  "…; reconnecting".
- **Worth taking alone:** step 3 is this fix and nothing else, so it can also go into PR #13 by
  itself (open question 11).

#### 7.4 The notice on the connect screen (`ContentView.swift`)

- `StreamClient.notice: Notice?` (`text`, `storeLink`) is set, with the status line, by a notice
  goodbye. The link shows while `client.status == notice.text`, so the next status (a tap, a dial,
  Forget) takes it away.
- Under the status line (:361-366), when `notice.storeLink` and `SillLinks.appStore` is set: a
  `Link`, "Update Sill in the App Store", styled like Search Nearby (15 pt semibold, the accent
  colour, the column's width, at least 44 pt tall), with the hint "Opens the App Store."
- **VoiceOver** hears the notice as it hears every ended session's line: the connect screen announces
  its status line when it appears and when it changes (:314-326), and a notice is never an idle
  line.
- **A refused home session flashes the stream screen.** At home the device counts as connected at
  `.ready` (StreamClient.swift:786-806), a round trip before the host's refusal arrives. So a refused
  device shows the empty stream screen for a frame or two, then the connect screen with the notice.
  Accepted (open question 10). A remote session counts as connected only at its first window list,
  so it never flashes.
- Nothing else changes: the rows, the hint, Search Nearby, Add a Mac….

#### 7.5 The App Store link (`SillLinks.swift`)

```swift
/// Where Sill sends people outside the app.
enum SillLinks {
    /// Sill's App Store page, https://apps.apple.com/app/id<Apple ID>. The Apple ID is the App Store
    /// Connect record's, known once the record exists: the release checklist fills it in before the
    /// first upload. While the placeholder stays, no link shows.
    static let appStoreText = "APP_STORE_URL_PLACEHOLDER"
    /// An https URL from `appStoreText`, else nil. DEBUG: -SillAppStoreURL <url> replaces it.
    static var appStore: URL? { … }
}
```

- While the placeholder stays, the notice shows without the link: the message already says what to
  do (open question 8).
- The release checklist (§6.5) gains: "Replace APP_STORE_URL_PLACEHOLDER in
  iOSClient/SillLinks.swift with https://apps.apple.com/app/id‹Apple ID›."

#### 7.6 The Mac's version

- The window list's `hostVersion` and `protocol` go into `StreamClient.hostVersion` and
  `hostProtocol` (published; cleared in `tearDown`). Nothing shows them.
- DEBUG console, once per session: "host: Sill 0.4.0, protocol 1"; "host: no version, protocol 1"
  (SillHost, the bare binary); "host: no version (a Mac from before 2026-09-25)".
- They exist so that a later device can tell a Mac from the first public build from what it needs
  (§14).

#### 7.7 DEBUG arguments and harness cases (the contract comment at ContentView.swift:55-138, and CLAUDE.md)

- `-SillConnectCase update`: the connect screen after a refusal, "Update Sill on your iPad to keep
  using Mac mini. It needs version 1.2 or later." as its status line, above a Wi‑Fi row. With
  `-SillAppStoreURL https://apps.apple.com/app/id000000000` the link shows.
- `-SillConnectCase notice`: a reason this build does not know, a two-line message, no link.
- `-SillRemoteFailure quit`, `removed` and `remoteoff`: their lines now come from GoodbyePolicy (the
  same words).
- `-SillHelloVersion <v>`: the hello's `appVersion`.
- `-SillAppStoreURL <url>`: the link's address.

### 8. Timeouts and limits (one table)

| What | Value |
|---|---|
| Update check: first check | 30 s after the host has started, if due |
| Update check: period | 24 h plus a random 0–30 min |
| Update check: after no HTTP answer | 1 h (not stored) |
| Update check: request | 10 s; one at a time; the body at most 1 MB |
| Update check: redirects | only to https://api.github.com/ |
| Device gate: the first message (floor above "0") | within 2 s of `.ready`; the 1 MB cap |
| Device gate: goodbye, then close | once the send is processed, or after 250 ms |
| Device gate: a source that loops | after 5 refusals in 60 s, each next goodbye 2 s after its first message |
| Refused lines | one per source a minute, then one count line |
| Hello | one per connection (a second is skipped); about 90 bytes |
| A notice's message on the device | SafeText.label, at most 300 characters |

### 9. Edge cases

| Case | Behaviour |
|---|---|
| The repository private (today), or public with no release yet | A 404 every day: one "failed" line, nothing offered, no alert |
| A release withdrawn after it was offered | The next 404 clears it, and the item goes |
| The latest release older than the running app (a build ahead of its tag) | Not offered; Check Now says "Sill is up to date." |
| A tag that is not a version ("nightly") | "not a published release"; nothing offered |
| The person updates | At the next launch the stored release is not newer: no item, no request needed |
| The person downgrades | The stored release is newer again: the item is there at launch |
| Offline at login | The check at 30 s fails with no connection, and runs again in 1 h; the stored offer shows meanwhile |
| Asleep through the due time | Checked 30 s after the wake |
| Many Macs behind one address (an office) | 0–30 min of jitter; a 403 is quiet and waits a day |
| A captive portal | Its TLS interception fails (-1202): no connection, again in 1 h |
| Two copies of Sill.app | One defaults domain: the second sees the first's `updateLastCheck` and waits |
| Automatic checks off | No request ever; a stored offer still shows; Check Now works |
| The bare binary, or test pattern mode | The bare binary never checks without `-SillUpdateVersion`, and test pattern mode never without `-SillUpdateFeed`; the pane says why |
| A device with automatic updates off, below a later host's floor | The notice and the App Store link |
| A device whose iOS the floor's version does not support | The message still shows, and the App Store page says the app needs a newer iOS. §4.6 rule 2 makes the host's release notes say so first |
| A device from before this change, against a later host with a floor | It loops: it cannot read the notice. After five refusals in a minute the host answers each 2 s late and logs two lines a minute. Only development and TestFlight builds are that old |
| A hostile "Mac" on the network sending "update" with a scary message | Plain text, at most 300 characters, no link from it, no reconnect: the person taps the row to try again. It could already show anything through its window list |
| A host that sends a goodbye and does not close | The device waits for the close; its liveness rule ends the connection within 6 s |
| The hello to an older host | Skipped as an unknown kind |
| Two hellos on one connection | The second is skipped |
| A pairing connection | No hello, and no gate: pairing is not refused for age |
| A move from AWDL to the network, floor above "0" | The move's connection sends its own hello first and is admitted; the fence is unchanged |
| A remote session, floor above "0" | The update goodbye is the first message inside TLS; no "Remote client connected" line |
| A later host sends "update" with `"reconnect":true` | The device reconnects and is refused again: a host bug, which §3.7 and §4.6 forbid |

### 10. Test gates

**Hard rules for the implementing session** (also §12):
- **Every run that starts a host counts as using the hardware encoder:** SillHost of any kind, and
  the bare SillMenuBar except with `-SillRenderPreviews`, because at launch the host pushes one
  frame through it (EncoderProbe). Before each such run, read `~/Library/Logs/Sill/Sill.log`: its
  last "[30s] idle · 0 clients" or "Client left" line must be newer than its last "Client
  connected" or "Remote client connected" line. Otherwise skip the run, do what needs no host (the
  swiftc checks, H7, the previews), and write down what was skipped.
- Never touch /Applications/Sill.app, the `me.saffer.sill.mac` domain, Noah's login keychain or his
  iPad. Never `make-app.sh --install` or `--open` (a plain `make-app.sh` build is fine), `tccutil`,
  `simctl recordVideo` or XCUITest. Drive the simulator with launch arguments,
  `xcrun simctl io … screenshot` and the simulator control tool's taps.
- Only synthetic hosts from `.build/release`, started from Python with `start_new_session=True`,
  killed by PID, none left running.
- The bare `SillMenuBar --synthetic` for the app's paths; `defaults delete SillMenuBar` after each
  gate.
- **No test contacts GitHub:** every update-check test passes `-SillUpdateFeed` (a loopback feed),
  and test pattern mode never checks without one. During H8, `lsof -nP -i -a -p PID` shows no socket
  but the listener's and the feed's.
- Never tap a real Mac's row in the simulator: Noah's Mac is listed.
- `$T` is a fresh temporary directory per gate.

**Test tools:**
- **`Scripts/sillfeed.py PORT`** (new; Python's standard library):
  - flags: `--tag v0.4.0`, `--status CODE` (200, 304, 403, 404, 429 or 500), `--etag 'W/"x"'`,
    `--draft`, `--prerelease`, `--html-url URL`, `--body JSON`, `--slow S`, `--reset EPOCH`;
  - it answers 304 when `If-None-Match` matches its ETag;
  - it prints one line per request: the time, the path, User-Agent, If-None-Match and Cookie.
- **`Scripts/sillclient.py`** gains `--hello=VERSION[,PROTOCOL]`: a kind 23 first, before the
  select, with the `--device` name (else "sillclient"); `--hello=none` sends `{}`. It prints kind
  22's `message`, `minimumVersion` and `reconnect`.

**Headless (H): no permissions needed.**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). Record cb0ec55; `git archive` it to `$SP/base` and build it. Baselines, under the encoder rule: `SillHost --synthetic` idle 35 s, and with `sillclient.py PORT 8 desktop`; both again with `--direct-wireless`. The bare app's `-SillRenderPreviews` (no host). Probes: P1, §6.2's URLSession probe from the implementer's own build; P2, one unauthenticated GET of the feed; P3, §3.5's JSON (keys, nil fields left out, the old struct reading "update") | The files exist; P1 answers as §6.2 says (the 304 delivered, no cookie, -1004, -1001 at 10 s), P2 is a 404, P3 as §3.5 says; otherwise the plan changes first |
| H1 | Builds: `swift build -c release`; iOS Debug and Release | Only the known warnings (CaptureProbe; the old `StreamClient` capture warning) |
| H2 | **The CLI byte for byte.** H0's runs on the new build, digits masked, lines sorted | Identical |
| H3 | **Pure checks** (swiftc; each with mutants caught, at least five per module). `SillVersion`: every §3.2 example; the order of 1,000 random pairs against a reference; the description's round trip. `DeviceGate`: floor "0" admits nil, "", "junk" and every version; floor 1.2 refuses nil, "0.1", "1.1.9" and "junk" and admits "1.2", "1.2.0", "1.10" and "2"; the message for an iPad, an iPhone and any other name; the Refused lines; the shipped constant parses. `UpdatePolicy`: every row of §6.4; a 304 with and without a stored release; the offer after an update and after a downgrade; the due rule, a clock in the future included; the jitter's range; loopback-only feeds; every text. `GoodbyePolicy`: every row of §7.3; messages with control and bidi characters, of 1,000 characters, and empty after cleaning; `reconnect` nil, true and false; a saved and an unsaved Mac. The payloads: Hello's keys; `{"reason":"quit"}` byte for byte; WindowList with and without the new keys | All pass |
| H4 | **Compatibility.** A swiftc check with cb0ec55's StreamProtocol: it decodes the new Goodbye (reason "update"), a WindowList with `hostVersion` and `protocol`, and maps kind 23 to `.unknown`. Live, under the encoder rule: cb0ec55's host with `sillclient.py PORT 5 none --hello=1.0,1` | All decode; the old host serves the client with the catalog as always and prints nothing new |
| H5 | **The hello, floor "0".** `SillHost --synthetic`; `sillclient.py PORT 5 none --hello=1.0,1 --device='iPad (iPad14,1)'`, then `--hello=none` | "Client hello: iPad (iPad14,1), Sill 1.0, protocol 1 (127.0.0.1:P)", then "Client hello: 127.0.0.1:P, no version"; the catalog in its usual order; no refusal; nothing else new |
| H6 | **The gate** (`SILL_TEST_MIN_DEVICE_VERSION=1.2`, synthetic hosts). (a) `--hello=1.1 --device='iPad (iPad14,1)'`; (b) `--hello=1.2`, then `--hello=1.10`; (c) no `--hello` (a select comes first); (d) a raw TCP client that sends nothing; (e) 20 refused connections from 127.0.0.1 in 5 s; (f) `--remote` with SILL_TEST_REMOTE_DIR: pair, then a `--tls --hello=1.1` session, then `--hello=1.2`; (g) (a) with `SILL_TEST_GOODBYE='{"reason":"later","message":"x","reconnect":true}'`; (h) `SILL_TEST_MIN_DEVICE_VERSION=abc` | (a) Exactly one message, kind 22 with §3.5's fields and this Mac's name, then EOF within 300 ms; no "Client connected", "Catalog" or "Client left" line; one Refused line. (b) Served, the catalog as usual. (c) Refused as "an older Sill". (d) Refused at 2.0 ± 0.1 s. (e) One Refused line and one count line; from the sixth on, the goodbye 2 s after the first message. (f) The update goodbye and no "Remote client connected" line; then served. (g) That payload instead. (h) The "ignored" line, and floor "0" |
| H7 | **The checker alone** (swiftc: UpdatePolicy, UpdateChecker and Compatibility with a small driver; no host, no encoder) against `sillfeed.py`, on short schedules | The headers: User-Agent, Accept and the API version, never a Cookie, If-None-Match only with a stored release. Every row of §6.4, live. The timeout at 10 s (`--slow 30`). A closed port retried after the scaled hour. Over 20 s at a 4 s period with a 404, 5 ± 1 requests. Check Now during an automatic check sends no second request. A 1.5 MB body refused |
| H8 | **The app end to end** (the bare `SillMenuBar --synthetic`, under the encoder rule; `sillfeed.py P --tag v0.4.0`). Run 1: `-SillUpdateFeed http://127.0.0.1:P/latest -SillUpdateVersion 0.3.0 -SillUpdateNow 1 -SillLogFile $T/app.log -SillQuitAfter 8`. Run 2: the same without `-SillUpdateNow`, quitting after 40 s. Run 3: run 2's arguments plus `-SillUpdateInterval 4 -SillSetAfter '2 updateCheck=0'`, quitting after 20 s. Run 4: `-SillUpdateNow 1 -SillUpdateVersion 0.3.0` and no `-SillUpdateFeed`, quitting after 40 s | Run 1: the found line, and the four keys in `defaults read SillMenuBar`. Run 2: "Update: Sill 0.4 is available (found by an earlier check)." and no request at the feed. Run 3: "Update check: automatic checks off." and no request. Run 4: the "SillUpdateNow ignored" line, no request, and no socket but the listener's. Then `defaults delete SillMenuBar` |
| H9 | **Previews**, before and after | Only `pane-general-*`, the new `pane-updates-*` and menu.txt's `update-available` sample differ; look at each, light and dark |
| H10 | **Hard rules** (grep) | No `URLSession` or `api.github.com` in Sources/SillHost or Sources/SillHostCLI; no `Authorization`, token or `Sparkle` in Sources; `minimumDeviceVersion = "0"`; the TEST ONLY variables read only where `advertise` is false; no `assumeIsolated` or `updateConfiguration` in Sources/SillHost; `-SillUpdateFeed` takes loopback only |
| H11 | **Regression:** the existing checks (the ledger, the discovery policy, the remote dial policy, the move's fence, ClientLink, OriginPolicy) | As before |

**Simulator (S):** the iPad Pro 13" simulator the earlier steps used (40522E9E-8B13-4676-BC94-D94FDD048471), launch arguments, `simctl io … screenshot`, the simulator control tool's taps. Host runs obey the encoder rule.

| # | Check |
|---|---|
| S1 | **Photos.** `-SillConnectCase update` with `-SillAppStoreURL https://apps.apple.com/app/id000000000`, the same without it, and `-SillConnectCase notice`, at 1000x710, 710x1000, 500x710, 710x500, 402x874, 874x402 and 375x667, and at `content_size accessibility-extra-large` (reset afterwards). Nothing crosses y = 500 in the half-folded layout; the message wraps and never truncates; the link is at least 44 pt tall; the title does not move sideways. Send Noah the sheet |
| S2 | **A live refusal at home.** `SILL_TEST_MIN_DEVICE_VERSION=99 SillHost --synthetic`; the normal app with `-SillConnect 127.0.0.1:P`. The connect screen says "Update Sill on your iPad to keep using ‹this Mac's name›. It needs version 99.0 or later."; the host prints one Refused line with the simulator's name and "Sill 0.1", and no "Client connected"; the console says "not reconnecting"; the host sees no second connection in 60 s |
| S3 | **Admitted.** Floor 0.1, and floor 1.2 with `-SillHelloVersion 1.2`: streams as before, with one "Client hello" line; the console reads "host: no version, protocol 1" |
| S4 | **A reason this build does not know.** `SILL_TEST_GOODBYE` with `"reconnect":false`, then true: the message is the status line either way, and the console says "not reconnecting" or "reconnecting". Through the remote door (pair with `-SillPairURL`, dial with `-SillDialSaved 1`): with false the host sees one session connection in 60 s; with true, a redial about 3 s after each refusal, as a saved Mac's remote reconnect does |
| S5 | **A remote refusal.** The same host with `--remote` and floor 99: the update notice, not "isn’t accepting remote connections"; one session connection in 120 s |
| S6 | **An older host.** cb0ec55's `SillHost --synthetic` from `$SP/base`, with `-SillConnect`: streams as always; the host logs no hello line; the console reads "host: no version (a Mac from before 2026-09-25)" |
| S7 | **The link.** In the `update` case with the override, a tap on the link opens its URL (Safari, in the simulator) |

**Noah's Mac and devices (V), handed over at the end:**

| # | Check |
|---|---|
| V1 | **The real check, today.** Install this Sill.app (`make-app.sh --install --open`, yours to run): within a minute the log says "Update check failed: GitHub has no release of Sill (HTTP 404)." once, the menu has no item, and Check Now says "Couldn’t check: GitHub has no release of Sill yet."; a day later one more line; never an alert. `defaults read me.saffer.sill.mac updateLastCheck` is set |
| V2 | **Once the repository is public, with a release newer than the installed app:** the menu shows "Sill X Is Available…" within about 30 s of a launch, or after Check Now; the item opens the release page in the browser; Settings › General says so too; after installing it, no item, and Check Now says "Sill is up to date." |
| V3 | **A refusal on the iPad.** The iPad's Debug build, launched with `-SillConnect <this Mac's LAN address>:P`, against `SILL_TEST_MIN_DEVICE_VERSION=99 SillHost --synthetic`: the message, spoken by VoiceOver as it appears; the link with `-SillAppStoreURL`; no reconnect in 2 minutes; a relaunch dials again and is refused again |
| V4 | **Mixed builds.** The iPad's installed build (PR #13) against this Sill.app: as before. This iPad build against PR #13's Sill.app: as before (the host skips the hello) |
| V5 | **VoiceOver on the Mac:** the toggle, Check Now and its result read after a click; the menu item |
| V6 | **The first two notarized builds:** installing the second over the first keeps Screen Recording and Accessibility (the team-based designated requirement), and `make-app.sh --release` refuses a HEAD without the version's tag |
| V7 | **The privacy line** on the published site/privacy.html reads as §6.10 |

### 11. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

0. **Preflight** (no commit): H0.
1. **"Protocol: the hello, the host's version and the goodbye's notice"** (StreamProtocol):
   - Compatibility.swift (`SillProtocol`, `SillVersion`, `Hello`) and kind 23;
   - `Goodbye`'s three fields and "update"; `WindowList`'s two fields;
   - `sillclient.py --hello` and kind 22's fields.

   Gates: H1, H3 (SillVersion, the payloads), H4 (the decode part).
2. **"Host: the device floor, the hello and the update goodbye"**:
   - DeviceGate;
   - in StreamServer: the gate, the hello, the refusal and its lines, the TEST ONLY variables,
     `Goodbye` values;
   - `serve(…, admitted:)` and RemoteServer's line;
   - the coordinator's `macName`, `hostVersion` and early name.

   Gates: H1, H2, H3 (DeviceGate), H4 (live), H5, H6.
3. **"iOS: a goodbye the device does not know no longer loops"** (the fix alone; it can also go into
   #13):
   - GoodbyePolicy for today's reasons and unknown ones; `goodbye: Goodbye?`;
   - `sessionEnded` looks at notices first;
   - MockCatalog's lines.

   Gates: H1 (iOS), H3 (GoodbyePolicy), S4.
4. **"iOS: say hello, and show a Mac's update notice"**:
   - the hello on every session connection;
   - "update", `notice` and the link; SillLinks;
   - `hostVersion` and `hostProtocol`;
   - the harness cases and DEBUG arguments.

   Gates: H1, H3, S1–S3, S5–S7.
5. **"Sill.app: check GitHub for a newer Sill"**:
   - UpdatePolicy, UpdateChecker, `updateCheck`;
   - the pane's section, the menu item;
   - DebugHooks and the previews;
   - `sillfeed.py`;
   - the `make-app.sh --release` tag check.

   Gates: H1, H3 (UpdatePolicy), H7, H8, H9, H10.
6. **"docs: update check and device notice"**:
   - this plan, with its Results;
   - CLAUDE.md: the current step; the compatibility floor (§13, as written); Layout (the new files);
     Build and run (the arguments, the variables, the tools); Untested, for Noah (V1–V7);
   - README: an Updates paragraph in the Sill.app section (what it checks and sends, the toggle,
     Check Now, that it only opens the page, the keys) and the tag rule under Distribution;
   - app-store-readiness: the privacy line (§6.10) and the checklist lines (§6.5, §7.5), in its
     files if it has merged, else in a note for it in this PR's body.
7. **Review and hand-over.** Three lenses:
   - wire and compatibility: nothing sent before the gate's judgement, older builds both ways, the
     five goodbyes' JSON unchanged;
   - the update check: nothing sent but §6.2's headers, no storm, no alert, the modal-loop rule, the
     stored state across launches;
   - the device: the notice at every size, VoiceOver, no reconnect.

   A "Review fixes" commit if needed; adversarial re-runs of H6–H8 and S2–S5; then V1–V7 to Noah.
   **Stop there.**

### 12. Hard rules (for every step)

- **The CLI's default stdout stays byte for byte** the base's (masked and sorted), idle and
  streaming, with and without `--direct-wireless`. New lines appear only on events the baseline runs
  never produce (a hello, a refusal).
- **This build refuses no device:** `minimumDeviceVersion = "0"`, and the TEST ONLY variables work
  only on hosts that do not advertise.
- **Additive wire:** optional fields only, nothing renamed or retyped, kind 23 new and never to be
  reused, the five existing goodbyes' JSON unchanged.
- **Apple frameworks only:** Foundation's URLSession, Observation, AppKit, SwiftUI. No Sparkle and
  no package. The test tools use Python's standard library.
- **Zero operating cost:** GitHub Releases is the only feed. No server, no token, no analytics.
- **Never contact GitHub from a test,** and never with a token.
- **Never `MainActor.assumeIsolated`** in Sources/SillHost; hop with `Task { @MainActor }`. App code
  may use it in main-queue callbacks (AppDelegate's doc comment).
- **The modal-loop rule** in the app: no `NSAlert`, `runModal`, `NSMenu.popUp` or `.terminateLater`
  terminate from a Task, a continuation or a main-queue block. The update check shows errors inline
  only.
- **The encoder rule** of §10 before every host run; never `simctl recordVideo`, never XCUITest.
- **Never touch** Noah's Sill.app, `/Applications`, `me.saffer.sill.mac`, his login keychain or his
  iPad.
- **New iOS files** need their four pbxproj entries by hand. Swift 5 language mode.

### 13. Docs: CLAUDE.md's compatibility floor, and the rest

**A new section in CLAUDE.md, before "## Conventions", as written (open question 14 answered):**

> ## Compatibility floor
>
> The first public builds (Sill for iPhone and iPad from the App Store, Sill.app from GitHub) set it
> for good. Sill.app changes only when its user downloads a new version (its update check only points
> at one), and a device can stay on an old version (automatic updates off, an iOS the next version
> dropped). So every later host keeps serving devices from the first public build on, and every later
> device keeps working with Macs from the first public build on, or each says why
> (docs/update-notice-plan.md):
> - Kept as they are: the home door as Sill.app 1.0 ships it, TLS with pairing at home
>   (docs/home-pairing-plan.md, branch `home-pairing`, in progress; it ships before 1.0, Noah
>   2026-09-25), not today's plain-TCP `_sill._tcp` door, which only development builds and the CLI
>   keep; the 14-byte header; kinds 0–23 and their payloads (HEVC with ParameterSets; the JSON of
>   Switcher, Input, Viewport, HostSettings, Remote and Compatibility); the ping echo; a kind 16
>   within 2 s of the first window list; kind 22's `reason`, `message` and `reconnect`.
> - Additive only (HostSettings.swift's rules): new fields optional, never renamed or retyped; kind
>   numbers never reused; no new case in an enum an older peer decodes. `StreamSource` keeps its
>   three cases (a new source goes in an optional field, with `active` still one of the three). A new
>   `InputEvent` case, scroll phase or window command goes only to a host that said it takes it (a
>   kind or a field only newer hosts send), and a gesture ends with a scroll phase the first build
>   knows.
> - A device is refused, never served wrong. A host that can no longer serve older devices raises
>   `DeviceGate.minimumDeviceVersion` ("0" today) by the plan's §4.6, and they get kind 22 "update"
>   before anything else. A device from 2026-09-25 on that receives it shows the host's message word
>   for word, with its App Store link, and does not reconnect; older development builds cannot. At
>   the TLS home door only devices from home pairing on receive it (Decided, below).
> - Every device says hello first (kind 23: its version, build, protocol and name), and every host's
>   window list gives its version and protocol (`hostVersion`, nil from SillHost and from Macs
>   before 2026-09-25). A later device facing an older Mac tells what it lacks from these and from
>   which kinds and fields arrive, and says "Update Sill on ‹Mac›", as the Settings panel already
>   does for a Mac without kind 16.
> - `SillProtocol.current` (1) rises only with a change an older peer cannot skip, and the floor
>   rises with it.
> - Decided (Noah, 2026-09-25; the plan's open question 14): home pairing ships before 1.0, so the
>   floor is the TLS home door with pairing, and no 1.0 device speaks plain TCP to Sill.app. The
>   hello goes first inside TLS at both doors, through `serve`'s gate: whichever of this branch and
>   `home-pairing` lands second puts the gate in home-pairing's `Door`, one place for both doors,
>   and settles `SillProtocol` against home pairing's ALPN (`sill/1`; a later generation `sill/2`):
>   if 1.0's TLS home door is protocol 1, pairing on the home door leaves the examples of what
>   raises it (Compatibility.swift, the plan's §3.2 and §4.6). Builds from before home pairing,
>   this one included, dial plain TCP and say hello in plaintext: at the TLS door they get a failed
>   handshake and EOF, never kind 22 "update", and redial. Only development and TestFlight builds
>   are that old, so no plaintext path or sniffer answers them.

**CLAUDE.md, elsewhere:**
- the current step: both features, the defaults taken, what was verified;
- Layout: Compatibility.swift, DeviceGate.swift, UpdatePolicy.swift, UpdateChecker.swift,
  GoodbyePolicy.swift, SillLinks.swift, sillfeed.py;
- Build and run: `-SillUpdateFeed`, `-SillUpdateNow`, `-SillUpdateVersion`, `-SillUpdateInterval`,
  `-updateCheck 0`, `SILL_TEST_MIN_DEVICE_VERSION`, `SILL_TEST_GOODBYE`, `sillclient.py --hello`,
  and on iOS `-SillConnectCase update` and `notice`, `-SillHelloVersion`, `-SillAppStoreURL`;
- the settings list: `updateCheck`, and the four keys the check keeps.

**README:**
- in the Sill.app section, "Updates": once a day, what it sends, the toggle, Check Now, that it only
  opens the page; and to check again at the next launch:
  `for k in updateLastCheck updateETag updateLatestTag updateLatestURL; do defaults delete me.saffer.sill.mac $k; done`
  (`defaults delete` takes one key at a time);
- under Distribution: the tag rule (§6.5).

### 14. What comes later

- **The device-side floor.** When a later iOS build can no longer work with a Mac from the first
  public build, it reads `hostVersion` and `protocol` (or the kinds that never come), and says
  "Update Sill on ‹Mac› to use it with this ‹iPad›. It needs version ‹v› or later." on the connect
  screen, with the Mac download page's link, without dialing again.
- **Pairing on the home door (M5; the audit's finding 3; open question 14).** Superseded (Noah,
  2026-09-25): home pairing ships before 1.0, so the first public build already pairs at home over
  TLS, and its hello goes first inside TLS; only pre-1.0 builds meet the TLS door unable to read a
  notice. (As first written, the host that brought it would have raised the floor to the first
  device version that pairs there, and `SillProtocol.current` to 2.)
- **The Mac's version on the device** (the Settings panel's footer), for support.
- **"Skip This Version"**, release notes in Settings, and Sparkle, if BRIEF.md ever allows it (§6.1).

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **A new kind 23 hello instead of fields on the Viewport or ClientStats?** Default: **the hello.**
   Neither is the device's first message (Decision); on the remote door a host waiting for a
   Viewport would wait for ever.
2. **The Mac's version and protocol in every window list?** Default: **yes**, shown nowhere yet. A
   Mac from the first public build that never updates can then be told apart by later devices.
3. **The refusal names the Mac** ("…to keep using Mac mini.") instead of saying "…this Mac.".
   Default: **the name.** On the iPad's connect screen "this Mac" reads as the iPad, above a list of
   Macs.
4. **The floor is a build constant, not a setting.** Default: **a constant.** A setting could be
   lowered below what the host needs.
5. **Pairing is not refused for age.** Default: **not gated.** A device too old for the sessions
   hears the notice when it connects.
6. **A found update stays in the menu with automatic checks off.** Default: **yes.** Off stops
   asking GitHub, not showing what is known.
7. **No glyph change; the item after the card and the attention items.** Default: **as written**
   (§6.6).
8. **No App Store link until the placeholder is replaced.** Default: **hidden.** The message says
   what to do without it.
9. **`make-app.sh --release` builds only a commit tagged `v‹version›`.** Default: **yes.**
10. **A refused home session flashes the stream screen for a frame or two** (connected at `.ready`).
    Default: **accept.** The alternative shows the stream screen at the first window list on every
    route, as remote sessions do: a change to every connection for a rare event.
11. **Where the device changes land first.** Default: **stacked on #13.** If the first public build
    ships from main before #13, steps 1, 3 and 4 go to main with kind 22 and `Goodbye`; step 3 alone
    can also go into #13.
12. **0–30 minutes of jitter on the daily check.** Default: **yes.**
13. **Devices from before this change loop against a refusing host** (they cannot read the notice).
    Default: **accept**: only development and TestFlight builds are that old; the host slows them
    and sums them up in its log.
14. **Home pairing before or after 1.0?** (Review, 2026-09-25; no default: Noah's call before either
    branch merges.) **Answered (Noah, 2026-09-25): before 1.0.** The floor is the TLS home door with
    pairing (CLAUDE.md, Compatibility floor, and §13), and the hello goes first inside TLS, through
    `serve`'s gate. As asked: the floor then kept the plain-TCP `_sill._tcp` home door, and §14
    assumed pairing would come after the first public build, while docs/home-pairing-plan.md (branch
    `home-pairing`) makes Sill.app's home door TLS-only for 1.0 and rejects a plain listener or a
    sniffer for older builds, so a device from this build at a TLS-only door gets a failed handshake
    and EOF, never kind 22 "update", and redials. Pairing in 1.0 made the floor "the home door as
    1.0 ships it (TLS)"; after 1.0, the home door would have kept a plaintext path that reads the
    hello and answers kind 22 "update" (a first byte of 0x16 is a TLS handshake record; a device
    never sends kind 22). Left for the merge with `home-pairing`: whether 1.0's TLS home door is
    `SillProtocol` 1 with ALPN `sill/1`; if it is, pairing on the home door leaves the examples of
    what raises the protocol (Compatibility.swift, §3.2, §4.6 rule 1), and a later generation raises
    both it and the ALPN (`sill/2`).

---

## Results

Implemented 2026-09-25 on `update-notice` (from `remote-access` at cb0ec55): the protocol
(3a2470b), the host (0d93a5f), the device's goodbye rule on its own (1024830, the fix that can also
go into PR #13), the hello and the notice (19214e4), the update check (a20b00f), two commits of
review fixes (6390d4f, 93c32ae), then these docs. Not pushed.

### Defaults taken

All thirteen open questions at their defaults: a kind 23 hello; the version and protocol in every
window list, shown nowhere; the refusal names the Mac; the floor a build constant ("0"); pairing not
gated; a found update stays offered with automatic checks off; no glyph change; no App Store link
until the placeholder is replaced; `--release` needs the tag; the home refusal's flash accepted;
stacked on #13; 0–30 minutes of jitter; older development builds loop against a refusing host.

### Where the build departs from the plan, and why

- **`Accept-Language: en` on every check.** URLSession adds the Mac's preferred languages
  (`en-US,en;q=0.9` here, seen by the fake feed) unless the header is set; fixed to "en" it says
  nothing about the Mac. It also adds Host, Accept-Encoding and Connection, which say nothing either.
  §6.2's list of headers is these plus the four the plan names.
- **The pane's line, first match wins:** a check running, this run's Check Now result, *then* why
  Sill cannot check (no version; test pattern mode without a test feed), then an offer, the last
  check, never. §6.7's table put the two "cannot check" rows last, where "Not checked yet." would
  always have matched first.
- **A hello without a version is refused as "(no version)"** in the Refused line (§4.5 names only
  "Sill 1.0" and "an older Sill").
- **`UpdateChecker` imports StreamProtocol** (for SillVersion) besides Foundation and Observation;
  the swiftc checks drop that import and compile Compatibility.swift alongside, as they do for
  DeviceGate and GoodbyePolicy.
- **`-SillPrintMenuAfter <s>`** (a test argument, in release builds like the others): the status
  menu as it would open, as menu.txt draws it, and the pane's update line, in the log, so H8 sees the
  live item without a click. `MenuBuilder.entries(for:)` builds that menu and the real one.
- **`make-app.sh --release` reads `git tag --points-at HEAD`** rather than `git describe
  --exact-match`, which names one tag when HEAD carries several.
- **The hello is built on the main thread** (in `StreamClient.init`): it reads UIDevice for the
  device's name, and connections become ready, and send it, on the network queue.
- **The gate's goodbye closes with a FIN and a drain**, not `sayGoodbye`'s cancel on
  `.contentProcessed`: cancelled with what the device sent after its first message still unread,
  TCP answered with a reset (sillclient, which sends on after its hello, got the goodbye and then
  ECONNRESET 20 times in 20 in a loopback A/B), and on a real link a reset can reach the device
  before it has read the notice. Now the goodbye goes with this side's FIN, what the device still
  sends is read and dropped until it closes (at most `DeviceGate.closeWait`, 1 s), and then the
  connection is cancelled: 0 resets in 20. Only connections that were never registered close this
  way: the gate's, and (review fix) a held session the recheck refuses and the remote door's
  refusals at admission (remoteOff, busy); a registered client's goodbye (closeSessions', Quit's)
  keeps `sayGoodbye`. Over TLS the close_notify and FIN go only at the cancel: the device sees the
  end, and shows the notice, up to `closeWait` after the goodbye (1,050 ms measured, the goodbye
  itself in under 1 ms).
- **Test rig:** the bare binary ran as a copy named `SillMenuBarUN`, so its defaults domain is
  `SillMenuBarUN` and no other worktree's run shares it; the simulator runs used a simulator of this
  stage's own ("iPad update-notice", iPad Pro 13-inch (M5), iOS 27.0; the simulator's app reports
  that name, and a name that starts with "iPad" gets "your iPad" in the refusal) rather than
  40522E9E, which other sessions use, with the app built ad hoc signed (`CODE_SIGN_IDENTITY=-`) for
  the remote door's runs: unsigned, its device key cannot be made, and pairing stops without a line;
  `sillfeed.py` gained `--no-etag`, `--big`, `--redirect`,
  `--set-cookie`, `--bind`, `--all-headers` and `/__control`, and its default ETag follows its
  body, as GitHub's does.

### Verified

- **H1, builds.** A clean `swift build -c release` of the final commit (a `git archive` copy):
  only the old CaptureProbe warning. iOS Debug for the simulator and for a device (build only,
  unsigned), and Release for the simulator, each from fresh derived data: only the old
  `StreamClient` capture warning. `make-app.sh` without `--install`: `.build/Sill.app` 0.3.0 (91),
  signed with the Apple Development identity; nothing installed.
- **H3, pure checks with swiftc, each with its mutants.** The protocol (SillVersion and the
  payloads): 74 checks, 13 of 13 mutants caught; every §3.2 example, tags with and without "v",
  "0.3.0 (85)" equal to 0.3.0, "0.10" above "0.9", 1,000 random pairs against a reference, the
  description's round trip, Hello's keys, the five goodbyes byte for byte, the update goodbye, the
  window list with and without the new keys. DeviceGate: 58 checks, 14 of 14; floor "0" admits no
  hello, "", "junk" and every version, floor 1.2 refuses no hello, "0.1", "1.1.9" and "junk" and
  admits "1.2", "1.2.0", "1.10", "2"; the message for an iPad, an iPhone and another name; the
  Refused, count and hello lines, one line whatever the device sends; the shipped constant parses
  and is "0". GoodbyePolicy: 42 checks, 16 of 16; every row of §7.3, control and bidi characters,
  1,000 characters, empty after cleaning, reconnect nil, true and false, saved and unsaved.
  UpdatePolicy: 124 checks, 18 of 18; every row of §6.4 (a 304 with and without a stored release,
  drafts, prereleases, "nightly", a page off github.com, a refused redirect, 1 MB), the offer after
  an update and after a downgrade, a forged stored page never offered, the due rule with a clock in
  the future, the jitter's range, loopback-only feeds, every text.
- **H4, decode part.** cb0ec55's StreamProtocol, compiled with a check, reads the update goodbye's
  reason, a later reason, a window list with `hostVersion` and `protocol`, and maps kind 23 to
  `.unknown` with its length to skip.
- **H7, the checker alone** (swiftc: UpdatePolicy, UpdateChecker and Compatibility with a driver;
  no host) against `sillfeed.py`, which sets a cookie on every answer: 42 of 42. Every row of §6.4
  live (200 newer and the same; 304 through If-None-Match; 404 clearing the stored release; 403
  with a reset; 429; 500; a draft; a prerelease; "nightly"; not JSON; a page on ftp; a redirect
  elsewhere refused; 1.5 MB refused; a closed port, -1004 in 0.03 s; the feed held 30 s, a timeout at
  10.01 s); every request had only Host, User-Agent `Sill/0.3.0`, Accept, X-GitHub-Api-Version,
  Accept-Language `en`, Accept-Encoding, Connection and (once a release was stored) If-None-Match,
  never a Cookie or an Authorization; a 4 s period against a 404: 4 requests in 20.5 s; a closed port
  retried every scaled hour (1 s): 5 in 6 s; Check Now during an automatic check: one request,
  logged and shown as Check Now's.
- **H9, previews** from the bare binary, base and new at the same path: 69 files identical, and
  only `pane-general-{light,dark}` (the new section, fixed at "Not checked yet.") and `menu.txt`
  (the `update-available` sample appended) differ; 20 new `pane-updates-*` (ten states, light and
  dark), each looked at.
- **H10, the hard rules.** No URLSession or api.github.com in Sources/SillHost or SillHostCLI; no
  Authorization, Bearer or Sparkle in Sources; `minimumDeviceVersion = "0"`; the two TEST ONLY
  variables read only by `gateSettings(testHost:)`, which returns first on a host that advertises;
  no new `assumeIsolated` or `updateConfiguration` in Sources/SillHost (HostShutdown's one is
  cb0ec55's); no NSAlert or runModal in the app; `-SillUpdateFeed` goes through `isLocalFeed`.
- **H11, regression.** The remote-access protocol check on this StreamProtocol: 188 of 188 with its
  "kind 23 is unknown" now "kind 23 is hello, 24 unknown"; the merged DiscoveryPolicy check 187 of
  187; the remote rules checks of the remote-access build, 41 and 49. The ledger, ClientLink,
  OriginPolicy and SessionLink (a doc comment) are unchanged.
- **S1, photos** on this stage's simulator (`simctl io … screenshot`): `update` with and without
  `-SillAppStoreURL` and `notice` at 1000x710 and 500x710, and also 710x1000, 710x500, 874x402,
  402x874 and 375x667, and at accessibility-extra-large (the connect screen's type is fixed-size,
  as before, so they match): the message wraps and never truncates, the link sits under it at
  44 pt, nothing crosses the half-folded layout's middle, and the title stays put.
- **`make-app.sh --release`** refuses an untagged HEAD before building ("…HEAD is tagged
  'nothing'…", exit 2) and one tagged v0.2.0; in a scratch clone with `v0.3.0` among three tags on
  HEAD it goes on to build.
- **The gate on StreamServer alone** (compiled with swiftc from StreamServer, DeviceGate and what
  they need, with a stand-in for the coordinator's catalog: no capture, no encoder), before any
  host could run: floor 0 serves a hello'd device, an empty hello and cb0ec55's client alike, with
  "Client hello: iPad (iPad14,1), Sill 1.0, protocol 1 (127.0.0.1:P)" and "Client hello:
  127.0.0.1:P, no version" after their "Client connected"; floor 1.2 answers a 1.1 hello with
  exactly one message, the update goodbye with its four fields, and EOF 2 ms later; serves 1.2 and
  1.10; refuses cb0ec55's client (a select first), silence at 2.09 s and a 5 MB viewport header at
  once; registers only the admitted (two "Client connected", two "Client left"); one Refused line a
  minute per source, "(an older Sill)" for no hello; SILL_TEST_GOODBYE's payload as written, and a
  payload that is no Goodbye ignored with one line; SILL_TEST_MIN_DEVICE_VERSION=abc ignored, floor
  0; 20 refusals in 5 s: five at once, fifteen 2.07–2.10 s after their hello, then one Refused line
  and "Refused 19 more connections from 127.0.0.1 in the last minute: too old for this Mac (needs
  1.2 or later)." at the minute. After the FIN-and-drain fix, sillclient (which sends on after its
  hello) reads the goodbye and then EOF, and a hello followed at once by 50 pings, 20 times: the
  goodbye and EOF 20 times, 0 resets (the build before: 20 resets in 20).
- **The device against a stand-in Mac** (`fakehost.py`: it logs a connection's first message and
  answers with a kind 22; no encoder), the normal app on this stage's simulator by `-SillConnect`:
  the first message is the hello (`{"appVersion":"0.1","build":"1","protocol":1,"device":"iPad
  update-notice (iPad17,4 simulator)"}`) and nothing else came before the goodbye; "update" puts the
  Mac's words on the connect screen ("status: Update Sill on your iPad to keep using Mac mini. It
  needs version 99.0 or later."), the console says "not reconnecting", one connection in 30 s; with
  `-SillAppStoreURL` the live screen shows "Update Sill in the App Store" under it (photo); a reason
  it does not know shows its message and says "not reconnecting" with `"reconnect":false`,
  "reconnecting" with true; a kind 22 that does not decode gives "127.0.0.1:P closed the connection.
  Tap it to try again." and no reconnect; "quit" keeps its words.
- **Host runs, under the encoder rule** (each start checked Noah's Sill.log first; the runs that
  stream were watched and would have been stopped had a device connected to his Sill.app): three
  windows, 17:31–17:38, 17:49–17:58 and 17:59–18:04, on 6390d4f and then on the final build; the
  first idle baseline of cb0ec55 at 15:54.
- **H2, the CLI byte for byte** against cb0ec55, `SillHost --synthetic` idle 35 s and with one
  Desktop pick for 8 s (cb0ec55's sillclient.py for both builds): masked and sorted, `[1s]` lines
  dropped, identical, idle (6 lines) and with the client (10 lines), on 6390d4f and again on the
  final build; the `[1s]` lines' Stats keys the same (enc.out, enc.probeOK idle; cap.complete,
  cursor.shape, enc.mailboxDrop, enc.out, enc.probeOK, net.sent, net.tick streaming); the distinct
  masked `[1s]`/`[30s]` lines identical on 6390d4f and, on the final build, one more because
  cursor.shape landed in a later second (the Mac's own cursor moved: its count, not a key).
- **H4 live:** cb0ec55's `SillHost --synthetic` with `sillclient.py --hello=1.0,1`: served, the
  catalog as always (`2 16 4×119 5 2`), nothing new printed (it skips kind 23).
- **H5** (floor 0, the real CLI): "Client hello: iPad (iPad14,1), Sill 1.0, protocol 1
  (127.0.0.1:P)" and "Client hello: 127.0.0.1:P, no version", both served with the catalog in its
  usual order, no refusal; the stats line names the device.
- **H6 on the real CLI** (`SILL_TEST_MIN_DEVICE_VERSION=1.2`), passed on the final build: (a) one
  message, kind 22 `{"minimumVersion":"1.2","reason":"update","message":"Update Sill on your iPad to
  keep using Noah’s MacBook Pro. It needs version 1.2 or later.","reconnect":false}`, EOF 2 ms later,
  one Refused line, no Client connected/Catalog/left for it, and sillclient (which sends on) reads
  the goodbye and a clean EOF; (b) 1.2 and 1.10 served; (c) cb0ec55's sillclient refused as "an older
  Sill"; (d) silence refused at 2.075 s; (e) 20 in 5 s: five at once, fifteen at 2.03–2.10 s, one
  Refused line and "Refused 19 more connections from 127.0.0.1 in the last minute…"; (f) the remote
  door (`--remote`, SILL_TEST_REMOTE_DIR): paired, a `--tls --hello=1.1` session gets the update
  goodbye inside TLS and no "Remote client connected", a 1.2 one is served; (g) SILL_TEST_GOODBYE's
  payload as written, a non-Goodbye payload ignored with its line; (h) `abc` ignored, floor 0.
  cb0ec55's client is served at floor 0 (nothing new printed) and refused at floor 0.1.
- **H8, Sill.app end to end** (on 6390d4f; the bare SillMenuBar as `SillMenuBarUN --synthetic`,
  against `sillfeed.py`): run 1 (`-SillUpdateFeed`, `-SillUpdateVersion 0.3.0`, `-SillUpdateNow 1`): one
  request (`User-Agent 'Sill/0.3.0'`, no Cookie, no If-None-Match), "Update check: Sill 0.4 is
  available (this is 0.3.0): https://github.com/Saffsanity/sill/releases/tag/v0.4.0", the live menu
  (`-SillPrintMenuAfter`) with "Sill 0.4 Is Available…  — You have 0.3; opens its download page"
  right after the card, the pane's line "Sill 0.4 is available.", the four keys in the defaults,
  exit 0; run 2 (no Check Now, 40 s): "Update: Sill 0.4 is available (found by an earlier check).",
  the item, no request; run 3 (`-SillUpdateInterval 4 -SillSetAfter '2 updateCheck=0'`): "Update
  check: automatic checks off.", saved, no request; run 4 (Check Now in test pattern mode without a
  feed): "SillUpdateNow ignored: …", no request, and at 35 s its only socket the listener's; run 5
  (the feed at v0.3.0): "Update check: up to date (this is 0.3.0; the latest release is v0.3.0).",
  no item, the pane "Sill is up to date."; run 6: a 200 stores the ETag, the next check sends it and
  gets 304, and still offers 0.4; run 7 (a 404, automatic at a 6 s period): one request, one "Update
  check failed: GitHub has no release of Sill (HTTP 404)." line, no item, the pane "Last checked …",
  the stored release cleared.
- **The simulator against real hosts** (the normal app, `-SillConnect`): S2 (floor 99, the final
  build): "status: Update Sill on your iPad to keep using Noah’s MacBook Pro. It needs version 99.0
  or later.", the host's one line "Refused iPad update-notice (iPad17,4 simulator) (Sill 0.1): needs
  99.0 or later.", no Client connected, no second connection in 60 s, "not reconnecting" (photo
  `s2-live-refusal`); S3 (on 6390d4f; floor 0.1, and 1.2 with `-SillHelloVersion 1.2`): admitted with one
  "Client hello: iPad update-notice (iPad17,4 simulator), Sill 0.1 (1), protocol 1 (…)" (1.2 with
  the argument), streamed, "host: no version, protocol 1"; S4 at home (SILL_TEST_GOODBYE,
  `pairingRequired`): the message as the status line, "not reconnecting" with false, "reconnecting"
  with true; S6 (cb0ec55's host): streamed as always, no hello line on the host, "host: no version (a
  Mac from before 2026-09-25)". Through the remote door (`--remote`, the app ad hoc signed so it has
  a keychain, paired at launch with `-SillPairURL`): S4 with `"reconnect":false`, paired, the
  after-pairing dial ready "by address", the Mac's words as the status line, "not reconnecting", one
  session connection in 60 s, never "isn’t accepting remote connections"; with true, redialled
  automatically ("Reconnecting to … remotely…", then the words again), 12 session connections in the
  minute (the host's count line: 11 more; about 5 s apart, the redial's 3 s and, from the sixth, the
  gate's 2 s); S5 (floor 99): "Update Sill on your iPad to keep using Noah’s MacBook Pro. It needs
  version 99.0 or later." with the saved Mac's Remote row kept, no dial failure, one session
  connection in 120 s, never "Remote client connected" (photo `s5-remote-refusal`).

### Review fixes (after a85118d)

A review of the branch (wire and app lenses, each finding verified by a second pass) found five
defects, wire rules out of date in HostSettings.swift, and a conflict with the home-pairing plan.
Fixed in dc8b3ec (iOS), 58d957a (host) and
1378385 (Sill.app), then these docs; not pushed. Every host run checked Noah's Sill.log first (his
Sill.app had no device from 19:47 to the end), and the runs that stream were guarded.

- **The hello first on a home dial** (dc8b3ec). `connect(to:)` made its connection the session's
  before `.ready` and sent the hello only at `.ready`, so what the session sent through the link in
  between went first: a coast's end (the momentum's `onEnd` as the stream screen goes, with the
  reconnect already dialling) or the pointer's viewport re-send 200 ms after a tear-down, which
  never cleared `lastViewport`. Under a raised floor the gate would refuse an up-to-date device as
  "an older Sill", and it would stop reconnecting. The hello is now written to the connection as it
  is made (Network.framework sends what was sent before `.ready` in order once it is), and a
  tear-down forgets the viewport and a pending re-send (`forgetViewport`). A stand-in with the real
  SessionLink.swift, connect(to:)'s order and a listener that logs kinds: the hello first in 5 of 5
  each for a send right after start, after a hop to the network queue, and 200 ms into a Bonjour
  dial still resolving (a `_silltest._tcp` service registered 0.7 s in; ready at 1.65 s); the old
  order put the hello second in all three (5, 5 and 1 runs); a source check (the hello before
  `connection = c` and `start`, none at `.ready`). The simulator against fakehost.py: the stage's
  thirteen checks, and "hello: sent" now with "Connecting…"; S2 and S3 against real hosts pass.
- **A session the gate held is judged again** (58d957a). While the gate reads (up to 2 s) a session
  is neither pending nor a client: `closeSessions` (Remove, Remote Access off, internet access off)
  and the session count missed it, and admitting it read nothing again; at home, Direct Wireless
  off missed a connection on peer-to-peer Wi-Fi the same way. `serve` takes a `recheck`, answered
  by `RemoteServer.stillAdmits` from the trust snapshot as the gate admits (RemoteAccess changes the
  snapshot before it queues `closeSessions`, so an admission before the change is a client when
  that runs, and one after is refused); the home door disconnects a connection its peer-to-peer
  listener accepted once the replacement without peer-to-peer is up. On a rig of StreamServer and
  RemoteAccess alone (no coordinator, no encoder; the floor 1.2): a paired session holding its hello
  through Remove, Remote Access off and internet access off gets `removed`, `remoteOff` and
  `internetOff`, with "Removed …: disconnecting it at …", "Remote access off: disconnecting …" and
  "Internet access off: disconnecting …" (a85118d served all three); 12 sessions held, then 12 hellos:
  8 served and 4 `busy` (a85118d: 12); the controls (a hello at once, then the change) and floor 0 as
  before. The real CLI (`--direct-wireless`, the en0 stand-in, a loopback client turning it off
  through kind 17, the held client's hello 1.8 s in): "Direct wireless off: disconnecting clientB
  at fe80::…%en0…" and no "Client connected" for it (a85118d registered it and sent it the catalog
  after the off); at floor 0 it is registered and then disconnected as always.
- **The remote door's refusals close with a FIN** (58d957a). `admitSession`'s `remoteOff` and `busy`
  went through `sayGoodbye`, which cancels once the goodbye is processed: a device of this build
  sends its hello as soon as it is ready, and a cancel with it unread answered with a reset. They
  now use `closeWithGoodbye` (internal now). On the rig with the door's own TLS, a client sending
  its hello 0.5 ms after its handshake: `remoteOff` (Remote Access off, a pairing window keeping the
  door up) 30 of 30 goodbye, close_notify and FIN (a85118d: 8 of 30 ended in a reset), `busy` (8
  sessions held) 30 of 30 (a85118d: 21 of 30 resets). Over TLS the close_notify and FIN go only at
  the cancel: the goodbye arrives in under 1 ms, the end at 1,050 ms, so the device shows the notice
  about a second later than it did (the gate's update notice through the remote door already did).
- **Settings › General follows a later check** (1378385). `result` (this run's Check Now) outranked
  the offer and the last check until Sill.app quit, and Sill.app runs from login for weeks. An
  automatic check that GitHub answers now clears it; one with no answer leaves it; VoiceOver still
  hears Check Now's results only (`resultCount`). §6.7's row says so. The checker alone against
  sillfeed.py: Check Now up to date, HTTP 500 or offline, then an automatic answer offering 0.4; 0.4
  then withdrawn (404); 0.4 then 0.5; up to date then a timeout (kept): 12 of 12, where a85118d's
  checker failed 5; the stage's H7, 42 of 42; UpdatePolicy 124 of 124.
- **The switch works from launch** (1378385). `onUpdateCheckChange` was set only once the host had
  started, so a change before that (Settings… is in the menu from launch; `-SillSetAfter` counts
  from launch) was saved but not applied. It is set in `AppModel.init`; `setAutomatic` before
  `start()` only records the value. The bare app (`--synthetic`, a loopback feed,
  `-SillUpdateInterval 4`): `-SillSetAfter '0 updateCheck=0'` sends no request in 12 s (a85118d:
  2), `'0 updateCheck=1'` from a saved off asks (a85118d: none in 12 s), `'2 updateCheck=0'` none (as H8
  run 3), and with Check Now at launch up to date and 0.4 published 3 s later the pane and the
  menu offer 0.4 at 9 s (a85118d: "Sill is up to date."); H8's seven runs pass.
- **Docs.** HostSettings.swift's rules: settings support is known by kind 16, never by a version;
  kind numbers are never reused (the rule CLAUDE.md's floor credits it with); Compatibility.swift's
  three rules. StreamMessage.swift's kind 17 note. Open question 14 and CLAUDE.md's floor: home
  pairing before or after 1.0 (a review finding with no fix here: Noah's call).
- **Gates rerun:** `swift build -c release` and iOS Debug and Release for the simulator and Debug for
  a device, only the known warnings; H2, the CLI's stdout idle 35 s and with a Desktop pick, masked
  and sorted, equal to cb0ec55's (the `[1s]` keys lack `enc.mailboxDrop` only because this run's
  encoder kept up, 60 of 60 fps against the base run's ~37 with drops); H4–H6 on the CLI, all 30
  checks; H9, the previews byte for byte the build before's when rendered from the same path (against
  a85118d's own render only General's "Running from" path differs).

### Not verified here

- **The host gates after each step:** the runs that start a host waited on the encoder rule (Noah's
  iPad was connected to his Sill.app for most of the afternoon), so they ran on the build after the
  update check (6390d4f) and on the final one, not after steps 2–4; what needs no host (the pure
  checks, H7, the previews, the gate on StreamServer alone, the device against a stand-in Mac) ran as
  each step landed.
- **S7** (tapping the link opens the App Store page): not driven; the simulator control tool's first
  use asks the person for permission. The link's address is SillLinks'; the photos show it.
- **The plan's V1–V7** are Noah's (CLAUDE.md, Untested).

### For the app-store-readiness branch (merged since: see "Merged with main" below)

- **site/privacy.html**, the plan's §6.10 line as written, with one addition after "(for example
  “Sill/1.0”)": "and a fixed “en” as its language".
- **docs/release-checklist.md**, in order: bump CFBundleShortVersionString in Packaging/Info.plist
  and commit; `git tag v‹version›`; `make-app.sh --release` (through `release.sh`); publish the
  GitHub release for that tag, with the zip (not a draft, not a prerelease); within a day every
  older Sill.app offers it. And before the first upload: replace APP_STORE_URL_PLACEHOLDER in
  iOSClient/SillLinks.swift with https://apps.apple.com/app/id‹Apple ID›.
- **SillLinks.swift** exists on both branches: merging them is an add/add conflict to resolve by
  keeping both enums' members in one file (and one set of pbxproj entries).

### Merged with main (2026-09-25)

Main at 1f3072a (PRs #11 encoder recovery, #12 follow-best-path, #14 App Store readiness, #15 the
public README) merged into this branch in 104a9bd, not rebased, with two fix-ups after it.

**Where they met, and how:**
- **The hello on every connection, #12's included.** `StreamClient` makes connections in two places
  and adopts one more: `connect(to:)` (a tap, a reconnect, a wired dial and its fallback,
  `-SillConnect`), `startMove` (the move from AWDL, and #12's to the cable, to Wi-Fi and a rescue's
  reconnect, with each one's fallback), and `adopt` (a remote winner). `connect(to:)` and `adopt`
  already wrote the hello before anything else. `startMove` sent it at `.ready`, where main's side
  now guards a connection that is ready again after waiting; its hello moved to where the
  connection is made, as `connect(to:)` has it, so no path can put anything ahead of it. Nothing of
  the session goes out on a move's connection before the hand-over either way: SessionLink's fences
  and #12's hold release what waited onto it only at `finishMove`.
- **Main's `rescue`** read `goodbyeReason`, which this branch replaced with the whole `Goodbye`: it
  reads `goodbye`, so a session the Mac said goodbye on (any reason, a notice included) ends with
  that goodbye's words instead of being carried on.
- **`SillLinks.swift`**, added on both sides: one enum with main's site, download, support, privacy
  and siteName and this branch's `appStoreText` and `appStore`; the project file keeps main's entries
  (A201/F201) and drops this branch's (A01F/F01F).
- **README.md** is main's public front page; this branch's Updates paragraph, tag rule and hello
  paragraph went to docs/DEVELOPMENT.md (Sill.app, Releasing, The iOS app), sillfeed.py to its
  Layout.
- **docs/pointer-visibility-plan.md** held kinds 23–25 for the Mac menu bar sketch: 23 is the hello,
  so the sketch has 24, 25 and 27, and the pointer keeps 26.
- **Fix-up 184d902, the release.** Main's `release.sh` runs `make-app.sh --release`, which this
  branch made refuse an untagged HEAD, so the checklist's rehearsal (`release.sh --dry-run`, on any
  commit) was refused. A dry run now passes `SILL_RELEASE_DRY_RUN=1` and is only warned; a real run
  names the missing tag in its preflight, before building. The checklist gains the tag and its push
  (part 2) and the App Store address (Placeholders, part 1 §4).
- **Fix-up 05d9d3a, the site.** §6.10's line, as the Results adjusted it, is the privacy policy's
  "Update check" section, in the page's voice ("the developer") and with "Mac" never possessive, as
  PR #14's pages keep it; the short version and the device-to-Mac list name the check and the
  version the device sends; the download page says Sill tells you about a new version.

**Verified on the merge** (scratch: `…/scratchpad/integrate-update/`):
- Builds from a `git archive` of 104a9bd: `swift build -c release`, only the CaptureProbe warning;
  iOS Debug and Release for the simulator and Debug for a device (`CODE_SIGNING_ALLOWED=NO`), each
  from fresh derived data, only the `StreamClient` capture warning; `make-app.sh` without
  `--install`: 0.3.0 (157), Apple Development, sdk 27.0.
- This branch's pure checks against the merged sources: the protocol 74 (13 of 13 mutants),
  DeviceGate 58 (14 of 14), GoodbyePolicy 42 (16 of 16), UpdatePolicy 124 (18 of 18).
- Main's: the discovery policy 286 with 70 of 70 mutants, and main's own 187 with the 20 older
  mutants; the fence in its 12 modes with 16 of 16; the remote rules (rf2) 64 with 35 of 35; the
  ledger 90 with 5,000 random runs and 3 of 3; the remote protocol 188 ("kind 23 is hello, 24
  unknown").
- The hello first: the review's check against the merged SessionLink (5 of 5 in each case, its
  mutant caught), and a new one for #12's moves (`checks/movehello`): a hold and adopt, and a
  fenced hand-over released by its timeout, each with the hello written as the move's connection is
  made and at `.ready` (both first, 5 of 5, the three held inputs right after it), and a move
  connection with no hello caught 5 of 5; the source: two `NWConnection`s made (connect, startMove),
  three hellos (those and adopt), none in a `.ready` case.
- The checker alone against sillfeed.py: 42, and the stale-result check's 11; the bare app
  (`SillMenuBarIU`, deleted after) H8 runs 1 and 2: the found line, the live menu's item, the pane,
  one request with §6.2's headers, then the item at launch with no request.
- Previews from the bundle (a copy with its own bundle ID, both at one path) against origin/main's:
  77 files identical; `pane-general-{light,dark}` (the update section), menu.txt (the
  `update-available` sample) and the 20 `pane-updates-*` differ, as they should.
- The CLI's stdout against origin/main's build (`SillHost --synthetic`, idle 35 s and with a
  Desktop pick, origin/main's sillclient.py for both), masked and sorted: identical (6 and 10
  lines), the `[1s]` keys the same.
- The gate on the merged CLI: H5, H6 a–d, g, h, the remote door (f) and the slowdown with its count
  line (e) as in the Results; origin/main's sillclient.py refused at floor 0.1 and served at 0;
  origin/main's host serving a hello'd client with nothing new printed.
- A simulator of this stage's own ("iPad integrate-update", deleted after), the Debug build:
  floor 99, the notice as the status line, "not reconnecting", one Refused line and no second
  connection in 60 s; floor 0.1, admitted with one Client hello line, streaming; floor 0.1 with
  `-SillMoveTest 1`, the move's own connection admitted with its hello, "the session moved to the
  network", the direct one left; the `update` and `notice` cases at 1000x710, 500x710, 710x500 and
  710x1000 with main's footer below: nothing overlaps.
- Every host run checked Noah's Sill.log first (idle, nothing streamed in the last minute) and
  every 10 s while it ran, one host at a time, each under 90 s.
