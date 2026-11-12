**Full screen: Sill's controls hidden from Settings › Full Screen, back by a swipe in from the left edge or a shake
(2026-11-12, branch `full-screen` from main at a4bad80, main at 0d22bbf and 919e05a merged in, PR #360; issues #279,
#92, #280; the design, Noah's device test, the numbers and why, the open questions with the defaults taken, the
results and his test are in `docs/full-screen-plan.md`).** Settings › Full Screen hides every control, so the Mac's
picture gets the screen's room; a swipe in from the left edge brings them back, the controls following the finger,
and so does a shake while Settings › Shake to Show Controls is on; nothing of Sill's stays on screen. Device only:
no wire change, nothing on the Mac, nothing stored but how often the hint has shown and the shake's switch.
- The first build (a flick off the left edge to hide, the system's edge pan to show) failed Noah's device test on
  his iPad mini and iPhone 15 Pro ("The touch detection is really bad", nothing on their side); the coordinator's
  try builds (`full-screen-try`, never pushed) gave him this design, which he approved on both devices, and this
  branch is it written properly. The plan has his words and what the device logs showed.
- The rule (`FullScreenPolicy.swift`, pure; `Tests/checks/full-screen`): `EdgeSwipe` (a finger landing within
  max(24 pt, the window's left safe-area inset), judged after 8 pt: right and no steeper than 45° is the swipe in,
  anything else is let go; a second finger, or 0.3 s without setting off, lets it go), `EdgeReveal` (finishes
  after min(a third of the width, 80 pt) with the lift's coast, or a 300 pt/s flick in after 12 pt; springs back
  moving back at 200 pt/s), `RevealCut` (the preview's picture's place in each layout, from the layout's own
  geometry: under landscape's bar; over the halves' controls block, DuoPosture's split; over a phone's picture's
  room, PhonePortraitLayout), `EdgeDwell`, `FullScreenPolicy` (offered while Sill's window covers the screen; why
  the controls come back by themselves; `Sill.shakeToShowControls` and Shake to Undo; where the Settings rows go;
  the hint; the room; the words), `ChromeLevel` (one level; a slot for a second, parked by Noah).
- The recognizer (`RevealEdgePan.swift`): a UIPanGestureRecognizer of Sill's on its window, on only while hidden,
  in the window's space, so the interface's left edge in every orientation (the system's edge pan read the device's
  upright left edge); while it judges a touch in its band the picture's recognizers wait (`EdgeRecognizers.waits`),
  and a held scroll carries its travel (`heldLanding`, `panHysteresis`, `releasedAtLift`). While the controls show
  nothing of full screen's listens. Removed with the flick: `EdgeFlick`, `EdgeFlickGate`, its recognizer and
  arming, the trackpad's tracker changes (TrackpadView.swift is main's again).
- The preview: each layout's own, drawing its controls with the black they sit on and nothing of the picture's
  place, by construction (the picture pane an empty view, the black only at `RevealCut.shown`, landscape's bar
  carrying its own); no mask and nothing measured (a mask a frame late flashed on the try builds).
- Settings: Full Screen (a button) with its words, then Shake to Show Controls with its line, right after Frame
  Rate while the Mac's settings show, in This iPad's group while they do not.
- DEBUG: `-SillFullScreen 1`, `-SillFullScreenReveal P`, `-SillFullScreenHint 1|hold`, `-SillFullScreenRoom
  screen|housing|safe`, `-SillFullScreenToggle`, `-SillFullScreenSwipe`, `-SillShakeAt`, `-Sill.shakeToShowControls
  0`, `-SillSettingsScroll fullscreen`; the console's `full screen:` and `reveal:` lines, and `pointer: this device
  has it (…)` now names the input (ContentView's contract, docs/DEVELOPMENT.md). The touch rig: `RIG_ONLY=edge`,
  `RIG_ONLY=reveal RIG_ORIENT=landscape`, `compare.py --edge`.
- Verified: the plan's Results.
- **Untested, for Noah:** the plan's "Noah's test" on the iPad mini and the iPhone 15 Pro.
