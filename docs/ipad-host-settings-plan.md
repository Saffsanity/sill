# iPad host settings: final plan

A device (iPad, iPhone, the Duo) changes the Mac's streaming settings the way the Mac's Sill menu
does: Quality (bitrate), Resolution (capture scale), Frame Rate limit, Prioritize Speed and
Virtual Display. Judged 2026-09-23 against `menu-bar-app` at 59fc510, with the working tree read
as well. Message kinds 16 and 17 are still free there. Nothing in the repo was changed by this
workflow.

The concurrent oddities work, uncommitted when this was written, modifies these files:

- `VirtualStage.swift` and `WindowSizer.swift`;
- `StreamServer.swift` (stats-line maxima);
- `Viewport.swift` (optional `ClientStats` maxima);
- `StreamClient.swift` (`linkStats` replaces `fps`, `frameAgeMs` and `rttMs`);
- `DiagnosticsHUD.swift` and `HEVCDisplayView.swift`.

None of it conflicts with this plan's protocol or host seam. The plan notes the two places where
it matters: the baseline must be taken after it lands, and the settings timeout reads its rtt.

This file is self-contained: an implementer should not need d0, d1 or d2.

---

## Decision

**Winner: d0 (protocol-minimal)**, used as the backbone for the wire protocol, the host seam and
the device ledger. Most of the UI comes from d1 (UI-first). Pinned Disconnect, connect-by-address
for tests, RTT-scaled timeouts and the remote-access groundwork come from d2 (operational).

### Scores (0–10)

| Criterion | d0 protocol-minimal | d1 UI-first | d2 operational |
|---|---|---|---|
| Correctness under concurrency (two clients, mid-switch, reconnect) | 9 | 8 | 7 |
| CLI parity and hard rules | 9 | 8 | 8 |
| Native iOS feel across layouts | 7 | 9 | 7 |
| Implementation risk (10 = lowest) | 8 | 7 | 5 |
| Readiness for remote access | 6 | 6 | 9 |
| **Average** | **7.8** | **7.6** | **7.2** |

The four check programs all pass when re-run: d0 (5,000 random runs), d1 (20 checks plus 5,000
runs), d2 (21 checks) and the sketch (8 checks).

### Why d0 wins

The protocol and the host seam are the parts that are hard to change once devices exist. d0 gets
them most right with the least code:

- **The state devices see is a pure function** of two values: the host's target
  (`pendingConfig ?? config`) and the `HostStatus` snapshot. A grep of every writer confirms that
  each capability flag (`useSoftwareEncoder`, `apiProblem`, `stage.disabledReason`) is mirrored
  into the snapshot where it is set. So two publish triggers cover everything: the target
  changing, and the snapshot changing. Nothing can be missed, and nothing stale can stick.
  - d1's `restarting` flag and d2's `applying` flag both live outside the snapshot, so each needs
    hand-placed publishes. d2's can stick at true: `adopt` returns early when a change made
    mid-switch was reverted, so its trailing publish never runs.
- **The handler never awaits.** Every answer goes back in request order, before any restart.
- **`HostSettings.config` and the host's target are equal at every main-actor turn**, because
  AppModel's `onChange` becomes synchronous. A menu click and a device change can never undo each
  other.
- **Its model check is the strongest:** 50,000 runs, plus mutation runs showing that each rejected
  alternative fails.

### Grafts from d1 (UI-first)

- **The panel's look and behaviour.** No dim over the stream: a clear tap catcher closes the panel
  and never clicks the Mac, so a change can be judged on the picture. Also the open and close
  motion (a fade only under Reduce Motion), Dynamic Type rows that stack when they don't fit,
  VoiceOver, the refusal haptic, and the per-layout geometry.
- **Keyboard handoff.** Opening the panel resigns the overlay's first responder, which hides the
  software keyboard and stops hardware-key forwarding. Closing it restores whatever was there. Esc
  presses Done through `.keyboardShortcut(.cancelAction)`.
  - Verified in the code: `InputOverlayView` forwards keys only while it is first responder
    (InputOverlay.swift:338-398).
  - d0's `interceptEscape` contradicted its own keyboard hiding, so it is dropped.
- **The narrow queued pick.** A pick is queued only when it arrives during a restart of the active
  source.
  - d0's and d2's broader versions also queue the device's automatic Desktop request.
    StreamClient.swift:432-440 sends that request 2 s after a watched window closes, while the
    device still believes nothing streams. If the user picks another window in those 2 s, the
    broader rule lets the Desktop override the pick after it has started.
- **"Turn it off and on to try again"** in the note for a virtual display that is off for the
  session. That is true: `adopt` calls `enableVirtualDisplay`, which clears the session disable.
- **The `stream` readout** (size, fps, Mbps, whether it is on the virtual display), taken from the
  snapshot, so d0's pure-function rule still holds. It confirms that a change took effect, and it
  shows what actually runs when the software encoder caps the target.
- **d1's prototype** (`scratchpad/ipad-settings/d1/d1-prototype.patch`) is a reference for the
  panel and bar code. Its host half follows d1's rules (`restarting`, permissions, refresh,
  publishing at select), so don't apply it as is.

### Grafts from d2 (operational)

- **A pinned header and a pinned Disconnect foot**, with only the middle scrolling. At 500×710 the
  panel gets 259 pt. Disconnect replaces a one-tap bar button, so it must never fall below the fold.
- **DEBUG `-SillConnect host:port`.** The synthetic hosts deliberately stay off Bonjour, so this is
  the only way for the simulator to reach `SillHost --synthetic` and the bare
  `SillMenuBar --synthetic`. With it, the whole feature can be tested end to end without any
  permission. It is also the seed of step 3's "add a Mac by address" (docs/BRIEF.md: "Manual 'add
  by address' as fallback").
- **Timeout of max(4 s, 4 × RTT).** It changes nothing on the LAN and matters on a remote link.
- **Test tooling and checks:** the `sillclient.py` flags `--stats` and `--raw17`, the idle-dedupe
  check, and the step-3 security prerequisites (§9).
- **The CLI stays session-only**, for d2's reason: it is the stateless measuring tool, and
  baselines must not depend on hidden state.

### Rejected from each

- **d0:**
  - the 0.3 dim;
  - Disconnect as a scrolling last row;
  - `interceptEscape`;
  - the broad queued pick.
- **d1:**
  - the `restarting` flag, with its publishes at select's start and end and the guard that
    suppresses status changes mid-switch;
  - the refresh sent when the panel opens;
  - disabling the device's virtual display switch when a permission is missing. The Mac's own
    toggle never does that (SettingsPanes.swift:191; StatusItemController.swift:58-59).
- **d2:**
  - host-sent `choices`, `host.kind`/`version`, `features`, `permissions`, `changedBy` with
    "Changed on the Mac" captions, `refused` maps, `applying`, `editable`/`readOnlyReason`;
  - device `receivedMbps` and `route`;
  - live checkmarks in the open Mac menu.

  Each is either not needed for this feature ("don't add features the current milestone doesn't
  need") or can arrive later as an optional field without breaking v1 devices (§1.5).

---

## Final plan

### 0. Ground rules for the implementing session

- **Branch and plan.**
  - Branch `ipad-host-settings` from `menu-bar-app` after the oddities fixes have landed.
  - Copy this file to `docs/ipad-settings-plan.md` (/private/tmp is wiped at boot).
  - Open the PR against `menu-bar-app`.
  - Per Noah, implementation and review agents run on Opus 5.5.
- **Hard rules (repeat them in every review):**
  1. Never `MainActor.assumeIsolated` in core (`Sources/SillHost`). Hop with `Task { @MainActor in … }`.
  2. Never `SCStream.updateConfiguration`. A settings change restarts the pipeline through `select`
     (a new SCStream), which is the existing path.
  3. The CLI's stdout stays byte-for-byte identical on the default path. New lines appear only
     when a device sends kind 17. Nothing new prints on connect, on publish or on the state sent in
     `sendCatalog`. No new `Stats.bump` key runs unless kind 17 arrives.
  4. Swift and Apple frameworks only; no third-party code; zero operating cost.
  5. Host code stays in `SillHostCore` with `package` access, never `public`.
  6. Errors show inline, never in alerts (Mac rule, and the device follows it).
- **Test safety:**
  - Never touch `/Applications/Sill.app` or the `me.saffer.sill.mac` defaults domain.
  - Use the bare `.build/release/SillMenuBar --synthetic` (defaults domain `SillMenuBar`, deleted
    afterwards) and `.build/release/SillHost --synthetic`. Neither advertises on Bonjour.
  - Never run a non-synthetic host: it would raise Terminal's Screen Recording prompt. Those
    checks are Noah's.

### 1. Wire protocol

#### 1.1 Two new kinds (`Sources/StreamProtocol/StreamMessage.swift`)

Insert after `windowCommand = 15`, before `unknown = 255`. First re-check that 16 and 17 are free.

```swift
case hostSettings = 16    // host → client: JSON HostSettingsState — the settings as the Mac's menu shows them and what
                          // this host allows; on connect (right after the window list), whenever it changes, and with
                          // `answering` set as the reply to one device's changeSettings
case changeSettings = 17  // client → host: JSON HostSettingsChange — only the fields one control changed, plus a token
```

There is no ack kind, no "send me the state" kind and no version handshake. The answer to a change
is a `hostSettings` sent to that device alone.

#### 1.2 Types (new `Sources/StreamProtocol/HostSettings.swift`, all `public`, with explicit public inits)

```swift
/// The five streaming settings as the Mac's menu and Settings show them. Plain values, never enums:
/// an unknown case would fail an older reader's whole decode.
public struct StreamSettings: Codable, Hashable, Sendable {
    public var maxFPS: Int            // frame rate limit: a ceiling; each device still gets its own panel's rate below it
    public var bitrate: Int           // bits per second per 60 fps
    public var captureScale: Double   // 2 = Retina, 1 = Standard
    public var prioritizeSpeed: Bool
    public var virtualDisplay: Bool
}

/// The pipeline as it was last started: what actually runs after the devices' rates and the
/// software encoder's caps. Read-only on the device.
public struct RunningStream: Codable, Hashable, Sendable {
    public var width: Int             // encoded pixels
    public var height: Int
    public var fps: Int
    public var mbps: Int              // the encoder's target (per-60 bitrate × fps / 60), whole Mbps
    public var onVirtualDisplay: Bool
}

/// Host → device (.hostSettings).
public struct HostSettingsState: Codable, Hashable, Sendable {
    public var settings: StreamSettings        // the TARGET: a change still waiting for its restart included
    public var persistent: Bool                // Sill.app saves changes; SillHost keeps them until it quits
    public var virtualDisplayAvailable: Bool   // false: this host cannot run it at all (SillHost without --virtual-display)
    public var virtualDisplayNote: String?     // why it is unavailable or not working; nil when nothing is wrong
    public var softwareEncoder: Bool           // streams run at up to 60 fps at Standard until the Mac restarts
    public var stream: RunningStream?          // nil while nothing streams
    public var answering: Int?                 // only in the reply to one device: the token of the change it answers
}

/// Device → host (.changeSettings). A nil field is left as it is.
public struct HostSettingsChange: Codable, Hashable, Sendable {
    public var token: Int?                     // chosen by the device, strictly increasing for its process, never reset
    public var maxFPS: Int?
    public var bitrate: Int?
    public var captureScale: Double?
    public var prioritizeSpeed: Bool?
    public var virtualDisplay: Bool?
    public init(token: Int? = nil, maxFPS: Int? = nil, bitrate: Int? = nil, captureScale: Double? = nil,
                prioritizeSpeed: Bool? = nil, virtualDisplay: Bool? = nil)
    public var isEmpty: Bool                   // all five setting fields nil
    public func applied(to s: StreamSettings) -> StreamSettings   // the one merge, used by both sides
}

/// What a device may pick: exactly the Mac menu's choices. The host checks against these.
public enum SettingsChoices {
    public static let maxFPS = [60, 120]
    public static let captureScale: [Double] = [2, 1]
    public static var bitrate: [Int] { QualityPreset.allCases.map(\.rawValue) }
}

/// Moved unchanged from Sources/SillMenuBar/HostSettings.swift:83-106 and made public, so the Mac
/// and the device name the presets the same way.
public enum QualityPreset: Int, CaseIterable, Identifiable, Sendable {
    case efficient = 8_000_000, balanced = 15_000_000, high = 25_000_000, maximum = 40_000_000
    public var id: Int { rawValue }
    public var name: String                     // "Efficient" / "Balanced" / "High" / "Maximum"
    public var title: String                    // "Balanced — 15 Mbps"
    public static func title(forBitrate bitrate: Int) -> String   // preset title, else "Custom — 12 Mbps"
    /// "15", or "8.5". The same text as HostConfig.mbps, which StreamProtocol cannot see.
    public static func mbps(_ bitsPerSecond: Int) -> String
}
```

#### 1.3 On the wire

The synthesized encoder leaves nil optionals out. Key order is not guaranteed, so readers must
never depend on it. A state is about 300 bytes, and nothing is sent while nothing changes.

```
change   {"token":7,"bitrate":25000000}
state    {"settings":{"maxFPS":120,"bitrate":15000000,"captureScale":2,"prioritizeSpeed":false,"virtualDisplay":false},
          "persistent":true,"virtualDisplayAvailable":true,"softwareEncoder":false,
          "stream":{"width":3024,"height":1898,"fps":60,"mbps":15,"onVirtualDisplay":false}}
answer   the same state plus "answering":7
CLI      … "persistent":false,"virtualDisplayAvailable":false,
         "virtualDisplayNote":"Start SillHost with --virtual-display to use it." …
```

Field meanings:

- `settings` is the **target**, not the running pipeline. A change still waiting for its restart
  is already reported, because the Mac menu checks it too.
- `stream` is what runs. With the software encoder, `settings` can say 120 fps and Retina while
  `stream` says 60 fps at 1× pixels.
- Change fields are **absolute** ("set the frame rate limit to 60", never "toggle"). Sending the
  same change twice therefore gives the same result, and the second is answered as a no-op.

#### 1.4 What the host accepts from a device

| Field | Accepted | Otherwise |
|---|---|---|
| `maxFPS` | 60, 120 | refused |
| `bitrate` | 8, 15, 25 or 40 Mbps (`QualityPreset`) | refused |
| `captureScale` | 2, 1 (Python's integer `1` decodes as 1.0) | refused |
| `prioritizeSpeed` | either | — |
| `virtualDisplay` | `false` always; `true` only where `virtualDisplayAvailable` | refused |

- **Refusal is per field.** The valid fields of the same change still apply. The refused fields
  are named in one log line, and the answer carries the host's values, so the device's control
  goes back.
- **The Mac can hold values outside this list** (from `defaults write`, launch arguments, or
  `validated()`'s wider 24–120 fps and 1–100 Mbps). The state reports them as they are. The device
  shows them read-only ("Custom — 12 Mbps") and can replace them with a menu choice, but can never
  set one itself.
- **There is no generic "write a default" message.** A device can move these five knobs, to these
  values, and nothing else.

#### 1.5 Compatibility and evolution

| | Older device (b67f87d or later) | New device |
|---|---|---|
| **Older host** | As today. | No kind 16 ever arrives. The panel shows "Update Sill on ‹Mac› to change these from here", and nothing is sent. |
| **New host** | Skips kind 16: `parseHeader` maps it to `.unknown` (StreamMessage.swift:61-70), then `default: break` (StreamClient.swift:465). Never sends 17. | Full feature. |

Rules for every later change:

- A device knows the host supports settings when a kind 16 arrives **on this connection**. There
  is no version number.
- **Fields added later must be optional.** A missing required key fails the whole decode, and the
  device would then treat the Mac as an older one.
- **Never remove, rename or retype a field.** Swift property names are the JSON keys.
- **No enums in these payloads.** `JSONDecoder` ignores unknown keys in both directions, so either
  side can add fields.
- A newer device's extra change fields are ignored by an older host. Its answer shows them
  unchanged, and the control goes back: correct feedback, with no negotiation.

### 2. Host

#### 2.1 Seam and threading

- **Inbound.** `StreamServer` needs no change. Its receive loop hands every kind except ping and
  clientStats to `onMessage` on the `sill.net` queue (StreamServer.swift:198-216). The coordinator
  hops each message to the main actor in its own Task (StreamCoordinator.swift:171-173). Those
  Tasks start in arrival order; the input path already relies on that.
- **The new case.** It sits in `handle(_:from:)` (:404) beside `.windowCommand` (:411) and
  `.viewport` (:442), and **contains no `await`**. So its answer leaves in request order, per
  device and across devices, and before any restart.
- **Outbound.** `server.broadcast` and `server.send(_:to:)` are thread-safe. They queue on
  `sill.net` and keep per-connection order. Every settings message is composed on the main actor,
  so each device receives states in the order the host composed them.
- **Tasks.** The only new one is `Task { @MainActor in await self.applyPending() }` inside
  `setTarget`, which is safe under the CLI's `dispatchMain`.

#### 2.2 `Sources/SillHost/HostStatus.swift`

- Add `@ObservationIgnored var onChange: (@MainActor () -> Void)?` to `HostStatus`.
- In `update`, call it only when the snapshot really changed:
  `if next != snapshot { snapshot = next; onChange?() }`.
- `onChange` must never call `update` itself.

#### 2.3 New `Sources/SillHost/DeviceSettings.swift`

```swift
import CoreGraphics
import StreamProtocol

extension HostConfig {
    /// As a device sees them.
    var streamSettings: StreamSettings {
        StreamSettings(maxFPS: maxFPS, bitrate: bitrate, captureScale: Double(captureScale),
                       prioritizeSpeed: prioritizeSpeed, virtualDisplay: virtualDisplay)
    }
    /// This config with a device's change laid over it; nil fields keep their value. `package`: the app's hook uses it.
    package func applying(_ change: HostSettingsChange) -> HostConfig {
        var c = self
        if let v = change.maxFPS { c.maxFPS = v }
        if let v = change.bitrate { c.bitrate = v }
        if let v = change.captureScale { c.captureScale = CGFloat(v) }
        if let v = change.prioritizeSpeed { c.prioritizeSpeed = v }
        if let v = change.virtualDisplay { c.virtualDisplay = v }
        return c
    }
}

enum DeviceSettings {
    /// §1.4: exactly the Mac menu's choices. Refused fields are named for the log; the rest still applies.
    static func accepted(_ c: HostSettingsChange, virtualDisplayAvailable: Bool) -> (HostSettingsChange, refused: [String]) {
        var ok = HostSettingsChange(prioritizeSpeed: c.prioritizeSpeed)
        var refused: [String] = []
        if let v = c.maxFPS { if SettingsChoices.maxFPS.contains(v) { ok.maxFPS = v } else { refused.append("frame rate limit \(v)") } }
        if let v = c.bitrate { if SettingsChoices.bitrate.contains(v) { ok.bitrate = v } else { refused.append("bitrate \(v)") } }
        if let v = c.captureScale { if SettingsChoices.captureScale.contains(v) { ok.captureScale = v } else { refused.append("capture scale \(v)") } }
        if let v = c.virtualDisplay {
            if !v || virtualDisplayAvailable { ok.virtualDisplay = v } else { refused.append("virtual display (needs SillHost --virtual-display)") }
        }
        return (ok, refused)
    }
}

extension HostStatusSnapshot.Stream {
    var wire: RunningStream { RunningStream(width: width, height: height, fps: fps, mbps: mbps, onVirtualDisplay: onVirtualDisplay) }
}
```

#### 2.4 `Sources/SillHost/StreamCoordinator.swift` (line numbers at 59fc510; re-read first)

1. **Replace `apply(_:) async` (:303-316) with a synchronous `setTarget`.** AppModel is its only
   caller (AppModel.swift:58). `applyPending` (:318), `restartNeeded` (:330), `adopt` (:343) and
   select's commit (:594-608) stay exactly as they are. They already turn one change into one
   apply with at most one restart, hold a value that arrives mid-switch (select's defer at :582
   re-runs `applyPending`), and let the newest pending value win (:605).

   ```swift
   // MARK: Settings (the app's menu and Settings window, and devices through .changeSettings, on both hosts)

   /// What the host is set to: a value still waiting for its restart, else the running one. What the
   /// Mac's menu checks and what devices are told. (Private: the app merges over its own settings.)
   private var target: HostConfig { pendingConfig ?? config }

   /// Who keeps the settings when a device changes one. Sill.app lays the change over its HostSettings
   /// (saved, shown) and returns the result. Unset (the CLI): the change lands on `target` and lasts
   /// until the process ends.
   package var onDeviceSettingsChange: (@MainActor (HostSettingsChange) -> HostConfig)?

   /// New settings from the app or a device. Synchronous: validated, the virtual display kept off
   /// without the AppKit loop, compared with the target, told to every device. The pipeline takes it
   /// in a Task, at once or through one restart (mid-switch: select's defer). Returns whether the
   /// target moved.
   @discardableResult
   package func setTarget(_ requested: HostConfig) -> Bool {
       guard !shuttingDown else { return false }
       var new = requested.validated()
       if !appKitLoop { new.virtualDisplay = false }
       guard new != target else { return false }
       pendingConfig = new
       publishSettings()
       Task { @MainActor in await self.applyPending() }   // a burst before it runs is one restart
       return true
   }
   ```

   Why the pipeline work is scheduled rather than awaited:

   - The device handler must answer before any await.
   - A burst of changes that arrives before the Task runs is taken as one restart.
   - `applyPending` already tolerates repeated calls: it returns while `switching`, and a later
     Task finds `pendingConfig` already consumed.

2. **The handler**, a new case in `handle(_:from:)`:

   ```swift
   case .changeSettings:
       // A device's settings control. No `await` in this case: the answer leaves in request order,
       // before any restart (setTarget schedules the pipeline work).
       guard let change = Wire.decode(HostSettingsChange.self, from: message.payload) else { return }   // no token to answer
       let (ok, refused) = DeviceSettings.accepted(change, virtualDisplayAvailable: appKitLoop)
       let who = deviceName(connection)
       if !refused.isEmpty { print("Settings from \(who) refused: \(refused.joined(separator: ", "))") }
       if !ok.isEmpty, !shuttingDown {
           let before = target
           setTarget(onDeviceSettingsChange?(ok) ?? before.applying(ok))   // app: the hook's own onChange already set it
           if target != before { print("Settings from \(who): " + before.changes(to: target)) }
       }
       server.send(settingsMessage(settingsState(answering: change.token)), to: connection)   // exactly one answer
   ```

3. **State, publishing and naming:**

   ```swift
   /// The last broadcast. Answers and the state sent on connect never touch it.
   private var lastPublished: HostSettingsState?

   /// A pure function of the target, the status snapshot and two constants (appKitLoop, the hook).
   private func settingsState(answering: Int? = nil) -> HostSettingsState {
       let t = target, s = status.snapshot
       return HostSettingsState(settings: t.streamSettings,
                                persistent: onDeviceSettingsChange != nil,
                                virtualDisplayAvailable: appKitLoop,
                                virtualDisplayNote: virtualDisplayNote(target: t, snapshot: s),
                                softwareEncoder: s.softwareEncoder,
                                stream: s.stream?.wire,
                                answering: answering)
   }

   /// The Mac's Virtual Display pane order (SettingsPanes.swift:223-233), without the permission
   /// lines: permissions are polled, not event-driven, and a missing one still reaches the device as
   /// the fallback reason on the next pick.
   private func virtualDisplayNote(target t: HostConfig, snapshot s: HostStatusSnapshot) -> String? {
       if !appKitLoop { return "Start SillHost with --virtual-display to use it." }
       if s.virtualDisplayAPIMissing, let p = s.virtualDisplayProblem { return "Not available on this version of macOS: \(p)" }
       guard t.virtualDisplay else { return nil }
       if let p = s.virtualDisplayProblem { return "Off for this session: \(p). Turn it off and on to try again." }
       if let f = s.lastStageFailure { return "The last window streamed where it is: \(f)" }
       return nil
   }

   private func settingsMessage(_ state: HostSettingsState) -> StreamMessage {
       StreamMessage(kind: .hostSettings, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                     payload: Wire.encode(state))
   }

   /// To every device, when the state differs from the last broadcast. Prints nothing.
   private func publishSettings() {
       let state = settingsState()
       guard state != lastPublished else { return }
       lastPublished = state
       server.broadcast(settingsMessage(state))
   }

   /// "iPad (iPad14,1)" once the device has sent its stats, its address until then.
   private func deviceName(_ connection: NWConnection) -> String {
       status.snapshot.devices.first { $0.id == ObjectIdentifier(connection) }?.name ?? "\(connection.endpoint)"
   }
   ```

4. **Wiring:**
   - In `init`, right after the first `status.update { $0.synthetic = … }` (:122), add
     `status.onChange = { [weak self] in self?.publishSettings() }`. A publish before
     `server.start()` reaches nobody, and every device gets a fresh state from `sendCatalog`, so
     early calls are harmless.
   - In `sendCatalog` (:1103), right after `server.send(listMessage(), to: connection)`, add
     `server.send(settingsMessage(settingsState()), to: connection)`. It is silent; the existing
     "Catalog → …" line is unchanged.
   - Replace the MARK at :276 ("the menu bar app; the CLI never calls these"), which is no longer
     true.

**Why no change is missed.** `settingsState` reads only the target, the snapshot, `appKitLoop` and
whether the hook is set.

- The target changes only in `setTarget`. Select's commit and `applyPending`'s direct `adopt` move
  `pendingConfig` into `config` without changing the target.
- The snapshot changes only in `HostStatus.update`, which now calls `onChange`. That covers:
  - a stream starting or stopping;
  - the encoder fallback;
  - virtual display problems and `lastStageFailure`;
  - `virtualDisplayOn`.

  The once-a-second device stats and encoded-fps updates also change the snapshot, but not the
  state, so dedupe sends nothing. An idle host sends no settings messages at all.

**What a device sees for a change:**

1. the broadcast of the new target (`setTarget` publishes before the handler answers);
2. the answer carrying its token;
3. if the pipeline restarted, new parameter sets and a keyframe, and a broadcast with the new
   `stream` once the pipeline has started. These two come in either order: frames leave from the
   encoder's thread.

**Log lines**, printed only when a device sends kind 17:

```
Settings from iPad (iPad14,1): bitrate 15 → 25 Mbps per 60 fps      ← new: the request
Settings from 127.0.0.1:52344 refused: virtual display (needs SillHost --virtual-display)   ← new
Settings: bitrate 15 → 25 Mbps per 60 fps                           ← existing, when the pipeline takes it
Streaming a synthetic test pattern at 3024×1898, 60 fps, 25 Mbps     ← existing, after the restart
```

A no-op change prints nothing and still gets its answer.

#### 2.5 Other host files

- **`HostConfig.swift`:** the doc comment's "See `StreamCoordinator.apply`" becomes `setTarget`.
  No code change.
- **The CLI (`Sources/SillHostCLI/main.swift`): no change.**
  - It sets no hook, so a device's patch lands on the target and lasts until SillHost quits.
    `persistent: false` tells the device so.
  - Without `--virtual-display` there is no AppKit loop. `virtualDisplayAvailable` is false,
    turning it on is refused and answered, and `setTarget` would force it off anyway.
  - With the flag, a device can turn it on and off. `HostShutdown` is installed exactly when the
    flag is (main.swift:74-83), which is the only case where a display can exist, so the emergency
    restore still covers every staged window.

### 3. Sill.app: persistence through `HostSettings.config`

**`Sources/SillMenuBar/AppModel.swift`**, in `start()`, replacing the closure at :57-59 and adding
the hook before `await c.start`:

```swift
// One path from the controls to the host, synchronous: the host's target equals settings.config
// at every main-actor turn, so a device's change and a menu click never undo each other.
settings.onChange = { [settings, weak c] in _ = c?.setTarget(settings.config) }
// A device's change goes through HostSettings like a menu click: saved (only the keys it changed)
// and shown live in Settings. Laid over settings.config, never over the host's value. No
// validated(): the host accepted only menu values, and validating here would rewrite unrelated
// hand-set keys (which save(changedFrom:) would then write).
c.onDeviceSettingsChange = { [settings] change in
    settings.config = settings.config.applying(change)
    return settings.config
}
```

**`Sources/SillMenuBar/HostSettings.swift`:**

- Remove `QualityPreset` (now in StreamProtocol) and add `import StreamProtocol`.
- Type `onChange` as `(@MainActor () -> Void)?`.
- Update the doc comment: `StreamCoordinator.apply` → `setTarget`, and devices assign `config`
  too, through the hook.

**`StatusItemController.swift` and `SettingsPanes.swift`:** add `import StreamProtocol`. They use
`QualityPreset`; nothing visible changes.

How a device's change behaves in the app:

- **Saved** like a click. `didSet` writes only the keys that changed (HostSettings.swift:74-80), so
  a launch-argument override of another key stays unsaved.
- **Shown** live in the Settings panes through `@Bindable`, and in the status menu the next time it
  opens (it is rebuilt in `menuNeedsUpdate`). A menu that is already open keeps its old checkmarks
  until reopened. That is a known, accepted minor issue; don't rebuild an open NSMenu.
- **Order of events.** The hook assigns `settings.config`, whose `didSet` calls
  `setTarget(settings.config)` synchronously, which publishes. The handler's own `setTarget` call
  then finds an equal value and does nothing. The log shows "Settings from …" before the
  pipeline's "Settings: …".
- **Every other writer** keeps working and now reaches the host synchronously: menu actions
  (AppKit target/action), the pane bindings, and `-SillSetAfter` (a Timer in the app target, where
  `assumeIsolated` is allowed).

### 4. The queued pick (its own commit)

Today `select`'s `guard !switching` (:564) drops a pick that lands mid-switch. A settings panel
makes that likely: change Quality, then tap a thumbnail within the restart. Fix it narrowly, in
StreamCoordinator:

```swift
/// A restart of the active source is in flight (a settings change, a resize, a rate change, the
/// encoder fallback, a lost display): the source being restarted. Nil during a switch to another source.
private var restartOf: StreamSource?
/// A device's pick of a different source that came in during that restart; taken by select's defer.
/// Never set during a switch to another source: the device's automatic Desktop request can land
/// then (StreamClient.swift:432-440) and must not override the user's pick.
private var pickArrivedWhileSwitching: StreamSource?
```

- **In `select`**, after `switching = true`:
  `restartOf = (source == active && source != .none) ? source : nil`.
- **In `handle(.selectSource)`**, before `await select(source, bringForward: true)`:

  ```swift
  if switching {
      if let r = restartOf, source != r { pickArrivedWhileSwitching = source }   // newest wins; same source: dropped
      return
  }
  ```

- **In select's `defer`**:
  - Right after `switching = false`, add `restartOf = nil`, then
    `var pick = pickArrivedWhileSwitching; pickArrivedWhileSwitching = nil`.
  - After the existing deselect-when-settled block, add `if catalog.clientCount == 0 { pick = nil }`
    (the last client leaving wins).
  - Then:

    ```swift
    if let pick, pick != active {
        viewportArrivedWhileSwitching = false        // the pick's own select fits the latest viewport
        Task { @MainActor in await self.select(pick, bringForward: true) }
    } else if viewportArrivedWhileSwitching { … existing … }
    if pendingConfig != nil { … existing applyPending Task … }   // a no-op if the pick's select commits it
    ```

  - Skipping the viewport tail matters. Run after the pick's select has started, that tail would
    resize the old window, because `active` still names it mid-switch.

Out of scope and unchanged: `windowsChanged`'s launch pick (:1044-1047) is still lost when it
lands mid-switch.

### 5. iOS client

#### 5.1 Files

| File | Change |
|---|---|
| `iOSClient/HostSettingsLedger.swift` | New. Pure logic, no UIKit, compiles with swiftc for tests (§5.2). |
| `iOSClient/HostSettingsPanel.swift` | New. The panel (§5.5–5.7). |
| `iOSClient/StreamClient.swift` | A `// MARK: Host settings` section (§5.3). It stays in this file so the DEBUG echo can reach the private `connection`. Also the `connect(to endpoint:name:)` refactor and `-SillConnect`. The oddities work is rewriting this file's measurement code (`fps`, `frameAgeMs` and `rttMs` become `linkStats`, and the pings move to dispatch timers), so re-read it on the branch. Nothing here depends on that code except the timeout's rtt. |
| `iOSClient/StreamScreen.swift` | `settingsOpen`, `setSettings`, the TopBar's last slot, the landscape placement, the DEBUG init parameter. |
| `iOSClient/PortraitStreamScreen.swift` | The windowBar's last slot and the portrait placement. |
| `iOSClient/InputOverlay.swift` | `InputOverlayProxy.setKeyboard(shown:)`. |
| `iOSClient/ContentView.swift`, `MockCatalog.swift` | Harness arguments, mock cases, `-SillConnect`. |
| `iOSClient/Sill.xcodeproj/project.pbxproj` | Each new file needs four hand-written entries (the project uses explicit file references). |

The pbxproj entries for each new file:

- a `PBXBuildFile`;
- a `PBXFileReference`;
- a child of the main group `A1000001000000000000C001`;
- an entry in the Sources phase `A1000001000000000000B001`.

IDs, both pairs checked free: `HostSettingsLedger.swift` = `A1000001000000000000A012` /
`A1000001000000000000F012`, and `HostSettingsPanel.swift` = `A1000001000000000000A013` /
`A1000001000000000000F013`. StreamProtocol's new file needs no project edit, because it is a local
package (project.pbxproj:392-397).

#### 5.2 The ledger (`HostSettingsLedger.swift`)

```swift
enum SettingsField: CaseIterable, Hashable { case maxFPS, bitrate, captureScale, prioritizeSpeed, virtualDisplay }

/// What the panel shows: the Mac's last word on this connection with this device's unanswered
/// picks laid over it, field by field.
struct SettingsLedger: Equatable {
    struct Entry: Equatable { var change: HostSettingsChange; var token: Int; var sentAt: Double }   // change: this field only
    private(set) var host: HostSettingsState?                 // last state on this connection, `answering` stripped; nil = none yet
    private(set) var pending: [SettingsField: Entry] = [:]     // latest unanswered pick per field
    var displayed: StreamSettings?                             // host.settings with every pending entry applied
    func pendingSince(_ f: SettingsField) -> Double?           // for the 300 ms spinner
    mutating func pick(_ change: HostSettingsChange, token: Int, now: Double) -> HostSettingsChange?   // nil = send nothing
    mutating func receive(_ state: HostSettingsState) -> Set<SettingsField>   // fields this answer refused
    mutating func expire(now: Double, timeout: Double) -> Bool                  // true if anything expired
    mutating func reset()
}
```

Rules. Each was model-checked in d0: 50,000 random runs over two devices, the Mac menu,
disconnects and slow hosts, plus mutation runs.

1. **No state on this connection:** `pick` returns nil. Nothing is ever sent to an older Mac.
2. **Filter to real changes.** `pick` keeps only the touched fields whose value differs from
   `displayed`. If none is left, it returns nil, so picking what is shown sends nothing.
   - Tapping back to the host's value while another pick for that field is pending **does** send.
3. **Record.** Each sent field gets an entry carrying this token, which replaces any older entry
   for that field.
4. **Broadcasts never clear entries.** An answer (`answering == t`) clears only the entries whose
   token is `t`.
   - So a double tap 60 → 120 → 60 never flashes 120: answer 1 finds maxFPS held by token 2 and
     leaves it.
5. **Refusals.** A cleared entry whose value differs from the answer's `settings` is a refusal.
   The control snaps back to the Mac's value, and the caller plays the haptic and posts the
   VoiceOver announcement.
6. **Timeout.** `expire` drops entries older than `max(4, 4 × rtt)` s, where rtt is the device's
   latest measured round trip (rtt unknown counts as 4 s). At 59fc510 that is `rttMs`. The
   oddities work in progress replaces it with `linkStats?.rtt` (median and max per second); use
   its `max` if that has landed.
   The field returns to the Mac's value, and the panel shows "‹Mac› didn't answer. Try again."
   inline, never in an alert. A late answer or broadcast still applies normally.
7. **`reset`** on every tear-down. **Never persist** a Mac's settings on the device, as
   `windowOrder` is: Bonjour names change ("Mac (2)"), and a cached copy is wrong the moment the
   Mac menu changes a value.
8. **Never send on your own.** Nothing goes out on connect, on a broadcast or from
   `onChange(of:)`; only a control's action sends.

#### 5.3 `StreamClient` additions (main thread unless noted)

```swift
@Published var settings = SettingsLedger()      // internal setter: MockCatalog seeds it
@Published var settingsProblem: String?         // "Mac mini didn't answer. Try again."
@Published var settingsRefusals = 0             // bumped per refusal: haptic + VoiceOver announcement
@Published var connectedAt: Date?               // set on .ready, cleared in tearDown: "Loading…" vs "Update Sill…"
private var settingsToken = 1                   // never reset: strictly increasing for the process
#if DEBUG
var mockFrozen = false                          // harness `pending` case: no echo, no expiry
#endif
```

- **`handle`**, on the network queue: add
  `case .hostSettings: guard let s = Wire.decode(HostSettingsState.self, from: data) else { return }; DispatchQueue.main.async { self.receiveSettings(s) }`.
  It hops to main the same way `.windowList` does.
- **`receiveSettings(_:)`:** `let refused = settings.receive(s)`. If an answer arrived, clear
  `settingsProblem`. If anything was refused, bump `settingsRefusals`.
- **`changeSettings(_ change: HostSettingsChange)`:**
  1. `guard let out = settings.pick(change, token: settingsToken, now: ProcessInfo.processInfo.systemUptime) else { return }`
  2. `settingsToken += 1; settingsProblem = nil`
  3. `send(.changeSettings, payload: Wire.encode(out))`
  4. Schedule `expireSettings()` after the timeout plus 0.05 s.
  5. DEBUG with no connection (the harness), in the style of `select()` at :256-262: unless
     `mockFrozen`, answer locally after 0.35 s with `out` applied to the mock state and
     `answering` set. A virtual display turned on while the mock says it is unavailable is refused.
- **`expireSettings()`:** if `settings.expire(…)` returns true, set `settingsProblem` to
  "\(macName) didn't answer. Try again."
- **`tearDown`** (:228-251): `settings.reset(); settingsProblem = nil; connectedAt = nil`.
- **Refactor `connect(to result:)`** into `connect(to endpoint: NWEndpoint, name: String)`. The
  Bonjour path calls it with `result.endpoint` and `Self.serviceName(of:)`.
- **DEBUG `connectFromLaunchArgument()`:** reads `-SillConnect host:port` and calls
  `connect(to: .hostPort(host:port:), name: raw)`.
  - It is called after `startBrowsing()` in `ContentView.app.onAppear`, and in the harness's live
    branch (`LayoutHarness.onAppear` when `spec.live`).
  - If such a connection drops, the reconnect timer never finds it on Bonjour and backs off to
    10 s. That is harmless in DEBUG.

#### 5.4 Entry point: Settings takes Leave's slot (Q1)

The last slot of every bar changes from Leave (`xmark.circle`, `client.disconnect()`) to
**Settings**:

- the `gearshape` symbol, labelled "Settings";
- `open: settingsOpen`, which gives the accent glyph on `Palette.controlOpen`;
- the accessibility label "Settings for ‹Mac›" while closed and "Close settings" while open;
- it fades while the Aa ruler is open, as Leave does today.

| Layout (`DuoLayout`) | Where | Button |
|---|---|---|
| inner landscape 1000×710 | `TopBar`'s last slot (StreamScreen.swift:321-325) | 66×66 |
| outer landscape 710×500 | same, compact bar | 64×58 |
| inner portrait 710×1000 | `windowBar`'s last slot (PortraitStreamScreen.swift:249-253) | 64×58 |
| outer portrait 500×710 | same, compact | 56×50 ("Settings" at 11 pt is about 42 pt wide) |

**Why not a sixth button.** It would cost the thumbnail strip 25–35%. The worst case is the outer
portrait display, which would drop from about 2.1 thumbnails to about 1.4.

**If Noah keeps one-tap Leave (Q1 alternative):**

- Leave stays in the bar.
- A "Settings for ‹Mac›" row is pinned to the bottom of the Apps drawer. It closes the drawer and
  opens the same panel.
- The panel then has no Disconnect foot.

#### 5.5 Presentation and placement

A custom panel mirroring the Apps drawer on the trailing edge. It is not a `.sheet`, `.popover` or
`Menu`, for these reasons:

- The client has no system presentation anywhere.
- Sheets and popovers adapt by size class, which is unknown for the Duo.
- The `-SillLayout` harness draws a fake Duo screen inside an iPad window, and a system
  presentation would escape it, so the photos would be wrong.
- A tall sheet or a flipped popover can cross the half-folded crease, which the brief forbids.

State and dismissal:

- `settingsOpen` lives in `StreamScreen`, next to `drawerOpen`, so rotation keeps it open and it
  re-anchors.
- There is no dim. A clear tap catcher covers the content area; a tap closes the panel and never
  reaches the Mac. It is hidden from VoiceOver.

| Layout | Container | Width | Top | Trailing inset | Room for the panel |
|---|---|---|---|---|---|
| inner landscape | `contentArea`'s ZStack (:201-242); pass it `bar` | 360 | 8 under the bar | 22 (`BarMetrics.padding`) | 602 pt, no scrolling |
| outer landscape | same | 340 | 8 under the bar | 14 | 400 pt, the middle scrolls |
| inner portrait | `PortraitStreamScreen`'s ZStack (:150-176) | `min(360, width − 2·padSide)` | `half + padTop + barHeight + 8` = 598 | `padSide` = 14 | 380 pt, the middle scrolls a little |
| outer portrait | same | same | 355 + 10 + 62 + 8 = 435 | 14 | 259 pt, the middle scrolls |

- The trailing insets line the panel's trailing edge up with the Settings button's.
- In portrait the panel sits entirely in the lower half, so it never spans the crease and the
  stream above stays visible.
- Code shape:

  ```swift
  HostSettingsPanel(...)
      .frame(width: w)
      .frame(maxHeight: .infinity, alignment: .top)
      .padding(.top, t)
      .padding(.bottom, bottomPad)
      .padding(.trailing, inset)
      .frame(maxWidth: .infinity, alignment: .trailing)
  ```

  `bottomPad` is 14 in landscape and `padBottom` in portrait.

**Inside the panel:**

- `VStack(spacing: 0)` holding:
  - a **pinned header**;
  - a middle as `ViewThatFits(in: .vertical) { rows; ScrollView { rows } }`, so the panel takes
    its content's height when it fits and scrolls when it doesn't (flash the indicators once on
    open);
  - a **pinned Disconnect foot**.
- Not a `Form` or `List`: those have no height of their own.
- Styling:
  - the container is `padding(14)`, `Palette.bar`, a 20 pt continuous radius, a 10% white stroke
    and the drawer's shadow;
  - rows are inset groups on `Palette.control`, with a 12 pt radius, rows at least 44 pt tall, and
    hairline dividers inset 14 pt.

**Motion.** Open with `.spring(duration: 0.25, bounce: 0.15)`, as
`.scale(0.94, anchor: .topTrailing)` combined with opacity. Close with `.easeOut(duration: 0.18)`.
Under Reduce Motion, opacity only.

#### 5.6 Rows, controls and copy

Order: most-changed first, so on the 259 pt display the header plus Quality, Resolution and Frame
Rate show before any scrolling. The virtual display, with its longer explanation, comes last.

| Group | Row | Control | Values | Notes |
|---|---|---|---|---|
| Stream | Quality | `Picker`, `.menu` style | `QualityPreset.allCases` titles ("Balanced — 15 Mbps") | A Mac-held non-preset shows as an extra "Custom — N Mbps" item. Re-picking it is a no-op. |
| | Resolution | segmented `Picker` | Retina (2), Standard (1) | |
| | Frame Rate | segmented `Picker` | 60 fps, 120 fps | A Mac-held value such as 90 selects no segment, as on the Mac. |
| | Prioritize Speed | `Toggle` | | |
| Mac | Virtual Display | `Toggle`, accent tint | | Disabled only when `!virtualDisplayAvailable` and it is off. Turning it off is always allowed. |

- **Bindings.** Each control binds to `client.settings.displayed`. Its setter calls
  `client.changeSettings(HostSettingsChange(<field>: value))`, one field per control. Never send
  from `onChange(of:)`. There are no sliders: one change is one apply and at most one restart.
- **Pending.** A row shows a small `ProgressView` beside its title only while its entry is more
  than 300 ms old.
- **Header**, pinned:
  - the Mac's name (`client.macName` from the window list, not the Bonjour name, so it also works
    for connections by address later), as a headline, middle-truncated;
  - a readout in footnote size with monospaced digits: "3024×1898 · 60 fps · 15 Mbps", plus
    " · virtual display" when `stream.onVirtualDisplay`, or "Not streaming" when `stream` is nil;
  - a trailing **Done** button with `.keyboardShortcut(.cancelAction)`.
- **Callouts** (orange, with `exclamationmark.triangle.fill`, above the groups):
  - software encoder: "‹Mac›'s hardware encoder isn't responding, so streams run at up to 60 fps at
    Standard until the Mac restarts." The controls stay enabled, because they are targets for when
    it recovers.
  - timeout: `settingsProblem`.
- **Stream group footer:**
  - "Quality is per 60 fps; a 120 fps stream gets twice as much."
  - Plus, when `StreamClient.wantedFPS() < 120`: " This iPad shows up to 60 fps." Say "iPhone" by
    idiom. With Low Power Mode on: " Low Power Mode holds this iPad to 60 fps."
- **Virtual Display footer:** the host's `virtualDisplayNote` in orange with ⚠ when present.
  Otherwise the device copy: "The window you pick moves onto an invisible display on ‹Mac› while
  it streams, so it keeps updating when covered."
- **Closing footer:** "Applies to every device streaming from ‹Mac›. The stream restarts for a
  moment." When `persistent == false`, add "SillHost keeps these until it quits."
- **Foot**, pinned: "Disconnect from ‹Mac›" in accent text with `xmark.circle`, 44 pt, calling
  `client.disconnect()`.

**States:**

| State | What the panel shows |
|---|---|
| No state yet, under 2 s since `connectedAt` | Spinner and "Loading settings…". Disconnect works. |
| No state after 2 s (an older Mac) | "Update Sill on ‹Mac› to change these from here." No controls. Disconnect works. |
| Normal | The rows as above. |
| Pending | The picked value at once; a spinner after 300 ms. |
| Refused | The control snaps back, a `.sensoryFeedback(.warning, trigger: settingsRefusals)` haptic plays (a no-op on iPad), and an announcement is posted. The reason is already in the footer or note. |
| Timeout | Back to the Mac's value, with the orange callout. The next answer clears it. |

**Never shown on the device** (Mac only): Launch at Login, Permissions, Show Log…, Reveal Log File,
Quit Sill, Running from, the network name, and the virtual display's Try Again (toggling off and on
does the same).

#### 5.7 Behaviour, keyboard, accessibility

- **`StreamScreen`** owns `@State settingsOpen` and `@State keyboardBeforeSettings`, plus
  `setSettings(_ open: Bool, restoreKeyboard: Bool = true)`. Pass `settingsOpen` and `setSettings`
  to `TopBar` and `PortraitStreamScreen`.
- **Opening:**
  - closes the drawer, the traffic-light menu (`windowMenu = nil`) and the Aa ruler;
  - stores `keyboardBeforeSettings = keyboardShown`;
  - calls `overlay.setKeyboard(shown: false)`.
- **Closing** (Done, the catcher, the Settings button, Esc or ⌘., the VoiceOver escape gesture)
  calls `overlay.setKeyboard(shown: true)` if the panel had taken the keyboard down.
- **Other controls while the panel is open:**
  - The Apps button calls `setSettings(false, restoreKeyboard: false)`, then toggles the drawer.
  - The landscape Keyboard button calls `setSettings(false, restoreKeyboard: false)`, then
    `toggleKeyboard()`.
  - Add `.onChange(of: scaleOpen)` and `.onChange(of: windowMenu)` that close the panel when
    either opens.
  - Window picks and the Desktop button leave the panel open; the readout follows the new stream.
  - In portrait the catcher covers both halves, like the drawer's dim, so a tap anywhere outside
    closes the panel first.
- **`InputOverlayProxy.setKeyboard(shown:)`:** calls `becomeFirstResponder()`, or
  `resignFirstResponder()` if the view is first responder. With the overlay not first responder,
  hardware keys don't reach the Mac, and Esc reaches the Done button's cancel shortcut.
  - If S4 shows that Esc does not trigger Done, make the panel focusable and handle
    `.onKeyPress(.escape)`.
- **VoiceOver:**
  - `.accessibilityElement(children: .contain)`, `.accessibilityAddTraits(.isModal)` and
    `.accessibilityAction(.escape) { close }`;
  - `@AccessibilityFocusState` moves focus to the header on open;
  - each control keeps its system label;
  - a disabled switch reads the note as its hint;
  - refusals and timeouts are announced with `AccessibilityNotification.Announcement`.
- **Dynamic Type:** text styles, capped with `.dynamicTypeSize(...DynamicTypeSize.xxLarge)`. Each
  row is `ViewThatFits(in: .horizontal) { HStack(label, control); VStack(alignment: .leading) { label; control } }`.
  The bar keeps its fixed sizes.

#### 5.8 Harness (DEBUG; add to the contract comment at ContentView.swift:51-66 and to CLAUDE.md)

- **`-SillSettings 1`:** start with the panel open. It goes through `LayoutHarness.Spec` to a new
  `settingsOpen:` parameter on StreamScreen's DEBUG init (:89-100), the same route as
  `-SillDrawer`.
- **`-SillSettingsCase <case>`** seeds `MockCatalog.client(active:settings:)`. The default mock
  stream is 2880×1800 · 60 fps · 15 Mbps.

  | Case | Mock |
  |---|---|
  | `default` | Sill.app: persistent, virtual display available |
  | `cli` | `persistent: false`, virtual display unavailable, with the CLI note |
  | `software` | `softwareEncoder: true`, stream 1440×900 |
  | `custom` | bitrate 12 Mbps ("Custom — 12 Mbps") |
  | `vdproblem` | virtual display on, note "Off for this session: the system removed the virtual display 3 times. Turn it off and on to try again." |
  | `legacy` | no state; `connectedAt` 10 s ago |
  | `pending` | a Quality pick in flight, sent 1 s ago; `mockFrozen` (never answers, never expires) |
  | `timeout` | `settingsProblem` set |

- **Combinations.** Both arguments work with `-SillLayout WxH`, `-SillActive` and `-SillHUD 1`.
  With `-SillLive 1`, the panel shows a real Mac's state.
- **`-SillConnect 127.0.0.1:PORT`** connects by address, in the normal app and under `-SillLive 1`.
- **Photograph:**

  ```
  xcrun simctl terminate booted me.saffer.sill
  xcrun simctl launch booted me.saffer.sill -SillLayout 500x710 -SillSettings 1 -SillSettingsCase software
  xcrun simctl io booted screenshot "$SP/settings-500x710-software.png"
  ```

### 6. Edge cases

| Case | Behaviour |
|---|---|
| Two devices, different fields | Each patch lands on the latest target; both stick. |
| Two devices, or a device and the Mac menu, same field | Handled in arrival order; last writer wins. The loser shows its own pick until its answer, then the winner's value. No flash of the old value. |
| A menu click and a device change | The click is already in `settings.config` (synchronous) and the device's patch merges over it. Neither undoes the other. |
| A change mid-switch (a virtual display staging takes seconds) | The target is set and answered at once. The pipeline takes it at select's commit (the newest pending value wins) or through select's defer. At most one extra restart. |
| A burst of changes | One answer each, in order, each showing its own value. Usually one restart. |
| A pick during a settings restart | Queued, and run after it (§4). A pick of the same source is dropped (no double restart). |
| A pick during a switch to another source | Dropped, as today (the automatic Desktop request hazard). |
| Disconnect with a change in flight | The host may or may not have taken it. The ledger resets; the state on reconnect shows the truth; the device never resends. |
| Host restarts | Sill.app reloads its saved values; the CLI returns to `HostConfig.standard` (the device knows from `persistent`). |
| CLI without `--virtual-display` | The toggle is disabled with the note. A forced request is refused, logged and answered. |
| Software encoder | 120 fps and Retina are accepted and saved as targets. `restartNeeded` skips the restart when the cap makes the change a no-op (:332-335). The readout shows what runs; the callout says why. |
| A 60 Hz device alone | 120 changes nothing for it (`wantedFPS` is the highest device rate under the limit); the footer says so. It is still a real setting for a ProMotion device connected at the same time. |
| Hand-set Mac values, launch-argument overrides | Shown read-only as Custom (or no segment). A device change to another key leaves an override unsaved; a change to the same key saves the new value, as a click would. |
| Quitting (`shuttingDown`) | Not applied, the hook is not called, and the answer carries the unchanged state. |
| A device connecting mid-restart | It is told the target: what the Mac menu shows. |
| Malformed JSON | Dropped with no answer; the device times out after 4 s. |
| A change without a token (test clients) | Applied, and answered without `answering`. |
| Main actor busy for more than 4 s (an app hung on Accessibility) | Timeout, back to the Mac's value; the late answer or broadcast applies normally. |
| Virtual display off from a device while a window is staged | The window comes home and comes forward (`applyPending` passes `bringForward`, :321-324), as with the menu (Q3). A full-screen window takes up to 2 s to leave. |
| Virtual display on with the private API missing | Accepted, for parity with the Mac's toggle. The note says "Not available on this version of macOS: …" once known (the host checks the API the first time the display is enabled; the Mac behaves the same). The real window streams. |
| Mac permissions missing | Not in the state. A staging failure reaches the device as "The last window streamed where it is: …". |
| The Mac's status menu is open during a device change | It keeps its old checkmarks until reopened (known, minor). |
| Settings messages and delta frames | A settings message counts toward a client's inflight count, so a delta can be dropped and replaced by a keyframe. The stream restarts anyway. |
| Security | Any peer that reaches the listener could already watch the Mac and drive its input. Now it can also change these five whitelisted settings, and Sill.app saves them. There is no generic defaults write. Step 3 must add pairing or authentication before the port is reachable beyond a VPN (§9). |

### 7. Test plan

`$SP` is the implementer's scratchpad.

- **CLI host:**
  `.build/release/SillHost --synthetic > "$SP/cli.log" 2>&1 & HOST=$!`, then
  `PORT=$(lsof -nP -iTCP -sTCP:LISTEN -a -p $HOST | awk 'NR==2{n=split($9,a,":"); print a[n]}')`.
- **App host:** `.build/release/SillMenuBar --synthetic -SillLogFile "$SP/app.log"`. Its port is
  in the "Status: Test Pattern Mode — … port N." line. Its defaults domain is `SillMenuBar`; run
  `defaults delete SillMenuBar` at the end.

#### 7.1 Extend `Scripts/sillclient.py` (with the host commit)

- `--set=K=V[,K=V]@T`: sends kind 17 with integer tokens 1, 2, 3… in send order. Booleans accept
  `1/0/true/false/on/off`.
- `--raw17=<json>@T`: sends the literal payload (split on the last `@`).
- `--pick=none|desktop|window:ID@T`: a timed `selectSource` (`none` is `{"none":{}}`).
- `--stats`: sends `{"fps":0,"frameAgeMs":0,"rttMs":0,"device":"sillclient"}` as kind 12 once a
  second, so the host logs a name. It still decodes after the oddities work adds its optional
  `frameAgeMaxMs` and `rttMaxMs`.
- `--expect=K=V[,…]`: at exit, compares the last kind 16's `settings` (and the top-level
  `persistent` and `virtualDisplayAvailable`), prints `EXPECT ok` or `EXPECT FAIL …`, and exits 1
  on failure.
- Prints every kind 16 on one line with its arrival time, `answering`, the settings, `persistent`,
  `vdAvail`, the note, `sw` and the stream, and adds `16:"settings"` to the `KIND` map. At exit it
  prints "settings messages: N".

#### 7.2 Headless (no permissions; the implementing session)

| # | Check | Pass when |
|---|---|---|
| H0 | `swift build -c release` | Clean, apart from the known CaptureProbe warning. |
| H1 | `xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -derivedDataPath $SP/dd build`, in Debug and in `-configuration Release` | Both build, with only existing warnings. |
| H2 | Ledger check: `swiftc Sources/StreamProtocol/HostSettings.swift iOSClient/HostSettingsLedger.swift $SP/ledger-check.swift`. Port the scenario and random-run parts of `scratchpad/ipad-settings/d0-protocol-check.swift` if it still exists; otherwise write these scenarios. | All pass: no state sends nothing; a pick moves at once and is cleared by its answer; picking the shown value sends nothing; 60→120→60 never shows 120; back to the host's value while pending sends; a refused toggle snaps back and is reported; a broadcast keeps a pending pick; expiry at the timeout; a newer host's extra keys are ignored; a state missing a required key fails to decode; 5,000 random two-device plus Mac-menu runs converge. |
| H3 | CLI baseline. Take `base.log` at the branch point, before any edit, with `sillclient.py PORT 5 desktop`; repeat after. | `diff <(grep -v '^\[1s\]' base.log \| sed -E 's/[0-9]+/N/g' \| sort) <(… new.log …)` is empty. The client sees one kind 16 right after the first windowList (`persistent:false`, `virtualDisplayAvailable:false`, the CLI note, `stream` absent), then one when the Desktop pipeline starts. No others. |
| H4 | Accept: `--set=bitrate=25000000@3 --expect=bitrate=25000000` | "Settings from 127.0.0.1:…: bitrate 15 → 25 Mbps per 60 fps", one "Settings:", one "Streaming … 25 Mbps". The client sees a broadcast with the new target, then the answer (`answering 1`), then parameter sets and a broadcast with `stream.mbps 25` in either order. |
| H5 | No-op: `--set=bitrate=15000000@3` | One answer; no broadcast, no "Settings" line, no new parameter sets. |
| H6 | Refusals (CLI without the flag): `--set=virtualDisplay=1@3 --set=maxFPS=30@4 --set=bitrate=500000000@5` | Three "refused" lines, three answers, no restart, state unchanged. |
| H7 | Partial: `--set=maxFPS=30,bitrate=8000000@3` | maxFPS refused, bitrate applied, one answer. |
| H8 | Burst: `--set=bitrate=8000000@3 --set=bitrate=25000000@3 --set=bitrate=40000000@3` | Answers 1, 2, 3 in order, showing 8, 25 and 40 Mbps. Final 40 Mbps. At most 2 restarts, usually 1. |
| H9 | Two clients at once: A `--set=bitrate=8000000@3`, B `--set=maxFPS=60@3`, both with `--expect=bitrate=8000000,maxFPS=60` | Both EXPECT ok; each gets exactly one answer, carrying its own token. |
| H10 | Rapid pairs, `captureScale=1` then `maxFPS=60`, at offsets 0, 20, 50, 100, 300 ms, with `--fps=120` | Always the merged state; at most 2 restarts per pair. |
| H11 | Reconnect: A sets 25 Mbps and exits; B connects | B's first kind 16 shows 25 Mbps (the CLI keeps it for the session). |
| H12 | Tolerance: `--junk`; `--raw17={@3`; `--raw17={"token":5,"bitrate":25000000,"future":1}@4`; `--raw17={"bitrate":8000000}@5` | The host keeps serving. The malformed one gets no answer. The extra key is ignored and the change applies. The tokenless change applies and its reply has no `answering`. |
| H13 | Idle dedupe: 20 s streaming with `--stats` | Exactly two kind 16 in total, even though the snapshot changes every second. Host CPU as in the baseline. |
| H14 | `SillHost --synthetic --virtual-display`: `--set=virtualDisplay=0@3 --set=virtualDisplay=1@5` | Both accepted: "Settings: virtual display on → off", then "off → on". No restart and no display created (the Desktop never uses one, :337). `virtualDisplayAvailable:true`. |
| H15 | App: `--set=bitrate=25000000@3` | `defaults read SillMenuBar bitrate` = 25000000; app.log has both lines; `persistent:true`. |
| H16 | App: `-SillSetAfter '4 maxFPS=60'` with a connected client | A broadcast (no `answering`) with maxFPS 60 at about 4 s. |
| H17 | App races: `-SillSetAfter '4 bitrate=8000000'` plus `--set=maxFPS=60@4`; then `-SillSetAfter '3 bitrate=25000000'` plus `--set=bitrate=8000000@3.05` | First: both keys in the defaults and in the final state. Second: whichever app.log shows last wins in the defaults, the final state and the running stream. |
| H18 | App relaunch after H15 | The first kind 16 shows 25 Mbps and `persistent:true`. Then `defaults delete SillMenuBar`. |
| H19 | `-SillRenderPreviews <dir>` before and after | `menu.txt` and the pane renders are identical (the QualityPreset move is import-only). |
| H20 | Mac-path regression after the synchronous `onChange` | Each `-SillSetAfter` change gives one "Settings:" line and at most one restart (virtual display on while the Desktop streams: none). Quit exits 0 through `releaseForQuit`. Idle CPU 0.0%. |
| H21 | Queued pick: `--set=captureScale=1@3 --pick=none@3.02`, 10 times | The stream stops after the restart every time (the last windowList has `active` none). Without §4 the frames continue. Also `--set=bitrate=25000000@3 --pick=desktop@3.02`: one restart only (same source dropped). Then H3 again. |

#### 7.3 Simulator

| # | Check |
|---|---|
| S1 | The photo matrix: the four Duo sizes (1000x710, 710x500, 710x1000, 500x710) with all eight cases; `default` at 1133x744, 744x1133, 874x402 and 402x874; `default` and `software` at 500x710 under `xcrun simctl ui booted content_size accessibility-extra-large`. Check each photo for: the panel's trailing edge under the Settings button; it fits or scrolls; header and Disconnect pinned; nothing above the half-way line in portrait; the "Settings" label fits at 56 pt; nothing clipped. Send Noah the sheet. |
| S2 | Harness taps through the DEBUG echo, with the simulator control tool (inspect, then tap): a pick moves at once and settles after 0.35 s; the Quality menu opens as a system menu; `pending` shows its spinner; `legacy` has no controls; Done, a tap outside, the Settings button and the Apps button all close the panel; rotating keeps it open. |
| S3 | Accessibility Inspector: modal trait, labels, escape closes it, focus on the header when it opens; Reduce Motion gives a fade only. |
| S4 | Hardware keyboard (I/O › Keyboard › Connect Hardware Keyboard), under `-SillKeyboard 1`: open the panel, and the overlay resigns. Esc closes it; after closing, the overlay is first responder again. |
| S5 | Live against the CLI: `-SillLayout 710x1000 -SillLive 1 -SillConnect 127.0.0.1:$PORT -SillSettings 1` against `SillHost --synthetic`. The panel shows the CLI state. Change Quality: the host log shows both lines, and the readout moves to the new Mbps. Then a Mac-side `sillclient --set=captureScale=1@5`: the simulator panel follows (screenshot). Repeat against the bare `SillMenuBar --synthetic` and watch `defaults read SillMenuBar`. |
| S6 | Older host: build the branch point in a `git worktree`, run its `--synthetic`, and connect the new client with `-SillConnect`. After 2 s: "Update Sill on …"; Disconnect works; nothing of kind 17 is sent. |

#### 7.4 Noah's iPad mini and the Mac (handed over; 60 Hz device, so 120 fps changes nothing on it)

| # | Check |
|---|---|
| D1 | Streaming a real window from Sill.app, open Settings: the values match the Mac menu, and the readout matches the status card. |
| D2 | Change Quality, Resolution, Frame Rate and Speed from the iPad. Each gives one short restart. The Mac's open Settings window follows live, and the menu shows the change when reopened. `defaults read me.saffer.sill.mac` holds it, and it survives a relaunch. |
| D3 | Virtual Display on from the iPad while a window streams: the window leaves the Mac's screen, and Displays shows "Sill". Off: it comes home and comes forward (Q3). Repeat with a full-screen window. |
| D4 | Change a setting from the Mac menu while the iPad panel is open: the panel follows within a second. |
| D5 | Two devices (the iPad plus an iPhone, or a simulator with `-SillLive 1`): a change on one shows on the other; simultaneous changes to different settings both stick. |
| D6 | `swift run -c release SillHost`: the virtual display switch is disabled with its reason, the footer says "SillHost keeps these until it quits", and changes last until it quits. With `--virtual-display` the switch works. |
| D7 | Reconnect (iPad Wi-Fi off and on, or quit and reopen Sill.app): the panel shows the Mac's values, including a change made while the iPad was away. |
| D8 | The 60 fps footnote on the iPad mini; toggle Low Power Mode. |
| D9 | Magic Keyboard: Esc closes the panel and does not reach the Mac; afterwards, keys reach the Mac again. |
| D10 | VoiceOver: open the panel, change Quality, close with the escape gesture. |
| D11 | Change a setting, then tap another window at once: the pick is not lost (§4). Keep the panel closed for 5 min: frame age and RTT unchanged. |

### 8. Implementation order (each step builds and passes its gates before the next)

0. **Preflight.**
   - Branch, and copy this plan into `docs/`.
   - Re-read `StreamMessageKind` (move to the next free pair if 16 or 17 is taken) and the
     coordinator (lines move).
   - Take the H3 CLI baseline and the H19 previews **before any edit**, on the tree that already
    contains the oddities fixes. They change the host's `client …` stats line, so a baseline from
    59fc510 would not match.
1. **Protocol** (commit 1).
   - Add `HostSettings.swift` and kinds 16 and 17.
   - Move `QualityPreset`, and add `import StreamProtocol` to HostSettings.swift,
     StatusItemController.swift and SettingsPanes.swift.
   - Gates: H0, H1, H19.
2. **Host core** (commit 2).
   - Add `DeviceSettings.swift` and `HostStatus.onChange`.
   - In the coordinator: `target`, `setTarget` in place of `apply`, the hook property, the
     handler, state and publish, `deviceName`, the send in `sendCatalog`, the init wiring and the
     MARK comment.
   - Extend `sillclient.py`.
   - Keep the app compiling: the AppModel closure must call `setTarget` in this commit.
   - Gates: H3–H14.
3. **App** (commit 3).
   - The synchronous `onChange` and the device hook in `AppModel.start()`.
   - The `HostSettings` doc comment and closure type, and the `HostConfig` doc comment.
   - Gates: H15–H20. Delete the `SillMenuBar` domain afterwards.
4. **Queued pick** (commit 4, on its own because it changes existing behaviour). Gates: H21, then
   H3 again.
5. **iOS model** (commit 5).
   - `HostSettingsLedger.swift` with its pbxproj entries.
   - The StreamClient section, the `connect(to:name:)` refactor and `-SillConnect`.
   - Gates: H1, H2.
6. **iOS panel** (commit 6).
   - `HostSettingsPanel.swift` with its pbxproj entries.
   - Both bar slots, both placements, `setSettings` and the keyboard handoff,
     `InputOverlayProxy.setKeyboard`.
   - The harness arguments and mock cases.
   - Gates: H1 (Debug and Release), S1–S6. Send Noah the photo sheet.
7. **Docs** (commit 7).
   - CLAUDE.md:
     - the current step;
     - the Layout entries for the new files;
     - the harness line (`-SillSettings`, `-SillSettingsCase`, `-SillConnect`);
     - the new `sillclient.py` flags;
     - "a device's change lasts until SillHost quits";
     - replace "`StreamCoordinator.apply`" with `setTarget`;
     - "Untested, for Noah" = D1–D11.
   - README: a device can change the Mac's settings; Sill.app saves them and the CLI keeps them
     for the session; reset with `defaults delete me.saffer.sill.mac <key>`.
8. **Review and hand over.**
   - Three review lenses, then adversarial verification of H0–H21 and S1–S6:
     - protocol compatibility;
     - concurrency and ordering;
     - the UI at the four sizes plus accessibility.
   - Open the PR against `menu-bar-app` and give Noah D1–D11.
   - **Stop there.** The VPN / public-IP step waits for Noah's approval of this one.

### 9. What step 3 (bring your own VPN or public IP) inherits

- **Connect by address.** `StreamClient.connect(to endpoint:name:)` and DEBUG `-SillConnect`
  already exist. Step 3 adds "Add a Mac by address" and a saved list on the connect screen, not in
  this panel. The panel is titled from `macName`, so it already works for such connections.
- **Remote tuning.** This panel is how a remote user drops to Efficient, Standard or 60 fps on a
  slow uplink. A "Low — 4 Mbps" preset is already valid under `validated()`. It needs a
  `QualityPreset` case on both sides; older devices show it as "Custom — 4 Mbps" until updated.
- **Growth without breaking v1.** Optional fields only:
  - `editable: Bool?` and `readOnlyReason: String?` for pairing, sent per connection (the answer
    path already addresses one device);
  - a Mac `id` for keying saved addresses;
  - read-only reachability (port, addresses).

  None may be device-writable. A device sets stream quality, never network exposure.
- **Timeouts** already scale with RTT (`max(4, 4 × rtt)`). A move to QUIC must keep kinds 16 and
  17 on one reliable, ordered stream, because the answer ordering depends on it.
- **Security prerequisites before any exposure beyond a VPN.** None is needed on the LAN today:
  1. pairing and encryption (M5);
  2. cap the client → host payload length in `StreamServer.receiveLoop`: today a header can
     announce 4 GB and the server waits for all of it, while about 1 MB covers every JSON kind;
  3. rate-limit kind 17 per connection (for example 4 per second; answer the rest unchanged);
  4. keep the whitelist, with no generic defaults write, ever.

---

## Open questions for Noah

Only decisions that change the work. Each has the default the implementation will use if Noah
doesn't say otherwise.

1. **Where the settings open.** Default: **Settings (gear) replaces Leave** in the last slot of
   every bar, and "Disconnect from ‹Mac›" moves to the panel's pinned foot, so leaving takes two
   taps. This reverses the 2026-09-23 Leave button. The alternative keeps one-tap Leave and adds a
   "Settings for ‹Mac›" row at the bottom of the Apps drawer. A sixth bar button is not offered:
   it would cut the outer display's strip from about 2.1 thumbnails to 1.4.
2. **Saving.** Default: **Sill.app saves a device's change like a menu click** (it survives a
   relaunch, and the Mac's Settings window moves). The request says "same as the Mac app". The
   alternative is session-only on both hosts. The CLI is session-only either way.
3. **The virtual display from a device.** Default: **a device may toggle it, with full menu
   parity.** Turning it on moves the streamed window off the Mac's screen. Turning it off brings
   the window home and forward on the Mac. The person at the Mac may not be the one tapping.
   Alternatives: toggle it, but never raise the returning window for a device-initiated change (a
   small flag through `setTarget`); or show it read-only on the device.
