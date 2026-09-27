# Full macOS trackpad gestures from the device — the plan

## Status (2026-09-27)

Built on the branch `trackpad-gestures` (worktree `/Users/noah/Downloads/winstream-gestures`) in
§13's order, one commit per step, every default of §12 taken: main merged twice (6678ca3 at
5c6a850; 5e6ddaa at 2b38179, PR #31 the Mac's pointer among it, which landed during the host step),
kind 28 and `WindowList.gestures` (649ff7f), the Mac's side (902e5e4), the pure recognizer (487ec26),
the surfaces, the device's switch and the rig (5cd067c), then these documents. §15 has the results
and what differs from the plan. **Tier 2 is not built and §10's probe was not run**: nothing was ever
posted to the Mac (the workflow's rule while Noah slept), so Tier 2 stays a later PR that starts with
that probe, run by Noah or with his go-ahead.

The review (§13's step 7: the stroke gate, the wire and the resolver, the Settings group) found
seven things, each checked here before it was fixed (§15, "Review fixes"; five reproduced, the
VoiceOver one read in the code, the chord's inferred, since nothing may be posted): three-finger
strokes placed slowly or beside a resting thumb clicked, dragged or scrolled; a pinch led by the
thumb read as a swipe; a brief extra contact decided a swipe as nothing; VoiceOver users were told
to use three fingers; a chord could leave control or fn set for the next click; a scroll before a
gesture broke the reversal; and what Sill opened never expired. Left: Noah's device tests, §9.5.


The plan, 2026-09-26. It stands alone: the implementer needs no other design document. Written from a
read-only survey of `/Users/noah/Downloads/winstream-gestures` (branch `trackpad-gestures` from
`origin/main` at 8b0d418) and read-only probes on this Mac (macOS 27.0, 26A428), then revised the
same day by a critique against the code, a simulator rig and this Mac's own settings (the list
after "Reading of it"; the evidence is in §2 and §14). Line numbers are at 6678ca3, the branch with
main at 5c6a850 (PRs #20 to #30) merged in; §14 keeps the numbers the critique checked at 8b0d418.
Since 8b0d418 `TrackpadView.swift` gained the phone's vertical span and a DEBUG input test (PR
#30), `PortraitStreamScreen.swift` the phone's layout, and CI's mutants matrix four checks. **No
gesture, key, click, drag or text was posted to the Mac. No CGEvent was posted, no event tap was
created, and the pointer was never moved.** Both passes only read: the window server's
symbolic-hotkey table through its getters, preferences with `defaults read`, and files. The
critique's rig drove the real `TrackpadView.swift` and `InputOverlay.swift` with synthesized
touches in a simulator of its own, deleted afterwards (§2.1); nothing it did reached the Mac.

**Noah's request (2026-09-23), in his own words:** "I also want to be able to use full macos
gestures on the touchpad, so far only 1 or 2 finger gestures are working. Would that be possible?"
and "Queue it after the VPN feature." On 2026-09-26: "Work on 5-12 as well please" (item 9 of the
queue is trackpad gestures with three or more fingers) and "Make sure to spawn as many Opus 5.5
agents as you need, don't hold back." This plan **is** that work; a later relayed message about
another topic does not narrow or cancel it. The small decisions are delegated (§12 records them).

**A limit Noah stated himself:** the iPad's trackpad view cannot see a four-finger gesture reliably
(iPadOS takes four-finger swipes for itself), so **three-finger gestures are the target and
four-finger ones are best effort**.

**Reading of it.** Today the portrait trackpad (`TrackpadView.swift`) is relative, like a Mac's:
one finger moves the pointer, a tap clicks, press-and-hold drags, two fingers scroll (with phases
and momentum) and a two-finger tap right-clicks. The landscape stream (`InputOverlay.swift`) is
direct: a tap clicks where it lands, a long press right-clicks, one or two fingers scroll, and the
Pencil is the mouse. Full macOS gestures — Mission Control, App Exposé, Spaces, Apps (Launchpad
before macOS 26), Show Desktop — are three- and four-finger gestures on a Mac. This plan recognizes
them from three fingers on the device's glass, sends each as one named gesture that the Mac turns
into its own shortcut for that action, and changes nothing about one- and two-finger strokes.

**What the critique changed (2026-09-26).** Each point's evidence is in §2.
1. **The wire.** A named gesture in a new kind 28, resolved on the Mac (§4, §7), replaces `.key`
   chords carrying a new fn modifier bit. Those chords would have gone through the host's key path,
   which first activates the streamed app and holds the key up to 0.6 s; a shortcut turned off or
   changed on the Mac would have let the keys reach the app in front (the pinch's F4 always would:
   nothing is bound to it); the device cannot name the Mission Control and Launchpad keys, whose
   shortcuts no other shortcut shares; and the arrow chords have the same signature as macOS's
   window-tiling shortcuts.
2. **The recognizers.** Today's recognizers already click, drag, right-click or scroll in some
   three- and four-finger strokes, and the old guard in `handlePan` read `numberOfTouches`, which a
   pan that has begun never raises past 2 (§2.1). A stroke gate (§6.2) now owns every stroke that
   reaches three fingers in time, and the old three-finger long press could not decide alone.
3. **The semantics.** A gesture is decided when the fingers lift, from their net travel: a swipe
   taken back does nothing, and touches the system cancels (four fingers on an iPad) send nothing.
   The opposite gesture closes what the last one opened, as on a Mac. While a window streams, a
   gesture shows the Desktop first, since none of these views is in a window's capture.
4. **The Mac.** Launchpad is Apps on macOS 26 and later, reached through the Launchpad key's
   shortcut, which is on; App Exposé's gesture is off on Noah's Mac, where a three-finger swipe
   down only closes Mission Control.
5. **The settings.** The group shows whatever state the Mac's settings are in, says when the Mac
   needs updating, and names the right device; the old claim that a Magic Keyboard's two-finger
   scroll reaches Sill was wrong.
6. **The tests.** No test sends input or a gesture to a host on this Mac (a synthetic host injects
   input into the real session); the old H4 was not pure and now is; a simulator touch rig checks
   the real surfaces; the project-file IDs move out of home-pairing's way.

---

## 1. Scope

**In.** Three-finger gestures on the two glass surfaces Sill owns — the portrait trackpad
(`TrackpadSurface`, `TrackpadView.swift`) and the landscape stream (`InputOverlayView`,
`InputOverlay.swift`):

| Gesture (three fingers) | What the Mac does |
|---|---|
| Swipe up | Mission Control |
| Swipe down | App Exposé (the front app's windows); right after Sill opened Mission Control, closes it |
| Swipe left | Next Space (the Space to the right) |
| Swipe right | Previous Space (the Space to the left) |
| Pinch in | Apps (Launchpad on macOS 14 and 15); right after Sill's Show Desktop, brings the windows back |
| Spread | Show Desktop; right after Sill opened Apps, closes it |

The device sends each as one kind 28 message (§4). The Mac posts its own current shortcut for that
action (§7), so a shortcut Noah changed is followed and one he turned off does nothing. A
device-local switch turns them off (§8). Four fingers do the same where the system lets them
through (§6.4).

**Out (v1 of gestures).**
- **Tracking gestures** (Mission Control that follows the fingers and can be taken back mid-swipe,
  pinch-to-zoom, rotate, smart zoom). They need a private gesture-event API on the host; §5 surveys
  it, §10 gives the bounded probe that must prove it on macOS 27 **before** any of it is built. It
  is **Tier 2**, not shipped here.
- **Notification Center** (a Mac's two-finger swipe from the right edge; its fn N shortcut is on
  here, §2.3, so a later pass could add it) and **Look Up** (a three-finger tap; off on Noah's Mac).
- The **Magic Keyboard trackpad's** three- and four-finger gestures: iPadOS's (§2.2).
- Any change to one- or two-finger strokes. Hard rule (§11).

---

## 2. Investigated

### 2.1 What the glass sees, and what today's code sends for three and four fingers

From the code:
- Both surfaces set `isMultipleTouchEnabled = true` (`TrackpadView.swift:178`,
  `InputOverlay.swift:48`), so every contact arrives.
- The portrait trackpad has five recognizers: the one-finger tracker (`FingerTracker`, a long press
  with no delay and unbounded movement that only watches, set up at `:183-188`, class at
  `:476-502`), a pan for one or two fingers (`:193-197`), a tap (`:199-202`), a two-finger tap
  (`:204-207`) and a 0.45 s long press (`:212-216`). The tracker, the pan and the long press have
  the view as delegate, whose answer lets each of them recognize beside any other (`:221-222`); the
  taps have none.
- The landscape overlay has a tap (`:61-64`), a 0.45 s long press (`:66-69`) and a pan for one or
  two fingers (`:72-76`), all direct-touch only (`:53`), and a hover recognizer (`:79-80`). One
  finger scrolls here (the pan's minimum is 1); there is no two-finger tap.
- `FingerTracker` counts a second finger from the view's own touches (`sawSecondFinger`,
  `:489-496`).
- Neither pan sets `allowedScrollTypesMask`; both read 0 (below).

**The critique's rig** (§14 has how): a scratch app for the iOS 27 simulator that compiles the real
`TrackpadView.swift` and `InputOverlay.swift` (stand-ins only for `Palette`,
`HEVCDisplayView.videoRect` and the key types), drives both surfaces with synthesized multi-finger
touches (KIF-style private UIKit calls, in the scratch app only), and logs every `InputEvent` each
surface would send and every recognizer transition. Its one- and two-finger strokes came out as the
code intends (a tap clicks, a drag moves the pointer or scrolls, a flick scrolls with momentum, a
two-finger tap right-clicks on the trackpad). Three and four fingers, 62 pt apart, landing 16 ms
apart unless the row says otherwise:

| Stroke | Portrait trackpad sends | Landscape overlay sends |
|---|---|---|
| Three land (16 or 50 ms apart, or together), then swipe or spread | nothing: the tap and the long press fail at the second finger, the pan and the two-finger tap at the third; the tracker moves nothing once it saw a second finger | nothing |
| Three pinch in | **a left click** as the last finger lifts | **a left click** (with its move) |
| Three rest 0.6 s, then swipe | **the left button goes down** 450 ms after the third finger landed and up at the end: a drag | **a right click** 450 ms after the third finger landed |
| Three tap | nothing | nothing |
| First finger slides 12 pt before the others land | pointer moves, then **a scroll with momentum**: the pan began with one finger, took the second and ignored the third | **a scroll with momentum** |
| Two scroll 60 pt, a third lands 133 ms after the first | the scroll goes on with two fingers (the third ignored), momentum at the end | the same |
| Three move, one lifts, two go on | nothing | nothing |
| Four land | **pointer moves**: the pan, failed at the third finger, starts again on the fourth and tracks it alone | **a scroll with momentum** |
| Three, then the touches are cancelled | nothing | nothing |

Two things follow. Recognizers that failed re-arm on a later finger (the one-finger tap, the long
press and the pan all did), and a pan that has begun ignores a third finger and keeps
`numberOfTouches` at 2. So the old §2.1 ("the pan ignores it") and the old §6.3 ("a third finger
already ends its recognition") were each half right, and the old guard in `handlePan` ("when the
count rises to ≥3 while `scrolling`") could never fire. The old plan's own recognizer (a long press
needing three touches, with no delay), added beside them, began when the third finger landed in
every three-finger stroke above, including the two where a scroll was already running; ended at
the first lift (a long press ends when a finger lifts, `UILongPressGestureRecognizer.h`); and
reported three touches with four down. It cannot decide on its own. Nothing here may rely on
UIKit's bookkeeping for staggered fingers either: it is unspecified, and synthesized touches may
differ from glass in exactly this. §6.2's gate makes the outcome independent of it, and P4 repeats
the table on the iPad.

### 2.2 What iPadOS and iOS keep

- **Four and five fingers** on an iPad are the multitasking gestures (Home, the app switcher,
  switching apps, a pinch to Home), on by default and switchable in Settings › Multitasking &
  Gestures. When iPadOS takes one it cancels the app's touches, after the app saw them begin. iOS on
  an iPhone (the Duo is one) has no four-finger system gestures, so there four fingers reach Sill.
  → **Three fingers are the target**; four are best effort (§6.4).
- **The three-finger text gestures** (undo and redo: a swipe left or right, or a double tap; copy,
  cut and paste: a pinch and a spread; the edit bar: a tap) follow the first responder's
  `editingInteractionConfiguration` (`UIResponder.h:26-29`, `:140`). In the rig, the moment
  `InputOverlayView` (a `UIKeyInput`) became first responder, UIKit added a `UITextEffectsWindow`
  holding a `UIEditingOverlayGestureView` with a `_UIKBUndoGestureObserver`; with the property
  overridden to `.none` and first responder taken again, the observer was still installed and
  enabled. Whether it then stays quiet the rig cannot see: its touches go to the app's own window
  and never reach another window's recognizer (an attempt through UIKit's own HID entry point,
  `_enqueueHIDEvent:`, delivered nothing). So `.none` on `InputOverlayView` is the defence and P6 is
  the proof. It belongs there only: `InputOverlayView` is the one responder Sill makes first, in
  both layouts (the portrait picture pane is the same overlay, `PortraitStreamScreen.swift:375-390`),
  and with a hardware keyboard it stays first responder to forward keys. `TrackpadSurface` never
  becomes first responder, so an override there does nothing, and while the keyboard is up in
  portrait the overlay's `.none` is the one iPadOS reads. Deciding at lift (§6.1) makes a lost race
  harmless: cancelled touches send nothing.
- **Accessibility:** with VoiceOver on, three-finger swipes scroll and a three-finger tap speaks;
  with Zoom on, three-finger double taps and drags are Zoom's. Neither surface has
  `.allowsDirectInteraction`, so these stay the system's, as today, and the Settings group's rows
  do the six gestures instead, as accessibility actions (§8).
- **The Magic Keyboard trackpad:** its three- and four-finger swipes and pinches are iPadOS's
  (Home, the app switcher, switching apps) and never reach an app → glass only. **Correction:** its
  two-finger scroll does not reach Sill either. Both pans leave `allowedScrollTypesMask` at 0 (read
  in the rig), so trackpad and wheel scrolling make no pan callbacks; its pointer (hover) and its
  clicks (indirect touches, `InputOverlay.swift:223-269`) do reach Sill. Unchanged here; a later
  change could set `.continuous`.
- `INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES` (`project.pbxproj:382,414`).
- A finger that lands on the bottom edge starts the Home indicator's gesture, as it does for any
  stroke today.

### 2.3 macOS: what the gestures are called, and how the Mac binds them

Read on this Mac, read-only: the window server's symbolic-hotkey table through SkyLight's getters
(`CGSGetSymbolicHotKeyValue`, `CGSIsSymbolicHotKeyEnabled`, loaded with `dlsym`; nothing set),
`defaults read`, and files. Keycodes are Carbon virtual keys; the modifiers are the window server's
stored signature (`CGEventFlags` bits).

| Action | Hotkey | Here | Keycode | Stored modifiers |
|---|---|---|---|---|
| Mission Control | 32 | on | 126 (↑) | `0x840000` control + fn |
| The Mission Control key (inferred) | 108 | on | 160 | `0x800000` fn |
| Application windows (App Exposé) | 33 | on | 125 (↓) | control + fn |
| Control + the Mission Control key (inferred: application windows) | 115 | on | 160 | control + fn |
| Show Desktop | 36 | on | 103 (F11) | fn |
| Command + the Mission Control key (inferred: Show Desktop) | 110 | on | 160 | `0x900000` command + fn |
| Move left a Space | 79 | on | 123 (←) | control + fn |
| Move right a Space | 81 | on | 124 (→) | control + fn |
| Show Apps (Show Launchpad before) | 160 | off, unbound | — | — |
| The Launchpad key (inferred) | 173 | on | 131 | fn |
| Show Notification Center | 163 | off, unbound | — | — |
| fn N (inferred: Notification Center's fn shortcut) | 212 | on | 45 (N) | fn |
| Tile Left, Right, Top, Bottom Half | 240-243 | on | 123, 124, 126, 125 | control + fn |
| Fill, Center, Return to previous size | 237-239 | on | 3 (F), 8 (C), 15 (R) | control + fn |
| Arrange … | 248-251 | on | the arrows | `0x860000` control + shift + fn |
| (not named here) | 198-200 | on | 125, 123, 124 | control + fn |
| Spotlight (the key row's) | 64 | on | 49 (Space) | `0x100000` command |

- **The fn finding, revised.** Arrow and F keys carry fn by themselves (a synthesized Up reads back
  `flags = 0x20a00000` from the constructor: fn `0x800000` and numeric pad `0x200000`,
  `keyflags.swift`), every arrow and F11 shortcut is stored with fn, and `InputInjector.key`
  rebuilds the flags from five bits and drops it (§2.4). But the window-tiling shortcuts macOS 15
  added (fn control arrows, 240-243) are stored with the **same keycodes and modifiers** as the
  Spaces and Mission Control ones (79, 81, 32, 33), and 198-200 share them too. The table does not
  say how the window server tells a held fn (Globe) key from an arrow's own fn, so a synthesized
  control-fn-→ might switch the Space or might tile the front window; which one is unknown until P2.
  Keycodes 160 and 131 avoid the question: they are the Mission Control and Launchpad keys of Apple
  keyboards (160 alone opens Mission Control, with control the application windows, with command
  Show Desktop; 131 opens Launchpad — what those keys do; the names are inferred and P2 confirms
  them), and nothing else binds them. So the Mac prefers them (§7.1); only the Spaces have no key of
  their own.
- **Names** (the Keyboard settings extension's `DefaultShortcutsTable.loctable`): "Show Apps" (the
  old "Show Launchpad"), "Tile Left Half" through "Tile Bottom Half", "Fill", "Center",
  "Arrange …". `/System/Applications` has `Apps.app` (`com.apple.apps.launcher`, macOS 27 at least)
  and `Mission Control.app`, and no `Launchpad.app`.
- **The Mac's own trackpad settings** (Noah's Mac, `defaults read`): `com.apple.dock
  showAppExposeGestureEnabled = 0`, so App Exposé's gesture (a three-finger swipe down) is off, as
  macOS ships it, and a three-finger swipe down there only closes Mission Control.
  `com.apple.AppleMultitouchTrackpad`: three-finger vertical and horizontal swipes 2 (Mission
  Control and the Spaces), four- and five-finger pinches 2 (Launchpad or Apps, and Show Desktop,
  which on a Mac are thumb-and-three-finger pinches), three-finger drag 0, three-finger tap 0 (Look
  Up off), two-finger swipe from the right edge 3 (Notification Center). Sill's three-finger pinch
  and spread therefore stand in for the Mac's four-finger ones, which iPadOS keeps.
- **What the device can see.** A window stream captures that window only
  (`desktopIndependentWindow`), and a window on the virtual display is captured with its own app's
  windows only (`VirtualStage.swift:343-344`, `:488-489`). Mission Control, App Exposé, Apps and
  Show Desktop are drawn over the display by the system, so only the Desktop source shows them —
  the reason the Spotlight key exists only there (`showSpotlight`,
  `PortraitStreamScreen.swift:578-580`). After a Space switch, a window stream still shows its
  window. → §3's Desktop rule.
- **No public CGEvent constructor makes a gesture.** `CGEventTypes.h` has a public `CGGesturePhase`
  enum (`kCGGesturePhaseBegan = 1`, …) for **reading** magnify and rotate events, and the private
  event types 29 (`NSEventTypeGesture`) and 30 (`NSEventTypeMagnify`) can be set on a `CGEvent` from
  Swift (`CGEventField(rawValue:)` and `CGEventType(rawValue:)` never return nil for these; a
  `CGEvent`'s `type` can be set to 29 or 30 and private fields written — verified without posting,
  `fields.swift`). But there is **no public API to construct and post a magnify, rotate, swipe or
  dock-swipe gesture**. That path is Tier 2 (§5).

### 2.4 The host's key path, and a hazard for tests

- A `.key` goes through `raiseIfInteracting` and `deliver` (`StreamCoordinator.swift:605-609`,
  `:1079-1156`): a key-down while a window streams activates that window's app through
  Accessibility when it is not frontmost, makes the window key, and holds all input up to 0.6 s
  (`activationTimeout`, `:1077`) until the app is up. A Mission Control chord sent as a key would
  first bring the streamed app forward and wait for it.
- `InputInjector.key` posts only the HID usages its table knows (`virtualKeys`,
  `InputInjector.swift:366-416`): keycodes 160 and 131 have none. It sets the flags from five bits
  (`:348`; `flags(from:)` at `:356-364`).
- A chord the Mac does not bind reaches the frontmost app as keys. The old plan's pinch (F4, bound
  to nothing here) would have reached it every time; F4 means something in some apps (Excel repeats
  the last action with it).
- **Tests must not send input to a host on this Mac.** A synthetic host still injects: `.input`
  goes to `InputInjector` with `currentSourceRect()`, which for the Desktop is the real display's
  frame (`StreamCoordinator.swift:674-679`), and the processes agents run here hold Accessibility
  (`AXIsProcessTrusted()` is true, §5). The old H4 ("send, from a scratch client, a `.key(hidUsage:
  0x52, …)`") would have opened Mission Control on Noah's Mac. `sillclient.py` sends no input
  today; §9 keeps it that way and gives gestures a test path that cannot post (§7.4).

### 2.5 Idle and encoder guards (for §10's probe)

- `HIDIdleTime` (IORegistry, `IOHIDSystem`) reads seconds since the last user input, from a process
  without any grant (`state.swift`); the probe uses it to refuse to run within 60 s of real input.
- Sill.app's log (`~/Library/Logs/Sill/Sill.log`) shows `[30s] idle · 0 clients` while no device is
  connected; the probe wrapper refuses to run unless the last such line (or `Client left`) is newer
  than the last connect. At the time of writing Sill.app (pid 5205) was idle, 0 clients.

---

## 3. The gestures and what the Mac does (exact)

Three fingers (four where the system lets them through), on either surface. **Natural direction**,
as on a Mac: the content follows the fingers, so fingers moving **left** bring the Space on the
**right**.

| Gesture | Action | The Mac's shortcut: the first that is on (§7.1) |
|---|---|---|
| Swipe up | Mission Control | 108 (key 160, fn), else 32 (⌃↑) |
| Swipe down | App Exposé | 115 (key 160, control + fn), else 33 (⌃↓) |
| Swipe left | Next Space | 81 (⌃→) |
| Swipe right | Previous Space | 79 (⌃←) |
| Pinch in | Apps | 173 (key 131, fn), else 160 (Show Apps, when bound) |
| Spread | Show Desktop | 36 (F11, fn), else 110 (key 160, command + fn) |

- **Decided at lift** (§6.1), from the fingers' net travel between the stroke arming and the first
  of its three fingers lifting: a swipe taken back before lifting does nothing, as on a Mac, and a
  stroke the system cancels sends nothing.
- **Once per stroke, and nothing else in it.** From its third finger down (before any has moved
  24 pt), a stroke sends no pointer motion, click, button or scroll (§6.2), however slowly the
  fingers came and whatever rests on the glass. Motion before the third finger is today's (the
  tracker's 2 pt slop, as before any two-finger scroll).
- **The opposite gesture closes what Sill opened** (§7.2): a swipe down after Sill's Mission Control
  closes it; a swipe up after its App Exposé closes that; a spread after its Apps closes Apps; a
  pinch after its Show Desktop brings the windows back. The same gesture again does nothing (the
  view is already open) and, made once more straight after, opens it again (it was closed on the
  Mac itself); the Spaces leave an open view as it is. A click, a key or text from any device, a
  window picked or an app launched from one, and the last device leaving forget what was open; a
  pointer move or a scroll does not. Each of these shortcuts toggles its view, so closing is the
  same chord again.
- **The Desktop first.** While this device streams a window, a gesture first selects the Desktop, as
  the Desktop button does (§6.3), because none of these views is in a window's capture (§2.3).
- **A latched modifier** is ignored and stays latched: a gesture is not a keystroke (the Spotlight
  cap ignores latches too, `Spotlight.press` at `StreamScreen.swift:601-605`, though its tap spends
  them, `PortraitStreamScreen.swift:670-673`).

---

## 4. Wire

### 4.1 Kind 28, `gesture` (device → host)

```
/// Device → host (kind 28): a three- or four-finger gesture the device recognized. The host turns
/// it into its own shortcut for the action (docs/trackpad-gestures-plan.md §7). Sent only to a host
/// whose window list says `gestures` 1 or more.
public struct TrackpadGesture: Codable, Equatable {        // StreamProtocol, Gesture.swift (new)
    public var gesture: String   // "swipeUp" | "swipeDown" | "swipeLeft" | "swipeRight" | "pinch" | "spread"
    public var fingers: Int?     // 3 or 4, as the device counted them
}
```

`case gesture = 28` joins `StreamMessageKind` in this change, with a comment like kind 23's.
HostSettings.swift's rules apply: JSON; strings, not enums, on the wire; later fields optional; a
host skips a name it does not know. 24, 25 and 27 (the menu bar sketch) and 26 (the Mac's pointer,
`pointer-visibility`) stay reserved by their plans; 28 was free in every worktree on 2026-09-26.

### 4.2 The Mac says it takes them

`WindowList.gestures: Int?` (`Switcher.swift`): 1 means this host takes kind 28's six gestures; nil
from every host before this change. The device keeps it as `StreamClient.hostGestures`, beside
`hostProtocol` (`StreamClient.swift:495-496`, set at `:2331`), and sends kind 28 only while it is 1
or more. Tier 2 would make it 2 and add optional tracking fields to the same kind (§5), sent only to
a host that says 2.

### 4.3 Compatibility

- **This device, an older host:** `gestures` is nil, so no kind 28 goes out; the settings group
  says to update Sill on the Mac (§8), and the stroke gate still keeps three-finger strokes from
  clicking or scrolling. A kind 28 sent anyway would be skipped: an older `parseHeader` maps 28 to
  `.unknown`, and the coordinator's `handle` ignores that.
- **An older device, this host:** it sends no kind 28 and ignores `gestures` (JSONDecoder skips keys
  it does not know).
- **`sillclient.py` and the CLI:** the window list carries one more key, which neither prints;
  nothing prints unless a kind 28 arrives. The default synthetic stdout stays byte-identical.
- **The compatibility floor** (CLAUDE.md): additive. A new kind and an optional field, and the new
  message goes only to a host that said it takes it.

### 4.4 Why not `.key` chords with an fn bit (the old §4.1)

- The key path activates the streamed app and holds the key up to 0.6 s before posting (§2.4).
- A shortcut turned off or changed on the Mac lets the keys reach the app in front, and the pinch's
  F4 always would. The Mac reads its own live table instead and posts nothing rather than guess
  (§7.1).
- The Mission Control and Launchpad keys (160, 131), which no tiling shortcut shares, have no HID
  usage the device could send.
- An older host drops an fn bit silently, so the device could not tell a Mac where the gesture
  works from one where it leaks keys; a capability field can.
- The live table and the reversal (§7.2) belong to the Mac, which sees every device's input.

What the old fn bit would still fix is a separate thing: the hardware keyboard's and the key row's
arrows lose their fn on the way to the Mac, so a latched ⌃ plus the key row's ↑ may not open
Mission Control. A later change could keep the constructor's own fn and numeric-pad bits for arrow,
F and navigation keys in `InputInjector.key`. Not in this plan.

---

## 5. Tier 2 survey (private gesture events) — do not build until §10 proves it

This is a **read-only survey**, not an implementation. Building any of it is gated on §10's bounded
probe passing on macOS 27; if it does not, Tier 2 is dropped and Tier 1 is the whole feature.

**What Tier 2 would add:** a Mission Control or Spaces swipe that *tracks the fingers* and can be
taken back, pinch-to-zoom, rotate, smart zoom — the gestures whose semantics are continuous, which
a discrete shortcut cannot express. On the wire it would extend kind 28 rather than take a new
kind: optional `phase` (`"began"`, `"changed"`, `"ended"`, `"cancelled"`), `dx` and `dy` (fractions
of the pad), `magnification` and `rotation`, sent only to a host whose window list says
`gestures: 2`. A Tier 1 host keeps getting one message per gesture.

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

**What is unknown and must be proven (§10):**
1. Whether macOS 27 **accepts** such a synthesized gesture from a **background, non-GUI process**
   (Sill's host) that holds **Accessibility** (`AXIsProcessTrusted() == true`,
   `CGPreflightPostEventAccess() == true`, both true here) but is not a foreground app.
2. Whether it needs **Input Monitoring** (`kTCCServiceListenEvent`) or any grant beyond
   Accessibility. If it does, Tier 2 costs a third permission (after Screen Recording and
   Accessibility) — a second system alert, another row in Settings › Permissions, one more grant a
   re-sign or `tccutil reset` loses, one more App Store privacy answer — and the plan's default
   (§12 Q7) is **not** to pay that for gestures: Tier 1 stays the feature.
3. Whether the events are **stable on macOS 27** at all (private fields drift between releases).

**Honesty.** The event-**posting** probe was **not executed in this environment.** The read-only
survey above (the symbol surface, the Swift addressability of types 29/30 and the private fields,
the idle/encoder guards) is done; the one remaining step — posting a self-reversing dock-swipe and
watching whether Mission Control opens — moves the real desktop and so must run under §10's guards
on Noah's Mac, deliberately, for a few seconds, while he is away and no device is connected. Until
it passes, **Tier 2 is not built** and this plan ships Tier 1 only.

---

## 6. iOS design

### 6.1 `TrackpadGestures`, the pure recognizer (new file, checked with swiftc)

`iOSClient/TrackpadGestures.swift`: a **pure struct** (Foundation and CoreGraphics only, no UIKit),
so it compiles and is checked on its own, like `DiscoveryPolicy` and `HostSettingsLedger`. It is
the whole decision and the stroke gate's state, so it is the whole test surface for them (§9.1).

```
struct TrackpadGestures {
    enum Gesture: String, Equatable { case swipeUp, swipeDown, swipeLeft, swipeRight, pinch, spread }
    enum Output: Equatable { case none, silenced, gesture(Gesture, fingers: Int) }

    // Tunables, in the surface's points and seconds (P1 and P3 tune them on glass).
    var chordWindow: TimeInterval = 0.15   // the three fingers that arm a stroke land within this of each other…
    var chordTravel: CGFloat = 24          // …before any finger has moved this far from where it landed
    var swipeDistance: CGFloat = 40        // the fingers' centroid, net travel, for a swipe
    var flickDistance: CGFloat = 20        // or this much, moving at flickSpeed over the last 50 ms
    var flickSpeed: CGFloat = 500
    var axisRatio: CGFloat = 1.3           // the dominant axis beats the other by this
    var swipeShare: CGFloat = 0.5          // each of the three moved this share of the centroid's way along it
    var pinchRatio: CGFloat = 0.25         // the fingers' mean spread changed by this fraction

    // Fed every touch of the surface by its StrokeObserver (§6.2).
    mutating func down(_ id: Int, at point: CGPoint, time: TimeInterval, holding: Bool) -> Output  // .silenced once
    mutating func moved(_ id: Int, to point: CGPoint, time: TimeInterval)
    mutating func up(_ id: Int, at point: CGPoint, time: TimeInterval) -> Output                   // .gesture at most once
    mutating func cancelled(_ id: Int)                // the system took the touch: nothing is decided
    mutating func otherTouch()                        // a Pencil's or the iPad's own pointer's touch
    private(set) var silent: Bool                     // from three fingers down until the next stroke's first touch
    var armed: Bool                                   // the stroke can become a gesture
}
```

- **A stroke** runs from its first touch down to its last touch up. It goes **silent** once three
  fingers are down, before any finger has moved `chordTravel` from where it landed and while no
  button it pressed is held (`holding`: the trackpad's press-and-hold drag, whose button must still
  come up), however slowly the fingers came down and whatever else rests on the glass. A two-finger
  scroll that a third finger joins after moving is never silent and goes on exactly as today (the
  rig's "two scroll, a third 133 ms later" had moved 60 pt).
- **Silence** lasts from then until the next stroke's first touch — not until the last lift, because
  a tap's action runs after its touch has ended — and the surfaces send nothing (§6.2).
- A silent stroke **arms**, and can become a gesture, when the three fingers that landed last came
  down within `chordWindow` of each other, before any finger moved `chordTravel`, with no button
  held, no touch of it cancelled and at most four down. A thumb resting on the glass before neither
  keeps three fingers from arming nor becomes one of them; three fingers placed more slowly than
  that are silent and decide nothing.
- **The decision**, at the first lift of one of the three that armed the stroke (any other finger
  lifting only leaves the stroke): the centroid of the three, from where they were at arming to
  where they are at that lift, and their mean distance from it. A **swipe** when the centroid
  travelled at least `swipeDistance` (or `flickDistance` while moving at `flickSpeed` or faster over
  the last 50 ms), one axis beats the other by `axisRatio`, and the fingers **moved together**: each
  of the three at least `swipeShare` of the centroid's travel along the swipe, and no other finger
  that moved (`chordTravel` or more since arming or landing) that share or more the other way. In a
  pinch or a spread some digit moves against the others however far the centroid goes: a pinch led
  by the thumb drags the centroid along with the thumb. Else a **pinch** or a **spread** when the
  mean distance from the centroid, of the three and of every other finger that moved (a thumb
  pinching with three fingers), changed by `pinchRatio`; else nothing. At most one decision per
  stroke. `fingers` counts the three and the other fingers that moved, 4 at most: a thumb resting on
  the glass does not count, a fourth finger swiping with them does. A fifth finger down leaves the
  stroke silent and deciding nothing.
- **Cancelled** touches (the system took them) decide nothing; the stroke stays silent. A touch
  cancelled before three fingers are down keeps the stroke from arming, not from going silent.
- Deterministic: the same events give the same outputs, which §9.1 checks with 5,000 random strokes
  and mutants.

### 6.2 The stroke gate, on both surfaces

- **An observer, not the view.** `StrokeObserver` is a `UIGestureRecognizer` subclass beside
  `ScrollMomentum` in `InputOverlay.swift` (no new file), one on each surface. It overrides the four
  touch methods to feed the surface's `TrackpadGestures` with every touch (counted from the view's
  own touches, as `FingerTracker` does), never leaves `.possible`, and takes nothing:
  `cancelsTouchesInView`, `delaysTouchesBegan` and `delaysTouchesEnded` false, `canPrevent(_:)` and
  `canBePrevented(by:)` false, and a delegate that lets it recognize beside any other. Both count
  direct touches only (a Magic Keyboard click on the trackpad is one indirect touch). Not the view's
  own `touchesBegan`: the pans, taps and long presses keep `cancelsTouchesInView` true, so once one
  of them recognizes, the view hears no more of that stroke.
- **Every existing handler's first line**, while `silent`: return, sending nothing.
  - `TrackpadSurface`: `handleTrack` (no pointer motion), `handlePan` (no scroll, no motion),
    `handleTap` and `handleTwoFingerTap` (no click), `handleLongPress` (`.began` ignored, so
    `.ended` finds `dragging` false).
  - `InputOverlayView`: `handleTap`, `handleLongPress`, `handlePan`.
  - The Pencil and trackpad-pointer paths (`touchesBegan` … for `.pencil` and `.indirectPointer`,
    `InputOverlay.swift:223-269`) and hover are untouched.
- **A scroll open when the stroke goes silent** (`.silenced`, `onSilenced`; the rig's slide: the
  pan began with one finger and took the second) is closed at once without momentum:
  `endScroll(momentumVelocity: nil)` on the trackpad; on the overlay, `.scrollGesture(.ended)` with
  `scrollGestureOpen` cleared and no `startMomentum`. Deltas already sent stay (they moved less than
  `chordTravel`), and a scroll closes no view the reversal counts on (§7.2).
- **A stroke that never goes silent is untouched:** `silent` is false and every handler runs as at
  6678ca3. H7 proves it. No stroke goes silent while the trackpad's drag holds the button, so its
  `.ended` always sends the button up.
- **The switch off** stops only the send (§6.3): three-finger strokes stay silent, so the stray
  clicks, drags and right-clicks of §2.1 are gone either way.

### 6.3 Sending

- On `.gesture(g, fingers:)` from `up`, when the switch (§8) is on and `client.hostGestures ?? 0 >= 1`:
  1. While `client.active` is a window, `client.select(.desktop)` — the Desktop button's own call.
  2. `client.sendGesture(g, fingers:)`: on StreamClient's queue, flush a pointer move still waiting
     (as `sendInput` does for anything but a move, `StreamClient.swift:2196-2222`), then send kind
     28. Kind 6 and then kind 28, in that order, on the session's connection.
  3. On the trackpad, `clickHaptic.impactOccurred(intensity: 0.7)` (a no-op on an iPad). The overlay
     has no haptics today and gets none.
- Nothing else: no `setLocalPointer`, no pointer or scroll message.
- The surfaces reach the client through a closure, as `send` does today (`Trackpad` and
  `InputOverlay` gain `sendGesture`); the Desktop rule and the capability check live in
  `StreamClient.sendGesture`, so the two surfaces share them.

### 6.4 Four fingers (best effort)

The stroke arms at its third finger; a fourth that moves with them makes `fingers` 4, one that
moves against them (a thumb pinching with three fingers, as on a Mac) makes the stroke a pinch or a
spread, and one that stays where it is (a thumb resting) changes nothing. With iPadOS's four-finger
gestures on, iPadOS takes the stroke, the touches are cancelled and nothing goes to the Mac. With
them off, or on an iPhone, a four-finger swipe does what three do. Deciding at lift is what makes
this safe: the old plan fired at 45 pt of travel, which could open Mission Control on the Mac while
the iPad went Home. A fifth finger: silent, nothing.

### 6.5 The editing interaction

`InputOverlayView` overrides `editingInteractionConfiguration` to return `.none` (§2.2), the one
responder Sill makes first. It holds no text of its own and the Mac's undo is ⌘Z, so nothing is
lost. `TrackpadSurface` needs nothing: it is never first responder, and while the keyboard is up in
portrait the overlay's `.none` is the one iPadOS reads.

---

## 7. Host design (the Mac turns a gesture into its own shortcut)

### 7.1 `GestureChords`, the pure resolver (new file, checked with swiftc)

`Sources/SillHost/GestureChords.swift`, compiled on its own (`-package-name sill`, like
`clientlink`):

```
package enum GestureAction: String { case missionControl, appExpose, nextSpace, previousSpace, apps, showDesktop }
package struct HotKey: Equatable { var enabled: Bool; var keyCode: UInt16; var modifiers: UInt64 }  // as stored
package enum GestureOutcome: Equatable {
    case chord(GestureAction, hotKey: Int, keyCode: UInt16, flags: UInt64)
    case nothing(GestureAction?, reason: String)
}
package struct GestureChords {
    /// The first of these that is on and bound wins (§2.3).
    static let preference: [GestureAction: [Int]] = [.missionControl: [108, 32], .appExpose: [115, 33],
        .nextSpace: [81], .previousSpace: [79], .apps: [173, 160], .showDesktop: [36, 110]]
    /// macOS 27's own, as read on 2026-09-26 (§2.3): for a Mac whose SkyLight getters are missing.
    static let defaults: [Int: HotKey]
    var open: GestureAction?                                          // §7.2
    mutating func resolve(_ gesture: String, table: [Int: HotKey]) -> GestureOutcome
    mutating func otherInput()                                        // §7.2
}
```

- `swipeUp` → Mission Control, `swipeDown` → App Exposé, `swipeLeft` → next Space, `swipeRight` →
  previous Space, `pinch` → Apps, `spread` → Show Desktop; then §7.2 adjusts.
- The chord: the first hotkey in the action's list that is on and bound (keycode not 65535), with
  exactly its stored modifiers' device-independent bits (16-23). None → `.nothing`, with the reason
  the log line gives ("no shortcut for Apps is on in Keyboard Shortcuts"); never another action's
  chord, never a guess.
- An unknown gesture name → `.nothing(nil, …)`.

### 7.2 What Sill opened (the reversal)

- `open` is the view Sill's last gesture opened — Mission Control, App Exposé, Apps or Show Desktop —
  or nil. The pairs: Mission Control and a swipe down, App Exposé and a swipe up, Apps and a spread,
  Show Desktop and a pinch.
- With a view open: its reverse posts that view's chord again (it toggles closed) and forgets it;
  the gesture that opened it posts nothing ("already open", as on a Mac) and, made once more
  straight after, posts its chord again (`repeated`: the view was closed where Sill cannot see); a
  Space posts its own chord and keeps it; any other gesture posts its own action and remembers that
  view instead.
- `input(_:)`, for every `.input` from any device: a button or a key going down, or typed text, can
  close the view or act in it, so it forgets; a pointer move, a scroll (it pages through Apps and
  closes none of them) and a button or key coming up do not. A stroke that scrolled before it
  became a gesture sends its scroll's bracket first (§6.2), so a scroll forgetting would have made
  that stroke's reverse gesture open the other view.
- `forget()`: a window picked (kind 6; the Desktop picked, as a device does before a gesture made
  over a window, keeps it), an app launched (kind 7), a window's button pressed (kind 15), and the
  last device leaving (whoever comes next did not open it).
- The Mac's own keyboard and trackpad are not seen, so a view closed there still counts as open: its
  reverse gesture then opens it again, or the same gesture made twice more does (one wrong step
  either way).

### 7.3 Reading the table, posting the chord

- `SymbolicHotKeys.read(_ ids:) -> [Int: HotKey]` (impure, beside the resolver):
  `CGSGetSymbolicHotKeyValue` and `CGSIsSymbolicHotKeyEnabled` from SkyLight through `dlopen` and
  `dlsym`, getters only, read at each gesture (microseconds), so a shortcut changed while connected
  is followed. With the symbols missing, `GestureChords.defaults`, and one line at the first
  gesture. Private, like the `CGVirtualDisplay` the host already uses; read-only.
- `InputInjector.chord(keyCode:flags:)`: a key down from its `hidSystemState` source with exactly
  those flags and a key up with the flags the HID system's state table held before the chord, posted
  at `.cghidEventTap`, counted as `in.gesture`. Accessibility, which input already needs, and
  nothing more; `remindAboutAccessibilityIfNeeded` runs as for input.
- **The key up's flags.** Events posted from a source leave their flags in its state table
  (CGEventSource.h), and every pointer and scroll event made from `hidSystemState` afterwards starts
  from them: a key up with control and fn would make the device's next tap a control-click (a
  context menu) and its next scroll a control-scroll (a zoom where Accessibility's zoom uses
  control), as the Spotlight key's ⌘ once reached the text typed after it. The shortcut acts on the
  key down. A quarter of a second after each posted chord the table is read again (a read, no
  permission): a modifier of the chord still set that was not set before is counted,
  `in.gestureModifiersLeft`, and said once a run ("Gestures: after a gesture's shortcut this Mac's
  modifier keys still read control + fn (not before it); …"), which P2 watches for. Inferred, not
  observed: nothing was posted while this was built.

### 7.4 In the coordinator

- `case .gesture:` in `handle` (`StreamCoordinator.swift:572`): decode `TrackpadGesture`; at most 4
  a second per connection (the excess dropped, with one line a minute, as `RefusalSummary` does);
  then `resolve` with the table just read.
- **No `raiseIfInteracting`:** these views act on the whole Mac, and App Exposé on the frontmost
  app, as they do from a keyboard.
- **In order behind held input:** while `deliver` holds input for an activation, the chord waits
  behind it (the hold queue carries either), so a click just before a gesture lands before Mission
  Control opens.
- **One line per gesture**, for P2: "Gesture from ‹device›: swipe up → Mission Control (shortcut
  108: key 160, fn)", or "… → nothing: no shortcut for Apps is on in Keyboard Shortcuts".
- `input(_:)` on every `.input`, from any device; `forget()` on a window picked, an app launched, a
  window's button and the last device leaving (§7.2).
- **A host that does not advertise never posts a chord** (the synthetic CLI, the bare app with
  `--synthetic`): it logs the line with "(not posted: a test host)" and counts `in.gestureDry`. That
  is what lets H8 test the wire without touching the session.
- The window list gains `gestures: 1` (`listMessage`, `StreamCoordinator.swift:1574-1578`).

---

## 8. Settings on the device (device-local; nothing on the Mac)

A **device preference**, not a host setting: `UserDefaults` key `Sill.trackpadGestures`, default
**on** (precedent: `Sill.savedMacs`, `Sill.directWirelessMacs`), never on the wire and never sent to
the Mac. The surfaces read it at each decision.

- **Where.** The last group of the panel's scrolling middle, after the whole `if let state … else if
  olderMac … else` block (`HostSettingsPanel.swift:174-260`), so it shows while the Mac's settings
  load and for a Mac without settings too. It is headed like "Away from home" (`:314-320`), "This
  \(device)" (the panel's own `device`, `:403`), since every other row is the Mac's; last, because
  it is the least changed and the outer display's 259 pt shows the Mac's rows first.
  `-SillSettingsEnd 1` scrolls to it.
- **What.** A `Toggle` "Three-Finger Gestures"; when it is on and the Mac takes them, five read-only
  rows, a symbol and the words each: "Swipe Up — Mission Control", "Swipe Down — App Exposé",
  "Swipe Left or Right — Spaces", "Pinch — Apps", "Spread — Show Desktop" (the pinch opens Launchpad
  on macOS 14 and 15, from the same key).
- **Footnotes.** On, and the Mac takes them: "Three fingers on the trackpad or over the stream.
  While a window is streaming, a gesture shows the Desktop first, and the opposite gesture closes
  what one opened. \(mac) uses its own keyboard shortcuts for these; one that is off in its
  Keyboard settings does nothing." On an iPad, one more sentence: "Four-finger swipes and a Magic
  Keyboard trackpad’s gestures stay with iPadOS." A Mac that does not take them (`hostGestures`
  nil): "Update Sill on \(mac) to use these." Off: "Three-finger strokes do nothing while this is
  off." While VoiceOver runs (`UIAccessibility.isVoiceOverRunning`, followed on
  `voiceOverStatusDidChangeNotification`), which keeps three-finger swipes and taps for itself so
  that none reaches Sill (§2.2), the first sentence is "VoiceOver keeps three-finger gestures for
  itself, so the rows above do them on \(mac) instead."
- **The rows do the gestures, for assistive technologies.** Each mapping row is an accessibility
  action, whether or not VoiceOver runs (VoiceOver, Voice Control, Switch Control, none of which
  makes a three-finger stroke on the glass): a button that does its gesture through
  `client.sendGesture` (the switch, the Mac's `gestures`, the Desktop first while a window streams),
  and for the Spaces row two named actions, "Space on the Right" (a swipe left) and "Space on the
  Left". A touch on a row does nothing, as before.
- **No `changeSettings`, ever.** The panel's doc comment (`:5-18`: every control "sends through
  `client.changeSettings`") gains a line: this group is the device's own and sends nothing.
- **Accessibility and layout** follow the panel's groups (`Rows`, `Footnote`, `RowTitle`),
  `dynamicTypeSize(...xxLarge)`, wrapping, never truncating; each mapping row is one VoiceOver
  element ("Swipe up, Mission Control"), a button (the Spaces row: two actions).
- **Harness.** The mock window lists carry `gestures: 1` except `legacy`'s; `-Sill.trackpadGestures
  0` photographs it off (the argument domain overrides the default for one run); DEBUG
  `-SillVoiceOver 1` shows the VoiceOver footnote.

The four pbxproj entries for `TrackpadGestures.swift` (build file, file reference, the group's and
the Sources phase's lines) use **`A1000001000000000000A401` / `…F401`**, not the next pair after
`F01E` (§13 says why). `StrokeObserver` lives in `InputOverlay.swift` and needs no entry.

---

## 9. Tests

### 9.1 Pure checks (`Tests/checks/`, swiftc, with mutants)

- **`gestures`**: `iOSClient/TrackpadGestures.swift` with a `main.swift`; at least 90 cases, one
  `ok`/`FAIL` each, and 5,000 random strokes against a small model. Each direction at, just under
  and just over `swipeDistance`; the flick rule; `axisRatio` both ways; pinch and spread at
  `pinchRatio`; travel winning over spread; the fingers moving together at exactly `swipeShare`
  (a pinch led by the thumb, a grab, the Mac's thumb-and-three-finger pinch either way round, a
  fourth finger against the swipe at and under the share, and at and under `chordTravel`); silence
  and arming at exactly `chordWindow` and `chordTravel`; three fingers placed slowly (silent, never
  armed); a thumb resting before (armed by the three that landed last; not counted; its lift decides
  nothing); no silence with a button held; two fingers never; a late third finger never; a fifth
  finger; a still fourth finger not counted; a brief extra contact's lift deciding nothing; one
  decision per stroke; cancelled → nothing; a swipe taken back → nothing; `silent` lasting until
  the next stroke's first touch. Mutants (at least 14): each threshold's comparison flipped; the
  window, travel and button conditions each dropped; the one-shot dropped; left and right swapped;
  pinch and spread swapped; any lift deciding; silence ending at the last lift, or coming only with
  arming; the first three to land arming; the together test and the other fingers' dropped; cancel
  ignored; a fourth finger re-basing the centroid.
- **`gesture-chords`**: `Sources/SillHost/GestureChords.swift`; at least 70 cases and 5,000 random
  sequences against a model. Each gesture to its chord on the default table; a preferred shortcut
  off or unbound → the next; none → nothing, and never another action's chord; a rebound shortcut
  followed exactly (its keycode, its device-independent bits only); every reversal pair; the same
  gesture twice (nothing) and three times (its chord again); the Spaces keeping `open`; a click, a
  key and text clearing it and a move, a scroll and a button or key coming up not; `forget`
  clearing it; unknown names; the modifiers a chord must not leave behind. Mutants (at least 12).
- **`protocol` and `compatibility`** gain: kind 28 is `gesture` and 29 is `.unknown`;
  `TrackpadGesture`'s JSON both ways; `WindowList.gestures` optional both ways.
- Both new checks go in `Tests/checks/README.md` ("Adding a check") and in CI's mutants matrix
  (`.github/workflows/ci.yml`, as it is on main after the merge).

### 9.2 The touch rig (simulator)

The critique's scratch rig (§14), promoted to `Tests/touchrig/`, outside the app's target and never
linked into it. It compiles the real `TrackpadView.swift`, `InputOverlay.swift` and
`TrackpadGestures.swift` into a scratch app, synthesizes touches with private UIKit calls (KIF's
technique; on iOS 27 `setGestureView:` and `setIsTap:` are gone and are skipped), and logs what each
surface sends and every gesture it decides. It runs on a simulator of its own that its script
creates and deletes (about 2.5 GB while it exists; this Mac had 0.2 to 3.4 GB free on 2026-09-26):
never the shared iPad Pro 13", no `simctl io recordVideo`, no Simulator live panel, no XCUITest.
Limits: synthesized touches, not glass; the editing overlay (§2.2) is out of its reach.

### 9.3 Harness photos (simulator; screenshots only, no recording, no live panel)

`-SillSettings 1 -SillSettingsCase default -SillSettingsEnd 1` with the new group; `legacy` (the
update note); `-Sill.trackpadGestures 0`; at 1000×710, 710×1000, 500×710 and 710×500, and at
accessibility-extra-large (the rows wrap, never truncate); one iPhone size (no iPadOS sentence).
Send Noah the sheet.

### 9.4 Headless gates (H)

**No gate sends `.input` or kind 28 to any host on this Mac, except H8, which sends two gestures to
a synthetic host that cannot post them.** A synthetic host injects input into the real session
(§2.4).

| # | Check | Pass when |
|---|---|---|
| H1 | **Builds.** `swift build -c release`; iOS Debug and Release for the simulator; Debug for a device (unsigned) | Only the known warnings (CaptureProbe; the old `StreamClient` capture warning) |
| H2 | **CLI byte-for-byte.** `SillHost --synthetic` idle 35 s and with `sillclient.py PORT 5 desktop`, digits masked and sorted, against `origin/main`'s after the merge | Identical |
| H3 | **`gestures`** and its mutants (§9.1) | Every case; every mutant caught |
| H4 | **`gesture-chords`** and its mutants (§9.1), pure: nothing is posted | Every case; every mutant caught |
| H5 | **Grep hard rules** | No `IOHIDEventCreate`, `tapCreate`, `addGlobalMonitorForEvents` or a `CGEventType` of 29 or 30 in `Sources/` or `iOSClient/` (Tier 2 not built); both pans still `maximumNumberOfTouches = 2`; `flags(from:)` unchanged; `sillclient.py` sends no kind 8; each existing handler's only change is its first-line guard |
| H6 | **Compatibility** (swiftc) | 6678ca3's `StreamMessage.swift` maps 28 to `.unknown`; its `Switcher.swift` decodes a new window list; a window list from 6678ca3 decodes with `gestures` nil; the device's send decision with it nil sends nothing |
| H7 | **The touch rig** (§9.2), with 6678ca3's surfaces and this branch's | One- and two-finger strokes: the same events as 6678ca3's, one for one (times masked). Each three-finger stroke of §2.1: one gesture and no other event after the third finger; armed with a scroll open: one `.scrollGesture(.ended)` and no momentum; cancelled: nothing; four: one gesture with `fingers` 4; five: nothing; the switch off: nothing at all |
| H8 | **The wire, dry.** `sillclient.py PORT 8 desktop --gesture=swipeUp@3 --gesture=swipeDown@4` (a new option) against `SillHost --synthetic`, only under §10's idle guards (a dry path that failed would open and then close Mission Control) | Two lines: swipe up → Mission Control (shortcut 108), then swipe down → Mission Control again (the reversal), each "(not posted: a test host)"; `in.gestureDry` 2, `in.gesture` 0 |
| H9 | **The Mac's UI unchanged.** `-SillRenderPreviews` from the bundle against `origin/main`'s | Identical |

### 9.5 Noah's list (P), handed over at the end

The iPad mini on Noah's Mac (Sill.app and the iOS build from this branch), and, for P9, a Magic
Keyboard trackpad if he has one.

| # | Check |
|---|---|
| P1 | **Portrait, the Desktop streaming.** Three fingers on the trackpad: swipe up → Mission Control; down → App Exposé; left → the Space on the right; right → the Space on the left; pinch → Apps; spread → Show Desktop. Sill's log names the shortcut each time (§7.4). No pointer jump once the fingers are down, no click; a light haptic on an iPhone, none on the iPad. Pinch and spread led by the thumb (the fingers still, the thumb travelling far) are a pinch and a spread, not a swipe. Right after a swipe left, right or down, a tap selects (no context menu) and a two-finger scroll scrolls (no zoom) |
| P2 | **Which shortcut works** (§2.3). Mission Control, App Exposé, Apps and Show Desktop open through 108, 115, 173 and 36; the Space swipes switch Spaces and do not tile the front window (fn control arrows are also Tile Left and Right Half). If a gesture tiles, or does nothing while its log line names a shortcut, note which: the fix is one entry of §7.1's table. Sill's log has no "Gestures: after a gesture's shortcut this Mac's modifier keys still read …" line (§7.3; if it has, the key up did not put the table back: note which gesture) |
| P3 | **Landscape.** The same six over the stream, with the Desktop streaming and while a window streams (the device switches to the Desktop first, then the view opens). Two-finger scroll still scrolls; a third finger landing on a scroll already under way leaves it a scroll. Right after a swipe left, right or down, a tap selects (no context menu) and a two-finger scroll scrolls (no zoom) |
| P4 | **One and two fingers unchanged**, both layouts: pointer, tap, two-finger tap, press-and-hold drag, long-press right click, two-finger scroll with momentum, haptics. And §2.1 on glass: three fingers resting 0.6 s no longer drag or right-click, a three-finger pinch no longer clicks at the end, four fingers no longer move the pointer or scroll. Also with a thumb resting on the glass first (a swipe or a pinch of the other three: the gesture, no pointer jump, no scroll) and with the three fingers placed slowly, one by one (nothing at all: no click, no scroll, no gesture). A brief touch of a fourth finger or the palm during a swipe does not cancel it |
| P5 | **The reversal.** Up then down closes Mission Control; down then up closes App Exposé; spread then pinch brings the windows back; pinch then spread closes Apps. A click in Mission Control between two swipes makes the next swipe down App Exposé. A swipe down whose first finger slid a little first (it begins as a scroll) still closes Mission Control. Mission Control closed with the Mac's own Esc: the next swipe up does nothing, the one after opens it; after the iPad reconnects, a swipe up opens it at once |
| P6 | **The keyboard up.** Software keyboard shown, and again with a hardware keyboard: three-finger swipes and pinches do the Mac's thing, and iPadOS shows no undo, redo, copy or paste (the `.none` of §6.5) |
| P7 | **Virtual Display on**, a window staged: a gesture switches the device to the Desktop (the window goes home), then the view opens; App Exposé shows the front app's windows |
| P8 | **The switch.** Settings › This iPad › Three-Finger Gestures off: nothing happens and nothing clicks or drags; the mapping hides. On again: they return. Survives a relaunch |
| P9 | **The Magic Keyboard trackpad.** Its three-finger gestures are iPadOS's; its two-finger scroll does not scroll the Mac (as today, §2.2) |
| P10 | **Remote (Tailscale).** A gesture works through the remote door; note any lag |
| P11 | **Four fingers.** With iPadOS's four-finger gestures on, the iPad goes Home or switches apps and the Mac does nothing; with them off (Settings › Multitasking & Gestures), four fingers do what three do |
| P12 | **An older Mac.** This iPad against `origin/main`'s Sill.app: the group says to update Sill on the Mac; three fingers send nothing and click nothing |
| P13 | **VoiceOver.** With VoiceOver on, Settings › This iPad's footnote says VoiceOver keeps three-finger gestures and the rows do them instead; each row is a button ("Swipe Up, Mission Control, button") whose double tap does it on the Mac, and the Spaces row has two actions, Space on the Right and Space on the Left |

---

## 10. The Tier 2 bounded probe (run before building any of §5; guarded)

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
28's tracking fields may be built in a later PR. If it needs Input Monitoring or does nothing →
**Tier 2 is dropped**; Tier 1 is the whole feature, which already covers Noah's ask ("full macos
gestures on the touchpad").

This probe was **not run in this environment** (writing it here tripped a safety stop; and it moves
the real desktop, so it belongs in a deliberate, guarded run). Its result is therefore **open**, and
Tier 1 does not depend on it.

---

## 11. Hard rules (every step)

- **One- and two-finger strokes never change** (pointer, tap, right-click, drag, scroll with phases
  and momentum, haptics). Each existing handler gains only a first-line `guard !silent`, and
  `silent` is false for every stroke that never arms (H7).
- **Apple frameworks only.** No third-party code.
- **CLI stdout byte-identical** on the default synthetic path (nothing prints unless a kind 28
  arrives).
- **Wire fields optional; kind numbers never reused.** Kind 28 is new; `WindowList.gestures` is
  optional; 24 to 27 stay with their plans.
- **No `MainActor.assumeIsolated`** in core code.
- **Four pbxproj entries** for `TrackpadGestures.swift`, `A401`/`F401` (§8). Swift 5 language mode.
- **No new permission.** Tier 1 needs none. Tier 2 must not need Input Monitoring, or it is dropped
  (§10, §12 Q7).
- **No test sends `.input` or kind 28 to a host on this Mac** except H8's two gestures to a
  synthetic host, which cannot post them; the rig and the checks send nothing anywhere.
- **Tests never post a gesture or a key to the real Mac** except §10's guarded probe; never
  `simctl io recordVideo`, no XCUITest, no Simulator live panel while Noah streams; screenshots only;
  the rig on a simulator of its own.
- Never touch `/Applications/Sill.app`, `make-app.sh --install/--open`, `tccutil`, or Noah's iPad.

---

## 12. Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **When a gesture fires.** Default: **at lift**, from the net travel. The alternative fires at a
   threshold mid-stroke: sooner, but it cannot be taken back, and four fingers race iPadOS.
2. **While a window streams.** Default: **the Desktop first**, then the view. Alternatives: gestures
   only while the Desktop streams (as the Spotlight key), or act anyway (the device would not see
   the result).
3. **Swipe down with nothing open.** Default: **App Exposé**. The alternative is nothing, as on
   Noah's Mac, where App Exposé's gesture is off.
4. **The reversal.** Default: **the opposite gesture closes what Sill opened**. The alternative sends
   each gesture's own chord always (a swipe down in Mission Control then shows App Exposé).
5. **Pinch.** Default: **Apps**, through the Launchpad key's shortcut (173, on). The alternative is
   nothing.
6. **Space direction.** Default: **natural** (fingers left → the Space on the right).
7. **Tier 2.** Default: **Tier 1 only** now; Tier 2 only if §10's probe shows macOS 27 accepts
   synthesized gestures from Sill's background process **without Input Monitoring**. Noah decides if
   a third permission is ever worth it.
8. **The switch's default.** Default: **on** (it conflicts with nothing: three-finger strokes send
   nothing today but the stray clicks of §2.1).
9. **Four fingers.** Default: **as three** where the system lets them through. The alternative
   ignores them.
10. **Haptic.** Default: **a light tick** on the trackpad (iPhone only; silent on iPad). The
    alternative is none.
11. **A latched modifier.** Default: **ignored and kept latched**. The alternative spends the latch.
12. **The tunables.** Defaults: 0.15 s and 24 pt to arm; 40 pt, or 20 pt at 500 pt/s, for a swipe;
    25 % for a pinch. Tuned on glass (P1, P3).

---

## 13. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution line.

0. **This plan** and its critique (committed).
1. **Merge `origin/main`** (150f781: PRs #20 and #21) into the branch, not a rebase. Gates: H1, H2's
   baseline.
2. **"Protocol: kind 28, the trackpad gesture; the window list says a Mac takes them."**
   `Gesture.swift` (`TrackpadGesture`), `case gesture = 28` with its comment, `WindowList.gestures`,
   the `protocol` and `compatibility` cases. Gates: H1, H2, H6.
3. **"Host: a gesture becomes the Mac's own shortcut."** `GestureChords.swift` (pure) and the
   `gesture-chords` check; `SymbolicHotKeys`; `InputInjector.chord`; the coordinator (kind 28, the
   rate cap, the order behind held input, the reversal, no posting on a host that does not
   advertise, the log lines, `gestures: 1`); `sillclient.py --gesture=NAME@T`. Gates: H1, H2, H4,
   H5, H8, H9.
4. **"iOS: recognize three-finger strokes (pure)."** `TrackpadGestures.swift` and its four pbxproj
   entries; the `gestures` check and its CI matrix line. Gates: H1 (iOS), H3.
5. **"iOS: three-finger gestures drive the Mac; a device switch to turn them off."** `StrokeObserver`
   and the guards on both surfaces; `editingInteractionConfiguration`; `StreamClient.hostGestures`
   and `sendGesture` (the Desktop first); the Settings group; the harness cases; the touch rig in
   `Tests/touchrig/`. Gates: H1, H5, H7, the photos (§9.3).
6. **"docs: three-finger trackpad gestures."** This plan's results; CLAUDE.md (Current step; Layout:
   the new files; Build and run: `--gesture`, the switch, the rig; Untested, for Noah: P1–P12);
   `docs/DEVELOPMENT.md`; `Tests/checks/README.md`.
7. **Review and hand-over.** Three lenses: the stroke gate against one- and two-finger strokes; the
   wire, the resolver and compatibility; the Settings group and its copy. A "Review fixes" commit if
   needed, then H1–H9 and the photos again. Hand P1–P12 (and the §10 probe decision) to Noah.
   **Stop there.** Tier 2 is a separate, later PR, only if §10 passes.

**IDs.** `A401`/`F401` rather than `A01F`/`F01F`: home-pairing's `StreamClient+Home.swift` holds
`A01E`/`F01E`, the pair main's `GoodbyePolicy.swift` also took, so its merge will move to the next
free pair; remote-pacing's `MessageReader.swift` holds `A020`/`F020` and pointer-visibility's
`PointerPresence.swift` `A301`/`F301`.

**Rebases.** Other open branches touch the same files: pointer-visibility (`InputInjector.swift`,
`StreamCoordinator.swift`, `StreamMessage.swift` with kind 26 after 23, `SessionLink.swift`, and by
its plan the trackpad's and overlay's pointer sprite); home-pairing (`StreamCoordinator.swift`,
`Switcher.swift`'s window list, `HostSettingsPanel.swift`, `StreamClient.swift`); remote-pacing
(`StreamServer.swift`, `StreamClient.swift`). Whichever lands first, re-check these; kind 28 stays
this branch's.

---

## 14. What the critique checked (2026-09-26)

- **The code at 8b0d418**, every file this plan names, and each line number above (the old plan's
  were off in places: `isMultipleTouchEnabled` at `TrackpadView.swift:164`, not 166; the delegate at
  `:207-208`, not `:145-146`; `handlePan` at `:274-328`, not `:246-303`; the overlay's `handlePan`
  at `:141-173`; its pointer path at `:223-269`; `press()` at `PortraitStreamScreen.swift:453-457`;
  the Spotlight cap at `:399-406`; `virtualKeys` at `InputInjector.swift:366-416`).
- **The rig**, in `scratchpad/gestures/critique/probe/` of this session: `TouchSynth.m` (the
  synthesizer), `main.swift` (the scenarios and the tracing), `run.sh` (build, install on the rig's
  own simulator, run one pass), `compact.py` (the log). Passes: `baseline` (today's surfaces),
  `plan` (the old plan's three-finger long press added), `editing` (the overlay first responder,
  with the editing configuration default and then `.none`), `route` (UIKit's own HID entry point:
  nothing delivered). Logs beside it: `baseline.txt`, `plan.txt`, `editing.txt`, `route.txt` and
  their `.compact.txt`. The simulator ("gestures-critique probe", an iPad Pro 11-inch (M5) on iOS
  27.0) was deleted afterwards.
- **This Mac, read-only:** the hotkey table (`scratchpad/gestures/critique/mac/hotkeys.swift`,
  getters through `dlsym`, nothing set or posted); `defaults read com.apple.symbolichotkeys`,
  `com.apple.dock` and `com.apple.AppleMultitouchTrackpad`; the Keyboard settings extension's
  `DefaultShortcutsTable.loctable` and `DefaultSpacesShortcuts.xml`; `/System/Applications` and
  `Apps.app`'s Info.plist; the UIKit and IOKit headers of the iOS 27 SDK.
- **The worktrees:** wire kinds 24 to 28 (menu bar 24, 25, 27; pointer 26; 28 free), the project
  file's IDs, and which files the open branches change.
- **Not checked** (glass or posting needed): whether iPadOS's editing overlay stays quiet under
  `.none` (P6); which of Spaces and tiling a synthesized control-fn arrow triggers, and whether keys
  160 and 131 open their views when posted (P2); what a second key 131 does to Apps (P5); §2.1's
  table on the iPad (P4).

---

## 15. Results (2026-09-27)

Built in §13's order on `trackpad-gestures`: the merge with main (6678ca3) and this plan's line
numbers (a66839c), kind 28 (649ff7f), SILL_TEST_LOOPBACK taken from PR #31 so the test hosts listen
on 127.0.0.1 alone (55f87cc), the Mac's side (902e5e4), main merged again once PR #31 landed
(5e6ddaa), the pure recognizer (487ec26), the surfaces and the device's switch (5cd067c), then these
documents. Every §12 default was taken. Nothing was pushed.

### What differs from the plan

1. **Project IDs** `A701`/`F701`: `A401`/`F401` are held by the local branch `first-run-walkthrough`.
   No branch or worktree holds `A701`/`F701`.
2. **GestureChords** also holds the log line (`line`, `describe`) and the TEST ONLY table
   (`testTable`, read from `SILL_TEST_HOTKEYS` by a host that does not advertise), so both are checked.
   Its outcomes carry no "closes" flag: the line says "closes" when a view's shortcut answers another
   view's gesture.
3. **The coordinator waits for a switch in flight**, at most 2 s, before it posts: the Desktop pick
   the device sends just before a gesture made over a window then starts first, and a window on the
   virtual display is home before Mission Control opens. Gestures post in arrival order.
4. **A held chord survives a select**: `select` drops input held for the old source, but a chord acts
   on the whole Mac, so it is posted there instead of dropped.
5. **`InputInjector.chord` posts through PR #31's `post()`**, so a dry run posts no chord either (the
   coordinator already calls it only on a host that advertises).
6. **`sillclient.py --gesture` and `--raw28`** go only to a `--synthetic` host on this Mac, as PR #31's
   input flags do (the listener's own arguments, by lsof and ps). H5's "sillclient.py sends no kind
   8" no longer holds since PR #31, whose `--input` flags send it to such hosts only.
7. **`TrackpadGestures.cancelled(_ id:)`** takes the touch, and a cancel before arming keeps that
   stroke from arming. **`TrackpadGestures.sending`** is the send rule (the switch, a session, the
   Mac's `gestures` at least 1, the Desktop first over a window), pure and checked;
   `StreamClient.sendGesture` runs it.
8. **`StrokeObserver`** is its own delegate (so the overlay, which has none, needs no change), and its
   `reset` counts a touch it never saw end as cancelled. It sees every touch type, but only direct
   touches are fingers: a Pencil's or the iPad's own pointer's touch only ends a finished stroke's
   silence (`TrackpadGestures.otherTouch`), since the portrait trackpad's recognizers take those too
   and would otherwise ignore a Pencil used right after a gesture (the review's fix).
9. **DEBUG**: `-SillInputScript`'s `gesture NAME[,FINGERS]` step (PR #31's script, with its refusal of
   any host but a test host on this Mac) instead of a new argument; `-SillSettingsScroll gestures`
   opens the panel at the group, whose rows a long footnote pushes out of `-SillSettingsEnd`'s view.
10. **The footnote** is a little shorter than §8's: "Three fingers on the trackpad or over the
    stream. While a window streams, a gesture shows the Desktop first, and the opposite gesture
    closes what one opened. ‹Mac› does these with its own keyboard shortcuts: one turned off in its
    Keyboard settings does nothing." (and on an iPad the iPadOS sentence).
11. **The public README** names the gestures, and `site/privacy.html` lists them among what a device
    sends; the published site needs a republish after the merge.

### Verified (without a device)

- H1: `swift build -c release`, only the CaptureProbe warning; iOS Debug and Release for the
  simulator and Debug for a device (unsigned), only the old `StreamClient` capture warning.
- H2: the CLI (`SILL_TEST_LOOPBACK=1 SillHost --synthetic`), idle 35 s (8 lines) and with a client
  streaming the Desktop for 5 s (17 lines up to its leaving), against main's at 2b38179, digits masked
  and sorted: identical. (A stats line after the client leaves follows the timer's phase in both.)
- H3: `gestures`, 108 checks (each swipe at, under and over its distances; the flick; the axis at
  exactly 1.3 both ways; pinch and spread exactly at 0.75 and 1.25 on a 3-4-5 triangle; arming at
  exactly 0.15 s and 24 pt; a button; two fingers; a late third; four; five; cancels; one decision; a
  swipe taken back; silence to the next stroke, which a Pencil's touch also starts; the send rule;
  5,000 random strokes against a model), 31 of 31 mutants.
- H4: `gesture-chords`, 106 checks (each gesture on macOS 27's table, fallbacks, rebound shortcuts and
  their bits, every reversal pair, the same gesture twice, the Spaces, other input, unknown names, the
  line, the TEST ONLY table, 5,000 random sequences against a model), 21 of 21 mutants. `protocol`
  and `compatibility` (92 checks, 19 of 19 mutants; `protocol` 20 of 20) know kind 28 and `gestures`;
  `pointer-control`'s kind table too (153 checks, 33 of 33 mutants). `Tests/checks/run-all.sh`: all 22.
- H5: no `IOHIDEventCreate`, event tap, global monitor, event type 29 or 30, or hotkey setter in
  `Sources/` or `iOSClient/`; both pans still at two touches; `flags(from:)` unchanged; the only
  change inside an existing finger handler is the first-line guard (eight of them).
- H6: 6678ca3's StreamProtocol maps 28 to `.unknown` and reads exactly its payload's length, and
  decodes a window list with `gestures`; this build decodes 6678ca3's list with `gestures` nil; the
  device's send rule sends nothing to it.
- H7: the touch rig on the surfaces before (487ec26) and after, and after with the switch off: 84 of
  84, on an iPad Pro 11-inch (M5) simulator and again, after the review's fix, on an iPhone 17 Pro
  Max's. One- and two-finger strokes, and a third finger that joins a scroll after 133 ms, send what
  they sent before; every other three-, four- and five-finger stroke sends one gesture or nothing after
  its third finger (before: a pinch clicked, a rest dragged on the trackpad and right-clicked on the
  stream, four fingers moved the pointer or scrolled, five scrolled); with the switch off the same,
  the gesture refused.
- H8: `sillclient.py --gesture` against loopback synthetic hosts: swipe up then down named 108 and
  closed it, every gesture and the reversals for Apps and Show Desktop, four fingers named, an unknown
  name cleaned to letters and digits, bad JSON and a nameless gesture ignored, the fifth gesture in a
  second dropped with its line, `SILL_TEST_HOTKEYS`'s fallbacks (32, 110, 115) and "no shortcut for
  Show Apps", a value that does not parse ignored with its line; `in.gestureDry` counted, nothing
  posted.
- H9: the bare app's 100 previews against main's: identical but the General pane's "Running from"
  path, which names each build's folder.
- Live, in a private simulator: the app in the layout harness with its real client, dialled to a
  loopback synthetic host on the software encoder, sent eleven gestures through `sendGesture`
  (`-SillInputScript`): all named and not posted, the reversal, four fingers, the fifth in a second
  dropped; with `-Sill.trackpadGestures 0` none sent; against main's host (no `gestures`) none sent.
  The live panel showed the group with the host's mappings.
- §9.3's photos: the group in its three states (on, an older Mac, off) at 1000×710, 710×1000, 500×710,
  710×500, an iPad mini's 1133×744 and 744×1133, and an iPhone's 402×812 and 812×402, at Large and
  accessibility-extra-large (the rows stack, nothing truncates): 48 screenshots, kept out of the
  repository.

### Review fixes (2026-09-27)

The review (§13's step 7: the stroke gate against one- and two-finger strokes; the wire, the resolver
and compatibility; the Settings group) found seven things at 027105e. Each was checked here before
it was fixed: the recognizer's reproduced in a probe of the real file and the surfaces' in the touch
rig on the review's own strokes (027105e's surfaces fail 18 of its 74 checks, every one of them on
those strokes), the reversal's on a loopback synthetic host that posts nothing, the VoiceOver one
read in the code (nothing there knows VoiceOver), and the chord's inferred, since nothing may be
posted. Nothing was posted to the Mac.

1. **A stroke of three fingers that missed the window was not gated.** Silence came only with
   arming, and arming counted from the stroke's first touch, so a thumb resting on the glass, or
   three fingers placed 100 ms apart, gave back the stray click, pointer jump and coasting scroll of
   §2.1 (the rig at 027105e: the slow pinch clicked on both surfaces; beside a resting thumb, a swipe
   threw the pointer ten moves on the trackpad and scrolled with a coast on the stream). Now a stroke
   is silent from three fingers down before any has moved (§6.1), whatever the timing, and arms on
   the three that landed last, so a resting thumb neither blocks a gesture nor becomes one of its
   fingers. Three fingers that take longer than 0.15 s to come down are silent and decide nothing
   (P4 on glass).
2. **A pinch or a spread led by the thumb read as a swipe.** With the thumb opposite two fingers the
   centroid moves with the thumb: 120 pt of the thumb's travel is 40 pt of the centroid's, a swipe
   (a probe: a thumb-led pinch of 120 and 130 pt, a spread of 120 and 150, a grab of 120 pt each way,
   and the Mac's own pinch with the thumb landing fourth were swipes). Now a swipe needs the fingers
   to move together (`swipeShare`, §6.1), and a fourth finger that moved takes part: against the
   swipe it breaks it, and it joins the pinch or spread measured after.
3. **The first lift of any contact decided.** A grazing fourth contact that lifted 21 or 33 pt into a
   slow swipe decided it as nothing, and `fingers` was the most ever down. Now only the lift of one
   of the three decides; another finger's lift only leaves the stroke, and `fingers` counts the three
   and the others that moved.
4. **VoiceOver users were told to use three fingers**, which VoiceOver keeps (§2.2), and nothing
   else offered the six actions. Now, with VoiceOver on, the footnote says the rows do them, and each
   row is an accessibility action, for Voice Control and Switch Control too (§8).
5. **A chord could leave its modifiers set for the next click** (inferred, not observed: nothing may
   be posted while this is built). The key up carried the chord's control and fn into the HID state
   table that the next click and scroll start from; the Spotlight key's ⌘ once reached text that way.
   Now the key up carries the table's flags from before the chord, and a quarter of a second after,
   a read of the table says so in the log if the chord's modifiers are still set (§7.3, P2).
6. **A scroll forgot what Sill opened**, so a stroke that began as a scroll before it became the
   reverse gesture opened the other view (a loopback host at 027105e: a swipe up, a scroll's bracket,
   then a swipe down gave App Exposé). Now only a click, a key or text forgets (§7.2); the same host
   run gives "closes Mission Control".
7. **What Sill opened never expired**: not when the last device left (a second session's swipe up
   said "Mission Control is already open" at 027105e), not on a window picked or an app launched from
   a device, and the same gesture repeated never recovered once the view was closed on the Mac itself.
   Now those forget (§7.2), and the gesture that opened a view, made twice more straight after, opens
   it again.

Also: `Output.armed` is `.silenced` (it now comes when the stroke goes silent, arming or not), the
touch rig runs the review's strokes (placed slowly, beside a resting thumb, thumb-led, the Mac's pinch,
a brief contact) and one- and two-finger strokes made right after a gesture, which `compare.py` holds
to the same strokes made fresh.

Verified after the fixes, without a device:
- `gestures` 156 checks and 45 of 45 mutants (14 new: silence only with arming, the first three to
  land arming, the together test, the other fingers' test and their edges, any lift deciding, the
  fingers counted); `gesture-chords` 141 and 33 of 33 (12 new: what input forgets, the repeat, the
  modifiers a chord must not leave); `Tests/checks/run-all.sh`, all 22 (149 s).
- The touch rig on a private iPad Pro 11-inch (M5) simulator and on an iPhone 17 Pro Max's, each
  deleted after: 144 of 144 on each against the surfaces before the gestures (487ec26), with the
  switch on and off (on the phone, the Mac's-pinch stroke first put its thumb below the surface: 150
  pt under the fingers is outside its half of the window; it is 110 now, on both).
- On loopback synthetic hosts that post nothing, this build against 027105e's: a swipe up, a scroll's
  bracket and a swipe down closes Mission Control (027105e: App Exposé); a second session's swipe up
  opens it (027105e: "already open"); the third swipe up in a row opens it again; a tap, Esc and a
  pointer move behave alike on both (a click and a key forget, a move does not).
- H1: `swift build -c release`, and iOS Debug and Release for the simulator and Debug for a device
  (unsigned), only the old `StreamClient` capture warning. H2: the CLI idle 35 s (7 lines) and with a
  client streaming the Desktop for 5 s (17 lines), against main's at 2b38179, both on the software
  encoder, masked and sorted: identical. H5: no private gesture API, event tap or hotkey setter; both
  pans at two touches; `flags(from:)` unchanged; eight first-line guards. H9: the app's 100 previews
  against main's: identical but the General pane's "Running from" path.
- Photos (§9.3; screenshots on a private simulator, deleted after): the group with its VoiceOver
  footnote (`-SillVoiceOver 1`) and without, at 1000×710, 710×1000, 500×710 and 710×500, at Large and
  accessibility-extra-large: the footnote wraps, the rows stack at the larger text, and on the short
  screens the panel's middle scrolls as it did.

### Not verified

Everything on glass and on the real Mac, §9.5's P1–P13, above all P2 (whether keys 160 and 131 open
their views when posted, whether ⌃→ switches Spaces or tiles the front window, and whether the key
up's flags leave no modifier set: no "modifier keys still read" line) and P6 (the editing overlay
under `.none`). §10's probe, before any Tier 2.

### Merged with main after PRs #34, #35 and #36 (2026-09-27)

Noah tried PR #38 on his devices (2026-09-27): "The gestures work amazing. Please merge that code."
Main had moved on meanwhile, to 59c4ec8 with PR #35 (the first-run tour) and PR #36 (the Mac's
menus: kinds 24, 25 and 27), and during this merge to 643af6b with PR #34 (remote pacing); PRs #30
and #31 were already here. The merge takes main at 643af6b in one merge commit, never a rebase:
59c4ec8 stopped in eleven files, and #34 then in four more: three documents and CI's matrix.
Where the features meet:

1. **The wire.** `StreamMessageKind` has the menus' 24, 25 and 27, the pointer's 26 and the
   gesture's 28; the gesture's comment no longer calls 24, 25 and 27 held. `SillProtocol` stays 1
   (both are additive), Compatibility.swift's doc names 28 beside the menus' kinds, and CLAUDE.md's
   compatibility floor keeps kinds 0–28 and Gesture's JSON.
2. **The coordinator** dispatches both: kind 8 feeds `GestureChords.input`, is delivered, then goes
   to the menus' `desktopInputMayActivate`; kind 28 keeps its four a second and its queue; kinds 27
   and 25 go to `MenuMirror`, with its own rates. Both init blocks (the dry run and the TEST ONLY
   table; the mirror and its TEST ONLY hook) and both cleanups when a device leaves are kept.
   **New:** a menu item chosen from a device (kind 25) forgets the view a gesture opened
   (`gestureChords.forget()` before `menus.press`), as a click does: the item acts as a click on it
   would and may bring a window forward (§7.2's rule, for a way in that did not exist when it was
   written). Not changed: a gesture does not ask the menus to look at the Desktop's frontmost app
   again, as a click or a key does (`desktopInputMayActivate` reads kind 8 only); under Sill.app's
   AppKit loop the menus follow an activation at once (NSWorkspace), so a Space switched by a
   gesture shows its app's menus straight away there, and on the CLI at the catalog's next poll
   (2 s).
3. **The checks.** `protocol` reads 24, 25 and 27 as the menus', 26 as the pointer's, 28 as the
   gesture's and 29 as unknown (189 checks); `menus`' "28 unknown" is now "28 the trackpad gesture;
   29 unknown"; `pointer-control`'s kind table lists 24 to 28 (156 checks); `compatibility`'s "27
   and 29 are not this build's" is now "27 is the menus' fetch, 29 not this build's". Four mutants
   renumbered a kind onto one that is now taken, which no longer compiles: `menus`' "the fetch at
   28", `pointer-control`'s "kind 26 numbered 28" and "… 29", and `compatibility`'s "kind 28 as 27";
   they use free numbers now (29; 29 and 30; 29). CI's mutants matrix lists all 25 checks that have
   mutants (#34's `message-reader` too), and the checks' README has the new counts.
4. **The device.** The Settings panel ends with This iPad's gestures and then Take the Tour, both
   the device's own; the tour's row no longer adds 10 pt above itself while the Mac's settings load,
   since it always follows the gestures' footnote now. The portrait trackpad keeps `sendGesture` and
   the tour's `.tourTarget(.trackpad)`. The Menus button, the phone's portrait layout and the tour's
   hooks are main's; the stream's overlay and the trackpad are this branch's.
5. **sillclient.py** takes both sides' flags: `--menus`, `--fetch`, `--press`, `--raw25`, `--raw27`
   and `--expect-menus`; `--gesture` and `--raw28`.
6. **The project file**: A701/F701 (TrackpadGestures) beside main's A040–A044/F040–F044 (the menus),
   A401/A402/F401/F402 (the tour) and A020/F020 (#34's MessageReader); every iOS source once in the
   Sources phase, no ID twice.
7. **Remote pacing** (#34: the host's send side for the remote door, the device's `MessageReader`)
   touches nothing of the gestures: its StreamServer and StreamClient changes merged by themselves.

Verified on the merge (with 59c4ec8, then again with 643af6b where #34's files reach it), without a
device and with nothing posted to the Mac:
- `swift build -c release` from clean (a scratch build path): only the CaptureProbe warning. iOS
  Debug and Release for the simulator (arm64) and Debug for a generic device, unsigned: only the old
  `StreamClient` capture warning.
- `Tests/checks/run-all.sh`: all 26 (214 s). The mutants of the 15 checks that compile a file the
  merge changed (StreamProtocol, GestureChords.swift, or the check itself), every one caught:
  compatibility 19 of 19, protocol 20 of 20, menus 43 of 43, menu-state 29 of 29, pointer-control 33
  of 33, pointer-watch 40 of 40, device-gate 14 of 14, goodbye 16 of 16, update-policy 18 of 18,
  addresses 15 of 15, pairing-address 35 of 35, remote-rules 35 of 35, fence 32 of 32,
  gesture-chords 33 of 33 and message-reader 17 of 17 (#34 changed none of the files the first
  fourteen compile).
- A loopback synthetic host (`SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SillHost
  --synthetic`, the merge's build, both times), sillclient with nothing picked: the menus
  subscription answered (no menus: that host has no fixture); a swipe up (Mission Control), a swipe
  down ("closes Mission Control"), a swipe up, a kind 25 (refused, nothing read or pressed), a swipe
  down: App Exposé; a four-finger pinch (Apps), an unknown name (nothing); every gesture "(not
  posted: a test host)".
- The app in a private simulator (deleted after), its real client dialled to that host, both
  times: its hello, the catalog, its menus subscription ("menus: none"), the test pattern on the
  software encoder (read by #34's MessageReader the second time), and four gestures from
  `-SillInputScript` through `sendGesture`, each named by the host, none posted.
- Photos (screenshots on that simulator, deleted after): the panel's end at 1000×710 (the gestures'
  rows, then Take the Tour), an older Mac's panel (This iPad, then Take the Tour, loading and after),
  the phone's panel end, and the tour's laptop step at 710×1000 lighting the key row and the
  trackpad.

Not run at the merge: the touch rig (its files, TrackpadView, InputOverlay, PointerPresence,
TrackpadGestures, Input and the portrait screen's keys, are the branch's byte for byte), and the
menus' gates against their fixture app (MenuMirror, the reader and the device's menu files are
main's byte for byte; kinds 25 and 27 reached the mirror through the synthetic host above).
