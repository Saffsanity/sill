# The Mac's pointer on the device — the plan

2026-09-25. It stands alone: the implementer needs no other design document. Written from a
read-only survey of `/Users/noah/Downloads/winstream-remote` (branch `remote-access` at 78d76e0,
which contains cb0ec55); line numbers are at 78d76e0. No host or app was started, no event was
posted, no event tap was created and the pointer was never moved. One read-only probe ran (see
"Measured"): it read the pointer's location and one window's bounds and timed them
(`scratchpad/pointer-plan/probe/probe.swift`). A critique pass the same day checked the plan
against the code, every branch and worktree, Apple's headers and docs and one outside measurement,
ran a second read-only probe (a process with no permission at all), and corrected the plan in
place; "Critique" at the end lists what changed. Both probes live under /private/tmp, which a
reboot empties: "Measured" says what each did, so H0 can rebuild them.

**Noah's request (2026-09-25):** "When the Mac is controlling the mouse pointer, it should show the
real mouse pointer on the desktop on Sill. When Sill is controlling the Mac, continue to hide the
real pointer and only render the client side one in portrait mode when the trackpad is used."

**Reading of it.** What the device draws depends on who moved the pointer last.
- **Someone at the Mac moved it** (its mouse or trackpad). The device shows the Mac's pointer over
  the stream: where it really is, in its real shape, in every layout, while it is over what is
  streamed. For the Desktop that means anywhere on that display; for a window, over the window.
- **The device moved it** (any input from Sill). The video still never carries the Mac's cursor.
  The device draws its own pointer only in the portrait (laptop) layout while its trackpad is in
  use, never in landscape's direct touch.
- **"The real pointer" is drawn by the device** from the Mac's position and shape. It is not put
  back into the video (see "Not in the video").

---

## Decision

### Who is in control

- **The Mac is in control** when its pointer has moved, by something other than Sill, since the
  host last read input from the device.
- **Control goes back to a device** with its next input message (kind 8) of any kind: a move, a
  click, a scroll, a key or typed text.
- **The host keeps one controller:** the Mac, or the one device whose input it read last. Every
  device except the controller is sent the pointer. So a second device that is only watching sees
  the first device's pointer, as it would see the Mac's (Q5).
- **At connect nobody has driven yet:** the Mac has the pointer, and the device shows it until the
  device's own first input (Q6).
- **A connection is a device, to the host.** A session that moves to a new connection (the move
  from AWDL to the network; with PR #12, to the cable and back to Wi-Fi) looks to the host like a
  new device that has not driven, so the new connection is sent the pointer's state at once. The
  device carries its control across the move and takes that report for what it is (§7.3).

### How the host tells: a position poll, not an event tap

| | **Position poll (chosen)** | Listen-only event tap | NSEvent global monitor |
|---|---|---|---|
| Permission | None (measured from a process with none) | Input Monitoring: without it a mouse-only tap is created but gets nothing, and no alert shows (measured elsewhere, below) | None for mouse events |
| In the CLI (`dispatchMain`) | Yes | Needs a run-loop thread of its own | Only under `--virtual-display` (the AppKit loop) |
| Sees | Position changes, including warps by any app | Moves, drags, clicks and scrolls | Moves, drags, clicks and scrolls, except over Sill's own windows |
| Tells Sill's own motion by | Time: a settle window after Sill's input | A tag on Sill's events (`.eventSourceUserData`) or the poster's pid | The poster's pid |
| Where it runs, and cost | `sill.net`, one read per 30 ms tick (0.1–1.3 µs) | A callback per mouse event, up to 1,000 a second from a gaming mouse | The main thread (the coordinator's), per mouse event |
| Misses | A click or scroll without motion; motion within 0.25 s of Sill's input; a move and back within one tick | Nothing that matters here | Motion over Sill's windows |

**The poll, chosen.**
- **When it reads.** At every link tick (StreamServer.swift:138-150). The tick runs only while a
  device is connected and a source is live, or input came in the last 3 s. Each read takes
  `CGEvent(source: nil)?.location`.
- **What it reads.** The pointer's position in the same top-left global points the injector
  posts to and window bounds use. VirtualStage already reads it this way (VirtualStage.swift:390,
  :655).
- **No permission.** The location is public to every process: NSEvent.mouseLocation, the same
  value flipped, is open to sandboxed apps too. A probe launched as an app of its own, with no
  Screen Recording, Accessibility, Input Monitoring or PostEvent grant, read it 30 times off the
  main thread ("Measured"). A probe run from this session's shell shows nothing either way: its
  responsible process (claude.app) holds all four.
- **What counts as a real move.** A read at least 0.5 pt from the last position that counted:
  where Sill's own motion left the pointer, or the last real move. Measured against that rather
  than against the previous read, a slow drag of under 0.5 pt a tick (17 pt/s) still adds up; a
  still mouse reads the same point every time (40 reads, 0 changes, "Measured"), so nothing
  creeps. The exception is motion Sill could have caused, which is anything within 0.25 s of one
  of these:
  - the host reading a pointer or scroll input;
  - posting one (noted just before the post, §4.5);
  - warping the cursor (noted just before the warp, §4.6).
- **Why a settle window works.** Sill's pointer events are absolute: InputInjector.swift:99-104
  posts `mouseCursorPosition: location`. So Sill's effect lands at a known moment. Two cases also
  settle inside the window:
  - a clamped position, such as a click past a display's edge;
  - a late post: activating the app is a synchronous AX call on the main actor with a 1 s
    timeout (StreamCoordinator.swift:1108-1122), and the input can then be held up to 0.6 s more
    (:1068-1080), so a click can be posted a second or more after it was read, long after the
    arrival's settle. The post opens its own.
- **What it cannot see (accepted).**
  - A click or scroll on the Mac without motion. The pointer did not move, so the device keeps
    what it shows.
  - Motion within 0.25 s of the device's last input. The device is still driving; the Mac's
    motion counts once it goes on past the window.
  - A move and back within one 30 ms tick.

**A listen-only event tap, rejected.**
- **How it would work.** `CGEventTapCreate(kCGSessionEventTap, …, kCGEventTapOptionListenOnly, …)`
  with a mask of mouse moved, dragged, down, up and scroll. Sill's own events would be told apart
  by a tag InputInjector sets on each (`.eventSourceUserData`), or by
  `.eventSourceUnixProcessID == getpid()`. It sees clicks and scrolls that come without motion.
- **What Sill would have to ask for.** Input Monitoring: Privacy & Security › Input Monitoring,
  TCC service `kTCCServiceListenEvent`. `CGPreflightListenEventAccess()` checks it and
  `CGRequestListenEventAccess()` asks for it, the one of the two that may raise the system alert
  (both macOS 10.15+; the SDK's CGEvent.h has a one-line comment on each and nothing more).
- **What is known.**
  - The macOS 27 SDK's CGEvent.h gates only key up and down events on assistive access, and says
    taps at `kCGHIDEventTap` need root; Apple's reference for `tapCreate` adds that events a tap
    may not see are cleared from its mask, and an empty mask returns NULL.
  - Measured elsewhere, macOS 26.7 (25G229), 2026-09-23
    ([omesser/ai-buddy#926](https://github.com/omesser/ai-buddy/pull/926), the measurement behind
    the same project's [#722](https://github.com/omesser/ai-buddy/issues/722)): a mouse-only,
    listen-only tap from an app with neither Input Monitoring nor Accessibility is created
    (`tap_created=true`) but never enabled (`tap_enabled=false`), receives nothing and raises no
    alert, with tccd logging "Service kTCCServiceListenEvent does not allow prompting; returning
    denied." So it does need Input Monitoring, only `CGRequestListenEventAccess()` would ask for
    it, and a tap made without it fails silently unless `CGEvent.tapIsEnabled(tap:)` is checked.
  - Whether Sill's Accessibility grant stands in for it is unknown: TCC keeps Accessibility,
    PostEvent and ListenEvent as separate services.
  - Not re-run here: this session's processes inherit claude.app's Input Monitoring grant, so a
    tap made from them would prove nothing, and the chosen design needs none.
- **The cost.** A third permission after Screen Recording and Accessibility:
  - a second system alert;
  - another row in Settings › Permissions;
  - one more grant that a re-sign or a `tccutil reset` loses;
  - one more permission for the README and the privacy policy (the Mac app ships as a download,
    outside the App Store, so no App Privacy answer changes).
- **Other costs.** It needs a run loop (the CLI runs `dispatchMain`, so a thread of its own), and
  every mouse event on the Mac is also delivered to Sill while it is installed.

**An NSEvent global monitor, rejected.**
- **What it is.** `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, …])`. Apple
  documents that only key-related events need Accessibility
  ([addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))),
  so mouse events need nothing.
- **Why not.**
  - It runs only under the AppKit event loop: Sill.app yes, the CLI only with `--virtual-display`.
  - It never sees events sent to Sill itself, such as the pointer moving over Sill's Settings or
    Log window.
  - It calls back on the main thread (the coordinator's) at the mouse's rate.

**Why the poll.**
- It needs no new permission.
- It works the same in the CLI and in the app.
- It runs on the thread and timer that already run while streaming, so it adds nothing when idle.
- A read costs about a microsecond.
- What Noah asked about is the moved pointer.

The tap stays the upgrade if clicks without motion should count (Q3).

### Not in the video

The capture keeps `showsCursor: false` (StreamCoordinator.swift:957). There are two ways to put
the cursor back while the Mac drives, and both are ruled out:
- **Reconfigure the running stream** with `SCStream.updateConfiguration`. That wedged capture
  (CLAUDE.md, "Frozen stream").
- **Restart the stream at each hand-over.** That costs a keyframe and a visible hitch every time
  the Mac's user touches the mouse. The cursor would also move only as unevenly as the video
  arrives, which is trackpad-stutter cause 3.

The device already draws the pointer as a sprite in the Mac's live shape (`.cursorShape`, kind
14). The Mac's position is the only thing missing.

### What the device draws

| Who moved the pointer last | Layout | The sprite |
|---|---|---|
| The Mac (its mouse or trackpad, or an app warping it) or another device | Any | At the Mac's pointer while it is over the streamed source, hidden when it is not. Moves at the tick rate, about 33 Hz (Q4). Jumps, never animates |
| This device, with the on-screen trackpad | Portrait (inner and outer) | This device's own pointer, as today. It follows the finger at touch rate and stays after the finger lifts until another input takes over (Q1) |
| This device, with the on-screen trackpad | Landscape | Hidden |
| This device: a finger on the stream (tap, long press, scroll), typing, a hardware key, the iPad's own trackpad or mouse | Any | Hidden (typing and keys hide it as today; the portrait key row does not) |
| This device, with the Pencil (hover or touch) | Any | Hidden. Today it shows (Q2) |

- **Shape.** The sprite's shape follows kind 14 in every row.
- **The Mac takes over.** The sprite jumps to the Mac's position.
- **The device takes over with the trackpad.** The pad carries on from where the sprite is (its
  anchor, §7.3), also mid-stroke: a finger resting on the pad while the Mac takes over carries on
  from the Mac's pointer, not from where it stopped (`pointerTakeovers`, §7.3). The device's first
  move is absolute, at the anchor plus the finger's travel, so a still Mac pointer does not jump
  on the Mac.
- **Both move at once.** Sill's moves are absolute and the Mac's mouse is relative, so the two
  fight and nothing here can stop that: the device wins while its input keeps coming (each input
  opens the settle), and each of its moves puts the Mac's pointer back where the device says. The
  device's first move also lands where it last heard the Mac's pointer was, one tick plus the
  one-way latency ago: a few points behind a moving mouse on the LAN, more over a remote link. The
  Mac's motion counts again 0.25 s after the device's last input.

**No new copy.** Nothing on either screen says who has the pointer: the arrow is the message.

### Measured (two probes, macOS 27.0 26A428, M2 Pro; read-only: nothing posted, no tap, no prompt)

| What | Result |
|---|---|
| `CGEvent(source: nil).location` | 0.10 µs a call on a background queue, 1.33 µs on the main thread (the first calls); a live point. This probe ran from the session's shell, whose responsible process (claude.app) holds Screen Recording, Accessibility, Input Monitoring and PostEvent (the probe prints all four as true), so it showed nothing about permissions |
| The same read with no permission at all (the critique's probe, `scratchpad/pointer-plan/critique/bundleprobe.swift` built into an ad hoc signed LSUIElement app, `PointerPermProbe.app`, launched with `open`, so it is its own responsible process; it asks for nothing, posts nothing and makes no tap) | `AXIsProcessTrusted`, `CGPreflightListenEventAccess`, `CGPreflightPostEventAccess` and `CGPreflightScreenCaptureAccess` all false; 30 of 30 reads on a background queue live, each equal to the flipped `NSEvent.mouseLocation` |
| `NSEvent.mouseLocation` | 0.62 µs a call (main thread); the same point as CGEvent's once flipped |
| One window's bounds, `CGWindowListCopyWindowInfo(.optionIncludingWindow)` | 134 µs (background), 144 µs (main), and 111 and 126 µs when the critique ran the probe again; bounds and `kCGWindowIsOnscreen` both present |
| All on-screen windows (22) | 343 µs; the windows above one window: 160 µs |
| `CGDisplayBounds(main)` | 27 µs, so the Desktop's frame is kept rather than read every tick |
| One kind 26 through JSONEncoder, rounded as §3.2 says | 1.7 µs, 49 bytes: `{"inside":true,"seen":1234,"y":0.1873,"x":0.4213}` |
| 40 reads 30 ms apart while the Mac's mouse was still | 0 changes. Reads carry fractions of a point (the threshold is 0.5 pt) |

---

## Final plan

### 1. Scope

**In this step:**

1. **The host.**
   - It polls the pointer's location at each link tick while a source streams.
   - It keeps who drives it: the Mac, or the device whose input it read last.
   - To every device except the one driving, it sends where the pointer is in the streamed frame
     (kind 26), only when that changed.
2. **The device.**
   - One sprite, whose shape comes from kind 14 as now, shows either the Mac's pointer or its own.
   - The rules are in "What the device draws".
   - Stale positions are dropped with an echoed input count (§3.3).
3. **Tests.**
   - A scripted test pointer for synthetic hosts, and a software-encoder switch for them.
   - Synthetic hosts record input and never post it.
   - `sillclient.py` input and pointer flags.
   - A harness case per sprite state, and a DEBUG input script so the simulator gates need no
     touch tool (§7.7).

**Not in this step:**
- clicks or scrolls without motion taking control (Q3);
- hiding the arrow where another Mac window covers a streamed window (Q7);
- hiding it when an app hides the Mac's cursor (Q8);
- moving the pointer home when the Mac takes over on the virtual display (Q9);
- a setting to turn any of this off (Q11);
- VoiceOver announcements of who has the pointer;
- any change to the video (`showsCursor` stays false);
- the Mac menu bar's kinds (24, 25 and 27; 23 is the device's hello, from update-notice).

### 2. The design on one page

```
 ┌──────────────── Mac (Sill.app / SillHost) ────────────────────────────────────────────┐
 │ sill.net receive loop   kind 8 read ─▶ client.inputsRead += 1                         │
 │                                      ─▶ PointerWatch.inputArrived(client, moves?)     │
 │ main: InputInjector      before a pointer or scroll post  ─▶ PointerWatch.sillMoved() │
 │ main: VirtualStage       before warping the cursor home ──▶ PointerWatch.sillMoved()  │
 │ main: coordinator        a source started or changed ─────▶ PointerWatch.setGeometry  │
 │ sill.net tick, every 30 ms (only with a device, and a live source or input < 3 s):    │
 │   p = CGEvent(source: nil).location                  no permission, about 1 µs        │
 │   PointerControl: moved ≥ 0.5 pt, not within 0.25 s of Sill's own ─▶ the Mac drives  │
 │   for each device but the one driving: MacPointer{x, y, inside, seen}, if changed ────┼─▶ kind 26
 └───────────────────────────────────────────────────────────────────────────────────────┘
 ┌──────────────── device ────────────────────────────────────────────────────────────────┐
 │ sill.net: kind 26 fresh? (seen ≥ kind 8 sent on this connection, and no move waiting)  │
 │           yes ─▶ control: elsewhere, and the Mac's position   any own input ─▶ here     │
 │ main:     PointerPresence(control, the Mac's position, own pointer and origin, layout) │
 │           ─▶ the one sprite (HEVCDisplayView), in the shape kind 14 gives              │
 └────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3. Wire protocol

#### 3.1 The new kind (`Sources/StreamProtocol/StreamMessage.swift`, continuing the enum)

```swift
    // 23 is the device's hello (update-notice). 24 and 25 are held for the Mac menu bar (sketched
    // 2026-09-25, not built: 24 macMenu, 25 pressMenuItem, and 27 for its optional fetch), so this
    // one is 26 and none of them can collide.
    case macPointer = 26     // host → device: JSON MacPointer (Pointer.swift) — where the Mac's pointer is while this
                             // device is not the one moving it (the Mac's own mouse, or another device). At most once a
                             // 30 ms tick per device, only when it changed. Older readers map it to `.unknown` and skip it
```

- **Who skips it.** Every device and test client since b67f87d (2026-09-23) skips an unknown kind:
  `parseHeader` maps it to `.unknown`, StreamMessage.swift:89-98, and StreamClient.swift:1687-1688
  ignores it.
- **Nothing else changes.** Kinds 0–23 (23 is the device's hello), `InputEvent` (kind 8) and
  `Viewport` (kind 9) are untouched.
- **Numbers taken elsewhere** (checked 2026-09-25 on every branch and in every worktree,
  uncommitted changes included): 18–22 remote access (this branch, PR #13); 23 `hello` from
  `update-notice` (3a2470b, merged with PR #18). The Mac menu bar sketch (not
  built) named 23–25 before the hello took 23, so it has 24 and 25 now and would put its optional
  third kind at 27. 26 is free everywhere. H0 checks again.

#### 3.2 The payload (`Sources/StreamProtocol/Pointer.swift`, new; the iOS app gets it through the package, no pbxproj entry)

```swift
/// Host → device (kind 26): the Mac's pointer while this device is not the one moving it.
/// JSON; every field optional (HostSettings.swift's rules: never renamed or retyped, no enums).
public struct MacPointer: Codable, Hashable, Sendable {
    /// Where the pointer is, as a fraction of the streamed frame: InputEvent's space, 0…1 across
    /// its width and height (Input.swift:3-5). Rounded to 4 decimal places (0.3 px on a 3000 px
    /// frame, and short JSON). Nil when `inside` is false.
    public var x: Double?
    public var y: Double?
    /// Over the streamed source: inside its rectangle (§4.7), and for a window in regular mode,
    /// that window on screen. Nil counts as false.
    public var inside: Bool?
    /// How many input messages (kind 8) the host had read on this connection when it sent this.
    /// A device that has sent more since drops it (§3.3). Nil counts as 0.
    public var seen: Int?

    public init(x: Double? = nil, y: Double? = nil, inside: Bool? = nil, seen: Int? = nil)
    public static func rounded(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
}
```

Two example payloads:
- over the stream: `{"inside":true,"seen":12,"y":0.1873,"x":0.4213}`;
- off it: `{"seen":12,"inside":false}`.

#### 3.3 Freshness: why `seen`

- **The rule.** The host sends kind 26 to a device only while that device is not the one driving.
- **The race.** A message the host built before it read the device's latest input can still be on
  its way when the device makes that input.
- **The bug it would cause.** Taken as fresh, it would show the Mac's arrow after the device's own
  tap. The host, now reading the device as the driver, sends it nothing more, so the arrow would
  stay there until the Mac's mouse moved again.
- **The fix.**
  - Every kind 26 says how many kind 8 messages the host had read on that connection (`seen`).
  - The device counts the kind 8 messages it has sent on the same connection.
  - It drops a kind 26 whose `seen` is lower, or one that arrives while a coalesced move is still
    waiting to go out (StreamClient.swift:1476-1491).
- **Why it is exact.** TCP keeps both directions in order, and no clock is compared.
- **Where it stops.** It is exact on one connection. A session that moves to a new one is a new
  device to the host, which sends it the pointer's state at once with `seen` 0; `seen` cannot
  tell that from news, so the device's carry-over does (§7.3).
- **Where it is judged.** On the device's network queue, where its input is sent and counted
  (§7.3).

#### 3.4 Compatibility

| Device | Host | Result |
|---|---|---|
| Older (any build since b67f87d) | This host | Skips kind 26. Its sprite behaves as today: the trackpad's and the Pencil's |
| This device | Older host (PR #13's Sill.app, main's, the CLI before this) | No kind 26 ever arrives, so there is never a Mac arrow. The device's own pointer shows only on the portrait trackpad, and no longer for the Pencil (Q2) |
| This device | This host | This plan |
| `sillclient.py` at 78d76e0 | This host | Unaffected: it skips kind 26, and only its `kinds=` and `first kinds:` summaries list it, by number |
| Devices before b67f87d | Any current host | Already stop at kinds 14–22; nothing new |

#### 3.5 Rules for later changes

HostSettings.swift's rules apply to `MacPointer`:
- JSON only;
- new fields optional;
- strings, not enums;
- never rename or retype a field.

A later "who moved it" field (the Mac or another device) would be an optional string.

---

### 4. Host (`SillHostCore`, folder `Sources/SillHost`), file by file

The ground rules for this section:
- Nothing becomes `public`.
- The network queue is StreamServer's `sill.net`.
- The main actor is reached with `Task { @MainActor }`, never `MainActor.assumeIsolated`.
- CoreGraphics is set up on the main thread before any tick, in both hosts: main.swift's
  `_ = CGMainDisplayID()`, and AppKit in the app.

#### 4.1 `PointerControl.swift` (new; pure: Foundation and CoreGraphics; checked with swiftc)

```swift
/// Who is moving the Mac's pointer: the Mac (its own mouse, or anything that is not Sill) or the
/// device whose input the host read last. A value type; PointerWatch holds it under a lock.
struct PointerControl {
    enum Controller: Equatable { case mac, client(ObjectIdentifier) }
    private(set) var controller: Controller = .mac     // at launch nobody has driven: the Mac has it
    /// Motion before this time may be Sill's own: input read and not yet posted, or posted and
    /// still landing (a clamped or late position).
    private var sillUntil = -Double.infinity
    /// The last position that counted: where Sill's own motion left the pointer, or the last real move.
    private var last: CGPoint?
    static let settle = 0.25          // seconds
    static let minMove: CGFloat = 0.5 // points; reads carry fractions of a point

    /// A kind 8 read from `client` (sill.net, in the receive loop). Every kind hands it the pointer;
    /// only one that can move the pointer (a pointer or scroll event) opens the settle.
    mutating func inputArrived(from client: ObjectIdentifier, movesPointer: Bool, now: Double)
    /// Sill moved the pointer itself: a posted pointer or scroll event, a warp (main, via PointerWatch).
    mutating func sillMoved(now: Double)
    /// One read at a tick. True when the pointer passed to the Mac with it.
    mutating func read(_ p: CGPoint, now: Double) -> Bool
    /// A device left; if it was driving, the Mac has the pointer again.
    mutating func clientLeft(_ client: ObjectIdentifier)
}
```

The rules of `read`:
- **Before `sillUntil`.** `last = p` and nothing else, so the settle ends at the position where
  Sill left the pointer.
- **After it.** A read at least `minMove` from `last` counts: `last = p` and `controller = .mac`,
  which returns true when the controller was a client. A smaller difference changes nothing,
  `last` included, so a slow drag adds up to `minMove` over a few ticks instead of hiding under
  it at every one. The very first read only sets `last`.

The rules of the others:
- **`inputArrived`.** `controller = .client(id)` always. For a pointer or scroll event it also
  sets `sillUntil = max(sillUntil, now + settle)`.
- **`sillMoved`.** `sillUntil = max(sillUntil, now + settle)`, with the controller unchanged. A
  held click's late post, or VirtualStage's warp, never hands the pointer to anyone.
- **Keys and typed text** hand control to the device without opening the settle. They do not move
  the pointer, so the Mac's next real motion shows its arrow at once.

**Also in this file, pure.** `static func fraction(of p: CGPoint, in r: CGRect) -> (x: Double, y: Double, inside: Bool)`:
- `inside` is 0 ≤ x < 1 and 0 ≤ y < 1 (the far edges are the next display's first column and row,
  or past a window: "Review fixes");
- an empty rectangle is never inside;
- x and y are rounded by `MacPointer.rounded`.

#### 4.2 `PointerWatch.swift` (new): the shell around PointerControl

Owned by the coordinator and handed to StreamServer, InputInjector and VirtualStage at init. One
`NSLock`; every method is thread-safe and short.

```swift
final class PointerWatch: @unchecked Sendable {
    enum Geometry: Equatable {
        case rect(CGRect)               // the Desktop's display, a staged crop or full-screen band, the test pattern
        case window(CGWindowID, CGRect) // regular mode: the window's live bounds, re-read (below)
    }
    struct Reading: Equatable { let x: Double; let y: Double; let inside: Bool; let controller: PointerControl.Controller }

    func setGeometry(_ g: Geometry?)                                // main: nil = nothing to point into
    func inputArrived(from: ObjectIdentifier, movesPointer: Bool)   // sill.net
    func sillMoved()                                                // main (injector, stage)
    func clientLeft(_ id: ObjectIdentifier)                         // sill.net
    func sample() -> Reading?                                       // sill.net, once a tick; nil without geometry
}
```

What `sample()` does:
- **No geometry.** Returns nil before it reads anything: no source streams, or the host is
  synthetic and has no test pointer. Synthetic mode replaces only the Desktop, so a real window
  can be picked on a synthetic host; it gets no geometry either (§4.7), and a synthetic host never
  reads the real pointer.
- **Otherwise.** It takes one location (`CGEvent(source: nil)?.location`, or the test pointer's on
  a synthetic host, §4.10) and runs `PointerControl.read`. On a hand-over to the Mac it bumps
  `ptr.mac`.
- **Regular-mode windows.** The window's bounds and on-screen flag
  (`CGWindowListCopyWindowInfo([.optionIncludingWindow], id)`, 110–144 µs on an idle Mac,
  "Measured") are re-read on PointerWatch's own serial queue (`sill.pointer`, utility QoS), never
  on `sill.net`: a window-server round trip there would sit in front of frames and pongs, and a
  pong must measure the network and nothing else (StreamServer.swift:806-809). A tick whose read
  moved starts one when none is running and the last is at least 0.1 s old, and (since the review,
  `sample(devices:)`) some device other than the one moving the pointer is there to be sent it;
  one runs every 2 s whatever the pointer does; the result lands
  under the lock, and each tick uses the newest bounds it has (at most about 0.1 s and one call
  old). `sample()` never waits for it. `kCGWindowIsOnscreen` false counts as not inside.

#### 4.3 `StreamServer.swift`

- **`Client` (StreamServer.swift:32-66) gains two fields.**
  - `inputsRead = 0`: the kind 8 messages read from it.
  - `lastPointer: MacPointer?`: the last kind 26 sent to it; nil also while it drives.
- **`var pointerWatch: PointerWatch?`,** set before `start()`.
- **The receive loop's `.input` branch** (StreamServer.swift:802-805) adds two steps before
  `onMessage`:
  - `client.inputsRead += 1`;
  - `pointerWatch?.inputArrived(from: ObjectIdentifier(c), movesPointer: …)`.
  `movesPointer` decodes the `InputEvent` there, a few µs at the device's ≤125 a second:
  `.pointer`, `.scroll` and `.scrollGesture` → true; `.text` and `.key` → false; undecodable →
  false. Count and controller change in the same queue turn, so no kind 26 can carry the new
  count with the old controller (§3.3).
- **`tick()`** (StreamServer.swift:138-150) samples once, then for each ready client:
  - **It is the controller.** `lastPointer = nil`; nothing is sent. Its tick goes out as today.
  - **Otherwise.** Build `MacPointer(x:y:inside:seen: client.inputsRead)`, with x and y nil when
    not inside. When it differs from `lastPointer`, send it and store it. It goes out the way the
    tick does, `connection.send` without counting it in `inflight`, so it can never make a slow
    remote link drop frames (`paceRemote`, StreamServer.swift:904). It sets
    `client.lastSentAt`, bumps `ptr.sent`, and stands in for that client's tick this turn.
  - **`net.tick`** is bumped once per tick, as now.
- **`unregister`** (StreamServer.swift:749-757) calls `pointerWatch?.clientLeft(id)`.
- **A new client** gets the current state at the first tick after it registers, because its
  `lastPointer` is nil. The catalog (`sendCatalog`) is unchanged.

#### 4.4 `StreamCoordinator.swift`

- **`let pointer = PointerWatch()`,** handed out at init:
  - `server.pointerWatch = pointer`;
  - `injector.watch = pointer`;
  - `stage.onWarp = { [pointer] in pointer.sillMoved() }`;
  - `injector.dryRun = synthetic` (§4.5).
- **`active`'s didSet** (StreamCoordinator.swift:85-92) and the end of `windowsChanged`, each
  catalog poll, call `pointer.setGeometry(pointerGeometry())`. `pointerGeometry()` is §4.7's
  table.
- **`currentSourceRect()`** (StreamCoordinator.swift:597-615): `.desktop` on a synthetic host with
  the test pointer is the test pattern's rectangle, (0, 0, 1512, 949). A test client's fractions
  then land in the same space as the scripted pointer. Without the hook it is unchanged.
- **The "The Mac cursor" comment** (StreamCoordinator.swift:623-628) gains a sentence: while the
  Mac, or another device, moves the pointer, the devices draw it from kind 26.

#### 4.5 `InputInjector.swift`

- **`var watch: PointerWatch?`.** Right before each post of a pointer event (`pointer`, line 104)
  and of a scroll event (`postScroll`, line 301) it calls `watch?.sillMoved()`. Before, not after:
  the tick reads on `sill.net` while main posts, so a read could fall between the post taking
  effect and a note made after it, and take Sill's own move for the Mac's. It matters most for a
  held click, posted a second or more after it was read ("Why a settle window works"), when the
  arrival's settle is long over. Keys and text call nothing.
- **`var dryRun = false`.** A synthetic host records input and never posts it: the test pattern
  is not the screen (Q10).
  - Today a synthetic host maps Desktop input onto a real display (the first one ScreenCaptureKit
    lists) and posts it whenever its launcher has Screen Recording and Accessibility, which this
    session's shell has.
  - In the dry run every `post(tap:)` is replaced by `Stats.shared.bump("in.dry")`. The per-type
    keys (`in.pointer`, `in.scroll`, `in.text`, `in.key`) are not bumped, and
    `remindAboutAccessibilityIfNeeded` is skipped.
  - With the test pointer on, a dry pointer event also moves the test pointer to its position
    (§4.10).
  - No line prints for it, so the CLI's output stays the same.
- **Sill's moves are absolute** (line 99-104: `mouseCursorPosition: location`). That is why the
  settle rule works and why the device can continue from its anchor.

#### 4.6 `VirtualStage.swift`

`var onWarp: (() -> Void)?`, called right before `CGWarpMouseCursorPosition` in `releaseWindow`
(VirtualStage.swift:655-658; before, for the reason in §4.5). That warp brings the cursor home
from the display about to go, and it must not read as the Mac taking over.
`VirtualDisplaySelfTest`'s warp runs with nothing streaming and needs nothing.

#### 4.7 Where the pointer is, per source (regular mode and the virtual display)

| Source | Rectangle (global points, top-left: the injector's) | Inside when | Notes |
|---|---|---|---|
| The Desktop | The streamed display's frame (`catalog.display.frame`, kept; not re-read each tick) | The pointer is on that display | Another display is outside. With the virtual display on, the Desktop is the main display (`preferMainDisplay`), and picking it removes the virtual display first (`select`'s release). So the Desktop never streams the virtual display: not a case |
| A window, regular mode | Its live bounds, the injector's own rectangle (StreamCoordinator.swift:603-613), re-read as §4.2 says | Inside the bounds, and `kCGWindowIsOnscreen` | The window is where the pointer really moves. Over another window that covers part of it, the arrow still shows (Q7). Minimized or on another Space: outside |
| A window on the virtual display | `stage.captureRectOnScreen` (VirtualStage.swift:168-172): the crop, offset by the display's bounds | Inside the crop | The virtual display is a real display to macOS, so the Mac's pointer can move onto it, and the device's own input already puts it there. The display's menu bar and anything outside the crop are outside |
| Full screen on the virtual display | The same property: the band, the panel's aspect around the display's middle | Inside the band | The letterbox bars are outside. Players hide their cursor, the device does not (Q8) |
| The synthetic test pattern | (0, 0, 1512, 949) with `SILL_TEST_POINTER_PATH`; no geometry otherwise | Inside | Without the hook the poll never runs on a synthetic host. The pattern is not the screen, so a real pointer means nothing to it |
| Any other source on a synthetic host (a real window picked there: synthetic mode replaces only the Desktop) | None, with or without the hook | Never | A synthetic host reads only the test pointer, never the real one, so no test depends on Noah's mouse and the CLI's output cannot change with it |

#### 4.8 Cost

| What | Cost | How often |
|---|---|---|
| One location read | 0.1–1.3 µs | Once a tick (30 ms) while a source has geometry |
| One window's bounds | 110–144 µs on an idle Mac, on `sill.pointer`, never on `sill.net` | At most 10 a second: regular-mode windows, while the pointer moves |
| One kind 26 | 1.7 µs to encode; 49 bytes plus the 14-byte header | Per device, only when it changed: at most about 33 a second, about 2.1 KB/s, while the Mac's pointer moves |
| Idle, no device | Nothing | The tick timer exists only with a device and a live source, or input in the last 3 s (StreamServer.swift:124-136) |
| Streaming, pointer still | One read per tick, no message | — |

#### 4.9 Log lines and Stats keys (exact; none by default)

```
Test pointer: 12 steps from /tmp/…/path; this host records input and never posts it.
SILL_TEST_POINTER_PATH=/tmp/x ignored: only a --synthetic host takes it.
SILL_TEST_POINTER_PATH=/tmp/x ignored: line 3 is not "T X Y" (seconds, then points).
Test encoder: software only (SILL_TEST_SOFTWARE_ENCODER); the hardware encoder is never probed.
SILL_TEST_SOFTWARE_ENCODER ignored: only a --synthetic host takes it.
```

- **These lines** print only when their variable is set.
- **New Stats keys** join the `[1s]` line only in seconds that bumped them; Stats prints only the
  keys that were bumped (Stats.swift:112):
  - `ptr.sent`: kind 26 messages sent;
  - `ptr.mac`: reads that handed the pointer to the Mac;
  - `in.dry`: events a synthetic host would have posted (one per pointer or scroll event, two per
    key or typed character).
- **No line on a hand-over.** It would print every time Noah touched his mouse.

#### 4.10 TEST ONLY hooks (honoured only by a synthetic host, which does not advertise)

- **`SILL_TEST_POINTER_PATH=<file>`: the scripted pointer.** It stands in for the Mac's pointer on
  the test pattern, and turns the poll on there.
  - **The file.** Up to 10,000 lines and 1 MiB. Each line is `T X Y`: T is seconds since the
    stream's first sample, and X Y are points in the 1512×949 pattern (any finite values; outside
    is allowed). Times never decrease; `#` comments and blank lines are ignored. A bad file is
    refused with one line and no test pointer.
  - **Where the pointer is.** Before the first step there is none, and nothing is sent. At each
    step it moves there. A dry-run pointer event (§4.5) moves it to that event's position, and the
    newer of the two wins.
  - **What it is for.** The gates exercise Sill's own motion, the settle and hand-backs with it,
    without touching the real pointer.
- **`SILL_TEST_SOFTWARE_ENCODER=1`.** Skips `EncoderProbe` and starts on the software encoder, so
  a gate never touches the hardware encoder while Noah streams (on 2026-09-24 and 25 another
  session on the Mac's one encoder, the Simulator's recorder, starved his stream). After a rebase
  onto PR #11 (encoder-recovery) it must also keep the host off the hardware for good: #11's
  `recheckLoop` tests the hardware at the stream's size (`EncoderProbe.throughput`) 30 s after a
  host with a device lands on software, and goes back to it when it keeps up. Under the hook that
  loop never starts; any gate longer than 30 s with a client (S2–S5) would otherwise use the
  encoder.

---

### 5. CLI (`Sources/SillHostCLI/main.swift`)

- **No new flag.** main.swift prints nothing new.
- **The default synthetic path is byte for byte what it prints today, idle and streaming.** Two
  reasons:
  - The poll never runs there: without the hook no source has geometry on a synthetic host, the
    test pattern and a real window picked there alike (§4.7). Noah moving his Mac's mouse during a
    parity run changes nothing.
  - A synthetic host sends no kind 26, so `sillclient.py`'s `kinds=` and `first kinds:` lines stay
    the same too.
- **A real (non-synthetic) host** adds `ptr.sent` and `ptr.mac` to `[1s]` lines in seconds when
  kind 26 went out. That is the connect's first state, and whenever the Mac's pointer moves while
  a device streams. These are events the parity runs never produce.
- **`Scripts/sillclient.py` gains:**
  - `--pointer`: print each kind 26 as
    `  pointer at 1.234s x=0.5000 y=0.5000 inside=1 seen=0` (`inside=0` without x and y);
  - `--move=X,Y@T`: a kind 8 pointer move at fractions X, Y;
  - `--tap=X,Y@T`: move, left down, left up (three kind 8 messages, so `seen` rises by 3);
  - `--key=USAGE@T`: a key down and up, no modifiers (two, so `seen` rises by 2);
  - the Swift encoding for input, checked: `{"pointer":{"_0":"move","x":0.25,"y":0.5}}`,
    `{"key":{"down":true,"hidUsage":4,"modifiers":0}}`;
  - a guard on the three input flags, checked before connecting: they exit 2 unless the host is
    this Mac (no `--host`, or a loopback one) and the process listening on PORT
    (`lsof -nP -iTCP:PORT -sTCP:LISTEN -t`) has `--synthetic` among its arguments
    (`ps -o args= -p PID`), with "sillclient.py: --move, --tap and --key only go to a --synthetic
    host on this Mac, which never posts input; nothing on port N is one." A variable in the
    client's own environment said nothing about the host it reaches; the listener's arguments do,
    since every synthetic host is a dry run (Q10) and neither Sill.app nor a real SillHost carries
    `--synthetic`. The host's environment cannot be checked instead: `ps -E` shows another
    process's environment empty here;
  - `KIND` gains `26: "pointer"`, and kind 26 stays out of `first kinds:` as the tick does.

### 6. Sill.app

Nothing changes on the Mac's screen:
- no setting (Q11);
- no menu item;
- no new copy;
- previews identical.

The app's host is the same coordinator, so it behaves as the CLI does. Show Log… shows `ptr.sent`
and `ptr.mac` in the `[1s]` lines when the feature fires. The bare `SillMenuBar --synthetic` is a
synthetic host: a dry run, and it honours the two hooks.

---

### 7. iOS client

#### 7.1 Files

| File | Change |
|---|---|
| `PointerPresence.swift` (new; pure, Foundation and CoreGraphics; checked with swiftc) | The rules (§7.2), freshness, the anchor, and `PointerFeed`, the queue's lock-protected half. Its four pbxproj entries take `A1000001000000000000A301` / `…F301`: A01E/F01E are GoodbyePolicy.swift's, A101/F101 and A201/F201 PrivacyInfo.xcprivacy's and SillLinks.swift's, and A020/F020, the critique's pick, went to remote-pacing's MessageReader.swift on 2026-09-26 ("Since the critique"); H0 checks again |
| `SessionLink.swift` | Counts the input messages on the session's connection (§7.3) |
| `StreamClient.swift` | Kind 26, the feed, `setOwnPointer`, the anchor, layout, tear-down (§7.3) |
| `HEVCDisplayView.swift` | `setPointer` replaces `setLocalPointer`; the wiring (§7.4) |
| `TrackpadView.swift`, `InputOverlay.swift` | Each call site says where its pointer came from (§7.5) |
| `StreamScreen.swift`, `PortraitStreamScreen.swift` | The layout reaches the client (§7.6) |
| `ContentView.swift`, `MockCatalog.swift` | The harness (§7.7) |

Swift 5 language mode, as now.

#### 7.2 `PointerPresence` (the rules, pure)

```swift
struct PointerPresence: Equatable {
    enum Control: Equatable { case here, elsewhere }        // this device moved it last, or the Mac / another device
    enum Origin: Equatable { case trackpad, pencil, none }   // what drew this device's own pointer
    var control: Control = .elsewhere       // a new connection: the Mac has it until this device's first input
    var mac: CGPoint?                       // the Mac's position from the last fresh kind 26 that was inside
    var macInside = false
    var own: CGPoint?                       // this device's own pointer (today's `localPointer`)
    var origin: Origin = .none
    var portrait = false                    // the laptop layout: innerPortrait or outerPortrait
    var streaming = false                   // `client.active != .none`
    var fingersOnTrackpad = 0               // only Q1's flip reads these two
    var trackpadLiftedAt: Double?

    static let pencilShowsPointer = false   // Q2: true draws the Pencil's pointer again, in any layout
    static let trackpadLinger: Double? = nil// Q1: 2 hides the trackpad's pointer 2 s after the last finger lifts

    func sprite(now: Double) -> CGPoint? {
        guard streaming else { return nil }
        switch control {
        case .elsewhere: return macInside ? mac : nil
        case .here:
            switch origin {
            case .trackpad:
                guard portrait else { return nil }
                if let linger = Self.trackpadLinger, fingersOnTrackpad == 0,
                   let lifted = trackpadLiftedAt, now - lifted > linger { return nil }
                return own
            case .pencil: return Self.pencilShowsPointer ? own : nil
            case .none: return nil
            }
        }
    }

    /// §3.3: a kind 26 counts only if the Mac had read every input this device sent on the connection.
    static func isFresh(seen: Int?, sentOnSession: Int, movePending: Bool) -> Bool {
        !movePending && (seen ?? 0) >= sentOnSession
    }

    /// §7.3, the carry-over: after a hand-over, while this device had control and has sent nothing on
    /// the new connection, a report of where this device itself put the pointer changes nothing.
    static func isRestatement(x: Double, y: Double, inside: Bool, anchor: CGPoint?, recent: [CGPoint]) -> Bool {
        guard inside else { return false }
        let near = { (p: CGPoint) in abs(Double(p.x) - x) <= 0.002 && abs(Double(p.y) - y) <= 0.002 }
        return anchor.map(near) == true || recent.contains(where: near)
    }
}
```

**"Used", for the trackpad (Q1).**
- **The default, today's rule.** The trackpad's pointer shows from its first input until another
  input takes over: a finger or Pencil on the stream, typing, a hardware key, or the Mac's own
  mouse.
- **Why not a timer.** In the laptop layout the trackpad is the only way to point. A tap on the
  pad clicks where the arrow is, so hiding it two seconds after each stroke would leave the next
  tap aiming blind. A Mac's own pointer does not vanish when a finger lifts either.
- **The flip.** `trackpadLinger = 2`. The timer it needs is built in this step (nothing like it
  exists today): one DispatchWorkItem that re-renders at lift + linger, idle while the constant
  is nil.

#### 7.3 `StreamClient` and `SessionLink`

**`SessionLink` counts input.**
- `inputsOnSession` is the number of messages whose first byte is 8 (kind 8) that `send` handed to
  the session's connection, or kept for it while a fence stands. It is kept under the link's lock.
  SessionLink stays Foundation and Network only.
- **When it restarts.** Whenever the session's connection changes: the `connection` setter and
  `handOver` (SessionLink.swift:46-49, :72-78). It restarts at the number of kind 8 messages still
  waiting in the fence, because those go out on the new connection.
- **PR #12.** On PR #12's branch `adopt` restarts it the same way, since its `hold` keeps messages
  for the next connection, and `unhold` leaves it as it is (what was held goes out on the
  connection it was counted for). The rebase must carry both.

**On `queue`, the feed** (`PointerFeed`: control, the Mac's position and inside, and the anchor;
lock-protected, read by main):
- **In `sendInput`'s queue block** (StreamClient.swift:1470-1491), for every input, coalesced
  moves included:
  - `control = .here`;
  - for a `.pointer` event, `anchor = (x, y)`;
  - the position of a `.pointer` event, and the location of a `.scroll` or `.scrollGesture`, into
    `recent`, a ring of what this device sent in the last 3 s (the carry-over's, below);
  - the end of a carry-over, if one stands (below);
  - a hop to main (`pointerFeedChanged()`) only when control changed.
- **A new `case .macPointer`** in `handle` (StreamClient.swift:1575-1690):
  - decode it;
  - if not `isFresh(seen:sentOnSession: link.inputsOnSession, movePending: pendingMove != nil)`,
    drop it (the console line, §7.8);
  - while a hand-over is carried over (below), drop it if it `isRestatement`;
  - otherwise `control = .elsewhere`, the position, `anchor = position` when inside, and
    `takeovers += 1` when control was `.here` (since the review `reseeds`, which also counts news
    that moves the anchor while the Mac has the pointer: "Review fixes");
  - hop to main when anything shown changed, checking `self.connection === from` as the other
    handlers do.
  The cap is `maxOtherHostPayload`, unchanged.

**On main.**
- **`presence`** (not `@Published`, like `localPointer` today, StreamClient.swift:210-215).
  `renderPointer()` hands `presence.sprite(now:)` to `onPointerChange`, which reaches the display
  view with no SwiftUI in between. It runs when these change:
  - the feed;
  - the device's own pointer;
  - the layout;
  - `active`;
  - the trackpad's fingers.
- **`setOwnPointer(_ p: CGPoint?, from: Origin)`** replaces every `localPointer = …` write.
  `localPointer` stays as the store of `own`. Its nil↔non-nil flips still call `setLocalCursor`,
  as `wirePointer` does today (HEVCDisplayView.swift:315-320). The Mac's arrow never calls it: the
  host has ignored `localCursor` since the cursor left the video, and nothing changes on the wire.
- **`pointerAnchor`** (main reads the feed's lock). This is where a trackpad stroke starts: the
  newest of the Mac's last position over the stream and this device's last pointer event. That
  also mends today's jump back after a finger tap: a tap left `localPointer` nil, and the pad
  carried on from its stale cursor.
- **`pointerTakeovers`** (the feed's `takeovers`; `reseeds` since the review, read with the anchor
  in one look, `pointerFeedState`). The pad reads it at each move and re-seeds its
  cursor from `pointerAnchor` when it changed since the pad's own last move. TrackpadView adopts
  the shared pointer only at a stroke's first finger today (TrackpadView.swift:368-373), so a
  finger resting on the pad while the Mac took over would otherwise carry on from where it
  stopped and pull the Mac's pointer back (§7.5).
- **`setPointerLayout(portrait:)`** and **`trackpadFingers(_ n: Int)`**.
- **`pointerFrameChanged()`** replaces the body of `onVideoSizeForPointer`
  (HEVCDisplayView.swift:323-327). It re-centres only this device's own pointer, and only while it
  shows under this device's control: `own = (0.5, 0.5)` and one move, as today. Under the Mac's
  control it does nothing, because the host's next kind 26 is already in the new source's
  geometry.

**`tearDown`** (StreamClient.swift:1346-1366) resets:
- the feed (elsewhere, no position, no anchor);
- the presence (no own pointer);
- the link's count, through the setter.

**A hand-over to a new connection** (the move from AWDL to the network; after the PR #12 rebase
also its `adopt` and `reconnectNow`) keeps the feed (same Mac) and restarts the count. The host
cannot tell the new connection from a new device (connections are its only identity, §4.3): the
new one is not the controller, so the host sends it the pointer's state at its first tick, and,
while it still applies what the device sent on the old connection, those positions too. Judged by
`seen` alone they are fresh whenever nothing is held for the new connection (seen 0 against a
count of 0), and the Mac's arrow would appear wherever the device left the pointer, in landscape
too, after every move: with PR #12 every time the cable goes in or out. So the feed carries the
hand-over over:
- **When.** Control was `.here` when the new connection took the session.
- **What it does.** Until this device's first kind 8 on the new connection, a fresh kind 26 that
  `isRestatement` (inside, within 0.002 of the anchor or of a position in `recent`) is the
  device's own doing reported back, and changes nothing. Any other is news, the Mac's or another
  device's, and takes control as usual.
- **Kept messages.** What `probeMove` kept is handled after the hand-over, so a kept kind 26 is
  judged against the new count and the carry-over: seen 0 against any held input is stale, and a
  restatement changes nothing.
- **Not a hand-over.** A session that ended on the connect screen starts afresh (`tearDown`),
  with Q6's arrow.

#### 7.4 The display view (`HEVCDisplayView.swift`)

- **`setPointer(_ p: CGPoint?)`** replaces `setLocalPointer(_:) -> Bool` (lines 107-116). It
  returns nothing, since `setLocalCursor` now follows the own pointer (§7.3).
- **`placeCursor`** (lines 148-160) and the no-animation transaction stay. So does `setCursorShape`
  (lines 121-143), for both sources.
- **`StreamView.wirePointer`** (lines 311-330) sets `client.onPointerChange = { [weak view] in view?.setPointer($0) }`
  and `view.onVideoSizeForPointer = { [weak client] _ in client?.pointerFrameChanged() }`, then
  catches up with `client.renderPointer()`. These are still plain assignments, so a re-host after
  a rotation replaces them.
- **The class comment** (lines 26-30) is updated to say both sources.
- **DEBUG `debugFrameSize(_:)`** sets the frame size the sprite needs without a stream, for the
  harness.

#### 7.5 Call sites

| Where (78d76e0) | Today | Now |
|---|---|---|
| TrackpadView `moveCursor`, `handleLongPress`, `click` (212-221, 394-427) | `setLocalPointer(cursor)` | `setOwnPointer(cursor, from: .trackpad)` |
| TrackpadView `adoptSharedPointer` (228-231), from `touchesBegan` and `didMoveToWindow` | From `localPointer` | From `pointerAnchor` |
| TrackpadView `moveCursor` (212-221), and the scroll and drag positions that read its cursor (313, 339, 400-409) | The pad's own cursor | The same, after re-seeding from `pointerAnchor` when `pointerTakeovers` changed since the pad's last move |
| TrackpadView `touchesBegan`, and a new `touchesEnded`/`Cancelled` | — | `trackpadFingers(count)` (only Q1's flip reads it) |
| InputOverlay `handleTap`, `handleLongPress`, `handlePan` (119, 129, 145) | nil | `(nil, .none)` |
| InputOverlay `handleHover` (211) | Pencil: shown; the iPad's own pointer: nil | Pencil: `(at, .pencil)`; the iPad's pointer: `(nil, .none)` |
| InputOverlay `touchesBegan`/`Moved`/`Ended`/`Cancelled` (240-267) | Shown, for the Pencil and the iPad's trackpad alike | Pencil: `(at, .pencil)`; the iPad's trackpad or mouse: `(nil, .none)`, since iPadOS draws its own pointer (the hover already assumed it) |
| InputOverlay `insertText`, `deleteBackward`, `pressesBegan` (300, 311, 391) | nil | `(nil, .none)` |
| InputOverlay's doc (24-31) | "The Pencil shows it…" | The Pencil draws it only with Q2's flip; a finger, typing, keys and the iPad's own pointer never do |
| PortraitStreamScreen (219-227, 244-249), StreamScreen (323-330) | `{ client.localPointer = $0 }`, `{ client.localPointer }` | `{ p, origin in client.setOwnPointer(p, from: origin) }`, `{ client.pointerAnchor }`, plus the trackpad's `onFingers` |

#### 7.6 Layout

- `DuoLayout` gains `var isPortrait: Bool { self == .innerPortrait || self == .outerPortrait }`.
- StreamScreen's `GeometryReader` (StreamScreen.swift:125-134) adds
  `.onChange(of: DuoLayout.of(geo.size).isPortrait, initial: true) { _, p in client.setPointerLayout(portrait: p) }`.
- The windowList handler sets `presence.streaming` from `active`.
- A rotation re-renders at once: the trackpad's arrow goes in landscape and comes back in portrait.
  The Mac's arrow stays through it.

#### 7.7 Harness (DEBUG; the contract comment at ContentView.swift:56-120, and CLAUDE.md)

- **`-SillPointer <state>`** seeds the mock client's presence and gives the display view the mock's
  2800×1800 frame size (`debugFrameSize`):
  - `mac@0.40,0.30`: the Mac has it, over the stream;
  - `device@0.62,0.55`: this device's trackpad pointer;
  - `hidden`: the Mac has it, off the stream;
  - `pencil@0.50,0.50`: this device's Pencil pointer.
- **`-SillPencilPointer 1`** turns Q2's flip on for one run, to photograph it.
- Both are ignored with `-SillLive 1`, whose session shows the real thing.
- **`-SillInputScript '<t> <step>; …'`** (with `-SillLive 1` only), for the simulator gates when
  the control tool cannot be used: t is seconds since the session's first window list, and a
  step is `pad DX,DY` (the portrait pad's own move path, as a finger moving DX, DY points; the
  first after a `lift` starts a stroke and adopts the anchor as a first finger does), `lift`,
  `tap X,Y` (the overlay's tap at a frame fraction) or `key USAGE`. The pad and the overlay
  register themselves in DEBUG and the script calls their own methods, so the feed, the anchor
  and the sprite get what a finger would give them.

#### 7.8 DEBUG console lines (device)

```
pointer: the Mac has it at 0.4213,0.1873
pointer: the Mac has it, off the stream
pointer: this device has it
pointer: ignored a position the Mac sent before reading this device's input (seen 41, sent 42)
pointer: carried over to the new connection; this device keeps the pointer
pointer: ignored the Mac restating this device's own position on the new connection
```

- **"the Mac has it"** prints once per hand-over, not per position.
- **"ignored"** prints at most once a second, each kind.
- **"carried over"** prints once per hand-over that carries control over.

---

### 8. Timeouts and limits

| What | Value |
|---|---|
| Poll | Once a link tick (30 ms), only while the tick runs and a source has geometry |
| Sill's settle | 0.25 s after the host reads a pointer or scroll input, or is about to post one or warp the cursor |
| A real move | 0.5 pt from the last position that counted, outside the settle (slow motion adds up) |
| Kind 26 | At most one per device per tick; only when x, y (4 decimals), `inside` or `seen` changed; about 63 bytes with the header |
| A regular window's bounds | Re-read on `sill.pointer` at most every 0.1 s, only after a tick whose read moved; and at every catalog poll (`windowsChanged`) |
| Freshness | `seen` ≥ the kind 8 messages sent on this connection, and no coalesced move waiting |
| The carry-over | From a hand-over while this device had control until its first kind 8 on the new connection; a restatement is within 0.002 of the anchor or of a position this device sent in the last 3 s |
| The trackpad's arrow | Until another input takes over (Q1: or 2 s after the last finger lifts) |
| Test pointer file | 10,000 steps, 1 MiB |

### 9. Edge cases

| Case | Behaviour |
|---|---|
| Two displays, the Desktop streams one | Off that display the arrow hides |
| Regular mode, another window covers part of the streamed one | Shown over the whole rectangle (Q7). The covered part is frozen on the device anyway (macOS stops repainting it) |
| The window minimized or on another Space | Hidden (`kCGWindowIsOnscreen`) |
| The Mac's pointer on the virtual display | Shown over the staged window, never on the Mac's screens. The device's own input already leaves it there, so the Mac's user moves an invisible pointer until it crosses back to a real display (as today; Q9) |
| Full-screen video on the virtual display | Shown inside the band. When the player hides its cursor after a few still seconds, the device's arrow stays (Q8) |
| Device input while the Mac's mouse also moves | The device wins while its input keeps coming (each one opens 0.25 s), and each device move puts the Mac's pointer back where the device says: absolute and relative input fight on the Mac, and nothing here prevents it. The Mac's motion shows once it goes on past that |
| The device starts a stroke while the Mac's mouse is moving | Its first move lands at the Mac's position as last reported, one tick plus the one-way latency old: a small jump back on the Mac, more over a remote link |
| The Mac takes over while a finger rests on the portrait pad | The sprite jumps to the Mac's pointer; when the finger moves again the pad re-seeds from it (`pointerTakeovers`), so the Mac's pointer is not pulled back to where the finger stopped |
| Two devices driving at once | Each input takes the controller, and a device hears the other's positions only while it has sent nothing since, so its sprite can alternate between its own and the other's. Accepted |
| The Mac's mouse and a device tap within one round trip | The echoed count drops the host's older message; the device keeps the pointer (§3.3) |
| A click held for an app's activation (a second or more when the app is slow to answer Accessibility) | The read at arrival opens the settle and the post opens it again, just before it posts; a real move in between counts |
| A streamed window moves while the Mac's pointer is still (an app or a shortcut moved it) | The reported fraction follows at the next catalog poll (up to 2 s); the pointer's next move re-reads the bounds at once |
| A tap past a display's edge (a window partly off screen) | The window server clamps the cursor; the settle absorbs it |
| A still Mac pointer, Sill untouched for minutes | The arrow stays where it is; no message goes out |
| An app warps the pointer (Universal Control, "move to default button", a game) | A move: the Mac has it. Across to another device or display: hidden |
| A game that captures the mouse (hidden, fixed cursor) | No motion is seen; nothing changes |
| Scroll events posted with a location | Whether they move the cursor is not known here; the settle covers both ways |
| Keys and text from the device | They hand it the pointer (the arrow hides in landscape) without opening the settle |
| Two devices | Each sees the pointer while the other drives it (Q5). A device typing takes control, so the other's arrow appears where the pointer is |
| The driving device disconnects | The Mac has the pointer again |
| A move to a new connection (AWDL to the network; after PR #12, cable ↔ Wi-Fi and `reconnectNow`) | Counts restart per connection. The host takes the new connection for a new device and sends it the state at once; the device carries its control over, and reports of its own positions change nothing until it sends input there (§7.3). No arrow appears while this device had the pointer |
| A reconnect through the connect screen | A new session: the Mac has the pointer and the arrow shows until the device's first input (Q6) |
| A remote session (TLS, slow link) | Kind 26 is not counted in `inflight`, so frame pacing is unchanged. The arrow trails the Mac by half the round trip plus up to a tick |
| Nothing streams | No geometry, no read; the device hides the sprite (`streaming` false) |
| A source switch while the Mac drives | The next tick's position is in the new geometry, so it is sent even without motion. The arrow may sit a frame or two against the old picture |
| The Aa slider, a resize, a rotation | Mac control: the host's next message follows. Device control: the device re-centres its own pointer as today |
| Sill's own windows (excluded from Desktop streams) | The pointer over them shows over what the stream shows there |
| Older device, newer host (and the reverse) | §3.4 |

### 10. Test gates

**Hard rules for the implementing session:**
- **Synthetic hosts only,** from `.build/release`, started from Python with
  `start_new_session=True`, killed by PID, none left running.
- **`SILL_TEST_SOFTWARE_ENCODER=1` on every host** except H2's parity runs.
- **H2's parity runs use the hardware encoder,** as every earlier parity run did. Run them only
  while Sill.app has no device connected: `~/Library/Logs/Sill/Sill.log`, read-only, has no
  `client ` line in the last minute. Otherwise wait, and say so in the results.
- **Never post a CGEvent and never move the pointer.** `--move`, `--tap` and `--key` only against a
  host started with `SILL_TEST_POINTER_PATH` (sillclient.py itself refuses anything but a
  `--synthetic` listener on this Mac, §5). Synthetic hosts are dry runs (§4.5).
- **The simulator:**
  - no XCUITest;
  - no `simctl io recordVideo`;
  - no iOS Simulator control tool `attach` (the Simulator's recorder runs at priority 80 and
    starves Sill's encoder);
  - screenshots with `xcrun simctl io <udid> screenshot`;
  - taps and strokes with the control tool's headless `tap`, `swipe` and `touch_path`, which asks
    Noah once per simulator device before its first use; a session that cannot ask (a workflow)
    drives the same steps with `-SillInputScript` (§7.7) instead;
  - a simulator of its own, not the shared iPad Pro 13".
- **Never touch** `/Applications/Sill.app`, the `me.saffer.sill.mac` domain or Noah's iPad. App
  paths use the bare `SillMenuBar --synthetic`; `defaults delete SillMenuBar` afterwards.
- **`$T`** is a fresh temporary directory per gate.

**Headless (H): no permissions needed.**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). Record the base (this plan's commit on `remote-access`); `git archive` it to `$SP/base` and build it; H2's baselines; both probes again ("Measured"; the permission one as an ad hoc app of its own launched with `open`, since anything started from the session's shell inherits claude.app's grants); on every branch and in every worktree's working tree, uncommitted changes included: kind 26 still free (23 is the hello's) and the pbxproj IDs A301/F301 unused | Files exist; the numbers are recorded; the no-grant probe reads live points with all four preflights false |
| H1 | **Builds.** `swift build -c release`; iOS Debug and Release for the simulator | Only the known warnings (CaptureProbe; the old `StreamClient` capture warning) |
| H2 | **The CLI byte for byte.** Base and new `SillHost --synthetic`: idle 35 s, and with `sillclient.py PORT 5 desktop`; both again with `--direct-wireless`; digits masked, sorted. Then `sillclient.py PORT 5 desktop --pointer` against the new default host | Identical; the client's `kinds=` and `first kinds:` identical (no 26); the `--pointer` run prints no pointer line |
| H3 | **Pure checks, each with mutants caught.** `PointerControl` (at least 28): the settle absorbs Sill's input and posts, keys do not open it, jitter of ±0.3 pt around one point never hands over, a drift of 0.2 pt a tick hands over by the third tick, a move after the settle hands over once, a leaving driver hands back, two clients. The fraction (at least 10: corners, edges, outside, empty rectangle, rounding). `PointerPresence` and the feed (at least 45): every row of "What the device draws", freshness (lower `seen`, equal with a move waiting, nil against 0 and 1), the anchor's newest-wins, both flips, the carry-over (a restatement of the anchor or of a position sent in the last 3 s changes nothing; any other position, and `inside` false, take control; the first kind 8 on the new connection ends it), `takeovers` counting only here → elsewhere. `MacPointer`'s JSON (round trip, `{}` decodes, unknown keys ignored). SessionLink's count: the fence check's four modes, plus the count restarting at a hand-over at the number held (after the PR #12 rebase also at `adopt`, and unchanged by `unhold`) | All pass; at least 7 mutants of `PointerControl` and 10 of `PointerPresence` and the feed, e.g. no settle, keys opening the settle, `last` moved at every read (a slow drift never hands over), no portrait check, the Pencil shown, `>` for `≥`, the pending move ignored, no carry-over, no mid-stroke re-seed |
| H4 | **The test pointer.** `SILL_TEST_POINTER_PATH=$T/path` with steps `0.5 756 474.5`, `1.0 1134 237.25`, `1.5 -40 474.5`, `2.0 378 711.75`, `2.0 378 711.75`; `sillclient.py PORT 4 desktop --pointer` | The "Test pointer: 5 steps…" line. Exactly four pointer lines, about 0.5 s apart after the stream starts: (0.5000, 0.5000), (0.7500, 0.2500), `inside=0`, (0.2500, 0.7500), all `seen=0`; nothing for the repeated step |
| H5 | **A move hands it back, and Sill's own motion is Sill's.** (a) A still path (one step at 0.5): `--move=0.25,0.25@2` with `--pointer`. (b) A path moving 5 pt every 0.05 s from 1.0 to 5.0 (X from 400, Y 474.5): `--move=0.25,0.25@3` | (a) `in.dry 1`; the first state, then no pointer line to that client for the rest of the run, although the test pointer moved to its position. (b) Lines until about 3.0; after the move's send, lines with `seen=0` only within a few ms (in flight), then a gap of 0.25–0.35 s; the next line has `seen=1` |
| H6 | **A key hands it back without the settle.** Path (b); `--key=4@3` | The gap after the key is at most 0.1 s; the next line has `seen=2` (the key's down and up are two kind 8 messages) |
| H7 | **Two clients.** A `--move=0.25,0.25@2 --pointer`, B `--pointer`, a still path | B prints (0.2500, 0.2500) `seen=0` after A's move; A prints its first state and nothing after its move (without `--pointer` A would print no pointer line at all, and the check would pass by default) |
| H8 | **Rate and stillness.** A path of 2,000 steps 1 ms apart, then none | At most 34 pointer lines in any second; none once the path has stopped |
| H9 | **Nothing posted.** H5–H8's host logs; a read of the real pointer before and after (inconclusive if the Mac's mouse moved in between: repeat) | Every second with input shows `in.dry` and never `in.pointer`, `in.scroll`, `in.text` or `in.key`; the real pointer unchanged |
| H10 | **Cost.** A swiftc harness times `PointerWatch.sample()` 100,000 times with a fixed rectangle, and 100,000 with a regular window whose re-read is due at every sample (a scripted point that moves each time, the 0.1 s gap set to 0), and times the re-read on `sill.pointer` alone. `ps` of a hook host with no client for 35 s | Up to 5 µs a sample in both (a sample never waits for the window server); the re-read up to 250 µs; idle CPU 0.0 % |
| H11 | **Hard rules** (grep the lines the branch adds, `git diff <base>..HEAD`, as well as the tree: the base already has `MainActor.assumeIsolated` in HostShutdown.swift:63 and `updateConfiguration` in a comment in WindowCapture.swift, so a grep of the tree alone fails before a line is written) | No `CGEventTapCreate`, `tapCreate`, `addGlobalMonitorForEvents`, `addLocalMonitorForEvents`, `CGRequestListenEventAccess` or `CGRequestPostEventAccess` in Sources/ or iOSClient/. No added `updateConfiguration` or `assumeIsolated` in Sources/SillHost. `showsCursor: false` still at the stream's capture start (StreamCoordinator.swift:957). The hooks are read only where `synthetic`. The dry run has no `post(` on its path, and `sillMoved()` comes before every `post(` of a pointer or scroll event |
| H12 | **Previews.** The bare app's `-SillRenderPreviews` before and after | Identical |
| H13 | **Compatibility.** The base's `sillclient.py` against an H4 host; the base's StreamMessage.swift with a kind 26 header (swiftc); the new device decoder against the base host's messages | The old client runs and fails nothing (26 counted as unknown); `.unknown`; nothing new decoded |

**Simulator (S):**

| # | Check |
|---|---|
| S1 | **The photo matrix.** `-SillPointer mac@0.40,0.30`, `device@0.62,0.55`, `hidden` and `pencil@0.50,0.50`, each at 1000x710, 710x1000, 500x710 and 710x500; `pencil` again with `-SillPencilPointer 1`: 20 photos. Expected: `mac` shows at all four, the tip at 40 %, 30 % of the video rect (±2 pt); `device` only at 710x1000 and 500x710; `hidden` nowhere; `pencil` nowhere, and at all four with the flip. Send Noah the sheet |
| S2 | **Live, portrait.** `-SillLayout 710x1000 -SillLive 1 -SillConnect 127.0.0.1:P` against a hook host, plus `sillclient.py --pointer` as a second device. The path steps at 1, 2, 3, 5.5 and 9 s only, the 5.5 s step at least 0.1 from where the stroke below rests. Screenshots at the first three steps show the arrow at the scripted fractions. A slow stroke on the trackpad (`touch_path` or `-SillInputScript`): down at 4.0, 20 pt by 4.5, the finger resting until 6.5, 20 pt more by 7.0, up. The first position the second client prints after 4.0 is within 0.02 of the 3 s step's (no jump); a screenshot at 6.0 shows the arrow at the 5.5 s step (the Mac took over mid-stroke); the first position after 6.5 is within 0.02 of the 5.5 s step's (the pad re-seeded: no jump back); the 9 s step jumps the arrow to it. The default `swipe` (0.3 s) moves 20 pt or more per touch sample and would miss the 0.02 bound by itself |
| S3 | **Live, landscape** (1000x710). The arrow shows at the steps (1 s apart); a tap on the stream half-way between two steps hides it (screenshot); the next step, 0.5 s later and so past the settle, shows it again |
| S4 | **Freshness through a delay.** `sillrelay.py --listen 0 --to 127.0.0.1:P --delay-ms 150` between the simulator and the host (`-SillConnect` to the relay's port); a path moving every 0.05 s; five taps on the stream 2 s apart. The console shows "ignored a position…" at least once, and never "the Mac has it" within 0.3 s after "this device has it". Correct behaviour gives about 0.40 s or more (the settle's 0.25 s, the relay's 0.15 s round trip, up to a tick); a stale position taken as fresh shows within about 0.15 s. A 0.4 s bound would sit on the correct minimum and flake |
| S5 | **A move carries control over.** `-SillLayout 1000x710 -SillLive 1 -SillConnect 127.0.0.1:P -SillMoveTest 1` against a hook host whose path steps at 0.5 and 12 s only. The arrow shows at connect (Q6); a tap on the stream at 1.5 s hides it; the session moves ("discovery: the session moved to the network", about 3 s in); screenshots 1 and 3 s after the move show no arrow, and the console prints no "the Mac has it" between the tap and 12 s; the 12 s step shows the arrow. After the PR #12 rebase, the same for its moves with `-SillPathTest` |

**Noah's devices (P), handed over at the end:** the iPad mini; an iPhone for P9; the cable for P12.

| # | Check |
|---|---|
| P1 | **The Desktop, landscape.** Move the Mac's mouse: the arrow on the iPad where it is on the Mac, in the same shape (the I-beam over text, the hand over a link), following within about a tick. Stop: it stays. Tap the iPad's screen: gone at once. Move the mouse again: back |
| P2 | **A window, regular mode** (virtual display off). Over the window: shown. Off it: gone. Over another app's window overlapping it: still shown (Q7). Minimized: gone |
| P3 | **Portrait.** The on-screen trackpad: the arrow follows the finger as before and starts exactly where the Mac's arrow was; on the Mac the pointer does not jump. Lift: it stays (Q1). Move the Mac's mouse: the arrow jumps to it. The trackpad again: it carries on from there. Rest a finger on the pad, move the Mac's mouse (the arrow jumps to it), then move the finger: it carries on from the Mac's pointer, never back to where the finger stopped. The same with the finger coming down while the Mac already has the pointer, then a move or a tap: never back to where the finger landed (the review's case, "Review fixes"). Both at once: the pointer fights on the Mac (expected); nothing sticks once either stops |
| P4 | **Rotation.** After the trackpad, rotate to landscape: no arrow. Move the Mac's mouse: the arrow shows in landscape. Rotate back and use the trackpad: the device's own |
| P5 | **Typing.** The software keyboard or a hardware key hides the portrait arrow (as today); the key row's keys do not; the next trackpad stroke shows it |
| P6 | **The Pencil** draws no arrow while it touches (Q2; before this change it did). Hover cannot be checked on the iPad mini 6 (iPad14,1), whose Pencil does not hover, nor in the simulator; only S1's photo covers that state |
| P7 | **The virtual display on.** Pick a window. Move the Mac's mouse onto the "Sill" display over the staged window: the arrow on the iPad, nothing on the Mac's screens. A video full screen there: the arrow inside the band; when the player hides its cursor, the iPad's arrow stays (Q8) |
| P8 | **Remote** (Tailscale, the iPad on the hotspot). P1 again: the arrow trails the Mac by about the round trip; `net.dropped` in the host's `[1s]` lines is no higher while the mouse moves |
| P9 | **Two devices** (the iPad and an iPhone). The iPhone shows the arrow the iPad's trackpad moves (Q5); the iPad draws its own only in portrait |
| P10 | **Mixed builds.** This iPad against PR #13's Sill.app: no Mac arrow; the trackpad's arrow in portrait only; no Pencil arrow. PR #13's iPad against this Sill.app: as before |
| P11 | **Five minutes on a still window,** the Mac's mouse moved now and then. Sill.app's CPU in Activity Monitor as before (±0.2 %); frame age and rtt in the `client …` lines unchanged; `ptr.sent` only in seconds the mouse moved; the arrow never choppy enough to want Q4 (Noah's call) |
| P12 | **Moves keep the device's control** (once PR #12 is in). Streaming in landscape, tap the stream, then plug the cable in, and later pull it: no arrow appears at either move; move the Mac's mouse: it shows. The same across the AWDL move (W6) |

### 11. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

0. **Preflight** (no commit). Branch `pointer-visibility` from `remote-access` at this plan's
   commit: kinds 18–22 must exist, and once PR #13 has merged, branch from main. Then H0.
1. **"Protocol: kind 26, the Mac's pointer."**
   - StreamMessage.swift: the case and its note (23 the hello; 24, 25 and 27 the menu bar's).
   - Pointer.swift: `MacPointer`.

   Gates: H1, H3 (the JSON), H13 (the decoder part).
2. **"Host: the Mac's pointer to every device not driving it."**
   - `PointerControl` and `PointerWatch`.
   - StreamServer: the counts, the tick, `clientLeft`.
   - The coordinator's geometry.
   - InputInjector: the notes and the dry run.
   - VirtualStage's `onWarp`.
   - The two hooks.
   - `sillclient.py`'s `--pointer`, `--move`, `--tap` and `--key`.

   Gates: H1–H13.
3. **"iOS: the Mac's pointer while it drives; the device's own on the portrait trackpad only."**
   - `PointerPresence`, with its pbxproj entries A301/F301.
   - SessionLink's count.
   - StreamClient.
   - HEVCDisplayView.
   - The trackpad and overlay call sites.
   - The layout flag.
   - The harness.

   Gates: H1 (iOS), H3 (the presence, SessionLink), S1–S5.
4. **"docs: the Mac's pointer on the device."**
   - This plan's Results section.
   - CLAUDE.md:
     - the Current step;
     - Layout (the new files);
     - Build and run: the hooks, the new `sillclient.py` flags, `-SillPointer`,
       `-SillPencilPointer`, `-SillInputScript`;
     - the trackpad-stutter section's cause 3: the sprite also shows the Mac's pointer while the
       Mac drives;
     - Untested, for Noah: P1–P12.
5. **Review and hand-over.**
   - Three lenses:
     - the control rule and its races, on both ends (the settle, the count, hand-overs);
     - threads, the lock and cost on the host;
     - the device UI in all four layouts and through rotation.
   - A "Review fixes" commit if needed, then H4–H9 and S2–S5 again on the final build.
   - Hand P1–P12 to Noah. **Stop there.**

**Rebases.**
- **PR #11 (encoder-recovery)** touches StreamCoordinator. Its `recheckLoop` must never start
  under `SILL_TEST_SOFTWARE_ENCODER` (§4.10).
- **PR #12 (follow-best-path)** touches StreamClient and SessionLink. Its `adopt` restarts the
  count and `unhold` leaves it; its `adopt` and `reconnectNow` carry control over as the AWDL
  move does (§7.3), and S5 runs again with `-SillPathTest`.
- **update-notice** (no PR yet; worktree winstream-update) takes kind 23 (`hello`) and the pbxproj
  IDs A01E/F01E and A01F/F01F, and touches StreamServer's receive loop and registration (its
  device gate), SessionLink and StreamClient. The `inputsRead` count stays in the `.input` branch,
  and a connection the gate holds unregistered gets no kind 26, as it gets no tick.
- Whichever lands first, the others need a small rebase.

### 12. Hard rules (for every step)

- **No new permission.** Never an event tap, never a global monitor, never
  `CGRequestListenEventAccess` or `CGRequestPostEventAccess`. The only read is the pointer's
  location, which needs none.
- **Never reconfigure a running SCStream.** `showsCursor` stays false; the cursor never goes back
  into the video.
- **Never `MainActor.assumeIsolated`** in core code. The tick samples on `sill.net`; the
  coordinator hands its geometry over through PointerWatch's lock.
- **Nothing on `sill.net` waits for the window server** beyond the pointer read itself: the
  window bounds are re-read on `sill.pointer` (§4.2).
- **The CLI's stdout stays byte for byte** on the default path, idle and streaming, with and
  without `--direct-wireless`. New output only under the hooks, or as `[1s]` keys on real hosts
  when kind 26 goes out.
- **Kinds 0–23 and kinds 8 and 9's payloads are untouched.** 24, 25 and 27 stay free for the Mac
  menu bar (23 is the device's hello, from update-notice).
- **Tests never post events or move the pointer,** and never use the hardware encoder while Noah
  streams. They never touch `/Applications/Sill.app`, `me.saffer.sill.mac` or his iPad.
- **TEST ONLY hooks** are honoured only by synthetic hosts, which do not advertise.
- **New iOS files** need their four pbxproj entries by hand. Swift 5 language mode.
- **Apple frameworks only.**

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **When is the trackpad "used"?** Default: **from its first input until another input takes
   over**, today's rule. In the laptop layout the arrow is the only way to aim a tap. The
   alternative hides it 2 s after the last finger lifts: `PointerPresence.trackpadLinger = 2`.
2. **The Pencil.** Default: **no arrow** (hover or touch), by the letter of the request. Today it
   draws one. The flip: `PointerPresence.pencilShowsPointer = true`. Noah's iPad mini 6 has no
   Pencil hover, so there the only change is under a touching Pencil's tip, which covers the arrow
   anyway; hover (an iPad Pro with M2 or later, or a Pencil Pro) is where the flip would matter:
   without it a hovering Pencil aims with no arrow.
3. **How the host notices the Mac's own mouse.** Default: **a position poll** at the link tick, no
   new permission. A click or scroll on the Mac without motion does not take the pointer back. The
   alternative is a listen-only event tap: it sees those too, and costs Input Monitoring (a third
   permission, a second alert; without it a mouse-only tap silently gets nothing) unless the
   Accessibility grant turns out to cover it.
4. **The rate of the Mac's arrow.** Default: **the 30 ms tick**, about 33 Hz. It can look choppier
   than a 60 or 120 fps picture. The alternative samples at the stream's frame rate while the
   Mac's pointer moves: a second timer on `sill.net`, about 20 lines, at most 120 messages (8 KB) a
   second. **Decided 2026-09-26: the alternative** ("Since the critique", below).
5. **Another device's pointer.** Default: **shown to every device but the one driving**, as if the
   Mac had moved it. The alternative is that only the Mac's own mouse counts, and another device's
   moves show nothing.
6. **At connect.** Default: **the Mac's arrow shows** until the device's first input: nobody has
   driven yet, so the Mac has it. The alternative is hidden until the Mac's mouse moves.
7. **A covered window, regular mode.** Default: **shown over the whole window rectangle**, even
   where another Mac window covers it. The alternative hides it there: one more window-list read,
   about 160 µs, at most 10 a second.
8. **An app that hides the Mac's cursor** (a video full screen, typing on the Mac). Default:
   **the arrow stays** (no public API tells another app's cursor is hidden). The alternative hides
   it after 3 s without motion, in the full-screen band only.
9. **The virtual display.** Default: **Sill never moves the pointer the Mac's user holds.** When
   they take over while it sits on the virtual display, they move it there, invisible on the Mac,
   and the device shows it. The alternative warps it back to where it was before the device drove
   it there (`cursorBefore`), and the device's arrow then goes.
10. **Synthetic hosts never post input.** Default: **yes**, always; it keeps every test off the
    real pointer. The alternative is only with the test pointer set.
11. **A setting.** Default: **none**. The alternative is a switch in Settings › Streaming and the
    menu, "Show the Mac's pointer on devices".
12. **The kind number.** Default: **26**, leaving 24, 25 and 27 to the Mac menu bar sketch (23 is
    the device's hello, from update-notice). If that sketch is dropped, 24.
13. **Windows too?** Noah wrote "the real mouse pointer on the desktop on Sill". Default: **the
    Mac's pointer shows over whatever streams**, the Desktop or a window ("on the desktop" read as
    "on the Mac's screen"). The alternative shows it only while the Desktop streams: one line in
    `pointerGeometry()`.

---

## Critique (2026-09-25, the same day)

An adversarial pass over this plan against the code at cf288cb and 2c83c86, every branch and
worktree (uncommitted changes included), Apple's SDK header and reference pages, and one outside
measurement. It changed the plan in place:

- **Permissions.** The first probe ran from this session's shell, whose responsible process
  (claude.app) holds Screen Recording, Accessibility, Input Monitoring and PostEvent, so its
  "without Screen Recording" was wrong. A second probe, an app of its own with none of the four,
  read the pointer 30 times off the main thread: the poll needs no permission. The listen tap is
  no longer "not settled": measured elsewhere on macOS 26.7, a mouse-only listen tap without Input
  Monitoring is created, never enabled, and shows no alert. The Mac app ships outside the App
  Store, so a tap would change no App Privacy answer.
- **Sill's own motion.** `sillMoved()` and `onWarp` now come before the post and the warp: a tick
  landing between a post and a note made after it took Sill's move for the Mac's. A held click can
  post a second or more after it was read (a 1 s AX activation timeout, then up to 0.6 s of hold),
  not 0.6 s at most.
- **Slow motion.** A real move is measured from the last position that counted, not from the
  previous read, which let a drag slower than 17 pt/s never count.
- **Hand-overs.** The host takes a moved session's new connection for a new device and sends it
  the state at once, and seen 0 against a count of 0 is fresh: as written, the Mac's arrow
  appeared after every AWDL move, and after PR #12 at every cable plug and pull, while the device
  was driving. The device now carries control over (§7.3). The trackpad adopted the anchor only at
  a stroke's first finger, so the Mac's takeover under a resting finger was undone by the next
  move: `pointerTakeovers` re-seeds it. "The Mac's pointer does not jump" held only for a still
  pointer; both moving at once is now described as it is.
- **Synthetic hosts.** Synthetic mode replaces only the Desktop, so a real window can be picked on
  a synthetic host, and the table gave it real geometry: the poll would have read the real pointer
  there. Now only the scripted test pattern has geometry on a synthetic host.
- **Threads.** The window re-read left `sill.net`, where a window-server round trip sat in front
  of frames and pongs.
- **Numbers.** Kind 23 is update-notice's hello (3a2470b), so "23–25 free for the menu bar" and
  Q12's fallback were stale; 26 is still free everywhere. The pbxproj IDs A01E/F01E are
  update-notice's GoodbyePolicy.swift: PointerPresence takes A020/F020.
- **Encoder.** After PR #11, a host kept on software by the hook would still test the hardware
  30 s in (`recheckLoop`); the hook now keeps it off.
- **Tests.** The input flags' guard read the client's own environment, which says nothing about
  the host; it now requires a `--synthetic` listener on this Mac. H6 expects `seen=2` (a key is a
  down and an up); H7's A needs `--pointer`, or it passes by default; H10 could not reach the
  window re-read (throttled, and the real pointer is still); H11 grepped the tree, where the base
  already has `assumeIsolated` and `updateConfiguration`, so it failed before a line was written;
  S2's default swipe missed its own 0.02 bound and its steps could land inside the settle; S4's
  0.4 s bound sat on the correct minimum; the simulator's touch tool asks Noah once per device,
  so a workflow gets `-SillInputScript`. New: S5 and P12 (moves), P3's resting finger, Q13
  (windows, or only the Desktop).
- **Smaller.** `in.dry` counts posted events, not inputs; the Q1 flip's timer is new code, not
  "already there"; the bounds timing was measured again (111 and 126 µs); Q2 now says Noah's iPad
  mini 6 cannot hover, so P6 checks a touching Pencil only; the edge cases gained both moving at
  once, the resting finger, two devices driving and a window moving under a still pointer; §8
  and the device's console lines gained the carry-over.
- **Checked and left alone.** The rectangle per source (the injector's own: live window bounds,
  the virtual display's crop and full-screen band from `captureRectOnScreen`, the Desktop's
  `catalog.display.frame`), the freshness rule and its coalesced-move check, the tick's rate and
  idle cost (no tick without a device and a live source or recent input), the CLI's parity on the
  default synthetic path, Q2's letter-of-the-request default, and the line references, which hold
  at cf288cb and at 2c83c86 (no host, protocol or device code changed since 78d76e0).

---

## Since the critique (2026-09-26)

- **The open questions.** The workflow implementing this plan, to which Noah left them, takes
  every default except Q4's: the host samples the pointer at the stream's frame rate while it
  moves, not only at the 30 ms tick. So faster sampling is in this step, and what §4.8, §8 and H8
  say per tick holds per sample while the pointer moves (up to the stream's rate, 120 a second at
  120 fps); the host's step sets the numbers. While the frame-rate sampler runs, the tick should
  only keep the link awake, not sample as well: in a model of the host (step 1's scratch, not a
  check) a pointer moving every 10 ms drew 73 reports a second at 60 fps with both sampling, 57
  with the sampler alone.
- **Step 1, the wire and the pure rules** (branch `pointer-visibility` from main at 8b0d418). Kind 26
  and `MacPointer` as §3 says, with `MacPointer.position` (x and y when `inside` is true and both
  are there and finite) as what a device draws. `PointerControl` as §4.1 says, with two additions:
  - a read more than `settle` (0.25 s) after the one before starts afresh, as the first read does:
    the pointer was not watched in between, and Sill may have moved it then with its settle over
    before the next read (VirtualStage's warp home as a stream stops, while no sample runs); a real
    move in such a gap counts at its next read instead;
  - `isMoving(now:)`: a read differed from the one before in the last 0.1 s, whoever moved it (a
    watching device wants another device's motion as smooth): the frame-rate sampler runs while
    it is true and some device is sent the pointer.
  `PointerPresence.swift` holds §7.2's rules, the feed as `PointerFeedState` under `PointerFeed`'s
  lock (a report comes in as MacPointer's `position`, nil off the stream), and `PadCursor`, the
  pad's cursor, where the mid-stroke re-seed (`pointerTakeovers`) lives. Its pbxproj entries are
  A301/F301: A020/F020, the critique's pick, went on 2026-09-26 to remote-pacing's
  MessageReader.swift (uncommitted in its worktree), and no A3xx is used anywhere.
  `SessionLink.inputsOnSession` as §7.3 says, `adopt` and `unhold` included, and `dropHandOver`
  takes back what it drops. Checks: `Tests/checks/pointer-control`, `Tests/checks/pointer-presence`,
  and the fence check's count (every mode, and a mode of its own).

---

## Results: the host (2026-09-27)

The host half as 49abee1 left it, read against §4–§6 and "Since the critique", then run. Nothing
the plan asks of the host was missing, and no Swift source changed in this step: `PointerWatch`
(§4.2, with the frame rate it samples at), StreamServer's counts, kind 26 at each tick and the
frame-rate sampler (§4.3), the coordinator's geometry per source and the two hooks (§4.4, §4.7,
§4.10), InputInjector's notes before each post and the dry run (§4.5), VirtualStage's `onWarp`
(§4.6), the lines and Stats keys (§4.9) and the test client's flags (§5). Added:
`sillclient.py --input=JSON@T`, a literal kind 8 for inputs the other flags do not make (a scroll, a
scroll gesture's phase), behind the same guard; the pointer-watch check in `Tests/checks/README.md`
and in CI's mutants matrix.

The frame-rate sampler (Q4). While the pointer moves (`PointerControl.isMoving`: a read differed
from the one before in the last 0.1 s) and some device is sent it, StreamServer samples at the
stream's frame interval (`PointerWatch.frameInterval`, from the `fps` the coordinator hands over
with the geometry) on `sill.net`, and the 30 ms tick only keeps the link awake; 0.1 s after the last
change the sampler stops and the tick samples again. A device that drives the pointer is never sent
it, so one device alone never starts the sampler while it drives; while it only watched, the
sampler also ran with the pointer off the source, where every report is the same `inside: false`
and nothing goes out (the review found that, and the rest of what "Review fixes" lists).

The step ran twice. The first run (to about 00:22) ran every gate below and was stopped before it
committed; the second (00:38 to 01:10) read the host again and ran every gate again from a fresh
folder but the two that use the hardware encoder: from 00:38:50 on a device streamed from Noah's
Sill.app over the cable, so main's `Scripts/encoder-check/no-device.sh` said no at every look. Those
two, H2 and the sampler at 120 fps, are the first run's, read again from its logs; Sill.log shows no
device connected while they ran (one from 00:05:46 to 00:10:06 only, which the first run's guard
caught, below). The numbers are the second run's unless a line says otherwise. Other sessions' jobs
held the Mac's load average between 15 and 232 (12 cores) through the second run; every gate passed
through it.

Checked, all without a device, the hardware encoder only where said (such a run started only while
no-device.sh said no device was connected to Sill.app, and was watched every 2 s; every host
synthetic, killed by PID, none left running), and the real pointer only read, never moved (read
before and after each batch of gates: the same point):
- Builds: a clean `swift build -c release` into a scratch path (27 s; only the CaptureProbe
  warning); iOS Debug and Release for the generic simulator, arm64, unsigned, from an empty
  DerivedData (only the old `StreamClient` capture warning).
- Pure checks: `Tests/checks/run-all.sh`, all 16 (pointer-watch 112, pointer-control 147,
  pointer-presence 141, the fence's 15 modes); mutants: pointer-watch 33 of 33, pointer-control 30
  of 30.
- H2, the CLI byte for byte (hardware encoder; the first run, 00:01–00:05): 8b0d418 from
  `git archive` against this branch, `SillHost --synthetic` idle 35 s and with
  `sillclient.py PORT 5 desktop`, both again with `--direct-wireless`: the host's output identical
  masked and sorted (7, 17, 8 and 18 lines), the client's too (which kinds, and
  `first kinds: 2 16 4×119 5 16 2 14` in all four); the default host with `--pointer`: no pointer
  line and no `ptr.` key. The second run read those logs again (the same verdicts), and checked
  that the base folder is 8b0d418's `git archive` file for file with its build current, and that
  the branch's binary is the one that ran (no Swift source changed since; `swift build` had
  nothing to do).
- The gates below ran on synthetic hosts with `SILL_TEST_SOFTWARE_ENCODER=1` and a scripted path,
  and `sillclient.py … --pointer`:
  - H4: the five steps give four lines, (0.5000, 0.5000), (0.7500, 0.2500), `inside=0`,
    (0.2500, 0.7500), all `seen=0`, 0.48–0.51 s apart; nothing for the repeated step.
  - H5a (a still path, a move at 2 s): the first state, then nothing for the rest of the run;
    `in.dry 1` in that second.
  - H5b (5 pt every 0.05 s, a move at 3 s): 39 lines before it, none in flight, the next 0.297 s
    after it with `seen=1`.
  - H5c, new (a scroll gesture's began, which posts nothing, so only the arrival opens the settle):
    the next line 0.305 s after it, `seen=1`, `in.dry 0`. H5d, new (a scroll delta): 0.292 s,
    `in.dry 1`. H5e, new (a kind 8 that does not decode): 0.054 s, `seen=1`: it hands its device
    the pointer, without the settle.
  - H6 (a key at 3 s): the next line 0.060 s after it, `seen=2`.
  - H7 (two clients, A moves at 2 s): B hears (0.2500, 0.2500) `seen=0`; A only its first state.
    H7b, new (A moves at 2 s, B at 3.3 s): each hears the other's position with its own count (B
    `seen=0`, A `seen=1`) and nothing after its own input. H7c, new (A moves, then leaves; the path
    moves 2 s later): B hears all 21 steps and no `ptr.mac` is counted, since the Mac had the
    pointer again. H7d, new (A sends 100 moves 10 ms apart, which the dry run applies to the
    scripted pointer): B hears A's motion 59 times in 0.99 s, 17.0 ms apart (the median): the
    sampler at 60 fps; `in.dry 100`.
  - H8 (2,000 steps 1 ms apart): 119 lines in 1.98 s, at most 62 in any second (the client's
    arrival times jitter by a few ms), 17 ms apart (the median); none once the path stopped. New,
    the stream's own rate: the client asking for 30 fps (the stream then 1512×948 at 30 fps): 60
    lines in 1.97 s, at most 31 in any second, 33.0 ms apart. At 120 fps (the first run, 00:18: the
    hardware encoder at Standard resolution, 1512×948, since the software one stops at 60): 239
    lines in 2.0 s, at most 121 in any second, 8.0 ms apart; its first try was stopped by the guard
    when a device connected to Sill.app at 00:05:46, the host killed within the watch's 2 s.
  - H9: the 17 host logs of the second run's gates: 11 seconds with `in.dry`, none with
    `in.pointer`, `in.scroll`, `in.text` or `in.key`; all 20 streams on the software encoder.
  - The remote door, new: a synthetic `--remote` host (`SILL_TEST_REMOTE_DIR`,
    `SILL_TEST_NO_ROUTER=1`), sillclient paired by its link, then a TLS 1.3 session with the moving
    path and a move at 3 s: 76 lines through TLS, the next after the move 0.302 s later with
    `seen=1`.
  - A path file with a bad line 3: the plan's line, no pointer, no `ptr.` key.
- H10, cost: `PointerWatch.sample()` with the real location read, 100,000 times: 0.20 µs mean
  (median 0.17, p99 0.29 µs); with a regular-mode window whose re-read was due at every sample:
  0.09 µs (11 re-reads ran meanwhile on `sill.pointer`, none waited for); the re-read alone, one
  window through `CGWindowListCopyWindowInfo`: 239 µs mean, median 131 µs, p99 2.0 ms, off
  `sill.net` (the first run: 132 and 192 µs mean); the location read alone
  0.10 µs. Idle: a hook host with no client, 35 s: 0.0 % CPU, 0.18 s of CPU time at 2 s and at
  35 s; a client that picks nothing, 8 s: no tick and no `ptr.` key, 0.0 %.
- H11: no `CGEventTapCreate`, `tapCreate`, `addGlobalMonitorForEvents`,
  `addLocalMonitorForEvents`, `CGRequestListenEventAccess` or `CGRequestPostEventAccess` in
  Sources/ or iOSClient/; no added `updateConfiguration` or `assumeIsolated`; `showsCursor: false`
  at the capture's start; the hooks read only through `PointerTestHooks`, which honours them on a
  synthetic host alone; `sillMoved` before every pointer and scroll post, and the dry run posts
  nothing.
- H12: the bare app's previews from 8b0d418 and this branch, rendered from one path: identical
  (100 files).
- H13: 8b0d418's `sillclient.py` against a hook host runs through, listing 26 by number in `kinds=`
  and `first kinds:`; 8b0d418's StreamMessage parses a kind 26 header as `.unknown` with its length.
- Integration mutants (a scratch copy of the tree, each built and run against one gate): 8 of 8
  caught: no `clientLeft` (H7c: `ptr.mac 1`), input not counted (H5b: `seen=0`), a pointer input
  opening no settle (H5c: 0.058 s; H5b alone cannot tell, since the dry run's post opens it too),
  the tick sampling beside the sampler (H8: 89 in a second, 13 ms apart), no sampler (H8: 34 in a
  second, 30 ms apart), the driver sent the pointer too (H5a: a line after its own move), every
  sample re-sent (H4: 123 lines), the test pattern's input mapped onto the real display (H7: y
  0.2587).

Not run: anything on a device, and a real (non-synthetic) host, which would advertise `_sill._tcp`
beside Sill.app: the real pointer's path is covered by the pointer-watch check's injected reader and
H10's harness, which read the real location and a real window's bounds. The synthetic hosts listen
on every interface, as SillHost always has (nothing binds it to loopback); they advertise nothing,
only loopback clients reached them, and the Application Firewall's list gained no entry.

---

## Results: the device (2026-09-27)

§7 as built (0a5a394, 67a78b1), then main at cf05a78 merged in (b6f57d0) and everything run again.
The device shows the Mac's pointer, in the Mac's shape, wherever kind 26 says it is while the Mac
or another device moved it last, in every layout; its own only for the portrait trackpad; none for
a finger, typing, a key, the iPad's own pointer or the Pencil (Q2's default); and nothing while
nothing streams.

Built as §7 says, but for these, each found while wiring it up:
- **The key row keeps what shows.** §7.5 says the portrait key row does not hide the arrow, and the
  table's rows gave it no rule: a key hands the pointer to the device, and after the Mac had taken
  it the sprite then went back to the pad's cursor from before, where the pointer no longer was.
  `StreamClient.sendFromKeyRow` asks `PointerPresence.ownForKeyRow` (pure, checked): while the Mac or
  another device has the pointer, the arrow stays where it shows, now the device's own (the
  trackpad's, portrait's only pointer), and none while the Mac's is off the stream.
- **A two-finger scroll on the pad** catches up with the anchor and shows the pad's arrow where it
  scrolls, as a move does; a click, a drag and each scroll step catch up first too (§7.5 named the
  moves, the scroll positions and the drag).
- **One look at the feed.** The pad reads the anchor and the takeovers together
  (`StreamClient.pointerFeedState`, one lock) instead of `pointerAnchor` and `pointerTakeovers`;
  `localPointer` is gone: `presence.own`, written only by `setOwnPointer`.
- **A new frame** re-centres the device's own pointer by `PointerPresence.recentresOnNewFrame`
  (pure, checked): only while it shows under the device's control.
- **Fingers** are counted by a recognizer that never recognizes (`FingerCounter`): the pad's pan
  and taps cancel the view's own touches as they recognize, after which the view never hears a
  finger lift. Only Q1's flip reads the count.
- **Resets.** The feed is reset at a new dial and at a remote dial's winner as well as at the
  session's end, on main and again on the network queue, behind anything of the old connection
  still being handled there.
- **The harness.** `-SillPointer` draws the mock's frame as a dim rectangle, so a photo shows what
  the sprite points into (the mock never streams). `-SillInputScript` gained `down` (a finger lands
  on the pad), `click` (a tap on the pad) and `row USAGE` (a key of the key row). The DEBUG console's
  "the Mac has it" also prints for a session's first report.

Checked, the hardware encoder never used (every host synthetic, on the software encoder, killed by
PID, none left running) and nothing posted to the Mac (every input to a synthetic host, which only
counts it); the real pointer read before and after the host gates, the same point:
- Builds: iOS Debug and Release for the generic simulator, arm64, unsigned (only the old
  `StreamClient` capture warning), before and after the merge; `swift build -c release`.
- Pure checks: pointer-presence 157 (141 and 16 new), 41 of 41 mutants (36 and 5 new: the key row
  hiding the Mac's arrow, leaving the pad's older cursor, keeping the Mac's arrow off the stream; a
  new frame re-centring under the Mac's control, or a hidden pointer). After the merge
  `Tests/checks/run-all.sh`, all 18, and `--mutants`, every one of the 452 caught (78 minutes beside
  other sessions' jobs): among them the fence check, main's event-driven one with this branch's
  count on top, 15 modes and 32 of 32 (main's 20 and the count's 12), pointer-control 30 of 30 and
  pointer-watch 33 of 33.
- S1, the photo matrix (a simulator of its own, "Sill pointer", an iPad Pro 13" whose screen draws
  every harness size): `mac@0.40,0.30`, `device@0.62,0.55`, `hidden`, `pencil@0.50,0.50`, and the
  Pencil again with `-SillPencilPointer 1`, at the Duo's four sizes, an iPhone 17 Pro Max's two
  (440x956, 956x440) and an iPad mini's two (744x1133, 1133x744): 40 photos, each measured (the
  frame's rectangle and the sprite's bounding box in the screenshot): the Mac's arrow in all eight
  layouts, its tip within 1 pt of 40 %, 30 % of the frame; the device's only in the four portrait
  ones, within 1 pt of 62 %, 55 %; `hidden` nowhere; the Pencil's nowhere, and with the flip in all
  eight. After the merge the 40 again, pixel for pixel the same inside the harness's frame (16 files
  differ only in the iPad's own home indicator, outside it).
- Live, the app in the harness (`-SillLive 1 -SillConnect`) against a synthetic host with the
  scripted pointer, `sillclient.py --pointer` as a second device, input from `-SillInputScript`, and
  a screenshot taken about 0.2 s after it is asked for (measured: an arrow walking 0.009 of the
  frame every 0.1 s):
  - S2, portrait (710x1000), steps at 1, 2, 3, 5.5 and 9 s: the Mac's arrow at the first three
    steps; a stroke from 4.0 to 4.5 s, the finger resting until 6.5 and moving again to 7.0: the
    second device's first position after 4.0 s 0.0037 from the 3 s step's (the stroke started where
    the Mac's arrow was); at 6.0 s the arrow at the 5.5 s step (the Mac took it under the resting
    finger); the first position after 6.5 s 0.0037 from the 5.5 s step's (the pad re-seeded, no
    jump back); the pad's own arrow at 4.8 and 7.6 s where the stroke took it; the 9 s step jumps the
    arrow there.
  - S3, landscape (1000x710): the arrow at each step; a tap on the stream half-way between two steps
    hides it (the photo taken as the tap's console line comes); the next step, past the settle,
    shows it again (the Mac's line 0.91–0.93 s after the tap's). The steps are 2 s apart, not the
    plan's 1 s: under load (other sessions' jobs) a screenshot took its frame up to 0.7 s after it
    was asked for, and with 0.5 s between a tap and the next step the photo showed that step.
  - S4, through `sillrelay.py --delay-ms 150`, a path moving every 0.05 s, five taps 2 s apart:
    "ignored a position the Mac sent before reading this device's input" once a second at each
    (seen 0 sent 3, seen 3 sent 6…), and the Mac's arrow back 0.42–0.45 s after each tap, never
    within 0.3 s.
  - S5, landscape, steps at 0.5 and 12 s, a tap at 1.5 s: the arrow at connect (Q6), none after
    the tap, and none at any move nor 1 and 3 s after it, the console printing "carried over" and
    "ignored the Mac restating this device's own position" at each, and no "the Mac has it" until
    the 12 s step, whose arrow shows: across the move from AWDL (`-SillMoveTest 1`, fenced), a move
    to the cable (fenced) and then to Wi-Fi when the cable goes (adopt), and a move to the cable then
    its connection closed and made again over it (adopt, the old connection gone), the last two by
    `-SillPathTest` on this Mac's own Wi-Fi and cable addresses, which the kernel delivers here.
  - S6, new (portrait): after the Mac took the pointer, `esc` on the key row leaves the arrow at the
    Mac's position (not at the pad's older cursor); a hardware `esc` hides it; the pad's next stroke
    starts from the Mac's position.
  - S7, new (§3.4's second row): a host that sends no kind 26 (a synthetic host without the
    scripted pointer, as every host before this change): no arrow at connect; a portrait stroke
    shows the pad's own arrow, from the pad's own cursor (there is no anchor); a tap hides it; no
    "the Mac has it" line, and no kind 26 at the second device either.
  Before the merge S2–S6, 50 of 50; on the merge S2–S7 in one run, 54 of 54 (a first run on the
  merge, at load averages of 150–330 on 12 cores from other sessions' jobs and the mutants, failed
  only S3's photos, which came seconds late and showed later steps while the device's console had
  the right lines at the right times: hence its 2 s steps).
- The host's gates again on the merge, every host synthetic: H4 (four lines 0.48–0.51 s apart,
  `seen=0`), H5a (nothing after the device's move, `in.dry 1`), H5b (the next report 0.308 s after
  the move, `seen=1`), H6 (0.067 s after a key, `seen=2`), H7 (the watcher hears the driver's move),
  H8 (120 lines over 2.0 s, at most 61 in any second, 17 ms apart, none after the path stopped), H9
  (no `in.pointer`, `in.scroll`, `in.text` or `in.key` in any second; the real pointer read before
  and after, the same point), H13 (main's `sillclient.py`, which knows no kind 26, runs through
  against a host sending it and lists 26 by number), H12 (the bare app's 100 previews from main and
  from the merge, rendered from one path: identical).

Not run: anything on a device (P1–P12); the Pencil's hover (the simulator has none; S1's flip photo
covers the state); rotation live (the harness draws fixed sizes: the pure check and the photos per
layout cover it); Q1's timer live (the pure check only; it is off by default); H2 after the merge,
which uses the hardware encoder: a device streamed from Sill.app throughout (main's
`Scripts/encoder-check/no-device.sh` said so at every look). The synthetic hosts listen on every
interface, as SillHost always has; they advertise nothing and only loopback clients, and the
simulator on this Mac through its own link-local addresses, reached them.

---

## Review fixes (2026-09-27)

The review of §11 step 5 (three lenses: the control rule and its races on both ends, the host's
threads and cost, the device in every layout) found eight things. Each was reproduced before it
was fixed, on 98d2860 (the device half merged with main); the seventh, a race, from the code and
the pure model only. Every fix has a check where one fits.

- **The frame-rate sampler ran off the source.** It started whenever the pointer moved and some
  device watched, over the streamed source or not, while every report there is the same `inside:
  false` and none goes out. The review's harness (the real StreamServer and PointerWatch, the
  server never started, a loopback-only NWListener feeding `serve`, a scripted pointer with the
  real location read only for its cost): at 120 fps with the pointer moving off the source, 120
  reads and 135–143 wakeups a second, against 33 and 34 still. Now `PointerWatch.samplerInterval`
  starts it only while the pointer moves over the source and some device is sent it; the sample
  that sees the pointer leave still sends `inside: false` and stops it, and the next tick sees it
  come back. Off the source: 33 reads and 34 wakeups a second. The price is up to a tick at the
  way back in: crossing the edge every half second at 120 fps, the first report over the source
  came 2.7–24 ms after the crossing (1.1–9.5 ms before the fix), the first `inside: false` 2.1–11
  ms after the way out (1.1–8.1), 77 reads a second instead of 120.
- **Below 33 fps the sampler sampled less often than the tick it replaced** (24 fps: 42 ms apart;
  30 fps: 33 ms). It runs only when the frame interval is shorter than the tick's, so at 24 and 30
  fps the tick samples: 29.7–29.8 ms apart in the harness, 29–30 ms in H8at24 and H8at30 (below).
- **A regular-mode window was re-read about 8.6 times a second while one device drove alone**,
  for a fraction nobody is sent. `sample(devices:)` takes the devices the host would send the
  pointer to (every ready one), and a re-read after a move starts only while one of them is not the
  one moving the pointer; the one every 2 s runs whoever is there. One device driving: 0.6 re-reads
  a second; with a second device watching: 8.6 (9.1 before), and it hears every position.
- **The far edges read as inside.** `PointerControl.fraction` took 0…1 closed, so (1512, 474.5) on
  the 1512×949 Desktop, the next display's first column, read x 1.0 and inside. Now 0 ≤ x < 1 and
  0 ≤ y < 1, judged before rounding as before; (1511.99, 474.5) is inside with x 1.0.
- **The pad acted from where a finger landed after the Mac moved the pointer under it.** The pad
  re-seeded from the anchor only when a report took the pointer from this device (`takeovers`), so
  a finger that landed while the Mac already had the pointer and rested while the Mac's mouse moved
  it on pulled it back with its next move, click, long press or scroll: in the review's run (the
  Debug app against a loopback stand-in) the first kind 8 after the Mac's move to (0.7, 0.7) went
  out at (0.2183, 0.2), where the finger had landed; with the device driving first it went to
  (0.7183, 0.7), which is why S2 never saw it. `reseeds` counts news that takes the pointer and
  news that moves the anchor while the Mac or another device has it, and every catch-up compares
  it; the real PointerPresence.swift with the review's sequence now gives (0.7184, 0.7).
- **A report just before a move's hand-over was never drawn.** It was recorded in the feed on the
  network queue, then drawn on main only if the session's connection was still the one it came on;
  one that landed after the probe had read the new connection's window list but before
  `moveProbed` ran was not, finishMove draws nothing, and the new connection's first report says
  the same (the pure model: news, `changed` false). The render reads only the feed, which already
  holds the report, so it no longer asks which connection carries the session.
- **`-SillInputScript` had no guard.** Its steps send real kind 8, and Sill.app's home door admits
  loopback and posts what it reads: a gate given a stale port, or a session on a Bonjour row, could
  have clicked and typed on this Mac. `InputScript.refusal` runs the script only when the session
  was dialled to a loopback address and the host's first window list has no `hostVersion`
  (Sill.app always sends one), else "input script: refused: …".
- **`PointerPresence.own`'s comment** named `StreamClient.localPointer`, which is gone.

New for the reruns, TEST ONLY: `SILL_TEST_LOOPBACK=1`, honoured only by a host that does not
advertise, puts both doors on 127.0.0.1 alone (`requiredInterfaceType` loopback and a required
local endpoint), so a test host takes no connection from another machine; one line says so.

Checks: pointer-control 152 (147 and 5: the edge column and row outside, the last ones inside, the
second display's first column its own, an infinite height), 33 of 33 mutants (30 and 3: the edge
column or row inside, the first column outside; its infinite-width case moved halfway down, since
at y = 1 the half-open test alone kept it out and the guard's mutant survived); pointer-watch 132
(112 and 20: the sampler rule at each edge, the re-read with one device, a watcher, the Mac taking
over and no device), 40 of 40 (33 and 7); pointer-presence 165 (157 and 8: re-seeds, and the
review's case in the order TrackpadSurface calls it, a move, a tap, another device driving on), 43
of 43 (41 and 2: a re-seed only on a takeover, the old rule, and only when the anchor moves).

Run, the hardware encoder only where said (while `Scripts/encoder-check/no-device.sh` said no
device was connected to Sill.app, watched every 2 s), every host synthetic and on 127.0.0.1 alone
(lsof checked at each start), nothing posted, the real pointer only read (the same point before
and after the host gates):
- The review's harness, extended by two phases (in and out of the source; a window with a second
  device watching), on 98d2860 and on the fixed tree: the numbers above. Three integration mutants
  of StreamServer's call, each built into the harness, bring one back each: the sampler whatever
  the source (120 reads a second off it), the watch never told who is there (0.6 re-reads a second
  with a watcher), no tick in the rule (24 reads a second at 24 fps, 43.5 ms apart).
- Builds: `swift build -c release`; iOS Debug and Release for the simulator and Debug for a device,
  generic and unsigned, only the old `StreamClient` capture warning; the host's commits of the fixes
  each built and checked on their own, and the pad's commit's app built for the simulator.
- `Tests/checks/run-all.sh` on the merge with main at 676b362: all 19 pass.
- Host gates (gates.py's H4–H9, H13 and the rest of the host step's, as before but for these): H8at30
  and H8at24 now expect the tick (67 lines in 2 s, at most 34 in any second, 29–30 ms apart);
  Hedge, new (a step on x = 1512 outside, on 1511.99 inside with x 1.0, the row at y = 949 outside);
  Hremote, both listeners on 127.0.0.1. All pass; H7c and H8at30 on a second run: in the first,
  under load averages near 200 from other sessions' jobs, H7c's first device started 2 s late and
  was still connected when the path moved, and H8at30's arrivals bunched (40 in a second) while the
  host's own count was 33. H2 against the host step's logs of 8b0d418 (hardware): identical masked
  and sorted but for the loopback line, in all four cases (the Direct Wireless client case in two of
  three tries; the third differed in its first second's counters, the client arriving a second
  later). The sampler at 120 fps (hardware): 238 lines in 2.0 s, at most 121 in any second, 8.0 ms
  apart.
- Live, on a simulator of its own (an iPad Pro 13-inch (M5), "Sill pointer", deleted after), the
  app in the harness against loopback-only hosts: S2–S7 as before, but S5 only across the move from
  AWDL (S5's cable and Wi-Fi moves need a host on this Mac's own Wi-Fi and cable addresses); S2b,
  new (portrait: the finger lands while the Mac has the pointer at the 1 s step, rests while it
  moves to the 3 s step, then strokes: the second device's first position after the stroke begins
  within 0.02 of the 3 s step, none near the 1 s step, the pad's arrow carried on from the 3 s
  step); S2c, new (the same rest, then a click on the pad: its arrow at the 3 s step, nothing near
  the 1 s step, `in.dry 2`); S8, new, against tools/fakehost.py (a loopback stand-in that logs each
  kind 8 and posts nothing): a host whose window list says Sill 9.9 gets "input script: refused: the
  host says it is Sill 9.9, which posts input to this Mac" and no kind 8; one with no version gets
  the script's input dialled by 127.0.0.1, ::1 and localhost (`-SillConnect [::1]:P` never reaches
  the app: UserDefaults reads an argument that starts with `[` as a property list and drops it).
  51 of 51 before the merge and again on it (a run on the merge between the two, at load averages
  of 100–240, failed only photos that came seconds late and showed later steps).
- S1, the 40 photos: all as expected; 25 identical to the device step's pixel for pixel, the other
  15 differing only in the iPad's own home indicator.
- H12: the bare app's 100 previews from main (676b362) and from the merge, rendered from one path:
  identical.

Merged with main again at 5c6a850 (e21ce1c): PR #30, the iPhone's portrait layout, landed minutes
after this branch's pull request opened. The pad keeps its PadCursor from the anchor and counts a
finger's travel down against main's vertical span (a phone's pad width ÷ 1.6); main's layout sends
its key row through `sendFromKeyRow` and gives its trackpad the pointer's closures; `DuoLayout` keeps
`isPortrait` beside main's `phoneArrangement`. Main's DEBUG input test said a synthetic host posts
what it gets, which since this branch it does not (it counts `in.dry`); its notes now say so, and
that a real host would. Run on the merge: `Tests/checks/run-all.sh`, all 20; the three iOS builds;
S2–S8, 51 of 51; S9, new: the phone's arrangement (`-SillIdiom phone` at 440x956 on the iPad
simulator), the Mac's arrow at the 1 s step, a stroke that starts there, and 50 pt down moving the
pointer 0.2427 of the frame (100 / the pad's width, by the span; by the pad's height it would be about
0.14), the pad's arrow where it went (the photo's analysis leaves out the picture's rounded corners,
which a first run counted as the sprite); S1's 40 photos, the same inside the frame as before the
merge; the four pointer states in the phone's arrangement at 440x956 and 402x874, the tips within
1 pt.

Not run: anything on a device (P1–P12; P3 now in both orders); S5's moves to the cable and back to
Wi-Fi, and its reconnect over the cable (they need a host on this Mac's Wi-Fi and cable addresses);
the hand-over race live (a report on the old connection between the probe's read and `moveProbed`
on main: from the code and the pure model); the host's gates after the second merge (no host source
changed in it).
