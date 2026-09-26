# Full macOS trackpad gestures from the device — the plan

2026-09-26. It stands alone: the implementer needs no other design document. Written from a
read-only survey of `/Users/noah/Downloads/winstream-gestures` (branch `trackpad-gestures` from
`origin/main` at 8b0d418) and read-only probes on this Mac (macOS 27.0). Line numbers are at
8b0d418. **No gesture, key, click, drag or text was posted to the Mac. No CGEvent was posted, no
event tap was created, and the pointer was never moved.** What was read is in §2 ("Investigated").

**Noah's request (2026-09-23), in his own words:** "I also want to be able to use full macos
gestures on the touchpad, so far only 1 or 2 finger gestures are working. Would that be possible?"
and "Queue it after the VPN feature." On 2026-09-26: "Work on 5-12 as well please" (item 9 of the
queue is trackpad gestures with three or more fingers) and "Make sure to spawn as many Opus 5.5
agents as you need, don't hold back." This plan **is** that work; a later relayed message about
another topic does not narrow or cancel it. The small decisions are delegated (§11 records them).

**A limit Noah stated himself:** the iPad's trackpad view cannot see a four-finger gesture reliably
(iPadOS takes four-finger swipes for itself), so **three-finger gestures are the target and
four-finger ones are best effort**.

**Reading of it.** Today the on-screen trackpad (portrait) and the direct-touch stream (landscape)
handle one finger (pointer, tap, long-press) and two (scroll with phases and momentum, two-finger
tap = right click). Full macOS gestures — Mission Control, App Exposé, switch Spaces, Launchpad,
Show Desktop — are three- and four-finger gestures on a Mac. This plan recognizes them from three
fingers on the iPad's glass and drives the Mac. It changes nothing about one- and two-finger
behaviour.

---

## 1. Scope

**In.** Three-finger gestures on the two glass surfaces Sill owns — the portrait `Trackpad`
(`TrackpadView.swift`) and the landscape direct-touch `InputOverlay` (`InputOverlay.swift`):

| Gesture (three fingers) | macOS action |
|---|---|
| Swipe up | Mission Control |
| Swipe down | App Exposé |
| Swipe left | Next Space (the Space to the right) |
| Swipe right | Previous Space (the Space to the left) |
| Pinch in (fingers together) | Launchpad |
| Pinch out (fingers spread) | Show Desktop |

Each maps to a macOS keyboard chord, sent through the **existing `.key` input path** (§4). A
device-local switch turns three-finger gestures off (§7). Four-finger versions are attempted where
iPadOS lets them through (§6.4), never relied on.

**Out (v1 of gestures).**
- **Tracking gestures** (Mission Control that follows the finger and can be reversed mid-swipe,
  pinch-to-zoom, rotate, smart zoom). These need a private gesture-event API on the host; §5
  surveys it, §9 gives the bounded probe that must prove it on macOS 27 **before** any of it is
  built, and it is reserved as **Tier 2** behind wire kind 28, not shipped here.
- **Notification Center** (two-finger swipe from the right edge) and **two-finger double-tap smart
  zoom**: no reliable default chord (§2.3); left to Tier 2 or a later pass.
- The **Magic Keyboard trackpad's** three- and four-finger gestures: iPadOS consumes them for the
  system before the app sees them (§2.2). Sill's existing two-finger scroll on that trackpad is
  unchanged.
- Any change to one- or two-finger behaviour. Hard rule (§10).

---

## 2. Investigated (read-only)

### 2.1 What the iPad's glass sees for three fingers today

- Both surfaces set `isMultipleTouchEnabled = true` (`TrackpadView.swift:166`,
  `InputOverlay.swift:47`), so all three contacts arrive.
- The portrait trackpad's pan is `maximumNumberOfTouches = 2` (`TrackpadView.swift:181`); the
  landscape overlay's pan is the same (`InputOverlay.swift:74`). **A third finger already scrolls
  nothing** — the pan ignores it — so three fingers are free to carry a new recognizer without
  touching the one/two-finger paths. The overlay's recognizers are `allowedTouchTypes = [.direct]`
  (`InputOverlay.swift:57`), so only finger touches reach them (Pencil and indirect pointer bypass
  to `touchesBegan`).
- The trackpad's `FingerTracker` already counts a second finger from the view's own touches
  (`sawSecondFinger`, `TrackpadView.swift:461-484`); the same technique reads three.

### 2.2 What iPadOS reserves (finger-on-glass vs. Magic Keyboard)

- **Four-finger swipes and four-finger pinch** are the system's (app switcher, Home). A plain
  `UIView` does not see them reliably; Noah confirmed this. → **three fingers is the target.**
- **Three-finger system *text* gestures** (undo/redo = three-finger swipe, copy/paste = three-finger
  pinch) fire through the **editing interaction**, `UIResponder.editingInteractionConfiguration`
  (SDK `UIResponder.h:140`, an enum `…None = 0`, `…Default = 1`, `UIResponder.h:26-29`). It engages
  in text-editing contexts. `InputOverlayView` conforms to `UIKeyInput` and becomes first
  responder for the software keyboard, so it is the one surface where the system three-finger edit
  gestures **could** engage. The safe, public defence: **override `editingInteractionConfiguration`
  to return `.none`** on both surfaces, which positively suppresses the system three-finger edit
  gestures so ours are the only ones (§6.1). `TrackpadSurface` is not a `UIKeyInput` and is lower
  risk, but overrides it too for symmetry.
- **The Magic Keyboard trackpad** delivers indirect touches (`UITouch.TouchType.indirectPointer`).
  Its two-finger scroll already reaches Sill's pan (the overlay routes `.indirectPointer` to
  `touchesBegan`, `InputOverlay.swift:220-236`; the trackpad's pan takes indirect touches).
  **Three- and four-finger gestures on that trackpad are consumed by iPadOS** (App Exposé, Home,
  switcher, Notification Center) and are not delivered to an ordinary app, so they are **out of
  reach**; a `UIGestureRecognizer` with `allowedTouchTypes = [.indirectPointer]` does not receive
  them. The plan therefore targets **finger-on-glass** three-finger gestures only. Stated in the
  copy so the expectation is right (§7).
- `INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES` is already set
  (`project.pbxproj:378,410`).

### 2.3 macOS: which gestures, and how each can be produced (Tier 1 = public API)

Read on this Mac, read-only, from the window server's symbolic-hotkey table
(`CGSGetSymbolicHotKeyValue` / `CGSIsSymbolicHotKeyEnabled`, SkyLight; getters only, nothing set).
The keycodes are Carbon virtual keys; Sill's wire uses **USB HID usages** which
`InputInjector.virtualKeys` (`InputInjector.swift:368-418`) maps to those keycodes. The modifier
mask column is the window server's stored signature for the chord:

| macOS action | Symbolic hotkey | Enabled here | Keycode | Stored modifiers | HID usage (wire) | Wire modifiers |
|---|---|---|---|---|---|---|
| Mission Control | 32 | yes | 126 (Up) | `0x840000` = **control + fn** | `0x52` | control `1<<18` + **fn `1<<23`** |
| App Exposé (Application windows) | 33 | yes | 125 (Down) | `0x840000` = control + fn | `0x51` | control + fn |
| Move left a Space | 79 | yes | 123 (Left) | `0x840000` = control + fn | `0x50` | control + fn |
| Move right a Space | 81 | yes | 124 (Right) | `0x840000` = control + fn | `0x4F` | control + fn |
| Show Desktop | 36 | yes | 103 (F11) | `0x800000` = **fn only** | `0x44` | **fn `1<<23`** |
| Launchpad | 160 | **no** (unbound) | 65535 | `0` | — | — (see §3, best effort) |
| Notification Center | 163 | no (unbound) | 65535 | `0` | — | — (out) |
| Spotlight (already used) | 64 | yes | 49 (Space) | `0x100000` = command | `0x2C` | command `1<<20` |

**The fn finding.** Every arrow chord's stored signature includes the **fn** (secondary-function)
bit, `0x800000` = `CGEventFlags.maskSecondaryFn` = bit 23; Show Desktop is fn alone. On a real
keyboard the arrow keys carry fn inherently (measured: a synthesized `CGEvent` for Up/Down/Left/Right
reads back `flags = 0x20a00000`, i.e. bit 29 + fn `0x800000` + numeric-pad `0x200000`, from the
constructor, `keyflags.swift`). But `InputInjector.key` **overwrites** the flags with only the five
mapped modifier bits (`InputInjector.swift:348`, `flags(from:)` at `:356-364`), so a chord Sill
sends as "⌃↑" today carries **no fn** and would likely **not match** the Mission Control hotkey.
The window server's hotkey matcher compares the device-independent modifier bits (control, shift,
option, command, fn); numeric-pad is not a hotkey modifier. So the gesture chords must carry the
**fn bit**, which needs one additive change to the wire and the injector (§4). This is the single
most important implementation detail, and P2/P3 verify it on Noah's Mac.

**Launchpad and Notification Center have no default chord** on this Mac (both unbound). Launchpad's
historical key is F4 (`0x3D`), which on modern macOS may do nothing or open Spotlight. So
pinch-in → Launchpad is **best effort**: the host sends F4, and if the Mac has no Launchpad
shortcut the gesture is a harmless no-op. Notification Center is out (§1). Show Desktop's default
here is fn+F11; a user who remapped it will see nothing, which is acceptable and stated in the copy.

**No public CGEvent constructor makes a gesture.** `CGEventTypes.h` has a public `CGGesturePhase`
enum (`kCGGesturePhaseBegan = 1`, …) for **reading** magnify/rotate events, and the private event
types 29 (`NSEventTypeGesture`) and 30 (`NSEventTypeMagnify`) can be set on a `CGEvent` from Swift
(`CGEventField(rawValue:)` and `CGEventType(rawValue:)` are non-failing initializers; a `CGEvent`'s
`type` can be set to 29 or 30 and private fields written — verified without posting, `fields.swift`).
But there is **no public API to construct and post a magnify, rotate, swipe or dock-swipe gesture**.
That path is Tier 2 (§5).

### 2.4 Idle and encoder guards (for §9's probe)

- `HIDIdleTime` (IORegistry, `IOHIDSystem`) reads seconds since the last user input, from a process
  without any grant (`state.swift`); the probe uses it to refuse to run within 60 s of real input.
- Sill.app's log (`~/Library/Logs/Sill/Sill.log`) shows `[30s] idle · 0 clients` while no device is
  connected; the probe wrapper refuses to run unless the last such line (or `Client left`) is newer
  than the last connect. At the time of writing Sill.app (pid 5205) was idle, 0 clients.

---

## 3. The gesture set and mappings (exact)

Three fingers, on either glass surface. **Natural direction** matches the Mac (the content follows
the fingers): swiping the fingers **left** moves to the Space on the **right** (`⌃→`), as on a Mac
trackpad. Each row's chord is sent as a `.key` down then up carrying the modifier bits, exactly as
the key row's `press()` does (`PortraitStreamScreen.swift:437-441`).

| Gesture | Action | HID usage | Modifiers sent (`KeyModifiers.rawValue`) |
|---|---|---|---|
| Swipe up | Mission Control | `0x52` (Up) | control `1<<18` + fn `1<<23` |
| Swipe down | App Exposé | `0x51` (Down) | control + fn |
| Swipe left | Next Space | `0x4F` (Right) | control + fn |
| Swipe right | Previous Space | `0x50` (Left) | control + fn |
| Pinch in | Launchpad (best effort) | `0x3D` (F4) | none |
| Pinch out | Show Desktop | `0x44` (F11) | fn `1<<23` |

- **A gesture never carries a latched modifier.** The key-row latches (`ctrl`, `opt`, `cmd`,
  `shift`) are for the next keystroke or click; a three-finger swipe is its own thing and ignores
  them (like Spotlight's cap, `PortraitStreamScreen.swift:392-401`). A latch stays latched.
- **A gesture fires once** per three-finger episode (§6.2), never repeats while the fingers stay
  down, and produces **no pointer motion, no click, no scroll**.

---

## 4. Wire

Tier 1 needs **no new message kind**: the discrete chords go over the existing `.input` → `.key`
path (`Input.swift:33`, `StreamMessage.swift` kind 8). The one additive change is a modifier bit so
the arrow and F11 chords can carry **fn**.

### 4.1 The fn modifier bit

- **Device (`PortraitStreamScreen.swift`, `KeyModifiers`).** Add
  `static let function = KeyModifiers(rawValue: 1 << 23)`. It sits at the same bit position as
  `CGEventFlags.maskSecondaryFn`, matching the existing rule that these bits share
  `CGEventFlags`'s positions (`PortraitStreamScreen.swift:8-15`). It is **not** in
  `shortcutMakers` and is never latched — only the gesture code sets it.
- **Host (`InputInjector.flags(from:)`, `InputInjector.swift:356-364`).** Add one line:
  `if modifiers & (1 << 23) != 0 { flags.insert(.maskSecondaryFn) }`. Nothing else changes; the
  existing five bits are untouched. `maskSecondaryFn` is not numeric-pad, so no app sees a
  spurious numpad arrow.

This is safe for the "one/two-finger behaviour must not change" rule: nothing but the gesture code
ever sets bit 23, and `flags(from:)` is a pure widening.

### 4.2 Kind 28, reserved for Tier 2 (documented, not built here)

`StreamMessageKind` in code reaches 23 (`hello`); 24 `macMenu`, 25 `pressMenuItem`, 27 (menu bar's
optional fetch) and 26 `macPointer` are **reserved by their plans** (`docs/pointer-visibility-plan.md`,
the menu-bar sketch in `sill-next-features-queue`), so the next free number is **28**. When Tier 2
is built (§5, only after the probe proves it), it takes kind **28** `gesture`, device → host, JSON:

```
struct GestureEvent {          // kind 28, device → host; Tier 2 only
    var kind: String           // "missionControl" | "appExpose" | "spaceLeft" | "spaceRight" |
                               //   "launchpad" | "showDesktop" | "magnify" | "smartZoom" | "rotate"
    var phase: String          // "began" | "changed" | "ended" | "cancelled"
    var dx: Double?            // normalized displacement, fraction of the pad (swipe / dock)
    var dy: Double?
    var magnification: Double? // cumulative, for magnify/pinch
    var rotation: Double?      // degrees, for rotate
}
```

Rules of `HostSettings.swift` apply (JSON only; every field optional; no enums on the wire — `kind`
and `phase` are strings, not enums, so an older reader that somehow saw one would not fail; never
reuse a number). An older host maps kind 28 to `.unknown` and skips it (`StreamMessage.swift`
`parseHeader`), so a device that has Tier 2 falls back to Tier 1's chords against an older host
(§6.5). **Do not add kind 28 to the enum in this plan's commits** — reserve it in the comment only,
so it is not half-built. The comment beside kind 23 gains: "28 the trackpad gesture (Tier 2, when
built; docs/trackpad-gestures-plan.md §4.2)."

### 4.3 Compatibility

- **Tier 1 against every host.** The chords are ordinary `.key` messages; every host since
  Milestone 2 injects them. The **fn bit** is dropped by a host older than this change
  (`flags(from:)` ignores bit 23), so on an older host an arrow chord goes out **without fn** and
  may not trigger Mission Control / Spaces (Show Desktop and the Space chords likewise). That is
  graceful degradation, not a break: the key still arrives, nothing wrong happens, and the newest
  host does it right. Stated honestly rather than claimed as "works with every host": the
  **messages** reach every host; the **gestures** need this host's fn mapping to fire the arrow and
  F11 chords. Sill.app and the CLI are one host; Noah runs the same build on the Mac, so in practice
  both ends update together.
- **Older device, this host.** No three-finger gestures sent; nothing new arrives; unchanged.
- **No new kind on the wire in Tier 1**, so `sillclient.py`'s `kinds=`/`first kinds:` summaries are
  unchanged for existing tests, and the CLI's synthetic stdout is byte-identical (nothing here runs
  on the synthetic path unless a test sends a `.key`).

---

## 5. Tier 2 survey (private gesture events) — do not build until §9 proves it

This is a **read-only survey**, not an implementation. Building any of it is gated on §9's bounded
probe passing on macOS 27; if it does not, Tier 2 is dropped and Tier 1 is the whole feature.

**What Tier 2 would add:** a Mission Control / Spaces swipe that *tracks the finger* and can be
reversed, pinch-to-zoom, rotate, smart zoom — the gestures whose semantics are continuous, which a
discrete key chord cannot express.

**How macOS produces them.** A trackpad posts, below the public layer, IOHID gesture events that
the window server turns into `NSEventTypeGesture`/`NSEventTypeMagnify`/`NSEventTypeRotate`/dock-swipe.
The functions that build them are exported from IOKit but **declared in no public header** (found in
the SDK stub `IOKit.tbd`, absent from `IOKit.framework/Headers`):

- `IOHIDEventCreateDockSwipeEvent` — the Mission Control / App Exposé / Spaces swipe (three- and
  four-finger vertical/horizontal navigation).
- `IOHIDEventCreateNavigationSwipeEvent` — page-level swipe navigation.
- `IOHIDEventCreateScaleEvent` — pinch/zoom (Launchpad, Show Desktop, magnify).
- `IOHIDEventCreateRotationEvent` — rotate.
- `IOHIDEventCreateDigitizerEvent` / `…DigitizerFingerEvent` — synthetic multi-touch contacts.
- `IOHIDEventCreateGenericGestureEvent`.

The event is wrapped into a `CGEvent` (`CGEventCreate`, then `CGEventSetType` to 29/30 and private
fields) and posted with `CGEventPost` — the public post call. Both `CGEventType(rawValue: 29/30)`
and the private `CGEventField`s are addressable from Swift **without any bridging header** (verified,
`fields.swift`), so no Objective-C shim is needed; the IOKit functions need a `dlsym` or a private
`@_silgen_name`/C declaration (they are not in the module map).

**What is unknown and must be proven (§9):**
1. Whether macOS 27 **accepts** such a synthesized gesture from a **background, non-GUI process**
   (Sill's host) that holds **Accessibility** (`AXIsProcessTrusted() == true`,
   `CGPreflightPostEventAccess() == true`, both true here) but is not a foreground app.
2. Whether it needs **Input Monitoring** (`kTCCServiceListenEvent`) or any grant beyond
   Accessibility. If it does, Tier 2 costs a third permission (after Screen Recording and
   Accessibility) — a second system alert, another row in Settings › Permissions, one more grant a
   re-sign or `tccutil reset` loses, one more App Store privacy answer — and the plan's default
   (§11 Q4) is **not** to pay that for gestures: Tier 1 stays the feature.
3. Whether the events are **stable on macOS 27** at all (private fields drift between releases).

**Honesty.** The event-**posting** probe was **not executed in this environment.** The read-only
survey above (the symbol surface, the Swift addressability of types 29/30 and the private fields,
the idle/encoder guards) is done; the one remaining step — posting a self-reversing dock-swipe and
watching whether Mission Control opens — moves the real pointer/desktop and so must run under §9's
guards on Noah's Mac, deliberately, for a few seconds, while he is away and no device is connected.
Until it passes, **Tier 2 is not built** and this plan ships Tier 1 only. This matches the request's
own instruction to "report honestly if nothing works or if it needs Input Monitoring."

---

## 6. iOS design (Tier 1)

### 6.1 A pure recognizer, `TrackpadGestures` (new file, checked with swiftc)

`iOSClient/TrackpadGestures.swift`, a **pure struct**: no UIKit, so it compiles and is checked on
its own (like `DiscoveryPolicy`, `HostSettingsLedger`). It is the whole decision, so it is the whole
test surface (§8).

```
struct TrackpadGestures {
    enum Gesture: Equatable { case missionControl, appExpose, spaceLeft, spaceRight, launchpad, showDesktop }

    // Tunables (points; the pad's own points, not the frame's).
    var swipeThreshold: CGFloat = 45      // centroid travel before a swipe fires
    var pinchThreshold: CGFloat = 0.22    // change in mean spread (fraction) before a pinch fires
    var axisRatio: CGFloat = 1.3          // dominant axis must beat the other by this to be a swipe
    var minFingers = 3
    var maxFingers = 4                    // best effort; §6.4

    // State machine, fed the view's live touch set each callback.
    // begin(count:centroid:spread:) when the finger count first reaches minFingers…maxFingers;
    // update(centroid:spread:) -> Gesture? each move, returning the gesture the first time a
    //   threshold is crossed, then nil for the rest of the episode (one-shot, `fired`);
    // end() resets. A drop below minFingers ends the episode without firing anything more.
}
```

- **Swipe vs. pinch.** From `begin`, track the centroid's travel and the mean pairwise spread
  (`InputOverlay`/`Trackpad` give per-touch points). A **swipe** fires when centroid travel crosses
  `swipeThreshold` and one axis dominates (`|dx| ≥ axisRatio·|dy|` → left/right, the reverse →
  up/down). A **pinch** fires when the spread changes by `pinchThreshold` **and** the centroid has
  moved less than `swipeThreshold` (so a drifting spread is not both). Whichever crosses first wins;
  after that the episode is `fired` and returns nil until `end`.
- **One-shot** so a long three-finger drag does not repeat Mission Control.
- **Deadband** (`swipeThreshold`, `pinchThreshold`) so a clumsy two-finger scroll that briefly
  touches a third finger does not fire — and because the third finger ends any open scroll first
  (§6.3), a spurious fling is impossible.
- Pure and deterministic: same samples → same decision, which is what §8 checks with 5,000 random
  runs and mutants.

### 6.2 Portrait `Trackpad` (`TrackpadView.swift`)

- Add a dedicated recognizer for exactly three (best effort four) fingers. Simplest and least
  entangled: a `UILongPressGestureRecognizer` subclass like `FingerTracker` with
  `minimumPressDuration = 0`, `numberOfTouchesRequired = 3`, `allowableMovement = .greatestFiniteMagnitude`,
  `cancelsTouchesInView = false`, reading the view's own touches each callback (count, per-touch
  locations) and feeding `TrackpadGestures`. Using the view's touches (as `FingerTracker` does,
  `TrackpadView.swift:470-478`) rather than the recognizer's `location(in:)` gives the individual
  contacts for the spread.
- `shouldRecognizeSimultaneouslyWith` stays `true` (`TrackpadView.swift:145-146`), so it runs
  beside the tracker, pan and taps without stealing their touches.
- On a fire, `send(.key(down:true))` then `send(.key(down:false))` with the row's modifiers (§3),
  and a **haptic** (`clickHaptic.impactOccurred(intensity: 0.7)`, the same generator, a no-op on
  iPad — `TrackpadView.swift:158-160`). No `setLocalPointer`, no pointer/scroll send.
- **Two-finger scroll must end cleanly when the third finger lands.** `handlePan`
  (`TrackpadView.swift:246-303`) already rebases when `numberOfTouches` changes; add: when the count
  rises to ≥3 while `scrolling`, call `endScroll(momentumVelocity: nil)` (no coast) and set a
  `suppressToThreeFinger` flag so the pan sends no further deltas until every finger lifts. This
  guarantees no half-scroll leaks into a gesture and no fling.

### 6.3 Landscape `InputOverlay` (`InputOverlay.swift`)

- The same recognizer, `allowedTouchTypes = [.direct]` (matching `InputOverlay.swift:57`), over the
  stream. Direct-touch only, so a Pencil or the Magic Keyboard pointer never triggers a gesture.
- `handlePan` (`InputOverlay.swift:139-172`) has `maximumNumberOfTouches = 2`, so a third finger
  already ends its recognition; add the same "≥3 fingers → end any open scroll, suppress until
  lift" guard in `touchesBegan`/the pan so no scroll leaks.
- **Override `editingInteractionConfiguration` → `.none`** on `InputOverlayView` (it is the
  `UIKeyInput` first responder, §2.2), so the system's three-finger undo/redo/copy/paste never
  competes with ours. Also on `TrackpadSurface` for symmetry.

### 6.4 Four fingers (best effort)

`maxFingers = 4`: if four contacts arrive before iPadOS claims them (rare on glass), the same swipe
logic fires the same action (four-finger swipe up is also Mission Control on a Mac). It is never
relied on; the copy and the P-list say three fingers.

### 6.5 Where a Tier 2 device falls back

When Tier 2 exists (later): the device sends kind 28 to a host that advertises it, else the Tier 1
chord. A host that skips kind 28 (older) leaves the device to send the chord. The recognizer is the
same; only the send site differs. Not built here.

---

## 7. Settings on the device (device-local; nothing on the Mac)

The request: "a 'Trackpad gestures' section with the mapping shown and a switch to turn three-finger
gestures off; on the Mac nothing." This is a **device preference**, not a host setting — it never
goes on the wire, is never sent to the Mac, and is saved in the iPad's `UserDefaults`
(key `Sill.trackpadGestures`, default **on**; precedent: `Sill.savedMacs`,
`Sill.directWirelessMacs`).

- **Where.** A new group in `HostSettingsPanel` (`HostSettingsPanel.swift`), clearly a **this-iPad**
  group, placed after the host's stream rows and the Direct Wireless row, before "Away from home".
  A small header "This \(device)" distinguishes it from the Mac's settings, since every other row in
  the panel is the Mac's.
- **What.** A `Toggle` "Three-finger gestures" bound to the local default, and, when on, the mapping
  as read-only rows (a symbol + name each): "Swipe up — Mission Control", "Swipe down — App Exposé",
  "Swipe left / right — Switch Spaces", "Pinch — Launchpad", "Spread — Show Desktop". A footnote:
  "Use three fingers on the trackpad or over the stream. Four-finger gestures belong to iPadOS.
  Gestures from a Magic Keyboard trackpad go to iPadOS, not \(mac)."
- **How it reaches the recognizer.** The two surfaces read `Sill.trackpadGestures` (through a tiny
  `GestureSettings.enabled` helper, or `@AppStorage` on the SwiftUI wrappers passed down); when off,
  the recognizer is disabled (added but its action does nothing) so no gesture is sent.
- **No `changeSettings`, ever.** This group's controls call no `client.changeSettings`; they write
  the local default only. The panel's rule "only a control's action ever sends" is preserved because
  this control sends nothing to the Mac.
- **Voice­Over / layout** follow the panel's existing group styling (`Rows`, `Footnote`,
  `RowTitle`), `dynamicTypeSize(...xxLarge)`, wraps not truncation.

The four new pbxproj entries for `TrackpadGestures.swift` (Build file + File reference + the two
group/Sources list lines) use the next free IDs after `F01E`: **`A1000001000000000000A01F` /
`…F01F`** (the pattern at `project.pbxproj:24,56,96,220`). `GestureSettings` can live in the same
file (no extra entry).

---

## 8. Tests

### 8.1 Pure check `gestures` (`Tests/checks/gestures/`, swiftc, with mutants)

Compiles `iOSClient/TrackpadGestures.swift` with a `main.swift`, added to `Tests/checks/` and to the
CI `mutants` matrix in `.github/workflows/ci.yml` (`Tests/checks/README.md`, "Adding a check").
Cases (≥ 60), one `ok`/`FAIL` each, plus 5,000 random episodes:

- **Each swipe** fires exactly its `Gesture` once: a centroid path past `swipeThreshold` on the
  dominant axis, in each of the four directions; nothing before the threshold; nothing again for the
  rest of the episode; `end` resets.
- **Direction is natural**: fingers left → `spaceLeft` (next Space, `⌃→` at the wire); fingers right
  → `spaceRight`.
- **Pinch in / out** fire `launchpad` / `showDesktop` when spread crosses `pinchThreshold` with the
  centroid still; a spread **and** a big centroid move is a swipe, not a pinch (the first to cross
  wins).
- **Deadband**: a path under `swipeThreshold`, a spread under `pinchThreshold`, and a diagonal that
  fails `axisRatio` all fire nothing.
- **Finger count**: two fingers never enter the recognizer (begin needs ≥ `minFingers`); a drop to
  two mid-episode ends it with nothing further; four fingers fire the swipe (best effort).
- **One-shot**: a long drag past the threshold twice fires once.
- **Random**: 5,000 episodes of random counts/paths never fire twice in one episode and never fire
  below the thresholds.

Mutants (≥ 8 caught): `>` for `≥` on each threshold, dropping the dominant-axis check, dropping the
`fired` latch, swapping left/right, swapping pinch in/out, `minFingers = 2`, the centroid-still
condition removed.

### 8.2 Harness photos (simulator; screenshots only, no recording, no live panel)

- `-SillSettings 1 -SillSettingsCase default` with the new group visible; `-SillSettingsEnd 1` to
  scroll to it on the short outer display; the toggle off and on; at 1000×710, 710×1000, 500×710,
  710×500, and at accessibility-extra-large — the mapping rows wrap, never truncate. Send Noah the
  sheet.
- The mapping group's copy checked in each width.

### 8.3 Headless gates (H) against a synthetic host with `sillclient.py`

The gestures land as `.key` messages; a synthetic host injects nothing (dry) but `sillclient.py`
prints what it receives. Add nothing to `sillclient.py` beyond what exists; the check reads the host
log.

| # | Check | Pass when |
|---|---|---|
| H1 | **Builds.** `swift build -c release`; iOS Debug + Release for the simulator | Only the known warnings (CaptureProbe; the old `StreamClient` capture warning) |
| H2 | **CLI byte-for-byte.** `SillHost --synthetic` idle 35 s and with `sillclient.py PORT 5 desktop`, digits masked, sorted, against `origin/main`'s | Identical (nothing here touches the synthetic path unless a `.key` is sent) |
| H3 | **The `gestures` check + mutants** (§8.1) | All cases pass; ≥ 8 mutants caught |
| H4 | **fn reaches the injector.** A host started with the §9 guard-free dry hook (or read from the host log under Accessibility on the build Mac, no device connected): send, from a scratch client, a `.key(hidUsage:0x52, down:true, modifiers: (1<<18)|(1<<23))`; the injector's `flags(from:)` yields `maskControl | maskSecondaryFn` | The flags include `0x40000` (control) **and** `0x800000` (fn); no numeric-pad bit |
| H5 | **Grep hard rules** | No `IOHIDEventCreate*`, `CGEventPost` of a gesture, `tapCreate`, `addGlobalMonitorForEvents` in `Sources/` or `iOSClient/` (Tier 2 not built); `maximumNumberOfTouches` on the existing pans is unchanged; the fn line is the only change to `flags(from:)` |
| H6 | **Compatibility.** `origin/main`'s `sillclient.py` and an older host decode the new `.key` (fn bit) as an ordinary key; the fn bit is dropped by `flags(from:)` without the change | The old host posts the arrow without fn (no crash, no new output) |

`InputInjector`'s `flags(from:)` is `private static`, so H4 reads it through a tiny swiftc harness
that includes the function (like `clientlink`'s `-package-name sill`), **not** by posting on the
Mac.

### 8.4 Noah's device list (P), handed over at the end

The iPad mini on Noah's Mac (Sill.app and the iOS build from this branch), and, for P8, a Magic
Keyboard trackpad if he has one.

| # | Check |
|---|---|
| P1 | **Portrait, three fingers on the trackpad.** Swipe up → Mission Control; down → App Exposé; left → next Space; right → previous Space; pinch → Launchpad (or nothing if unbound); spread → Show Desktop. The pointer does not jump; no click; a light haptic on iPhone (silent on iPad) |
| P2 | **The fn finding.** Confirm the arrow swipes actually open Mission Control / switch Spaces. If they do **not**, note it — the fn bit needs adjusting (or dropping); if a plain `⌃↑` already works on his Mac, the fn bit can go (one line, §4.1) |
| P3 | **Landscape, three fingers over the stream.** The same six, over the streamed window and over the Desktop source. Two-finger scroll still scrolls; a third finger landing mid-scroll does not fling |
| P4 | **One/two-finger unchanged.** Pointer, tap (left), two-finger tap (right), long-press drag, two-finger scroll with momentum, haptics — all exactly as before, portrait and landscape |
| P5 | **The switch.** Settings › Three-finger gestures off: no gesture fires; the mapping hides; one/two-finger still work. On again: they return. Survives a relaunch (device default) |
| P6 | **Not a text gesture.** With the software keyboard up, a three-finger swipe over the stream does Mission Control, **not** iPadOS undo/redo (the `editingInteractionConfiguration = .none` defence, §6.1) |
| P7 | **Virtual display on.** Pick a window; three-finger swipe up → Mission Control on the Mac (the chord is system-wide, not per-window) |
| P8 | **Magic Keyboard trackpad.** Three fingers there do the iPadOS gesture (App Exposé / Home), **not** Sill's — as designed (§2.2). Two-finger scroll on it still scrolls the Mac |
| P9 | **Remote (Tailscale).** A three-finger swipe still fires the chord over the tunnel (a `.key`, tiny); note any lag |
| P10 | **Four fingers (best effort).** If a four-finger swipe on the glass ever reaches Sill, it does the same as three; usually iPadOS takes it — either is acceptable |

---

## 9. The Tier 2 bounded probe (run before building any of §5; guarded)

This is the one step that posts a synthetic event. It is **not** part of Tier 1 and Tier 1 ships
without it. Run it deliberately, on Noah's Mac, under all of these — the wrapper refuses otherwise:

- `HIDIdleTime ≥ 60` s (no real input for a minute) **and** it stays ≥ 60 s across the run;
- Sill.app shows **0 clients** (the last `[30s] idle · 0 clients` or `Client left` in `Sill.log` is
  newer than the last `connected`), so no device is streaming;
- `CGPreflightPostEventAccess()` is already true — the probe **never** calls
  `CGRequestPostEventAccess` or raises any permission alert;
- the whole run is **under 10 s**;
- it posts **only** a self-reversing navigation gesture — open Mission Control, then close it — and
  **never** a key (except that the close may be the same reverse gesture), a click, a drag, or text;
- it verifies open/closed by **reading** the Dock's Accessibility state and the on-screen window
  list (read-only), and prints what it saw;
- a `--no-post` mode runs the guards and prints the plan, posting nothing.

**What it answers (§5):** does macOS 27 open Mission Control from a background, Accessibility-only
process via a synthesized navigation/dock-swipe gesture, or is it ignored / does it need Input
Monitoring? **Report the answer plainly.** If yes and no extra grant → Tier 2 is feasible and kind
28 may be built in a later PR. If it needs Input Monitoring or does nothing → **Tier 2 is dropped**;
Tier 1 (the chords) is the whole feature, which already covers Noah's ask ("full macos gestures on
the touchpad").

This probe was **not run in this environment** (writing it here tripped a safety stop; and it moves
the real desktop, so it belongs in a deliberate, guarded run). Its result is therefore **open**, and
Tier 1 does not depend on it.

---

## 10. Hard rules (every step)

- **One- and two-finger behaviour never changes** (pointer, tap, right-click, scroll with phases +
  momentum, haptics). The three-finger recognizer is additive; the fn bit is set by nothing else.
- **Apple frameworks only.** No third-party code.
- **CLI stdout byte-identical** on the default synthetic path (Tier 1 sends only `.key`, which the
  synthetic host handles as today).
- **Wire fields optional; kind numbers never reused.** Tier 1 adds no kind; Tier 2's kind is **28**,
  reserved in the comment, not added to the enum until it is built and proven.
- **No `MainActor.assumeIsolated`** in core code.
- **Four pbxproj entries** for `TrackpadGestures.swift` (§7). Swift 5 language mode.
- **No new permission.** Tier 1 needs none. Tier 2 must not need Input Monitoring, or it is dropped
  (§9, §11 Q4).
- **Tests never post a gesture to the real Mac** except §9's guarded probe; never `simctl io
  recordVideo`, no XCUITest, no Simulator live panel while Noah streams; screenshots only.
- Never touch `/Applications/Sill.app`, `make-app.sh --install/--open`, `tccutil`, or Noah's iPad.

---

## 11. Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **Pinch mappings.** Default: **pinch-in → Launchpad, pinch-out → Show Desktop**, the Mac's own
   pairing. Launchpad is unbound on Noah's Mac, so pinch-in may do nothing until he sets a Launchpad
   shortcut; the alternative maps pinch-in → Show Desktop and drops the spread, or maps pinch to
   nothing.
2. **Space direction.** Default: **natural** (fingers left → next Space, `⌃→`), matching the Mac.
   The alternative inverts it (`gestureNaturalSpaces = false`).
3. **The fn bit.** Default: **set fn** on the arrow and F11 chords (§2.3's finding). If P2 shows the
   plain chord already fires on his Mac, drop the fn bit so older hosts work too (one line).
4. **Tier 2.** Default: **Tier 1 only** now; build Tier 2 (tracking swipes, pinch-zoom, rotate) only
   if §9's probe shows macOS 27 accepts synthesized gestures from Sill's background process **without
   Input Monitoring**. If it needs that third permission, **do not** build it — the discrete chords
   are enough. Noah decides if a third permission is ever worth it.
5. **The off switch's default.** Default: **three-finger gestures on** (they conflict with nothing
   today). The alternative ships them off, discoverable in Settings.
6. **Four-finger.** Default: **best effort, same actions as three**; never relied on. The alternative
   ignores four fingers entirely (`maxFingers = 3`).
7. **Haptic on a gesture.** Default: **a light tick** (iPhone only; silent on iPad). The alternative
   is none.
8. **A gesture while a modifier is latched.** Default: **the gesture ignores the latch and leaves it
   latched** (like Spotlight). The alternative spends the latch.

---

## 12. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the branch's attribution line
(`Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`).

0. **This plan** (committed).
1. **"iOS: recognize three-finger gestures (pure)."** `TrackpadGestures.swift` + its four pbxproj
   entries; the `gestures` check and its CI matrix line. Gates: H1 (iOS), H3.
2. **"Protocol/host: the fn modifier bit for gesture chords."** `KeyModifiers.function` (device),
   `flags(from:)` one line (host), the kind-28 reservation comment. Gates: H1, H2, H4, H5, H6.
3. **"iOS: three-finger gestures drive the Mac; a device switch to turn them off."** Wire the
   recognizer into `Trackpad` and `InputOverlay` (with the scroll-end guard and
   `editingInteractionConfiguration = .none`); the send sites (the §3 chords); the Settings group and
   its `Sill.trackpadGestures` default. Gates: H1 (iOS), S (§8.2 photos).
4. **"docs: three-finger trackpad gestures."** This plan's result; CLAUDE.md (Current step; Layout —
   the new file; Build and run — the switch and the harness; Milestone/gestures note; Untested, for
   Noah: P1–P10).
5. **Review and hand-over.** Three lenses: the recognizer's state machine and its coexistence with
   the one/two-finger paths; the fn/wire change and compatibility; the device UI and the switch. A
   "Review fixes" commit if needed, then H1–H6 and the photos again. Hand P1–P10 (and the §9 probe
   decision) to Noah. **Stop there.** Tier 2 is a separate, later PR, only if §9 passes.

**Rebases.** This branch is off `origin/main` at 8b0d418. `pointer-visibility` (kind 26) and the
menu-bar sketch (24/25/27) reserve their kinds in docs; kind 28 stays free for Tier 2 whichever
lands first. Tier 1 touches `InputInjector.flags(from:)` (host) and `TrackpadView`/`InputOverlay`/
`HostSettingsPanel`/`PortraitStreamScreen` (iOS); `pointer-visibility` also touches the trackpad and
overlay draw sites, so if it merges first, re-check those files.
