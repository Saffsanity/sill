# Apple Pencil pressure and tilt — the plan

## Status (2026-10-13)

On the branch `pencil-pressure` (from main at 985a733). Built and passing (§13): step 0's
headless half (H0), step 1 (the wire), step 2 (the host), step 3 (the device), step 4 (the
switch's row), step 5 (the documents) and step 6 (the review): an iPad on this build sends its
Pencil to a Mac on this build as a pen, with pressure and tilt, palm rejection is in, and
Settings › This iPad turns it off. Step 0's other half, P0, is Hunter's: its first part passed (the window server
delivers the events whole to an AppKit app), and which drawing apps take them is still open.
P1 to P10 are still open (Hunter has drawn in Affinity, which found the line back to the
start, §13). What is left is Hunter's: P0's per-app run and P1 to P10. Line numbers are 985a733's.

**Rebased onto main (2026-10-20, branch `pencil-pressure-rebased` in Saffsanity/sill).** The pen
is kind 45, not 29: main keeps 29 to 31 free (29 the audio plan's, 30 and 31 pull request #66's),
32 is the clipboard, and open pull requests hold 33 to 44 (#66's, #94's 43, #93's 44). §2 to §9
say 45; §13's results before the rebase say 29, as they were run. §13's last section has the rebase.

**The request:** make Apple Pencil pressure and tilt reach Mac apps, where today the Pencil is only
a mouse.

**Reading of it.** A Pencil on the stream should draw in a Mac drawing app as a tablet pen does:
harder presses give a heavier line, and a tilted Pencil shades. That needs three things Sill lacks:
the device must read pressure and tilt from each touch, the wire must carry them, and the Mac must
post them as tablet events instead of plain mouse events. Everything else about the Pencil stays as
it is: it still clicks, drags and hovers as the mouse.

**The main unknown** is on the Mac, and step 0 settles it before anything else is built: whether
the drawing apps people use take pressure from *synthesized* tablet events (`CGEvent`s with tablet
fields). AppKit apps that read `NSEvent.pressure` should. Apps that talk to a tablet driver
directly may not. If the apps that matter do not, this plan stops after step 0 (§11 has the
fallback, which is a different and larger project).

## 1. What exists today

| Where | What it does | What it lacks |
|---|---|---|
| `InputOverlay.swift:281-338` | A `.pencil` touch is the left button: down, moves, up, each a kind 8 `.pointer` | Never reads `force`, `altitudeAngle`, `azimuthAngle`; never reads `coalescedTouches` |
| `InputOverlay.swift:269` | Pencil hover sends cursor-only moves, told from a trackpad by `zOffset` or `altitudeAngle` | Sends nothing when hover ends; never verified on a device |
| `Input.swift:14` | `InputEvent.pointer(action, x:, y:)` | No field for pressure or tilt |
| `StreamClient.swift:3001` | `sendInput` keeps only the latest move per 8 ms | A stroke loses samples (a Pencil reports 240 a second) |
| `InputInjector.swift:168` | Posts `leftMouseDown` / `Dragged` / `Up` | No `mouseEventPressure`, no tablet subtype, no proximity events |
| `TrackpadView.swift` | The portrait trackpad takes a Pencil as a finger (relative) | Unchanged by this plan |
| — | — | No palm rejection: a hand resting on the glass during a Pencil stroke taps and scrolls the Mac |

Kind 8 is special in six places, and Pencil input in a new kind must be treated the same in each:

1. `StreamServer.swift:1379`: keeps the ticks flowing, counts `inputsRead` (kind 26's `seen`) and
   hands the device the pointer (`PointerWatch.inputArrived`).
2. `SessionLink.swift:99`: `isInput` counts messages whose first byte is 8, for the same `seen`.
3. `StreamCoordinator.swift:894`: the source rectangle, `DroppedInput`, `gestureChords.input`,
   `raiseIfInteracting`, `deliver` and its held queue (`Held`, line 1477), `desktopInputMayActivate`.
4. `StreamClient.sendInput`: `lastInputAt` (the tour's rule), the `inputPaused` tripwire,
   `pointerNoteSent` on the network queue, and `flushPendingMove` before anything but a move.
5. `InputInjector`: the shared `left` button state, multi-click counting, `watch.sillMoved`,
   `lastPointerLocation`, the dry run and its test log, `releaseAll`.
6. `KeyStrokes.swift:300`: `DroppedInput.stillGoes`, the up of a button the Mac has down.

## 2. Decisions

Each is a default the implementer takes unless Noah, Sill's maintainer, says otherwise (§12 lists
the ones that are his call).

1. **A new kind 45, `pen`, device → host.** Not an optional field on `.pointer`: that would keep
   one message per sample (240 small TCP messages a second), give hover's end no message of its
   own, and change every pattern match on `.pointer` in the app and its checks. A new kind batches
   a callback's samples in one message and leaves `InputEvent` alone.
2. **The host advertises it:** `WindowList.pencil` 1, as `gestures` 1 does (`Switcher.swift:55`).
   A device sends kind 45 only to a host that says so; every other host gets kind 8 as today.
3. **Raw values on the wire, the Mac's mapping on the Mac.** The device sends pressure as a
   fraction and the Pencil's angles in radians. The host turns them into what macOS wants. A later
   change to the mapping then needs no new device build.
4. **Every contact sample goes out.** Hover moves keep the latest-only rule; a stroke's samples
   are never dropped, and go as one message per `touchesMoved` callback.
5. **Estimated pressure is sent as it is.** The Pencil's first samples carry an estimate that
   UIKit corrects tens of milliseconds later. An event already posted cannot be amended, and
   latency beats quality, so corrections are ignored.
6. **No predicted touches.** They would have to be unposted.
7. **Palm rejection is part of this.** While a Pencil is down or hovering, and for 0.5 s after,
   finger touches on the stream send nothing. Without it a resting palm ends the stroke: its tap's
   button-up releases the button the Pencil holds.
8. **A device switch, on by default:** Settings › This iPad › "Pencil Pressure"
   (`Sill.pencilPressure`, never sent to the Mac). Off, the Pencil is the mouse as today. It is the
   way out for a Mac app that mishandles tablet events.
9. **The picture only.** A Pencil on the portrait trackpad stays a finger.

## 3. Wire

`Sources/StreamProtocol/Pen.swift`, new. `StreamMessageKind.pen = 45`. JSON, strings not enums,
every later field optional (HostSettings.swift's rules).

```swift
public struct PenInput: Codable, Equatable, Sendable {
    public var phase: String          // "hover", "down", "move", "up", "cancel", "leave"
    public var samples: [PenSample]?  // oldest first; none for "leave"
    public static let generation = 1  // WindowList.pencil from a host that takes this
}

public struct PenSample: Codable, Equatable, Sendable {
    public var x: Double              // fraction of the video frame, 5 decimal places
    public var y: Double
    public var p: Double?             // pressure 0…1 (force ÷ maximumPossibleForce); nil while hovering
    public var alt: Double?           // altitude, radians: π/2 upright, 0 flat on the glass
    public var az: Double?            // azimuth in the frame, radians: 0 points along +x
    public var t: Double?             // ms before the message's last sample; 0 or nil for the last
}
```

Rules:

- "down" and "up" carry exactly one sample. "move" carries one callback's coalesced samples, at most
  32. "hover" carries one. "cancel" is an up where the Pencil last was. "leave" says the Pencil is
  out of range.
- A host skips a phase it does not know, a message with more than 32 samples, and a sample whose
  `x`, `y`, `p`, `alt` or `az` is not finite. `p` is clamped to 0…1.
- `WindowList.pencil: Int?`, nil from every host before. The host sets it to 1 whenever it would
  post input (every host: a synthetic one runs it dry).
- Kind 26's `seen` counts kinds 8 and 45. Both ends change together, and a 45 only ever goes to a
  host that counts it, so the two counts still agree in every mix of builds.

About 60 bytes a sample: 15 KB/s during a stroke.

| Device | Host | What happens |
|---|---|---|
| This | This | Kind 45 for the Pencil; pressure and tilt reach the Mac |
| This | Older (no `pencil`) | Kind 8 as today. The Settings row says "Update Sill on ‹Mac›" |
| Older | This | Kind 8 as today |
| This, switch off | Any | Kind 8 as today |

## 4. Host

### 4.1 `PenTablet` (pure, new: `Sources/SillHost/PenTablet.swift`)

Turns pen messages into the list of events to post. Pure, so `Tests/checks/pen` covers it.

- **Proximity.** A tablet pen is "in proximity" between an enter and a leave event, and many apps
  read pressure only from a pen that entered. The Mac enters lazily, before the first pen event,
  and leaves at the first of:
  - a "leave" from the device;
  - 1 s with no pen message and the tip up (an iPad whose Pencil cannot hover never sends hover,
    so the device's "leave" may be the only other signal);
  - any kind 8 pointer or scroll input from any device (a finger or trackpad click after it must
    not read as a pen);
  - that device leaving, and the host's end (`releaseAll`).
- **The tip.** "down" presses the left button, "up" and "cancel" release it. A down while the
  button is already down, and an up while it is not, post nothing. A device that leaves with the
  tip down gets its up.
- **The mapping**, from one sample:
  - pressure: `p`, but at least 0.01 while the tip is down (some apps read 0 as no contact); 0 on
    the up and while hovering;
  - tilt: with θ = π/2 − `alt`, tilt x = sin θ · cos `az`, tilt y = −sin θ · sin `az` (AppKit's y
    is positive away from the user; the frame's y grows downward). Step 0 checks the sign and the
    scale against AppKit's own reading before this is fixed.

### 4.2 `InputInjector`

- `pen(_ input: PenInput, in rect: CGRect, from device:)` runs `PenTablet` and posts what it
  returns through the existing `pointer(_:at:)`, which gains an optional set of tablet fields. The
  button state, multi-click counting, `watch.sillMoved`, `lastPointerLocation` and the dry run are
  then shared with kind 8, not copied.
- A pen point event is the mouse event Sill posts today (`leftMouseDown`, `leftMouseDragged`,
  `leftMouseUp`, `mouseMoved`) plus `.mouseEventSubtype` tablet point, `.tabletEventPointPressure`,
  `.tabletEventTiltX`, `.tabletEventTiltY`, `.tabletEventPointButtons` and `.tabletEventDeviceID`
  (`PenEvents.stamp`, built in step 0). The mouse event's own `.mouseEventPressure` is set to 0:
  AppKit reads that one when it is not 0, and it holds only 8 bits (§13).
- A proximity event is a `CGEvent` of type `.tabletProximity` with the same device ID, pointer
  type pen, enter or leave, and a capability mask naming pressure and tilt (IOLLEvent.h's
  `NX_TABLET_CAPABILITY_*` values).
- Stats: `in.pen` per sample posted, `in.penProximity` per enter or leave. A dry run counts
  `in.dry` and, with `SILL_TEST_INPUT_LOG=1`, prints each event with its fields ("Test input: left
  mouse dragged (none) at 756,474 pen 0.42 tilt 0.10,-0.30", "Test input: pen enters").
- A message's samples are posted back to back. Step 0 says whether apps need them spaced (§12 Q4).

### 4.3 `StreamServer` and `StreamCoordinator`

- `StreamServer.swift:1379`: kind 45 does what kind 8 does there, with `movesPointer` true.
- The coordinator's `.input` body becomes a helper that both kinds call. A pen message stands in
  as the pointer event it amounts to (down as `.leftDown`, up and cancel as `.leftUp`, the rest as
  `.move`) for `DroppedInput`, `gestureChords.input`, `raiseIfInteracting` and
  `desktopInputMayActivate`. `Held` gains `.pen(PenInput, CGRect, KeyStrokes.Device)`, so a stroke
  that starts during an activation is replayed in order.
- With nowhere to land, only an up or cancel whose down was posted still goes, and a "leave".

Nothing new prints unless a device sends kind 45, so the CLI's output stays byte for byte.

## 5. Device

### 5.1 `PenStrokes` (pure, new: `iOSClient/PenStrokes.swift`)

Decides what goes out, from the touch and hover callbacks. Pure, checked with the host's
`PenTablet` in `Tests/checks/pen`.

- **The mode is fixed per stroke** at the Pencil's down: pen (kind 45) when the switch is on and
  the Mac's `pencil` is 1 or more, else mouse (kind 8, today's path). A stroke never changes mode,
  so its up always matches its down.
- **Samples.** Pressure is `force ÷ maximumPossibleForce`, 0 when the maximum is 0. Angles as
  UIKit gives them. Positions from `preciseLocation(in:)`, normalized as today.
- **"leave".** Sent when hover has ended and, 0.1 s later, the Pencil is neither touching nor
  hovering. Hover ends as the tip lands, and that must not read as leaving.
- **Palm rejection.** `fingersSilent` is true while a Pencil is down or hovering and for 0.5 s
  after. A finger stroke that began while it was true stays silent to its end.

### 5.2 `InputOverlayView`

- The four touch callbacks, for a `.pencil` touch in pen mode: build samples from
  `event.coalescedTouches(for:)` and hand them to a new `sendPen` closure. `.indirectPointer` (the
  iPad's own trackpad or mouse) stays kind 8.
- `handleHover`, for a Pencil in pen mode: "hover" with its angles, and the end of hover into
  `PenStrokes`.
- Each finger handler's guard becomes `guard !strokes.silent, !pen.fingersSilent`. A scroll the
  palm had begun is closed as the Pencil arrives, with no coast, as a three-finger stroke closes
  one today.
- `setOwnPointer(at, .pencil)` is unchanged.

### 5.3 `StreamClient` and `SessionLink`

- `sendPen(_:)` mirrors `sendInput`: `lastInputAt`, the tour's tripwire, then on the network queue
  `pointerNoteSent` with the last sample's position, `flushPendingMove`, and the message. "hover"
  messages share the 8 ms latest-only rule; everything else goes at once.
- `hostPencil: Int?` from each window list, cleared at tear-down, beside `hostGestures`.
- `SessionLink.isInput`: first byte 8 or 45.

### 5.4 Settings

`HostSettingsPanel`, the This iPad group, on an iPad only (an iPhone has no Pencil): the switch
"Pencil Pressure" and a footnote: "Apple Pencil pressure and tilt reach Mac apps that support
drawing tablets.", or "Update Sill on ‹Mac› to use this." for a Mac without `pencil`, or "Apple
Pencil works as a mouse while this is off."

## 6. What does not change

- `InputEvent` and kind 8, the Pencil as the mouse on an older Mac, and the Pencil's hidden arrow
  (the pointer plan's Q2; see §12 Q1).
- The stream. Ink still trails the tip by the glass-to-glass latency, roughly 40–60 ms as measured
  in milestone 2. This plan does not shorten it.
- Sill.app's screen: no setting, no menu item.

## 7. Not in this plan

Barrel roll (Apple Pencil Pro), squeeze, double-tap, the eraser, hover distance, and a local ink
overlay to hide latency. The wire leaves room: each is an optional field or a new phase. Squeeze
and double-tap are a small separate change (`UIPencilInteraction`).

## 8. Steps, one commit each

0. **The probes (§9 H0, P0).** Stop here if P0 fails for the apps that matter.
1. **The wire:** `Pen.swift`, kind 45, `WindowList.pencil`; the checks that pin kind numbers (§9
   H1); `sillclient.py --pen` and `--raw45`.
2. **The host:** `PenTablet`, the injector, the server's count, the coordinator's helper and
   `Held.pen`; `Tests/checks/pen`'s host half.
3. **The device:** `PenStrokes`, the overlay, `sendPen`, `SessionLink.isInput`, palm rejection;
   the check's device half; the `fence` check's count.
4. **The switch** and its footnote.
5. **The documents:** CLAUDE.md (the Current step entry, Layout, Build and run, and the
   compatibility floor: kinds 0–28, 32 and 45, `pencil`, and `seen` counting 8 and 45), `docs/DEVELOPMENT.md`,
   `Tests/checks/README.md`, CI's mutants matrix, `site/privacy.html` (lines 73, 108 and 115 list
   what the device sends, the device's switches and what the log holds).
6. **A review**, then the device tests (§9 P1–P10).

The public claims (README, the site's intro, the App Store description's Pencil bullet) change
only after P1–P4 pass on a device, and the site is republished with them.

New Swift files in `iOSClient/` need their four pbxproj entries by hand, in a free ID block.

## 9. Gates

### Headless

| | Gate |
|---|---|
| H0 | **AppKit's reading of the events, with nothing posted.** `SillHost --pen-selftest`: build the proximity and point events exactly as the injector would, turn each into an `NSEvent(cgEvent:)`, and print what AppKit reads: `subtype`, `pressure`, `tilt`, `deviceID`, `isEnteringProximity`, `pointingDeviceType`, `capabilityMask`. Pass: pressure 0.25, 0.5 and 1 read back as sent; a Pencil leaning right, left, toward and away reads as tilt +x, −x, −y and +y; the enter and leave pair with the point events by device ID. This fixes §4.1's sign and scale. No event is posted and no permission is needed |
| H1 | **The kind numbers.** `compatibility`, `protocol` and `pointer-control` name the pen at 45 and 46 unknown (`pointer-control` sweeps every number); 29 to 31 and 33 stay unknown, as main's checks (`clipboard` among them) say, and `menus` is main's. No mutant renumbers a kind onto 45. (Built on 985a733 the pen took 29, the first free number then; §13's results up to the rebase name 29.) |
| H2 | **`Tests/checks/pen`**, with mutants, in `run-all.sh` and CI's matrix. The wire: each phase's JSON, an older decoder skipping unknown keys, an unknown phase, 33 samples, a non-finite value. The mapping at its edges: force 0, the maximum, a maximum of 0; the Pencil upright, flat, and at each quarter of azimuth. The host's rules: enter before the first point, leave at each of its four causes, a down while down, an up while up, a device leaving mid-stroke. The device's: the mode fixed per stroke, "leave" not sent as the tip lands, palm silence and its 0.5 s. Then random sessions of a Pencil, a finger and a second device against the invariants: every point event lies between an enter and a leave, the button is never left down, every posted down gets one up |
| H3 | **`fence`** counts kind 45 as input in every mode, and **`key-strokes`**' `DroppedInput` cases gain a pen up with nowhere to land |
| H4 | **The CLI's stdout** against main's, masked and sorted, idle 35 s and with a Desktop client: identical |
| H5 | **A dry run end to end.** `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_INPUT_LOG=1 SillHost --synthetic`, and `sillclient.py --pen` sending hover, down, a ramp of moves, up and leave: the log lists "pen enters", the moves with their pressure and tilt, one down and one up, "pen leaves"; then a `--tap` from a second client mid-hover: "pen leaves" before its click. `--pen` and `--raw45` go only to a `--synthetic` host on this Mac, as `--input` does |
| H6 | **Builds:** `swift build -c release`, iOS Debug and Release for the simulator and Debug for a device, only the known warnings; `Tests/checks/run-all.sh`, all |

### Simulator

The simulator has no Pencil. `-SillInputScript` gains `pen down X,Y,P`, `pen move X,Y,P[,ALT,AZ]`,
`pen up` and `pen leave`, which run `sendPen` (only against a `--synthetic` host on loopback, as
its other steps).

| | Gate |
|---|---|
| S1 | The script's stroke against H5's host: the host logs the same events as from `sillclient.py`; against main's host (no `pencil`): kind 8 only, and the console says why |
| S2 | Photos of the Settings group at the iPad's sizes and the largest text size, in its three footnote states; no row on a phone |
| S3 | `Tests/touchrig` if `TouchSynth` can make a `.pencil` touch with a force: a Pencil stroke with a finger landing mid-stroke sends no click and no scroll. If it cannot, this is a device test (P6) |

### On a device (an iPad with an Apple Pencil; Hunter's)

| | Gate |
|---|---|
| P0 | **Step 0's real probe, before anything else is built.** A scratch tool posts one synthetic stroke with a pressure ramp and a tilt sweep into the frontmost app after a countdown. Run it by hand over each app that matters (Krita, Blender's sculpt and Grease Pencil, Photoshop or Affinity, Pixelmator Pro, Freeform) and note which draw a line that swells. Repeat without the proximity events (`--no-proximity`), to learn whether they are needed, and with the mouse event's pressure set too (`--mouse-pressure`, Q8). It posts to the Mac, so a person at the Mac runs it (Hunter did), never an agent session. Built: `PenProbe` (§13) |
| P1 | Pressure in each app P0 passed: a light and a heavy stroke differ, and a stroke starts thin |
| P2 | Tilt in an app with a tilt brush: leaning the Pencil each way shades the matching way |
| P3 | The Pencil is still the mouse everywhere else: click, double-click, drag a window, select text, menus |
| P4 | A fast scribble has no straight segments where samples were lost, on a 60 Hz iPad and a 120 Hz one |
| P5 | Hover on an iPad that has it: the app's brush preview follows; lifting out of range and coming back draws again at once |
| P6 | A palm resting on the glass while drawing: no click, no scroll, the stroke is not cut; half a second after the Pencil lifts, a finger scrolls again |
| P7 | Mid-stroke: rotate, pick another window, drop Wi-Fi: the Mac's button is never left down (a click afterwards is a click, not a drag) |
| P8 | A finger tap, then the trackpad, right after a stroke: plain clicks; Sill.log shows `in.penProximity` moving |
| P9 | Mixed builds: this iPad against Sill for Mac 0.5.1 (the mouse, the "Update Sill" footnote); TestFlight's iPad build against this Sill.app (the mouse) |
| P10 | The switch off: the mouse; on again: pressure, with no reconnect. Frame age and rtt during a long stroke as before; away through the remote door, a stroke still reads |

## 10. Risks

- **Apps that ignore synthesized tablet events.** Step 0 exists for this.
- **A pen left in proximity** makes every later mouse click look like a pen's to some apps. Four
  causes end it (§4.1), and H2's invariant checks each.
- **Two devices.** The host has one left button for all devices. A second device's click during a
  stroke releases it, as it does a finger drag today. Not made worse, not fixed.
- **Burstiness.** Samples arrive in batches and are posted together, so an app that smooths by
  event time sees them bunched. Q4.
- **Palm rejection is a behaviour change** for someone who steadies a hand and taps with a finger
  between strokes: the 0.5 s is the cost. The switch does not turn it off (a mouse-mode Pencil
  drag is cut by a palm too).

## 11. If step 0 fails

The other way to be a tablet on macOS is a virtual HID digitizer (`IOHIDUserDevice`), which the
system treats as real hardware. It needs the `com.apple.developer.hid.virtual.device` entitlement,
which Apple grants on request, and a provisioning profile that carries it; `make-app.sh --release`
already embeds one for the keychain group (docs/keychain-plan.md). It would work only in Sill.app
built with that profile, never in the CLI or a development build. That is its own plan.

## 12. Open questions

| | Question | Default taken |
|---|---|---|
| Q1 | **Decided by Hunter (2026-10-14): shown while hovering, over an app's own cursor.** While drawing, a Mac app's brush cursor is the Mac's cursor, which Sill leaves out of the video, and the device's own arrow was hidden for the Pencil (the pointer plan's Q2). So a hovering Pencil previewed no brush | The arrow shows while a Pencil hovers as a pen over an app's own cursor (a brush outline), never over a standard one, and hides as the tip lands (§13, "The cursor while hovering" and "Only an app's own cursor"); the mouse-mode Pencil keeps Q2 |
| Q2 | The device switch | Yes, on by default (§2.8) |
| Q3 | The pressure floor of 0.01 while the tip is down | Yes; P0 says whether any app needs it |
| Q4 | Space a batch's samples in time (set each event's timestamp from `t`, or post them `t` apart)? | Back to back. Revisit if P4 shows uneven strokes |
| Q5 | Set the tablet's absolute position fields (`tabletEventPointX`/`Y`)? | Left unset, and not probed: they are in tablet units, and Sill has no tablet whose range an app could scale them by. The capability mask does not claim them |
| Q8 | The mouse event's own pressure: 0, so AppKit reads the tablet point's 16 bits (§13), or set too, for an app that reads the mouse event's field itself and would see 0? | 0. P0 tries both (`--mouse-pressure`) |
| Q6 | The palm rule's 0.5 s | 0.5 s |
| Q7 | A pressure curve (a softness setting) | None: linear. Mac apps have their own |

## 13. Results

### Step 0, the headless half (2026-10-13)

Built: `Sources/SillHost/PenEvents.swift` (the tablet fields of a pen's point and the proximity
event; building only, nothing posts), `PenSelfTest.swift` (`SillHost --pen-selftest`, H0) and the
`PenProbe` target (`Sources/PenProbe/main.swift`, P0's tool; not shipped). No existing source
changed but the CLI's `main.swift` (the flag) and `Package.swift` (the target).

**H0 passes: 37 readings, exit 0** (macOS 27.0.1, 26A434). Each event is built, serialized, read
back and turned into the `NSEvent` an app would get; nothing is posted.

- Proximity, entering and leaving: AppKit reads `tabletProximity`, a pen (`pointingDeviceType` 1),
  the device ID and the capability mask 0x581 as written.
- A point on a down, a drag, an up and a move, at pressures 0, 0.01, 0.25, 0.5 and 1: subtype
  `tabletPoint`, the pressure within one 16-bit step, the device ID.
- Tilt reads back one for one, sign and scale: ±1 on each axis, and 0.3, 0.7.
- A plain drag, as Sill posts today, is no tablet point.

**Found: where the pressure goes matters.** On a tablet point AppKit's `NSEvent.pressure` is the
mouse event's own pressure when that is not 0, and the tablet point's only when it is 0. The mouse
event's holds 8 bits (0.25 reads 0.2471, 63 of 255), the tablet point's 16. A down and a drag are
made with a mouse pressure of 1, so a tablet pressure alone reads 1.0 on them. So `PenEvents.stamp`
writes the pressure to the tablet point and sets the mouse event's to 0, and H0 pins both halves
of the rule (three of its readings are the 8-bit case). What an app that reads the mouse event's
field itself then sees is 0: Q8, and `--mouse-pressure` in the probe.

**Not settled by H0:** what one unit of tilt means in degrees. AppKit documents −1…1; H0 shows
only that what is written is what is read. P2 settles it with a tilt brush.

**The probe, `PenProbe`.** With no arguments it says what it would do and posts nothing. `--canvas`
opens a window that draws what it receives (line width from pressure, colour from tilt) and prints
each stroke's readings. `--canvas --self` hands that window the three strokes inside its own
process and checks what it read: 5 of 5, exit 0 (the control no tablet point; pressure 0.020…1.000,
finer than 8 bits; tilt −0.99…1.00; two enters and two leaves). That checks the canvas, not
delivery: an event posted to a process (`postToPid`) or handed to `NSApp.sendEvent` reached the
canvas as proximity but not as a mouse event, since the window server is what gives a mouse event
its window. Delivery through the window server is exactly what P0 tests.

### P0, for Hunter

It posts three left-button drags where the pointer is, after a countdown, so it is run by hand.
The terminal needs Accessibility (it asks the first time). Build once:

    swift build -c release --product PenProbe

1. **The canvas first**, to see delivery itself with no third-party app. In one terminal
   `.build/release/PenProbe --canvas`; in another `.build/release/PenProbe --post-to-this-mac`,
   then within 5 s click the canvas window and rest the pointer near its left edge. Pass: line 1
   thin and grey, line 2 swelling in the middle, line 3 changing colour along its length, and the
   canvas prints "tablet points", "finer than 8 bits" and a proximity enter and leave.
2. **Each drawing app** (Krita, Blender's sculpt mode and Grease Pencil, Photoshop or Affinity,
   Pixelmator Pro, Freeform): a brush whose size follows pressure, the pointer at the left of an
   empty canvas, then `.build/release/PenProbe --post-to-this-mac`. Note per app whether line 2
   swells and whether line 3 changes with a tilt brush.
3. **For an app where line 2 does not swell**, again with `--mouse-pressure`, and with
   `--no-proximity` for one where it does (to learn whether proximity is needed).

`--only pressure` posts one stroke, `--length 250` a shorter one, `--countdown 10` leaves more
time; Ctrl-C stops it with the button up.

### Step 1, the wire (2026-10-13)

Built: `Sources/StreamProtocol/Pen.swift` (`PenInput`, `PenSample`), `StreamMessageKind.pen` 29,
`WindowList.pencil`, and `sillclient.py`'s `--pen=PHASE[,X,Y[,P[,ALT,AZ]]]@T` and `--raw29=JSON@T`
(only to a `--synthetic` host on this Mac, as its input flags). No host sets `pencil` yet and none
acts on kind 29: that is step 2, so that no commit advertises what it does not do.

Beyond §3 as first written:

- **`checked()`** is the one rule for what a host acts on, in the protocol file so both ends and
  the checks share it: a known phase, at most 32 samples, the count its phase allows (one for
  "hover", "down" and "up"; one or more for "move"; none or one for "cancel"; "leave" drops any),
  every value finite, the pressure clamped to 0…1, the altitude to 0…π/2, a time never negative. A
  position off the frame is passed on, as for kind 8. One bad sample skips the whole message.
- **Rounding** at the device: a position to 5 decimal places, pressure and angles to 4, a time to
  0.1 ms.

Verified:

- H1: `compatibility` 147 checks (93 before: 54 for the Pencil), `protocol`, `menus` 309 and
  `pointer-control` 157 pass; 29 is `pen` in each and 30 the first unknown kind. The three
  mutants that renumbered a kind onto 29 use 30 and 31. `compatibility`'s mutants: 38 of 38 caught (19 new, of
  `Pen.swift`, kind 29 and `pencil`).
- `swift build -c release`, only the CaptureProbe warning; the iOS app for the generic simulator
  as CI builds it, only the known `StreamClient` warning.
- Against a `--synthetic` host on loopback with the software encoder: a hover, a down, a move, an
  up, a leave and an unknown phase are each skipped without a line, and the session goes on.
- `sillclient.py` refuses, before it connects, a phase it does not know, a down without a
  position, a leave with one, a non-finite number, and any host that is not a `--synthetic` one
  on this Mac.

### P0, the canvas (2026-10-13, run by Hunter)

`PenProbe --post-to-this-mac`, twice, over `PenProbe --canvas` (macOS 27.0.1): **delivery works.**
Posted at the HID event tap and routed by the window server, the events reached an AppKit view
as built:

- the pressure stroke: 300 drags, all tablet points, pressure 0.020…1.000, finer than 8 bits (the
  tablet point's 16, as H0 predicted with the mouse event's own pressure at 0);
- the tilt stroke: 300 drags, all tablet points, tilt x −0.99…1.00 at pressure 0.5;
- a proximity enter before each pen stroke and a leave after it, as a pen (`pointingDeviceType`
  1) with the device ID;
- the control: 298 drags, none a tablet point, pressure 1.0. (Two of its 300 drags did not
  arrive as drags; the pen strokes lost none. Not looked into: it is today's mouse path.)

So an app that reads `NSEvent`'s pressure and tilt gets them. Still open: the third-party drawing
apps (step 2 of "P0, for Hunter"), and with them `--no-proximity` and `--mouse-pressure`.

### Step 2, the host (2026-10-13)

Built: `Sources/SillHost/PenTablet.swift` (pure: what the Mac posts for each message),
`InputInjector.pen` and the tablet fields on its pointer path, StreamServer counting kind 29 as
input, the coordinator's `.pen` case with `Held.pen`, `pencil` 1 in every window list, and
`Tests/checks/pen` (in `run-all.sh` and CI's mutants matrix). `PenPoint` moved from PenEvents to
PenTablet, which decides it.

What §4 left open, as built:

- **Whose pen.** While one device's tip is down, another device's pen messages post nothing. With
  the tip up, any device's pen takes over, already in range. A leave counts only from the device
  whose pen it is.
- **Messages out of order.** A hover with the tip down (its up was lost) is the button's up,
  there. A move with the tip up (its down was lost) moves without pressure. A leave with the tip
  down is the up, then the leave.
- **The left button coming up under the pen's stroke** (kind 8, from another device or as
  dropped input's up) ends the stroke: the pen leaves, and the up that follows is the mouse's.
  This is the one time the pen leaves with its button down.
- **With nowhere to land** an up, a cancel and a leave still go (`PenTablet.stillGoes`), the up
  where the pointer is. This rule is PenTablet's and the `pen` check's, not `DroppedInput`'s and
  `key-strokes`' as H3 had it: `InputEvent` and its rules are untouched.
- **No pressure in a sample** with the tip down reads as full, as a mouse's.
- A sample's `t` is not used yet: a message's samples are posted back to back (Q4).
- A pen's point counts as `in.pen` in the stats line, not `in.pointer`; an enter or a leave as
  `in.penProximity`.

Verified:

- H2 (the host half): `pen` 149 checks and 5,000 random sessions of two devices' pens and mouse
  input against a model (every point between an enter and a leave; every down the pen posted
  with exactly one up; no mouse input with the pen in range and its tip up; the host's end
  leaving nothing); mutants 53 of 53. The first run caught 52: a repeated down was only refused
  through the button's state, and the check now pins the pen's own.
- H4: the CLI's output against main's (985a733, built from `git archive`), masked and sorted,
  idle for 35 s and with a Desktop client: identical (8 and 24 lines), each host on a pty so no
  line is lost in a buffer when it is killed.
- H5, on a `--synthetic` host on loopback (software encoder, the scripted pointer, the input log;
  nothing posted): a hover, a down, three samples in one move, an up, a hover print "pen enters",
  the move's tilt 0.70, the down at pressure 0.200, drags at 0.400, 0.800 and 1.000 with tilt
  0.54,0.00, 0.00,−0.88 and −1.00,0.00, the up at 0, the hover; a tap from the client then prints
  "pen leaves" before its plain move, down and up; a down, an unknown phase (skipped) and a hover
  1.3 s later: the enter, the down, the button's up at the hover's place, and "pen leaves" a
  second after. A client that leaves mid-stroke: the button's up where the pointer was, then
  "pen leaves". With nothing streaming, a down, an up and a leave post nothing.
- `swift build -c release`, only the CaptureProbe warning; `SillHost --pen-selftest` still 37 of
  37; `Tests/checks/run-all.sh`, all 41.

Not run: a real host posting (Sill.app or SillHost without `--synthetic`), which waits for a
device that sends kind 29 (step 3), and the idle leave's timing on a busy main thread.

### Step 3, the device (2026-10-13)

Built: `iOSClient/PenStrokes.swift` (pure: the mode, the samples, the leave, the palm rule),
`InputOverlayView`'s Pencil path (`pencilHover`, `pencilDown`, `pencilMoved`, `pencilUp`, under
its touch and hover callbacks) and palm guards, the portrait trackpad's palm guards,
`StreamClient.sendPen`, `pencilAsPen`, `hostPencil` and `penLink`, `SessionLink` counting kind 29,
and DEBUG `-SillInputScript`'s `pen` steps. pbxproj AC01/FC01.

Where it differs from §2 and §5, and why:

- **Palm rejection is for the tip on the glass, not for a hover** (§2.7 said down or hovering). A
  hovering Pencil silences nothing: the other hand must still be able to scroll while the Pencil
  waits above the canvas. The rule (`PenStrokes.Palm`): every finger stroke under way while the
  tip is down says nothing, to that stroke's end, and so does one that begins within 0.5 s of the
  lift. Judged by when the finger stroke's first finger landed (`StrokeObserver.strokeBeganAt`),
  so a palm that stays down after the Pencil lifts never clicks as it leaves. Known gap: a palm
  that rests for 0.45 s before the tip first lands is a long press, a right click, before any rule
  can know a Pencil is coming (P6).
- **The portrait trackpad is covered too** (§2.9 left it alone): in the laptop layouts the hand
  that holds the Pencil rests on the pad under the picture, and its motion would move the Mac's
  pointer mid-stroke. The pad's own press-and-hold drag is never silenced, since its button must
  come up. The key row is not covered: its caps are buttons, and a palm on one presses it.
- **The leave** goes only from a Pencil that has been seen to hover: 0.1 s after it stops
  touching or hovering, if it is doing neither. A Pencil that cannot hover says nothing between
  strokes and the Mac lets its pen go after a second (`PenTablet.idleLeave`), so quick strokes
  stay one pen in range. The surface going away tells the Mac too.
- **A down off the picture** (the letterbox) sends nothing, as for the mouse; the stroke's moves
  then reach the Mac with its tip up, as a hover's.
- **A hover** goes as pointer moves go, the newest only, at most one per 8 ms, on the same slot.
- A callback that brings more than 32 readings (after a stall) sends them all, in messages of 32.

Verified:

- H2 (both halves): `pen` 204 checks and 5,000 random sessions; the device's cases include a
  hover, a stroke and a leave sent by PenStrokes and posted by PenTablet, through the wire's JSON.
- H3: `fence` passes its 17 modes with every third input an Apple Pencil's message (kind 29),
  counted as kind 8 is on both ends.
- S1, in a private simulator (iPad Pro 11-inch, iOS 27.0; deleted after) with the normal client
  and `-SillInputScript`'s pen steps, against `--synthetic` hosts on loopback (software encoder,
  the input log; nothing posted). Against this branch's host: every step "a pen's", and the host
  logs the pen entering, the hover's tilt 0.70, the down at 0.200, drags at 0.500 and 0.900, the
  up, a hover, "pen leaves" before a finger's tap and its plain click, then the pen entering and
  leaving again. Against main's host (985a733, no `pencil`): every step "the mouse's", and the
  host logs only plain moves, a down, a drag and an up, as before. With `-Sill.pencilPressure 0`
  against this branch's host: the same.
- The iOS app, Debug and Release for the simulator: only the known `StreamClient` warning.
  `swift build -c release` as before. `Tests/checks/run-all.sh`, all 41.

Not run, and not runnable here: a real Pencil. So untested: what `UITouch` gives (force, its
maximum, the angles, 240 coalesced readings a second), the hover recognizer's angles and its end
as the tip lands, the 0.1 s leave on a hover-capable iPad, and all of palm rejection (the
simulator has no Pencil, and the script drives the code under the touch callbacks, not the
callbacks). S3 was not attempted: P6 covers it.


### The line back to the start (2026-10-13, found on Hunter's iPad)

Hunter, drawing in Affinity on an iPad Pro 13-inch (M4) with iPadOS 27.0.1, saw every stroke end
with a straight line back to where it began, in main's build (the Pencil as the mouse) and in step
3's (as a pen). Found with the device's console (`devicectl device process launch --console`) and
the Mac's log, both carrying tagged lines for the run, read by a script that judges each stroke:
red in 5 of 5 strokes. As the tip lifts, iPadOS sends one more hover update while the touch is
still down, about a millisecond before `touchesEnded`, and it carries where the Pencil hovered
before it landed, the stroke's start (in 6 of 6 strokes, its place within a point of the last
hover before the down). `handleHover` sent it as a pointer move (kind 8, in both modes: in pen mode
a hover during a stroke fell through to the mouse's path), and with the Mac's button still down it
was a drag back to the start.

Fixed: `PenStrokes.hover(isPencil:penMode:)` answers `.pen`, `.mouse` or `.ignore`, and any hover
while a Pencil touch is down is ignored, in both modes, nor does it count as hovering. Verified: the
`pen` check's new cases fail 8 times on the rule as it was and pass now (215 checks), and the `pen` mutants 90 of 90 caught (the rule as
it was among them); on Hunter's iPad again with the same logs, 5 of 5 strokes green, the stale update still
arriving in each and none sent on. The logging is gone.

### Step 4, the switch (2026-10-13)

`HostSettingsPanel`'s This iPad group, on an iPad only: a "Pencil Pressure" switch
(`@AppStorage(StreamClient.pencilKey)`, on unless turned off, read as each stroke begins, never
sent) in rows of its own under the gestures' footnote, before Take the Tour, and §5.4's three
footnotes: "Apple Pencil pressure and tilt reach Mac apps that support drawing tablets.", "Update
Sill on ‹Mac› to use this." (a window list without `pencil`, or at a lower generation) and "Apple
Pencil works as a mouse while this is off." The mock Mac takes a pen in every settings case but
`legacy`; DEBUG `-SillSettingsScroll pencil` starts the rows at the switch.

Verified (S2): iOS Debug and Release for the simulator and Debug for Hunter's iPad, only the
known `StreamClient` capture warning; photos on a private iPad mini simulator (iOS 27.0, deleted
after) at 1000×710 and 710×1000 in the three states (on, `legacy`, `-Sill.pencilPressure 0`), and
on at the largest accessibility text size; on a private iPhone 17 Pro Max simulator at 956×440, the
panel's end has no Pencil row. No pure check covers the panel; `PenStrokes.penMode` (the `pen`
check) already reads the switch. Not run: the switch flipped mid-session on a device (P10).

### Step 5, the documents (2026-10-13)

- CLAUDE.md: a Current step entry; the compatibility floor at kinds 0–29 (Pen.swift's JSON, kind
  29 only to a host whose window list says `pencil` 1 or more, its six phases and 32 samples,
  `checked()`, and kind 26's `seen` counting kinds 8 and 29); Build and run's harness line gains
  `-SillSettingsScroll pencil` and `-Sill.pencilPressure 0`. Layout and the rest of Build and run
  had the Pencil since steps 0–3.
- docs/DEVELOPMENT.md: an "Apple Pencil" section after Trackpad gestures (what reaches the Mac,
  hover and the leave, palm rejection and its gap, the switch, the stats keys, `--pen-selftest`
  and `PenProbe`); the Settings paragraph, the pure checks' list, the test client's `--pen` and
  `--raw29`, the harness's Pencil arguments, and three probes in Layout.
- site/privacy.html: what the device sends gains the Pencil's strokes with pressure and tilt, and
  what it keeps gains Pencil Pressure. The log's line is unchanged: the Mac's log has no line of
  the Pencil's own (a pen's down is a "Click at …" line, as any click; the stats lines count its
  events; the input log's pen lines are TEST ONLY). The page's
  "Last updated" date is left for the day the site goes out with it.
- `Tests/checks/README.md` and CI's mutants matrix had `pen` since step 2.

The public claims (README, the site's intro, the App Store's Pencil bullet) wait for P1–P4, as §8
says.

### Step 6, the review (2026-10-13)

One pass over the branch against main (985a733), read by layer: the wire (`Pen.swift`, kind 29,
`WindowList.pencil`), the host (`PenTablet`, `PenEvents`, the injector, StreamServer's count, the
coordinator's rules, `Held.pen` and the dropped-input path), the device (`PenStrokes`, the
overlay's touch and hover callbacks, `sendPen` and the shared move slot, the palm guards on both
surfaces, `SessionLink`), the switch, the tools (PenProbe's guard, `sillclient.py`'s), the checks
and the documents. Threads: InputInjector and the coordinator are main-actor, so the idle-leave
task runs there; the device's palm and strokes are main-thread only.

Fixed:

- **The documents said the Mac's log names no Pencil event.** A pen's down in a streamed window
  goes through `logClick` and is a "Click at …" line (at most one a second), as a finger's tap is.
  DEVELOPMENT.md, CLAUDE.md and step 5's note now say so; the privacy page's log line already
  covers it.

Left, with the reason:

- **`iOSClient/Sill.xcodeproj/project.xcworkspace/contents.xcworkspacedata`** came in with
  38fc2f6. It is Xcode's default and harmless, but main never tracked it, so a pull request would
  add an unrelated file: `git rm --cached` it before one (Hunter's commit).
- **A leave, and a cancel without a sample, open the pointer's settle.** StreamServer counts every
  kind 29 as moving the pointer (`movesPointer`), where the device counts a leave as `.other`. The
  effect: a Mac mouse move in the 0.25 s after a Pencil leaves is the Mac's a beat later. Telling
  them apart means decoding kind 29 on the network queue for no visible gain.
- **A pen down while another source holds the left button** (the portrait trackpad's
  press-and-hold drag, under the same hand) is refused, and the stroke's moves then drag without
  pressure. Two pointers on one button; no rule makes both right.

For the device tests:

- P5: a hovering Pencil held still for over a second sends nothing (UIKit reports hover on
  movement), so the Mac's idle leave (`PenTablet.idleLeave`) takes it out of range and the next
  hover update brings it back. Note whether an app's brush preview blinks.
- P1: pressure is the force over its maximum, linear (Q7). Note whether ordinary strokes read
  light in the apps.
- P6: the known gap, a palm resting before the tip first lands.

Verified on the reviewed tree: `swift build -c release` (only the CaptureProbe warning);
`SillHost --pen-selftest` 37 of 37; `Tests/checks/run-all.sh`, all 41; the mutants of every check
the branch changed: `pen` 90 of 90, `compatibility` 38 of 38, `fence` 33 of 33, `menus` 43 of 43,
`pointer-control` 33 of 33; the iOS builds as at step 4. The host has not changed since step 2,
whose H4 and H5 stand.

### Sidecar's behaviour, and the edge cases (2026-10-14)

Hunter asked for the review's edge cases to follow Sidecar. Nothing written says how Sidecar
handles them, so it was recorded: a read-only recorder (an AppKit window on the Sidecar display
with local and global event monitors, posting nothing; in the session's scratchpad, not in the
repository) logged every pointer, tablet and proximity event while Hunter ran eight steps on
an iPad Pro 13-inch (M4) with iPadOS 27.0.1, macOS 27.0.1. Step 4 was done twice; the second try
counts.

What Sidecar does:

- **Proximity.** An enter as the Pencil comes within hover range (with a `mouseMoved` of subtype
  2, tabletProximity, at the same place), then `mouseMoved` events of subtype 1, tabletPoint, with
  pressure 0, tilt and rotation, every 16.7 ms (60 Hz) **while it hovers, held still or not**: 3 s
  held still had no gap over 22 ms. The leave comes 17 ms after its last point as it goes out of
  range. Strokes lifted well away between them: an enter and a leave around each.
- **A stroke.** `leftMouseDown`, `leftMouseDragged`, `leftMouseUp`, all subtype 1, the down at
  pressure 0.0784 every time, then the reading; pressure in 8-bit steps (n/255) in both the mouse
  event's field and the tablet point's. Device ID 15203, capability mask 0x35c7, pointer type pen.
- **The Mac's button held, then the Pencil (step 4).** The Pencil's hover posts `mouseMoved`
  (not a drag) while the trackpad holds the button; its touch posts its own `leftMouseDown`
  though the button is down, and drags with pressure. When the trackpad lets go (its
  `leftMouseUp`, subtype 3), the Pencil's stroke goes on, `leftMouseDragged` with pressure while
  the system reads no button down, and ends at the Pencil's own `leftMouseUp`.
- **The Pencil down, then a Mac click (step 5).** The trackpad's up arrives mid-stroke; the stroke
  goes on as above to the Pencil's own up. The trackpad's moves meanwhile are `mouseMoved`.
- **Fingers (step 6).** One finger's tap or drag and a resting palm post nothing at all. A palm
  resting while the Pencil draws (step 7): only the Pencil's events.
- **The Mac's pointer moved while the Pencil hovers (step 8).** The pen stays in range throughout;
  its hover points pause while the trackpad moves and resume after.

Sill now does the same, but for fingers (direct touch is Sill's model: a tap is a click, and the
palm rule stays):

- **The pen's button is its own.** InputInjector keeps a button state for the pen apart from
  kind 8's (`penButton`): its move is a drag exactly while its tip is down, its down goes
  whoever holds the left button, its up is its own. PenTablet's `take` lost `leftDown`, and
  `stillGoes` judges by the pen's tip.
- **Mouse input never touches the pen.** `PenTablet.mouse` is gone: no leave before kind 8 input,
  and the left button coming up under a stroke no longer ends it.
- **A hovering pen does not time out.** `PenTablet.hovering`: while the last message was a hover,
  `leavesIn` is nil, and the pen leaves by its leave (sent 0.1 s after the Pencil is neither
  touching nor hovering), the device leaving or the host's end. The second's timeout stays for
  the case it was for: an up with no hover after it (a Pencil that cannot hover), and a move with
  the tip up. The device repeats nothing: Sidecar's held-still points move no pointer, and a
  repeat every half second would pull the Mac's pointer back while someone else moves it.
- **A leave opens no pointer settle** (the review's first edge case, before the recording):
  `PenTablet.movesPointer`, used by StreamServer: a message without a sample moves nothing.

Not followed: Sidecar's 8-bit pressure (Sill sends the tablet point's 16 bits, H0), and its fixed
first pressure. Not sent by Sill: rotation (barrel roll, which Sidecar sends; §7 keeps it out).

Verified: `pen` 197 checks and 5,000 random sessions, the model now with the pen's own button
(never a leave with it down, every down with exactly one up), new cases for each rule above and
for a minute's hover held still and for a stroke after a hover, 92 of 92 mutants caught (re-made
for the rules: the settle, the hover's timeout; the old mouse rules' gone; the first run caught 87,
and the three cases that survived were added); `Tests/checks/run-all.sh`, all 41; `swift build -c release`; a dry run on a `--synthetic` host
(loopback, software encoder, the input log): a kind 8 down, then the pen entering, hovering as a
plain move, its own down at 0.300 while the button is held, a drag, kind 8's up, the pen dragging
on at 0.700 and its own up; a tap while it hovered (plain click events, no leave); the pen
hovering 4.2 s with no message and staying in range until its leave.

### Rebased onto main (2026-10-20)

Noah: "Work on Apple Pencil pressure (the contributor's work needs a free message number, 44 or
above, since every lower one is now claimed by open pull requests)." The branch
`pencil-pressure-rebased` in Saffsanity/sill starts at main's d1fa97e. Its first commit (593cc12) is
the stale hover of "The line back to the start" on main's mouse path alone (`pencilTouching`), so it
can land ahead of the rest. Then Hunter's five commits, merged as they are (328314f: never rebased
or squashed, each keeping its author), then the maintainer's commits, and main again at 9a8e30c
(#136; only ci.yml's matrix conflicted).

The merge: eighteen files conflicted, every resolution keeping both sides. Main had gained the
clipboard (#78), the hardware keyboard and trackpad (#80) and Larger Picture (#79) since 985a733:

- `WindowList` keeps `clipboard` and gains `pencil`; one init takes both, and the coordinator's list
  sends both. compatibility's mutants follow the new init.
- `handlePan`: #80 moved the finger pan's body onto `scroll(gesture, .finger)`, a path it shares
  with the iPad's trackpad and a wheel. The palm guard stays in `handlePan`, before that call, so a
  palm silences fingers only.
- The stale-hover flag of 593cc12 gives way to `PenStrokes.hover`, the same rule in both modes
  (`gone()` resets it as the view leaves its window).
- Settings › This iPad: Larger Picture (an iPhone's), Share Clipboard, the gestures, then Pencil
  Pressure (an iPad's). `-SillInputScript` has #80's steps and the pen's. sillclient.py has the
  clipboard's flags and the pen's.

After the merge:

- **Kind 45.** 29 was free on 985a733. On main the clipboard's comment and checks keep 29 to 31
  free (29 the audio plan's, 30 and 31 #66's side streams), 32 is the clipboard, and open pull
  requests hold 33 to 44 (#66's 33 to 42, #158's 33 too, #94's 43, #93's `keyframeRequest` 44:
  read at every open head on 2026-10-20, #93's at 09549b3). 45 is in no head. `case pen = 45`;
  SessionLink counts 8 and 45; sillclient.py's `--raw45`; the docs; the compatibility floor's kinds
  0–28, 32 and 45.
  The checks: compatibility (kind 45, 46 unknown, the mutant "kind 45 as 46"), protocol (main's two
  kind checks kept, the pen at 45 and 46 unknown), pointer-control (the table and the sweep), fence
  (input and the two C10 mutants at 45). menus' line and mutant and pointer-control's two
  renumbering mutants are main's again, 29 being free once more; clipboard passes unchanged.
- **Project IDs.** PenStrokes.swift had A1000001000000000000AC01 and …FC01, which #80 gave
  HardwareKeyboardPolicy.swift. The project merged without a conflict but then held each ID twice,
  xcodebuild skipped one file ("Skipping duplicate build file") and the build failed on
  HardwareKeyboardPolicy. Now A045/F045, in no project file on main or at any open head.
- **The workspace file** (be8abf4 untracked it, a85fba7 brought it back): out.
- **The site.** privacy.html's two Pencil items now stand alone between `<!-- Pencil: …` and
  `<!-- /Pencil -->`, as the clipboard's are, and docs/release-checklist.md part 1 §3 cuts them
  before the Pencil's release. Checked on a copy: after the cut, site/ is main's byte for byte.
- **sillclient.py** prints `pencil=` on the window list's line.
- **Docs.** §2 to §9 say 45 (the results above say 29, as they were run); Hunter and Noah by name
  where the plan said "the owner"; the pen check's header after Sidecar's rules; CLAUDE.md's entry
  as a Current step entry.

Verified (2026-10-20, on a Mac busy with other sessions, load averages of 30 to 990):

- **Builds.** `swift build -c release` from `git archive` of the branch, only the CaptureProbe
  warning; the iOS app for the simulator in Debug (CI's command) and Release and for a generic device
  in Debug, only the known StreamClient capture warning, PenStrokes.swift compiled and no file
  skipped. 593cc12 alone builds too (Debug, the simulator).
- **`SillHost --pen-selftest`:** 37 ok, "All readings are what was written.", nothing posted.
- **The checks.** `Tests/checks/run-all.sh`, all 46 (#136's `installed-apps` among them). `pen` 197
  checks and 5,000 random sessions, 92 of 92 mutants; `compatibility` 157, 41 of 41;
  `pointer-control` 158, 33 of 33; `protocol` 193 and the 8 cross-checks, PROTOCOL of 24; `menus` 309,
  43 of 43; `fence` its 17 modes, 33 of 33; `clipboard` 259; `key-strokes` 347;
  `pointer-presence` 165; `gestures` 156; `message-reader`; `hardware-keyboard` 51.
- **H4**, the CLI's stdout against main's (9a8e30c; both from `git archive`, `--synthetic` on
  loopback with the software encoder): idle for 35 s identical masked and sorted (7 lines); with a
  Desktop client, three runs: one identical (32 lines), two identical but for the per-second stats
  lines, whose seconds fell differently (the second the client left; the software encoder stalling
  under the machine's load, four times in each build alike).
- **H5**, a dry run (`SILL_TEST_INPUT_LOG=1`, a scripted pointer) fed by `sillclient.py`: this
  host's window list says `pencil=1`, and its log reads the pen entering, a hover at tilt
  0.47,0.26, the down at 0.200, drags at 0.400, 0.800 and 1.000 with their tilts, the up at 0.000, a
  hover, a finger's tap as plain mouse events with no leave before it, and the pen leaving at the
  device's leave. Main's host says no `pencil`, skips kind 45 and logs the tap alone.
- **S1**, on a private iPad Pro 13-inch (M4) simulator (iOS 27.0, deleted after) with `-SillLive 1
  -SillConnect` and `-SillInputScript`'s pen steps: against this host every step went "a pen's" and
  the host logged H5's sequence; against main's every step went "the mouse's" and the host logged
  plain moves, a down, drags and an up. The mock's Settings panel shows Pencil Pressure under the
  gestures, before Take the Tour.

Not run here: anything on a device (P0's per-app run, P1 to P10), and with them, on this rebase, a
finger's scroll, the iPad's trackpad and a wheel beside the Pencil, and the This iPad group with Share
Clipboard on a real iPad. The open questions (§12) keep their defaults.

### The cursor while hovering (2026-10-14, Q1)

The owner, drawing in Affinity: hover works, but nothing on the iPad shows where the Pencil is,
while the Mac's own screen shows the cursor. Decided: show it.

`PointerPresence.Origin.penHover` (pure): while this device's Pencil hovers as a pen (kind 29) the
sprite shows where it hovers, in every layout, in the Mac cursor's shape (kind 14), so a drawing
app's brush outline is under the Pencil when the app makes it its cursor (one that draws the outline
into the canvas already shows it in the video). The tip landing sets `.pencil` again, hidden as Q2
decided (no arrow under the tip while it draws), until the next hover. After the Pencil leaves range
the arrow stays where it last hovered, as a pointer at rest does, until other input moves it. A new
frame size does not move a hovering Pencil's pointer to the middle (`recentresOnNewFrame`): its next
hover says where it is. The mouse-mode Pencil (the switch off, an older Mac) is unchanged: hidden.
The Mac's own screen always shows its cursor: it is the one pointer, and Sidecar's is the same.

Verified: `pointer-presence` 183 checks (new: the hover shown in both layouts with and without Q2's
flip, hidden again as the tip lands, the Mac's arrow once it moves it, no re-centring) and 46 of
46 mutants caught (three new); the iOS app for the simulator and for the owner's iPad, installed. DEBUG:
`-SillPointer pen@X,Y`.

On the owner's iPad through Sill (2026-10-14, `PenProbe --canvas`, device ID 20753 = 0x5111,
Sill's): three strokes, every drag a tablet point, pressure finer than 8 bits (0.015…1.000), tilt x
0.36…0.51 for the owner's natural grip, the sign Sidecar gave the same grip (0.39…0.69 in the
recording); an enter before each stroke and a leave after, and an enter and leave for a hover alone.

### Only an app's own cursor (2026-10-14, Q1 refined)

The owner, with the hover cursor on: Affinity's brush outline shows under the Pencil, but the arrow
should stay hidden in ordinary apps, as Noah first decided (the pointer plan's Q2). So the Mac now
says whether its cursor is one of macOS's standard ones.

Measured first (`NSCursor.currentSystem` polled while the owner visited cursors with the Mac's
trackpad; scratch probes, posting nothing): the window server's arrow (28×40) and I-beam (23×22)
carry 1×, 2×, 5× and 10× images, but its pointing hand, resize and other standard cursors only 1×
and 2×, so the number of images alone cannot tell; compared pixel for pixel with AppKit's own
standard cursors in the same process (a Hasher differs between processes), the arrow, the I-beam,
the pointing hand and two window-edge resize cursors matched, and Affinity's brush outline (68×68,
one 1× image) and another app's tool cursor (25×25) matched none. AppKit's arrow and I-beam have no
image in a process without an NSApplication (the CLI), so the 1×–10× images stand in for those two.

- Wire (additive): kind 46 `cursorKind` (30 when it was written; 46 on the rebase, below), host → device, JSON `CursorKind {standard}`
  (Viewport.swift), sent just before each kind 14 (and before the current shape to a device that
  connects). Older devices skip it. A device that gets a kind 14 with no kind 46 before it takes
  that cursor as standard.
- Host: `CursorClass.isStandard` (pure): its fingerprint one of AppKit's standard cursors' (the
  arrow, I-beams, hands, crosshair, the resize, column, row, zoom and frame-resize cursors, the drag
  and contextual-menu ones), or four images or more with the widest 10× its width; anything else
  an app's own. `CursorShapeWatcher` classifies each new shape with the fingerprint it makes anyway.
- Device: StreamClient keeps a kind 46 until the kind 14 it comes before and applies both together;
  `PointerPresence.cursorIsAppOwn` (false until a kind 46 says otherwise); `.penHover` shows only
  while it is true. The Mac's arrow and the trackpad's are unchanged.
- Known: a Mac whose pointer size or colours are changed in Accessibility may draw its standard
  cursors differently from AppKit's copies; such a cursor reads as an app's own, and the hover then
  shows it, as before this change.

Verified: `pen` 207 checks (the rule's cases: a table match, Affinity's outline, a 2× tool cursor,
the CLI's arrow and I-beam by their images, three images with and without a 10× one, an 8× widest,
no size, no images) and 97 of 97 mutants (the first run caught 96: the three-image case with a 10×
image was added);
`pointer-presence` 190 (hidden over a standard cursor and without a kind 46, shown over an app's
own, in both layouts with and without Q2's flip); `compatibility` 151 (kind 46, its JSON, a later
field skipped, an empty one), and `protocol`, `menus` and `pointer-control` with 30 taken and 31
the first unknown kind (their mutants that renumbered a kind onto 30 or 31 moved to 31 and 32);
every mutant of the six checks caught (`pointer-presence` 48, `compatibility` 40, `menus` 43,
`pointer-control` 33, `protocol` 23); `swift build -c release`; the iOS app for the simulator and
the owner's iPad, installed; a `--synthetic` host sends one kind 46 with its kind 14.

### The hover cursor on the rebase (2026-10-19)

Hunter's last commit, db5e2ae (the two sections above), came after the a85fba7 the rebase took, so it
went on top of `pencil-pressure-rebased` (1546dfc) by itself. Its kind was 30, which pull request #66
holds; every open pull request's head was read again (2026-10-19): 29 to 44 held, 45 the pen's, 46 in
none. So `case cursorKind = 46`. The checks: compatibility (kind 46 and its JSON, 47 unknown; the
mutant "kind 45 as 46" now "as 47", with "kind 46 as 47" and the field renamed), protocol (45 the pen,
46 the cursor's kind, 47 unknown), pointer-control (the table, and every other kind 29–31, 33…44,
47…254), clipboard unchanged (29, 30, 31 and 33 still unknown). sillclient.py names kind 46. The
files that conflicted (the docs, the checks' tables) took the rebase's side and the cursor's lines
again by hand.
