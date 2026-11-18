**Three-finger trackpad gestures (2026-09-27, branch `trackpad-gestures` from
main at 8b0d418, with main merged in at 5c6a850 (6678ca3), at 2b38179, PR #31
the Mac's pointer among it (5e6ddaa), and at 643af6b, PRs #35 the tour, #36
the Mac's menus and #34 remote pacing, never rebased, PR #38; the plan, its
§12 defaults, the results, the review's fixes and the last merge are in
`docs/trackpad-gestures-plan.md`, §15).** Noah: "I also want to be able to use
full macos gestures on the touchpad, so far only 1 or 2 finger gestures are
working" (2026-09-23), and "Work on 5-12 as well please" (2026-09-26). Built
and reviewed overnight while he slept, every default of the plan's §12 taken.
Tier 2 (tracking gestures through private IOHID events) is not built and
§10's probe was not run: nothing was posted to the Mac.
- Wire: kind 28 `gesture`, device → host, JSON `TrackpadGesture`
  (`Gesture.swift`): a name (`swipeUp`, `swipeDown`, `swipeLeft`, `swipeRight`,
  `pinch`, `spread`) and `fingers` (3 or 4). `WindowList.gestures` 1 says a
  host takes them; nil from every host before, which is sent none.
- Mac: `GestureChords` (pure) turns a name into the Mac's own shortcut for
  its action, read from its Keyboard Shortcuts at that moment
  (`SymbolicHotKeys`, SkyLight's two getters, read-only): the first of the
  action's that is on and bound, with its stored modifiers' device-independent
  bits (fn included). Mission Control 108 (the Mission Control key, 160) then
  32 (⌃↑); App Exposé 115 then 33; the Spaces 81 and 79 (⌃→, ⌃←); Apps 173
  (the Launchpad key, 131) then 160 (Show Apps); Show Desktop 36 (F11) then
  110. None on: nothing, never another action's. It remembers the view its
  last gesture opened: the opposite gesture closes it with the same shortcut,
  the same gesture again does nothing and, made once more straight after,
  opens it again (it was closed on the Mac itself), the Spaces leave it open.
  A device's click, key or text forgets it (`input`; a move, a scroll or a
  button or key coming up does not), and so do a window picked, an app
  launched, a window's button and the last device leaving (`forget`). The
  coordinator takes four a second per connection (the rest one line a
  minute), waits for a switch in flight (at most 2 s: a gesture over a window
  comes right after the device's Desktop pick), queues the chord behind input
  held for an activation, raises nothing, and logs one line: "Gesture from
  iPad (iPad14,1): swipe up → Mission Control (shortcut 108: key 160, fn)".
  `InputInjector.chord` posts the key down with the shortcut's flags and the
  key up with the flags the HID state table held before, so no control or fn
  is left for the next click or scroll to start from; a quarter of a second
  later a read of the table counts `in.gestureModifiersLeft` and says once
  "Gestures: after a gesture's shortcut this Mac's modifier keys still read …"
  if they are. A host that does not advertise posts none: "(not posted: a
  test host)" and `in.gestureDry`; TEST ONLY `SILL_TEST_HOTKEYS` gives it a
  table of its own.
- Device: `TrackpadGestures` (pure). A stroke goes silent once three fingers
  are down before any finger moved 24 pt, with no button held, however slowly
  they came and whatever rests on the glass, until the next stroke's first
  touch; it arms when the three that landed last came down within 0.15 s of
  each other (so a resting thumb is not one of them). The first lift of one
  of the three decides: a swipe at 40 pt, or 20 pt at 500 pt/s over the last
  50 ms, with one axis 1.3 times the other and the fingers moving together
  (each of the three half the centroid's travel or more, no other finger that
  moved half of it the other way: a pinch led by the thumb is no swipe); else
  a pinch or spread at 25 %, of the three and any other finger that moved;
  else nothing. Another finger's lift only leaves the stroke; `fingers`
  counts the three and the others that moved (4 at most); a fifth finger, or
  a cancel (iPadOS taking four fingers), decides nothing. `StrokeObserver`
  (InputOverlay.swift) feeds it every direct touch on both surfaces, and each
  existing finger handler's only change is a first line, `guard
  !strokes.silent`; a scroll the stroke had begun is closed as it goes silent,
  with no coast. `StreamClient.sendGesture` sends it (the switch on, the Mac's
  `gestures` 1; the Desktop first while a window streams; a light tick on an
  iPhone's trackpad). The stream's overlay turns off iPadOS's three-finger
  editing gestures. Settings' This iPad (or iPhone) group, after the Mac's and
  before Take the Tour since the merge: Three-Finger Gestures
  (`Sill.trackpadGestures`, on by default, never sent), the five
  mappings while the Mac takes them, and a footnote; with VoiceOver on (which
  keeps three fingers) the footnote says the rows do the gestures, and each row
  is an accessibility action doing its gesture (the Spaces row one each way).
- Verified (§15): gestures 156 checks and 45 of 45 mutants; gesture-chords 141
  and 33 of 33; compatibility 92 and 19 of 19; `Tests/checks/run-all.sh`, all
  22; swift build -c release and the three iOS builds with only the known
  warnings; the CLI idle and with a Desktop client against main's, masked and
  sorted: identical; the app's 100 previews against main's: identical but the
  General pane's "Running from" path; the merge commit's StreamProtocol reads
  kind 28 as unknown and the new list; the touch rig on an iPad's and an
  iPhone's simulator (one- and two-finger strokes unchanged, also right after
  a gesture; every stroke of three to five fingers, placed slowly, beside a
  resting thumb, led by the thumb or with a brief extra contact, one gesture
  or nothing; the review's HEAD fails 18 of those checks); dry runs on
  loopback synthetic hosts (every gesture, the reversal, a scroll before the
  reverse gesture, a second session, the third try, fallbacks, bad payloads,
  the rate cap); the app in a private simulator against such a host; photos
  of the group at the Duo's, an iPad mini's and an iPhone's sizes, at Large
  and accessibility-extra-large, and of its VoiceOver footnote.
- Merged with main at 643af6b (2026-09-27, one merge commit; the plan's §15,
  "Merged with main after PRs #34, #35 and #36"). Where the features meet:
  kinds 24, 25 and 27 (the menus), 26 (the pointer) and 28 (the gesture) side
  by side, and the compatibility floor below keeps 0–28; the coordinator
  dispatches both (kind 8 feeds `GestureChords.input`, then the menus'
  `desktopInputMayActivate`; kind 28 its four a second; 25 and 27 the mirror
  and its rates), and a menu item chosen from a device (kind 25) now forgets
  the view a gesture opened, as a click does; the Settings panel ends with This
  iPad's gestures, then Take the Tour (whose row no longer pads itself while
  the Mac's settings load); the portrait trackpad keeps `sendGesture` and the
  tour's target; sillclient.py both sides' flags; the checks that read 28 as
  unknown (`protocol`, `menus`, `pointer-control`) or 27 as free
  (`compatibility`) now read the gesture and the fetch, and four mutants that
  renumbered a kind onto one now taken (so they no longer compiled) use free
  numbers; CI's mutants matrix lists all 25. Remote pacing (#34: the host's
  send side, the device's MessageReader, A020/F020) met the gestures only in
  the documents, CI's matrix and the checks' README. Verified: `swift build -c
  release` from clean, only the CaptureProbe warning; iOS Debug and Release
  for the simulator and Debug for a generic device, unsigned, only the old
  `StreamClient` capture warning; `Tests/checks/run-all.sh`, all 26; the
  mutants of the 15 checks that compile a file the merge changed, every one
  caught; on a loopback synthetic host on the software encoder, nothing
  posted: sillclient's menus subscription and choice beside the gestures (a
  swipe up, a kind 25, a swipe down gives App Exposé, not "closes Mission
  Control"), and the app in a private simulator (deleted after) sending four
  gestures through `sendGesture` beside its menus subscription; photos of the
  panel's end at 1000×710, an older Mac's, the phone's and the tour's laptop
  step lighting the keys and the trackpad.
- Noah tried PR #38 on his devices (2026-09-27): "The gestures work amazing.
  Please merge that code." The P1–P13 list below was not reported item by item.
- **Left:** the republish of `site/privacy.html` (it names gestures now) after
  the merge; the §10 probe before any Tier 2.
- **Untested, for Noah (the plan's P1–P13, beyond "the gestures work"):** new
  with the merge, a swipe up, then an item chosen from the Menus button, then
  a swipe down: App Exposé (with no choice in between, the swipe down closes
  Mission Control). On the iPad and iPhone with this Sill.app: each gesture
  in portrait and landscape, with the Desktop and while a window streams (the
  Desktop first); which shortcut works (P2: that key 160 opens Mission
  Control and 131 Apps when posted, that ⌃→ switches Spaces
  rather than tiling the front window, and no "modifier keys still read"
  line: right after a swipe left, right or down a tap selects with no
  context menu and a two-finger scroll scrolls); no stray click, drag or
  pointer jump with three fingers, placed slowly or beside a resting thumb,
  and one- and two-finger strokes as before; a pinch led by the thumb is a
  pinch; the reversal pairs, after a scroll too, and Mission Control closed
  with the Mac's Esc coming back at the second swipe up; with the keyboard
  up, no iPadOS undo or paste; the virtual display; the switch and a
  relaunch; the Magic Keyboard trackpad (unchanged); remote; four fingers with
  iPadOS's gestures on and off; this iPad against main's Sill.app (the update
  note, nothing sent); VoiceOver (the footnote, the rows as actions).
