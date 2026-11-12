# Full screen: Sill's interface hidden, the picture with the whole screen

Branch `full-screen` (from main at a4bad80, main at 0d22bbf merged in); issues #279 (swipe the UI away),
#92 (hide the top bar) and #280 (use the freed room). Device only: no wire change, nothing on the Mac,
nothing stored but a count of how often the hint has shown.

## What Noah asked for, and what was decided

Noah, 2026-11-12: "a full screen mode that hides the UI to get the maximum sized picture … Swipe off the
left side of the device to hide the UI (finger starts somewhere on the display, swipes left off the
display), and swipe in from the left side of the device to show the UI (finger starts on bezel, moves
towards center of device). The reason I went with this idea is that no system functions are mapped to
swiping from the left edge … We need to nail the touch detection … I don't want a persistent
button/UI element … if the device is shaken in UI hidden mode it shows the UI again."

The coordinator's changes, which Noah took ("Let's build the fullscreen UI/UX with the context you just
provided and try it out!"):

1. Show: a swipe in from the left bezel, the system's own edge recognizer; the interface follows the
   finger and finishes or springs back by distance and speed.
2. Hide: not from anywhere on the picture (every touch there is the Mac's: a leftward swipe scrolls it,
   in Safari it goes back; a scroll that runs off the edge would hide the interface by accident), but a
   short outward flick at the left edge: the touch starts within about a thumb's width of the edge,
   moves left and leaves the screen. A touch that starts there is held back from the Mac only as long as
   it takes to judge it; a flick sends the Mac nothing; anything else goes on whole, in order; a tap still
   clicks.
3. Nothing persistent while hidden; safety nets instead: a hint the first few times, the interface
   coming back by itself whenever it is needed, a shake, an action for VoiceOver, Switch Control and Voice
   Control (and VoiceOver's escape gesture), and on an iPad the pointer pushed against the left edge.
4. iPadOS: priority on the left edge while hidden (`preferredScreenEdgesDeferringSystemGestures`), only
   there; full screen by gesture only while Sill's window covers the screen.
5. While hidden the picture gets the whole screen: no status bar, the home indicator fades, the viewport
   is the whole room, so the Mac fits a window to it where it already does (Virtual Display on, or Aa
   set), one restart per change as a rotation's. The Desktop is not fitted: it has the larger room.
6. A way in that is not a gesture: Settings › This iPad (This iPhone) › Full Screen. Nothing remembered
   across launches; kept across a rotation and a trip to another app.
7. Every layout, one level (all hidden or all shown), built so that a second level is a small addition.
8. The hardware keyboard keeps typing to the Mac while hidden.
9. No wire change; Picture in Picture, the Mac's pointer, the Menus and three-finger gestures keep working.

Noah, later the same night (through the coordinator), on the second level upright: "for now, only apps in
windowed mode will likely be able to take advantage of the full screen due to the aspect ratio of most
displays until Virtual Display is available, which could then create custom full screen resolutions to
utilize the portrait dimensions." So: one level only (the middle level is parked); upright, the case that
must be excellent is a window with Virtual Display on (or Aa set), which the Mac fits to the whole upright
room; the Desktop keeps its own shape in the larger room.

The Desktop upright: the Desktop is the Mac's display, landscape on nearly every Mac, so held upright it
keeps its shape in full screen's taller room, with black above and below. The Virtual Desktop's "match
this device" (PR #352's plan: a desktop display of Sill's own whose size can match the device) is what
will later give the Desktop a full screen upright. Full screen already sends the room it has as the
viewport, the same message every layout sends, so that feature can use it without a change here.

## What a person does and sees

- Flick off the left edge (from within 48 pt of it, out over the bezel): the bar, the thumbnails, the keys
  and the trackpad slide out by the left edge, and the picture grows to the screen's room. The first three
  times a card by the left edge says "Controls hidden — Swipe in from the left edge to bring them back." for
  2.5 s.
- Swipe in from the left bezel: the controls come in with the finger; let go past a third of the screen
  (or with a flick) and they settle, the picture shrinking into its pane; let go short and they slide back
  out.
- Shake the device: the controls come back. VoiceOver: the picture is one element, "‹Mac›’s picture.
  Sill’s controls are hidden.", whose activation, its Show Controls action and the escape gesture bring them
  back; Voice Control knows it as "Show Controls". On an iPad, the pointer held at the left edge for half a
  second brings them back.
- Settings › This iPad (This iPhone) › Full Screen hides them too, the panel closing first.
- The controls come back by themselves for the tour, a pairing or an outside link, the link's line ("The
  link can't keep up…"), the Mac's cover (locked, another user's, unlocking), the off-console view, nothing
  streaming (a window closed), and Sill's window no longer filling the screen.

## The parts

- `iOSClient/FullScreenPolicy.swift` (pure, Foundation and CoreGraphics; `Tests/checks/full-screen`):
  `ChromeLevel` (the levels; the slot for a second), `EdgeFlick` (the hide's touch rule), `EdgeFlickGate`
  (which touches are judged), `EdgeReveal` (the swipe in's finish or spring back), `EdgeDwell` (the pointer
  at the edge), `FullScreenPolicy` (offered, must show and why, a hide allowed, the flick armed, the hint, the
  room, the words).
- `iOSClient/EdgeFlickRecognizer.swift` (UIKit and the rule only, so the touch rig compiles it): the flick's
  recognizer and the swipe in's (`RevealEdgePan`, the system's `UIScreenEdgePanGestureRecognizer`), both on
  Sill's window, and the one rule of which other recognizers wait for them (`EdgeRecognizers.waits`).
- `iOSClient/FullScreen.swift`: `FullScreenEdges` (puts the recognizers and a hover on the window, says
  whether the window covers the screen, passes the window's shake on), the shake (`UIWindow.motionEnded`),
  the hint, the swipe in's preview hole and mask, the hidden picture's element, the DEBUG arguments.
- StreamScreen: the state (`chrome`, `reveal`), hide and show, the auto-show, the room, the status bar,
  home indicator and edge deferral, the landscape layout's hidden variant, the preview; PortraitStreamScreen:
  the halves' and the phone's hidden and preview variants; HostSettingsPanel: the row; TrackpadView: the
  tracker's touch-down point.

## The touch rule, and the numbers

No finger on glass could be measured here: every number is from the devices' geometry, UIKit's touch
sampling and the strokes the rule must tell apart, each is one constant, and a Debug build prints every
judged stroke's numbers on Xcode's console (`edge: a flick off the left edge (landed 31.0 pt from the edge,
29.0 pt left and 0.0 pt down, 640 pt/s at the end, last seen 2.0 pt in, 62 ms, 6 samples): hide`, or `edge:
not a flick, too slow (…)`), so Noah's first sessions measure them.

| | value | why |
|---|---|---|
| band | 48 pt | about 7.5 mm on the iPad mini (163 pt an inch) and 8 mm on the iPhone 15 Pro (153 pt an inch): a thumb's contact patch, so a thumb that sets off with its edge at the bezel lands in it. A stroke landing further in is the Mac's at once, as it always was. |
| travel | 12 pt left | a flick moves; a grip or a tap that rolls off the edge does not get this far, and a touch landing nearer the edge than this cannot be one. |
| duration | 0.25 s, landing to lift | a flick takes about a tenth of a second; a resting grip, a long press (0.45 s) and a slow drag are let go by then (the recognizer's own clock: a still finger sends no events). |
| speed | 300 pt/s left, over the last 50 ms | about 5 cm a second, half a brisk flick's slowest; a slow drag to the edge, 100 to 200 pt/s, is not one. Measured from where the finger was 50 ms before the lift, in proportion between the samples either side of that moment: a still finger sends no samples, so from the sample before that moment a flick after a rest would count the rest (36 pt in 37 ms after a 0.1 s rest: 250 pt/s over the whole stroke, 600 over its end). The lift's own sample, where the finger was last seen one sample later, counts as a stop: at 60 Hz a steady 450 pt/s reads 300. |
| reach | 24 pt | where the last sample may be. A finger that slides off the glass is last seen up to one sample interval short of the edge (16.7 ms at 60 Hz, 8.3 ms at 120: 5 to 17 pt at 300 to 1,000 pt/s), and a case's raised lip stops the finger's middle some 3 to 4 mm (20 to 24 pt) in, so the finger lifts there. |
| projection | 50 ms | a faster flick last seen further in counts when its last speed carries it past the edge within this (three samples at 60 Hz). |
| right slop, judge after | 6 pt, 8 pt | a drag right is let go after 6 pt, any stroke steeper than about 50° from straight left (\|dy\| ≤ 1.2 \|dx\|) after 8, both before a pan's own 10 pt, so the drags the band lets go are not even late. |

How the hold works: every other recognizer in Sill's window that takes fingers (the picture's tap, long
press and scroll, the trackpad's tracker, taps, pan and long press, the bars' buttons, the strip's scroll)
waits for the flick's recognizer to fail (`shouldBeRequiredToFail(by:)`). UIKit holds their recognition
back, not the touches: a touch outside the band fails the flick at its landing and nothing waits; a touch in
the band is held only until the rule decides, and then either is the hide and nothing else (the waiting
recognizers fail, its touch is cancelled in the views) or goes on whole, the waiting recognizers
recognizing it as they would have, their translation counted from the touch's landing. The trackpad's
tracker, which begins at touch-down, now starts from where the finger landed (`FingerTracker.downLocation`),
so a stroke it waited for loses no travel. A stroke judged only at its lift (a quick drag left that stops
short of the edge) has its waiting recognizers let go at that lift, beginning and ending at once: the
picture's scroll and the trackpad's tracker then carry the finger's travel at their end
(`EdgeRecognizers.releasedAtLift`, true only in that moment after an edge recognizer let a touch go at its
lift), and the trackpad's pan leaves a held stroke's travel to its tracker (`trackerPending`), so it counts
once. None of this is reached by a stroke away from the edge. Recognizers that only watch (the stroke observer, the finger
counter, the tour's touch watch) never recognize, so never wait. The Pencil and the iPad's pointer never
reach the flick (`allowedTouchTypes`), and the pointer's own recognizers take no finger.

The swipe in: `UIScreenEdgePanGestureRecognizer` on the left edge, only while hidden, with the same rule of
who waits for it; it finishes past a third of the screen's width (the lift's speed carrying it on for
0.15 s), or at a flick in (400 pt/s after 12 pt), and springs back when moving back toward the edge at
200 pt/s or more. A touch landing more than 40 pt in fails it at once, and one at the bezel that has not
begun to swipe in 0.3 s after it landed (`EdgeReveal.decideWithin`: a press, a rest) is let go then, so
nothing near the edge is held longer and a long press there (0.45 s) is never late.

## The Desktop button's screens (#355)

Hiding and showing the controls never picks a source and never steps the Desktop: the Desktop button, which
on a Mac with two screens or more reads "Desktop 2" and steps to the next screen at a tap (kind 47), goes and
comes with the bar, reading what the Mac says each time; the only message a hide or a show sends is the
viewport, which the Mac does not apply to the Desktop. So the Desktop stays on the screen it is on, and the
swipe in's preview shows the button as it will be ("Desktop 2", its dots).

## Where the picture goes while hidden (open question 5)

The room: the screen less the safe area's top, left and right (the Dynamic Island or the notch upright, the
sensor housing's side sideways, the iPhone Duo cover's camera strip), down to the bottom edge under the home
indicator, which fades. On an iPad with the status bar hidden that is the whole screen. On the Duo's inner
display upright in the laptop pose, the part above the fold. The picture keeps its shape in it (letterboxed
in black); a window the Mac fits to the viewport fills it. The other two choices, photographed for Noah:
the whole screen (under the island and the rounded corners) and the whole safe area (clear of the home
indicator too); DEBUG `-SillFullScreenRoom screen|housing|safe`.

## The software keyboard, the hardware keyboard, the rest (open questions 7, 8, 9)

- Hiding takes the person's own software keyboard down (it would cover half the picture); it comes back
  with the controls. A hardware keyboard's hold stays (HardwareKeyboardPolicy: the Keyboard button's toggle
  from the person's to the hardware keyboard's), so typing on one keeps reaching the Mac while hidden. No key
  of Sill's own shows the controls: keys belong to the Mac.
- Picture in Picture: unchanged (it takes the picture's layer whatever the layout). The Mac's pointer
  sprite: drawn over the picture as before (the trackpad's own arrow only upright with the trackpad shown).
  The Menus: the iPad's own menu bar stays reachable (a pointer at the top edge or a swipe down); the Menus
  button is with the hidden controls. Three-finger gestures: unchanged on the picture.
- The tour does not start while hidden (its rule counts the controls hidden as busy).
- The clipboard's chip shows over the hidden picture, in its corner, as over the picture while shown.

## How this relates to the open pull requests

- #197 (addhumal, Hide Top Bar; closes #92 as decided on 2026-10-19): a Settings switch hides the landscape top
  bar, a shake shows it, and a small pill button and ⇧⌘B show it too. Full screen covers more (every layout,
  every control) and keeps no button on screen, which Noah has now ruled out; it keeps the shake and puts the
  Settings way in as a row that hides at once. Both change StreamScreen.swift and HostSettingsPanel.swift; with
  this merged, #197's `TopBarVisibility` would go, and its photos and checks with it.
- #312 (lepeos, on #197): the Desktop edge to edge on an iPad under Hide Top Bar, through a display of the
  device's size on the Mac (`Viewport.deviceDesktop`, #156's host half). Full screen already sends its room as
  the viewport; such a request would hang off full screen's hidden state instead of Hide Top Bar. Noah's chosen
  way to give the Desktop the device's shape is the Virtual Desktop's "match this device" (PR #352's plan).
- #206 (RaffaelFerro, part 5 of #202–#206): Full Screen on an iPhone held upright, in by a ⤢ button in the
  picture's corner and out by a handle, the free room the window's display, and Keep Screen On. The room as the
  viewport is the same idea; the persistent button and handle are what Noah ruled out. It changes
  StreamScreen.swift, PortraitStreamScreen.swift, PhonePortraitLayout.swift and InputOverlay.swift heavily, so
  one of the two would be rebuilt on the other.
- #156 (dr-apple): the Desktop full screen by a second tap on Desktop, two small buttons to leave, the Mac's own
  display of the device's size with a curtain, and a picture clock. Noah said on #92 the second tap does not fit;
  its host half lives on in #312. Nothing of it is taken here.
- #161 (lepeos, closed): Immersive on an iPad with a hardware keyboard, closed in favour of #197.

## Open questions, with the default taken

1. The flick's numbers (band 48 pt, travel 12 pt, 0.25 s, 300 pt/s, reach 24 pt, 50 ms): defaults from
   geometry and sampling; the first sessions' `edge:` lines say whether to move any.
2. Where the flick works: anywhere along the left edge, on the picture, the trackpad and the controls in the
   band alike (a flick that starts on the Apps button hides, and the button does not act).
3. Offered only while Sill's window covers the screen; elsewhere (Split View, Slide Over, a Stage Manager
   window) the row is dimmed with "Full Screen works while Sill fills the screen.", and going into such a
   window while hidden brings the controls back.
4. The Settings row is a button that hides now, not a switch (Noah decided on 2026-10-19 that hiding the
   bar is a Settings toggle; with nothing remembered, a switch would read off whenever it is seen).
5. Where the hidden picture goes: clear of the housing, under the home indicator (photos of the three).
6. The hint: the first 3 times, 2.5 s; VoiceOver every time.
7. A hardware keyboard shortcut to show the controls: none (keys belong to the Mac).
8. The software keyboard: down while hidden, back with the controls; to type while hidden, a hardware
   keyboard, or show the controls.
9. The pointer at the left edge: half a second within 1 pt of it. With the Mac's Dock on the left, its
   own edge, this can bring the controls back as the Dock shows.
10. The iPad's status bar comes back as the swipe in lands, so the shown layout settles 24 pt lower then.
11. The edge deferral only while hidden; a person who wants Stage Manager's strip then swipes twice.
12. A second level upright (the trackpad alone hidden first): parked by Noah; not built. `ChromeLevel`
    keeps a raw value for it between the two, and `afterFlick`/`afterReveal` are the only steps.

## The gates

- G1 the rule: `Tests/checks/full-screen` (cases at every number's edge, 30,000 random strokes against an
  independent model) and its mutants, each caught.
- G2 the builds: the iOS app Debug and Release for the simulator and Debug for a device, the known warnings only.
- G3 the touch rig (Tests/touchrig, on the agents' iPad simulator): main's surfaces against this branch's, every
  existing stroke's events identical (`compare.py --all`); the strokes at the left edge (`compare.py --edge`):
  each flick hides and sends nothing, on the picture, the trackpad and a SwiftUI button; every other stroke
  that lands in the band (a tap, a long press, drags right, up and down, a slow drag left, a quick drag left
  lifted short of the edge, two fingers, a grip with a tap elsewhere, a scroll from the middle off the edge, a
  tap on the button) sends what main's surfaces send, in order; with the controls hidden, strokes near the edge
  and away from it as main's; UIKit's pan threshold measured.
- G4 live on loopback: `SillHost --synthetic` (loopback only, the software encoder, no router, no screen, the
  dry-run input log) and the app under `-SillLive 1` on the agents' iPad simulator, at an iPhone 15 Pro's upright
  size and an iPad mini's sideways: hidden and shown by a toggle, a shake and a played swipe in while an input
  script taps, presses keys and types around each change: the viewport one per change (the room, then the
  pane), and every input step reaching the host. Then the Desktop on the Mac's second screen (#355; the host's
  `SILL_TEST_DISPLAYS` with two stops): the device's own Desktop button steps to it (`-SillDesktopTapAt`), the
  controls hide, show, hide and come back by a shake, and every stream after the step is on display 2.
- G5 photos (Scripts/harness-photos.sh, the agents' Duo on iOS 27.1 and iPad on 27.0): every shown layout
  pixel for pixel main's; the hidden layouts, the hint, the swipe in's preview, the room's three choices with an
  iPhone's island, corners and home indicator drawn, a tall window upright on a phone and an iPad mini, the
  Desktop upright, the Settings row, at the default and the largest text size.
- G6 `Tests/checks/repo-rules`.

## Results

All on 2026-11-12, inside the heavy lock (07:41 to 08:2x), the branch with main at 919e05a merged in.

- **G1, the rule:** `Tests/checks/full-screen`, 56,514 checks, none failed: the cases at each number's edge
  at 60, 120 and 240 Hz, and 30,000 seeded random strokes against the independent model (5,061 hid, 9,536
  landed outside the band) with the invariants. Its mutants: 59 of 59 caught (`run.sh --mutants`).
- **G2, the builds:** the iOS app Debug and Release for the simulator and Debug for a device, at 25eac11a and
  again at 36686dc8 (after the room's fix below): each `** BUILD SUCCEEDED **`, the only warning the known
  `StreamClient.swift:4518` capture one. The shared photo tool built 25eac11a, 36686dc8 and 480728cc too.
- **G4, live on loopback** (`SillHost --synthetic` with SILL_TEST_LOOPBACK, SOFTWARE_ENCODER, NO_ROUTER,
  NO_SCREEN and INPUT_LOG; the app's Debug build under `-SillLive 1` on the agents' iPad simulator; no device
  on Sill.app before each run, `Scripts/encoder-check/no-device.sh`). An input script tapped (39), pressed a
  key (24) and typed a letter (12) every 0.1 s for a second around each change while the controls hid at 4 s,
  came back at 7, hid at 10, came back by a shake at 13, hid at 16 and came back by a played swipe in at 18.8:
  - An iPhone 15 Pro's size upright (393×852, the island's 59 pt, `-SillIdiom phone`): the viewport
    377×235 pt (the pane) as it connected (twice, as on main), then 393×793 at each hide and 377×235 at each
    show, one per change, six in all. Every input reached the host: 39 left mouse downs and 39 ups, 36 key
    events (24 presses and 12 letters: the dry run logs typed text as key 0 with its string).
  - An iPad mini sideways (1133×744): 1117×618 as it connected, then 1133×744 and 1117×618, one per change;
    every input reached the host, as above.
  - The Desktop on the Mac's second screen (#355; the host's `SILL_TEST_DISPLAYS` with two): the device's own
    Desktop button (`-SillDesktopTapAt 3`, as a finger's tap) stepped it ("Desktop: display 2 of 2 (DELL
    U2723QE), asked by Sill agents iPad"); then the controls hid at 6, came back at 9, hid at 12 and came back
    by a shake at 15: one viewport each (1133×744, 1117×618), and the host's only stream start after the step
    was display 2's, so the Desktop stayed there; the 12 taps around the changes all reached it.
  - A window's fit cannot run here: a synthetic host streams only the Desktop (SILL_TEST_NO_SCREEN keeps it
    off this Mac's windows), and the Mac ignores a viewport's size for the Desktop. What the window case
    needs from the device is the viewport above, one per change; the Mac fits a window to a new viewport by
    the path a rotation takes (`StreamCoordinator.applyViewportToActiveWindow`: one restart on the virtual
    display, a resize with Aa set), unchanged here, which Larger Picture's live gate (docs/larger-picture-
    plan.md, D4) measured: one restart per new viewport.
  - **Found and fixed:** the first run measured the hidden room on the upright phone at 393×852: the stream
    screen's GeometryReader ignores the safe area while hidden, and then reports none, so the picture would
    have gone under the Dynamic Island. The room and the swipe in's preview now take the window's safe area
    (UIKit's, from FullScreenEdges), or in the harness its fake screen's (36686dc8); the second run above.
- **G5, photos** (`Scripts/harness-photos.sh`, the agents' Duo on iOS 27.1 and iPad on 27.0):
  - Shown, against main (919e05a): on the Duo simulator 15 cases (an iPhone upright and sideways, Larger
    Picture, the Duo's book, laptop, flat and cover, the largest text size, the Desktop button on screen 2 of
    3): 13 pixel for pixel main's; the 2 Settings photos differ by the new row, as they must. On the iPad
    simulator 7 cases: 5 pixel for pixel main's, the 2 Settings photos by the row.
  - Hidden (37 photos, the mock's frame drawn as a dim rectangle, `-SillPointer hidden`): an upright iPhone
    with a tall window fills the room under the island to the bottom edge; the Desktop upright keeps its
    shape, black above and below; sideways the room is clear of both housing sides (iOS gives both); the
    Duo's laptop pose above the fold, its book pose and its cover; an iPad mini upright filled edge to edge
    by a tall window; the room's three choices drawn with an iPhone's island, corners and home indicator
    (`-SillMockHardware 1`); the hint, at the default and the largest text size; the swipe in's preview at
    40 to 70 % in, its Desktop button reading "Desktop 2" with its dots.
- **G6:** `Tests/checks/repo-rules`, 10 of 10 rules hold.
- **G3, the touch rig:** RIG_RESULTS

## Noah's test (the device test, short)

On the iPad mini and the iPhone 15 Pro, a Debug build from this branch, Xcode's console open for the
`edge:` and `full screen:` lines, Sill for Mac with Virtual Display on, a window streaming:

1. Flick off the left edge from the picture (your thumb at the edge, out over the bezel): the controls go,
   the window grows to the screen (one "Resized"/restart line in Sill.log). The card shows the first 3 times.
2. Swipe in from the left bezel slowly, stop half way, go back: the controls follow and slide back out.
   Again past a third: they settle. Then a quick swipe in: they come.
3. In a case if you have one: flicks stopped by its lip still hide (console: "last seen ~20 pt in").
4. Near the left edge: a tap clicks, a drag right/up/down scrolls at once, a slow drag left scrolls (a
   quarter second late at most), a scroll from the middle that runs off the edge scrolls and never hides.
5. Flick from the Apps button, the thumbnails and (upright) the trackpad at the left edge: hides, nothing
   pressed on the Mac or in Sill.
6. Hidden: shake: back. Settings › This iPad › Full Screen: hides. VoiceOver on: the picture element,
   double-tap: back.
7. iPad with a trackpad or mouse: hidden, hold the pointer at the left edge: back after half a second.
   Stage Manager on: hidden, swipe in from the left: Sill's controls (not the strip); twice: the strip.
8. Upright on both: a window with Virtual Display on fills the screen when hidden; the Desktop keeps its
   shape with black above and below.
9. Hardware keyboard: hidden, type: it reaches the Mac. Software keyboard up, hide: it goes; show: it
   comes back.
10. Rotate while hidden: stays hidden. Leave Sill and come back: stays hidden. Relaunch: shown.
