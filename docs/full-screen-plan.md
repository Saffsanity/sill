# Full screen: Sill's interface hidden, the picture with the whole screen

Branch `full-screen` (from main at a4bad80, main at 0d22bbf and 919e05a merged in), PR #360; issues #279
(swipe the UI away), #92 (hide the top bar) and #280 (use the freed room). Device only: no wire change, nothing
on the Mac, nothing stored but a count of how often the hint has shown and Shake to Show Controls.

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

Items 1, 2 and 6 changed after Noah tried the first build on his devices (the next section): there is no flick,
Settings › Full Screen is the one way in, and the swipe in is Sill's own recognizer, not the system's.

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

## Noah's device test of the first build, and the design now

Noah tried the first build (1515, PR #360 at b5abf668) on his iPad mini and iPhone 15 Pro on 2026-11-12: "The
touch detection is really bad." "Doesn't seem to work in landscape at all." "I think the simpler thing is to
remove the side swipe to start full screen and just have it be invoked from the button in settings. Swiping in
to re-show the UI or shaking can be kept. I also want a toggle in settings to enable/disable shake to revert."
"The swipe in is pretty bad on iPad, we need to improve that gesture regardless." "Seems to work perfectly on
iPhone in portrait, but landscape doesnt work. iPad I cant get it to work at all in either orientation." The
coordinator's try builds (branch `full-screen-try`, never pushed) gave him the design below one change at a
time; he approved it on both devices ("Works perfectly!"), then asked for the Settings rows after Frame Rate,
for the preview to draw nothing around the picture in any layout ("the bottom of it has a small black bar below
it"; "Ideally, no bezel gets rendered above or below the controls until they are fully summoned"), for "just a
touch of black above the UI buttons on iPhone in portrait to make it look uniform", and for the same on every
Duo pose. This branch is that behaviour, written properly.

What the device logs showed (Xcode's console from both devices, the first build and his try builds):
1. The hide flick hid 6 of 38 strokes it judged. Its 48 pt band was measured from the glass's edge, but an
   iPhone on its side keeps 59 pt clear of the picture there; a thumb landing 0 to 16 pt from the edge cannot
   travel 12 pt further left; the iPad mini's 60 Hz touch made a fast flick read as a tap (it began and ended
   at the same point); and a slide reaching the edge pins at x = 0 and read "too slow". Moot now: there is no
   flick.
2. The swipe in finished only past a third of the screen's width: 131 pt on an upright iPhone (it worked), 284
   pt on its side, 248 and 378 pt on the iPad mini (it never did). It now finishes after min(a third, 80 pt).
3. On their side, the system's edge recognizer (`UIScreenEdgePanGestureRecognizer`) on Sill's window failed
   every swipe from the interface's left edge: it reads the device's upright left edge as "left". Upright it
   began 13 to 150 ms after landings 0.0 to 6.7 pt from the edge. Sill's own pan replaces it, in the window's
   space, which is the interface's in every orientation.
4. On his try builds the new swipe in came in from lifts after 124 to 1,098 pt, and drags in and back sprang
   back (-27 pt at -993 pt/s, -25 at 0, -46 at -1,660, -62 at -1,008; on an iPhone on its side, 285 to 590 pt in
   and moving back at 587 to 3,667 pt/s).
5. The controls came back by themselves three times on the first build on the iPad, "shown by the window no
   longer fills the screen", each time with viewports of 939×610, 968×591 and 918×610 pt for a second or two
   before 1117×610 again: Sill's window really was narrower for that long (iPadOS's windowing answering left-edge
   flicks, most likely), so the auto-show did what it is for. None on the try builds, whose coverage lines read
   "fills" throughout (the iPad's window 1133×744 at 0,0 on a screen 1133×744, the iPhone's 393×852). Each
   change of the reading prints the window's and the screen's frames in a Debug build, so a recurrence can be
   read. `FullScreenPolicy.offered` reads the window's frame against the screen's bounds only when UIKit lays
   the window out, so a rotation (both turn together) does not read false between them; nothing else was found
   that could.

What was removed with the flick: `EdgeFlick` and `EdgeFlickGate` (its rule and which touches it judged), its
recognizer and its arming (`flickArmed`), the trackpad's tracker starting from the landing
(`FingerTracker.downLocation`, `trackerPending`: TrackpadView.swift is main's again; the trackpad is hidden
whenever the swipe in listens), and the flick's checks, mutants and rig strokes. Kept, because the swipe in holds
a touch in its band while it judges it, and the picture is the only surface then: `EdgeRecognizers.waits`
(which recognizers wait for it), `heldLanding` and `panHysteresis` (a pan held past its own start counts its
translation from where it is let go, so the picture's scroll carries the held travel as an unheld pan counts
it), `releasedAtLift` (a stroke held until its lift, a tap at the edge, ends with its travel), and
`WatchesTouchesOnly` (a recognizer that only watches never waits). While the controls show none of it is
reached: the swipe in's recognizer is off, and nothing else of full screen's listens to a touch.

## What a person does and sees

- Settings › Full Screen (right after Frame Rate and its words while the Mac's settings show; in This iPad's
  group, after Picture in Picture, while they do not): the panel closes and the bar, the thumbnails, the keys
  and the trackpad slide out by the left edge, and the picture grows to the screen's room. Under the button:
  "Hides Sill’s controls, so only the picture shows. Swipe in from the left edge to bring them back." (while
  Sill does not fill the screen, the button is dimmed and the line reads "Full Screen works while Sill fills
  the screen."). The first three times a card by the left edge says "Controls hidden — Swipe in from the left
  edge to bring them back." for 2.5 s.
- Swipe in from the left edge: the controls come in with the finger, with the background they sit on and
  nothing of the picture's place (no pane, rim, margin or room's black), so the hidden picture stays as it is
  under them until they land; let go after 80 pt (less on a screen under 240 pt wide), or with a quick flick
  in, and they settle, the picture shrinking into its pane; let go moving back and they slide back out.
- Shake the device (Settings › Shake to Show Controls, on unless turned off; "Shaking your iPad brings the
  controls back too.", naming the device): the controls come back. While the switch is on, Shake to Undo is off
  in Sill only while the controls are hidden; off, a shake does nothing of Sill's and Shake to Undo stays.
- VoiceOver: the picture is one element, "‹Mac›’s picture. Sill’s controls are hidden.", whose activation, its
  Show Controls action and the escape gesture bring them back; Voice Control knows it as "Show Controls". On an
  iPad, the pointer held at the left edge for half a second brings them back.
- The controls come back by themselves for the tour, a pairing or an outside link, the link's line ("The
  link can't keep up…"), the Mac's cover (locked, another user's, unlocking), the off-console view, nothing
  streaming (a window closed), and Sill's window no longer filling the screen.

## The parts

- `iOSClient/FullScreenPolicy.swift` (pure, Foundation and CoreGraphics, with DuoPosture.swift's split and
  PhonePortraitLayout.swift for the preview's cut; `Tests/checks/full-screen`): `ChromeLevel` (the levels; the
  slot for a second), `EdgeSwipe` (which touch at the left edge is a swipe in, and when it is let go),
  `EdgeReveal` (how far the interface has come; the finish or spring back), `RevealCut` (the preview's cut over
  each layout's picture's place), `EdgeDwell` (the pointer at the edge), `FullScreenPolicy` (offered, must show
  and why, a hide allowed, the shake, the Settings rows' place, the hint, the room, the words).
- `iOSClient/RevealEdgePan.swift` (UIKit and the rule only, so the touch rig compiles it): the swipe in's
  recognizer, a `UIPanGestureRecognizer` of Sill's on its window, and the one rule of which other recognizers
  wait for it (`EdgeRecognizers.waits`), with `heldLanding` and `releasedAtLift`.
- `iOSClient/FullScreen.swift`: `FullScreenEdges` (puts the recognizer and a hover on the window, on only while
  hidden; says whether the window covers the screen and its safe area; passes the window's shake on), the
  shake (`UIWindow.motionEnded`), the hint, the hidden picture's element, the DEBUG arguments.
- StreamScreen: the state (`chrome`, `reveal`), hide and show, the auto-show, the room, the status bar, home
  indicator and edge deferral, the landscape layout's hidden variant and its preview (the bar alone), the shake's
  switch and Shake to Undo; PortraitStreamScreen: the halves' and the phone's hidden variants and previews (the
  controls on their own black); HostSettingsPanel: the two rows and their place.

## The swipe in, and the numbers

| | value | why |
|---|---|---|
| band | max(24 pt, the window's left safe-area inset) | a finger that comes over the bezel is first seen within a few points of the edge (Noah's: 0 to 9 pt upright, up to 21 pt at speed on the iPad's side); an iPhone on its side keeps 59 pt clear of the picture on the sensor housing's side, and a swipe from that bezel is first seen anywhere in it. A touch landing further in is the Mac's at once. |
| judged after | 8 pt from the landing | right, and no steeper than 45° (\|dy\| ≤ dx): the swipe in; anything else is let go, before a pan's own 10 pt, so it is not late. |
| let go by | 0.3 s after the landing | a finger that has not set off by then (a press, a rest) is the Mac's, so a long press at the edge (0.45 s) is never late. A second finger lets it go at once. |
| finishes | min(a third of the width, 80 pt), the lift's speed carrying it on for 0.15 s | 80 pt is about 13 mm on both devices; a third of the width (131 to 378 pt) was more than a thumb's swipe on a phone on its side or an iPad (finding 2). |
| flick in | 300 pt/s, once it has moved 12 pt | a quick swipe in comes whatever its length. |
| springs back | moving back toward the edge at 200 pt/s or more | a drag in and back (finding 4). |

The cost: while hidden, a rightward drag that starts within the band (24 pt, or the left inset) brings the
controls in and never reaches the Mac. Every other touch there reaches the Mac whole and in order, held at most
until 8 pt of travel or 0.3 s. The interface's travel counts from where the pan began (UIKit's own hysteresis,
13 to 65 pt past the landing on Noah's devices: the preview trails the finger by that much), the feel Noah
approved; counting from the landing instead was not tried.

How the hold works: while hidden, every other recognizer in Sill's window that takes fingers (the picture's tap,
long press and scroll) waits for the swipe in to fail (`shouldBeRequiredToFail(by:)`). A touch outside the band
fails it at its landing and nothing waits; a touch in the band is held only until the rule decides, and then is
the swipe in and nothing else or goes on whole, the waiting recognizers recognizing it as they would have, in
order. UIKit holds their recognition back, not the touches; a pan held past its own start (only when one sample
carries a finger past 8 and 10 pt at once, the iPad mini's 60 Hz touch at speed) counts its translation from
where it is let go, so the picture's scroll carries the held travel in its next delta as an unheld pan counts it
(`heldLanding`, `panHysteresis`: main's pans never send their first 10 pt, measured in the rig); a stroke held
until its lift (a tap at the edge) has its waiting recognizers let go at that lift (`releasedAtLift`).
Recognizers that only watch (the stroke observer: `WatchesTouchesOnly`; the tour's touch watch is on the window)
never recognize, so they never wait: made to wait for the first build's flick, UIKit never reset them or it after
the first stroke it held. The recognizer calls super in every touch override (UIKit's subclassing contract), and
takes no Pencil and no pointer (`allowedTouchTypes`).

## The preview: the controls, and nothing of the picture's place

Until the controls land, the swipe in's preview draws them with the background they sit on (the black between
and around them, where the shown layout has it) and nothing of the picture's place: no pane, rim, margin or
room's black. Each layout gives its place from its own geometry (`RevealCut`), never from the picture (a pane at
the video's shape is narrower or shorter than its room), and its preview cannot draw there at all: its picture
pane is an empty view (no panel, rim, cover or line), the layout's own black is drawn only at `RevealCut.shown`,
behind the controls, and nothing open (the drawer, the Settings panel) is drawn in a preview. There is no mask
and nothing measured: the try builds cut a drawn pane away with a mask whose rect came from a measurement a frame
late whenever it changed (after a turn, or a new video size with Larger Picture), and Noah saw "something quickly
renders below the UI … very jarring" on an iPhone on its side.

- Landscape (an iPad or an iPhone on its side, the Duo open flat on its side, its book pose and its cover on its
  side): everything under the top bar, which carries its own background, so the cut ends exactly at its bottom
  edge (`RevealCut.landscape`, the bar's height, the fold cleared).
- The halves (an iPad upright, an iPad window under 600 pt wide, the Duo open flat upright, its laptop pose):
  everything over the controls' block (`RevealCut.halves`, `DuoPosture.PortraitSplit.controls`): the picture's
  half, the pane's margin and the laptop pose's fold go; the block's own top margin, 12 pt of black above the
  window bar (10 in an iPad window under 600 pt), stays, as it is once the controls land.
- A phone upright and the Duo's cover upright: everything over the bottom of the picture's room
  (`RevealCut.phone`, `PhonePortraitLayout.picture`, Larger Picture's room too, whatever the video); the gap above
  row 1 stays black, 24 pt to the buttons, as it is once they land ("just a touch of black above the UI buttons").

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

1. The swipe in's numbers (band max(24 pt, the left inset), judged after 8 pt within 45°, let go by 0.3 s,
   finishes after min(a third, 80 pt), a 300 pt/s flick after 12 pt, back at 200 pt/s): the try builds Noah
   approved; the `reveal:` lines say whether to move any.
2. Its cost: while hidden, a rightward drag from the band never reaches the Mac (above).
3. Offered only while Sill's window covers the screen; elsewhere (Split View, Slide Over, a Stage Manager
   window) the button is dimmed with "Full Screen works while Sill fills the screen.", and going into such a
   window while hidden brings the controls back.
4. Full Screen is a button that hides now, not a switch (nothing is remembered, and the interface is shown
   whenever the row is seen); Shake to Show Controls is a switch, on unless turned off.
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
    keeps a raw value for it between the two, and `afterHide`/`afterReveal` are the only steps.
13. The preview trails the finger by the pan's hysteresis (13 to 65 pt): kept, the feel Noah approved.

## The gates

- G1 the rule: `Tests/checks/full-screen` (the swipe in's cases at every number's edge at 60, 120 and 240 Hz,
  30,000 random strokes against an independent model; the finish; the preview's cut in every layout with the
  layouts' own geometry: the phones and the Duo's cover upright through PhonePortraitLayout with and without
  Larger Picture and six videos, the halves through DuoPosture's split for iPads, the Duo open flat and its
  laptop pose, landscape at both bars; the shake's switch; the Settings rows' place) and its mutants, each
  caught.
- G2 the builds: the iOS app Debug and Release for the simulator and Debug for a device, the known warnings only.
- G3 the touch rig (Tests/touchrig): main's surfaces against this branch's, every existing stroke's events
  identical (`compare.py --all`); at the left edge (`compare.py --edge`), with the controls shown, every stroke
  main's exactly on the picture and the trackpad (the first build's flicks among them); hidden, a swipe in from
  the band (from the very edge, from 20 pt at 30°, slowly) brings the controls and sends nothing, and a tap, a
  long press, drags down, up and left, a flick left and two fingers from the band, and strokes further in, send
  what main's surfaces send, in order; on the agents' iPad simulator, and the hidden strokes again on the agents'
  Duo simulator upright and with the scene on its side (`RIG_ORIENT=landscape`).
- G4 live on loopback: `SillHost --synthetic` (loopback only, the software encoder, no router, no screen, the
  dry-run input log) and the app under `-SillLive 1` on the agents' iPad simulator, at an iPhone 15 Pro's upright
  size and an iPad mini's sideways: hidden and shown (as Settings › Full Screen and the swipe in do), a shake and
  a played swipe in while an input script taps, presses keys and types around each change: the viewport one per
  change, and every input step reaching the host; the Desktop on the Mac's second screen kept through a hide, a
  show and a shake; a shake with Shake to Show Controls off doing nothing.
- G5 photos (Scripts/harness-photos.sh, the agents' Duo on iOS 27.1 and iPad on 27.0): every shown layout pixel
  for pixel main's but the Settings panel; the Settings panel with the rows after Frame Rate on an iPhone, an iPad
  and the compact halves; the swipe in's preview in every layout (an iPhone upright, with Larger Picture and a
  tall window, and on its side; an iPad mini upright and on its side; the compact halves; the Duo's cover upright
  and on its side, open flat upright and on its side, the laptop and book poses; a window and the Desktop), the
  controls and nothing of the picture's place.
- G6 `Tests/checks/repo-rules`.

## Results

### The first build (the flick; superseded)

All on 2026-11-12, inside the heavy lock (07:41 to 10:33, in four rounds), the branch with main at 919e05a merged in;
the builds and the check again at 1442d8ac, the code as it is in the pull request.

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
- **G3, the touch rig** (Tests/touchrig on the agents' iPad simulator, main's surfaces at 919e05a against this
  branch's, 134 strokes each): every existing stroke's events identical to main's, 88 of 88 (`compare.py
  --all`); the three-finger gestures' verdict 72 of 72; the strokes at the left edge, 59 of 59 (`--edge`):
  - Each flick hides and sends nothing, on the picture and on the trackpad (off the edge from 30 pt, stopped by
    a case's lip 22 pt in, 45° down from 40 pt, after a 0.1 s rest: 440 to 569 pt/s at their ends), and from a
    button at the edge; a flick while the recognizer does not listen goes on as main's.
  - Every other stroke in the band sends what main's surfaces send, in order: a tap (let go at its lift), a
    0.6 s long press (at 0.25 s), drags right (at 6 pt), down and up (at 8 pt), a slow drag left (at 0.25 s), a
    quick drag left lifted 26 pt in (at its lift), two fingers (at the second's landing), a scroll from the
    middle that runs off the edge (never held), a grip resting at the edge with a tap elsewhere.
  - The controls hidden: a tap, drags right and left, a drag down and a long press near the edge and away from
    it, as main's, none taken by the swipe in.
  - UIKit's pan began 10 pt into a 1 pt-a-frame drag, right, left and down alike: a drag the band lets go at 6
    or 8 pt is not late.
  - **Found and fixed by it**, each against main's surfaces: recognizers that only watch, made to wait, kept the
    flick and the trackpad from ever resetting after the first stroke it held (the trackpad answered nothing
    more; they no longer wait, `WatchesTouchesOnly`); a held pan counted its travel from where it was let go, so
    a slow drag left near the edge scrolled 20 pt where main's scrolled 30 (the picture's scroll now carries the
    difference, `heldLanding`); the recognizers did not call super in their touch overrides. The rig itself no
    longer built against main (InputOverlay's DuoPosture since #215, KeyChords' paste key since #64): it compiles
    DuoPosture.swift and StreamProtocol whole now.
  - Not shown by it: the system's edge recognizer takes no synthesized touch, so the swipe in was played in the
    live gate, not swiped; SwiftUI's Button takes no synthesized touch either (main's run pressed it neither), so
    on the button the rig shows a flick hiding and nothing pressed, not a tap pressing it.

## Noah's test (the device test, short)

On the iPad mini and the iPhone 15 Pro, a Debug build from this branch, Xcode's console open for the `reveal:`
and `full screen:` lines, Sill for Mac with Virtual Display on, a window streaming:

1. Settings › Full Screen (after Frame Rate): the panel closes, the controls go, the window grows to the screen
   (one "Resized"/restart line in Sill.log). The card shows the first 3 times. The two rows and their words do not
   touch.
2. Upright and on its side, on both: swipe in from the left edge slowly, stop half way, go back: the controls
   follow and slide back out, and nothing but the controls and their own black shows as they come and go (no
   frame, no box under the bar, nothing flashing as they slide back). Again past about 80 pt: they settle. Then a
   quick swipe in: they come. The console's `pointer: this device has it (…)` must not follow a swipe in.
3. Hidden, near the left edge: a tap clicks, a long press and drags up, down and left scroll or drag the Mac as
   before; only a drag to the right from the edge brings the controls.
4. Hidden: shake: back. Settings › Shake to Show Controls off: a shake does nothing (and Shake to Undo works in
   a text field while shown). VoiceOver on: the picture element, double-tap: back.
5. iPad with a trackpad or mouse: hidden, hold the pointer at the left edge: back after half a second. Stage
   Manager on: hidden, swipe in from the left: Sill's controls (not the strip); twice: the strip.
6. Upright on both: a window with Virtual Display on fills the screen when hidden; the Desktop keeps its shape
   with black above and below.
7. Hardware keyboard: hidden, type: it reaches the Mac. Software keyboard up, hide: it goes; show: it comes back.
8. Rotate while hidden: stays hidden, and the next swipe in shows the turned layout's controls at once. Leave Sill
   and come back: stays hidden. Relaunch: shown.
