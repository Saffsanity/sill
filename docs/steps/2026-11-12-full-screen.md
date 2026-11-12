**Full screen: Sill's controls hidden by a flick off the left edge, back by a swipe in from it (2026-11-12, branch
`full-screen` from main at a4bad80, main at 0d22bbf and 919e05a merged in, PR #360; issues #279, #92, #280; the design, the numbers
and why, the open questions with the defaults taken, the results and Noah's device test are in
`docs/full-screen-plan.md`).** Noah's design with the coordinator's changes: a short flick off the left edge
hides every control, so the Mac's picture gets the screen's room; a swipe in from the left bezel brings them
back, the controls following the finger; nothing of Sill's stays on screen. Device only: no wire change,
nothing on the Mac, nothing stored but how often the hint has shown.
- The rule (`FullScreenPolicy.swift`, pure; `Tests/checks/full-screen`): `EdgeFlick`, the hide's touch rule (a
  finger alone landing within 48 pt of the left edge, 12 pt left, within 0.25 s, 300 pt/s over its last 50 ms (from
  where the finger was 50 ms before the lift, so a rest before the flick does not count),
  lifting within 24 pt of the edge or carried past it within 50 ms; let go after 6 pt right or 8 pt steeper than
  about 50°), `EdgeFlickGate`, `EdgeReveal` (the swipe in finishes past a third of the width, or at a flick in;
  springs back moving back; a finger at the bezel that has not begun to swipe in by 0.3 s is let go), `EdgeDwell` (the iPad's pointer half a second at the left edge), `FullScreenPolicy`
  (offered while Sill's window covers the screen; why the controls come back by themselves; the hint the first
  3 times; the room: clear of the sensor housing, down under the home indicator; the words), `ChromeLevel` (one
  level: everything or nothing; a slot for a second, parked by Noah).
- The recognizers (`EdgeFlickRecognizer.swift`): the flick's and the swipe in's (`RevealEdgePan`, the system's
  edge recognizer, failing at once for a touch landing more than 40 pt in), on Sill's window; every other
  recognizer there that takes fingers waits for them to fail (`EdgeRecognizers.waits`), so a touch at the edge is
  held only while the rule decides and then is the hide alone or goes on whole. The trackpad's tracker starts from
  where the finger landed (`downLocation`); a stroke judged only at its lift keeps its travel
  (`EdgeRecognizers.releasedAtLift`: the picture's scroll and the trackpad's tracker carry it at their end, the
  trackpad's pan leaves it to the tracker, `trackerPending`). Nothing of this is reached away from the edge.
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
- Verified (the plan's Results; this Mac, inside the heavy lock, main at 919e05a merged in): the check, 56,514
  checks, and 59 of 59 mutants; the iOS app Debug and Release for the simulator and Debug for a device at every fix,
  only the known `StreamClient` warning; repo-rules 10 of 10; live on loopback (`SillHost --synthetic`, loopback,
  software encoder, no screen, the dry-run input log; the Debug app under `-SillLive 1` on the agents' iPad
  simulator), six hides and shows with input every 0.1 s around each: one viewport per change (an upright iPhone's
  393×793 hidden and 377×235 shown, an iPad mini's 1133×744 and 1117×618), every tap, key and letter at the host,
  and the Desktop kept on the Mac's second screen (#355) through a hide, a show and a shake; the shared photo tool,
  the shown layouts pixel for pixel main's but the Settings panel's new row (13 of 15 on the Duo simulator, 5 of 7
  on the iPad's), 37 hidden photos (the room's choices, a tall window filling an upright iPhone and iPad mini, the
  Desktop letterboxed, the Duo's poses, the hint, the swipe in's preview with "Desktop 2"); the touch rig, every
  existing stroke identical to main's (88 of 88), the gestures' verdict 72 of 72, and the strokes at the left edge
  59 of 59 (every flick hides and sends nothing; every other stroke in the band sends what main's surfaces send, in
  order). Found and fixed on the way: watch-only recognizers made to wait, which kept the flick and the trackpad
  from ever resetting after the first stroke it held (the rig's first run: the trackpad answered nothing more); a
  held pan's travel lost (the picture's scroll now carries it as an unheld pan counts it); the hidden room under the
  Dynamic Island (a GeometryReader that ignores the safe area reports none: the window's safe area now); a flick
  after a sample-free rest read slow (the speed's window interpolated); the swipe in holding a still finger at the
  bezel until it lifted (0.3 s now); the recognizers not calling super in their touch overrides (UIKit's
  contract); the rig itself no longer built against main (DuoPosture.swift, and StreamProtocol whole).
- **Untested, for Noah:** the plan's "Noah's test" on the iPad mini and the iPhone 15 Pro.
