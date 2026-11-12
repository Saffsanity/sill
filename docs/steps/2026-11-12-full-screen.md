**Full screen: Sill's controls hidden by a flick off the left edge, back by a swipe in from it (2026-11-12, branch
`full-screen` from main at a4bad80, main at 0d22bbf merged in; issues #279, #92, #280; the design, the numbers
and why, the open questions with the defaults taken, the results and Noah's device test are in
`docs/full-screen-plan.md`).** Noah's design with the coordinator's changes: a short flick off the left edge
hides every control, so the Mac's picture gets the screen's room; a swipe in from the left bezel brings them
back, the controls following the finger; nothing of Sill's stays on screen. Device only: no wire change,
nothing on the Mac, nothing stored but how often the hint has shown.
- The rule (`FullScreenPolicy.swift`, pure; `Tests/checks/full-screen`): `EdgeFlick`, the hide's touch rule (a
  finger alone landing within 48 pt of the left edge, 12 pt left, within 0.25 s, 300 pt/s over its last 50 ms,
  lifting within 24 pt of the edge or carried past it within 50 ms; let go after 6 pt right or 8 pt steeper than
  about 50°), `EdgeFlickGate`, `EdgeReveal` (the swipe in finishes past a third of the width, or at a flick in;
  springs back moving back), `EdgeDwell` (the iPad's pointer half a second at the left edge), `FullScreenPolicy`
  (offered while Sill's window covers the screen; why the controls come back by themselves; the hint the first
  3 times; the room: clear of the sensor housing, down under the home indicator; the words), `ChromeLevel` (one
  level: everything or nothing; a slot for a second, parked by Noah).
- The recognizers (`EdgeFlickRecognizer.swift`): the flick's and the swipe in's (`RevealEdgePan`, the system's
  edge recognizer), on Sill's window; every other recognizer there that takes fingers waits for them to fail
  (`shouldBeRequiredToFail(by:)`), so a touch at the edge is held only while the rule decides and then is the hide
  alone or goes on whole. The trackpad's tracker starts from where the finger landed (`downLocation`).
- The glue (`FullScreen.swift`): `FullScreenEdges` (the recognizers and a hover on the window, the window covering
  the screen, the window's shake), the shake (`UIWindow.motionEnded`; Shake to Undo off while hidden), the hint,
  the swipe in's preview hole, the hidden picture as one element (Show Controls; the escape gesture; Voice
  Control's "Show Controls"), DEBUG `FullScreenDebug`.
- The layouts: StreamScreen's `chrome` and `reveal` (kept across a rotation and a trip to another app, nothing
  across a launch); while hidden its reader takes the whole screen, the status bar hides, the home indicator
  fades, iPadOS's left-edge gesture is deferred; each layout's picture pane is the same view hidden or shown (its
  input view keeps first responder; the frame animates), placed at the room; the controls slide out and in by
  the left edge; the swipe in's preview is the shown layout over the hidden picture, its pane a hole.
- Settings › This iPad (This iPhone) › Full Screen, after Picture in Picture: a button that hides now (dimmed while
  a hide cannot start; "Full Screen works while Sill fills the screen." when the window does not).
- DEBUG: `-SillFullScreen 1`, `-SillFullScreenReveal P`, `-SillFullScreenHint 1|hold`, `-SillFullScreenRoom
  screen|housing|safe`, `-SillFullScreenToggle`, `-SillFullScreenSwipe`, `-SillShakeAt`, `-SillSettingsScroll
  fullscreen`; the console's `full screen:` and `edge:` lines (ContentView's contract, docs/DEVELOPMENT.md).
- Noah, after the build began (through the coordinator): one level only; upright a window with Virtual Display
  on (or Aa set) fills the device; the Desktop keeps its shape until the Virtual Desktop can match the device.
- Verified: (filled in below as the gates run.)
- **Untested, for Noah:** the plan's "Noah's test" on the iPad mini and the iPhone 15 Pro.
