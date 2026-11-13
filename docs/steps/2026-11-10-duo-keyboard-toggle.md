**The keyboard toggle on the Duo's inner display (2026-11-10 and 11, branch `duo-keyboard-toggle` from main at
f224323, PR #343, merged at baf0901 (c1e612a) on 2026-11-11; then `duo-keyboard-followup` from c1e612a, the
toggle at the left corner with these docs and the mutants; issue #215 after matt-cahill's device test of 0.6.1
(1304); the decision in Noah's words, the measurements, the rule and the results are in docs/iphone-duo-plan.md,
"The keyboard toggle").** On a real Duo the emoji keyboard covered the row until it had gone once (the glass was
learned only at a hide, one height per width), taps in the crease were hard to hit and a miss clicked the Mac,
and open flat the emoji keyboard covered the rows. Noah (2026-11-10): "read the keyboard's height while it is up.
If the keyboard is regular as we have done, we keep the compact view. If for some reason that would be covered up
(i.e. emoji keyboard) surface a small toggle on the top screen for the keyboard, and thats it. No full row."
Device only, no wire change; every Duo build and photo on the iOS 27.1 runtime.
- The first version (4e9f412) tracked which of the input mode's keyboards was up from the keyboard's own report
  at each switch and indexed the letters keyboards' heights (English 396, Pinyin 445). Noah's hand test: 😀
  brought the toggle, ABC left it up over the English keyboard. Cause (reproduced with that build): in the laptop
  pose, once the keyboard has been put away and brought back, or after any reload of the input views, iOS posts
  no keyboard report at a switch; 4e9f412 waited a second for one and took the switch for another keyboard. Its
  own tests had switched only in the first keyboard session. Noah: "Is there a more clever way to know when to
  show the button rather than indexing all the keyboards", and "I want it to be as instant as the old build was".
- Measured (the iOS 27.1 simulator): in the laptop pose UIKit reports every keyboard as the whole lower page (0,
  455.5, 669×495.5), whatever it draws (English's glass at 555, 396 pt; emoji, its search and Pinyin at 506, 445
  pt); open flat every keyboard is itself, live (English (0, 640, 669×311), emoji (0, 553, 669×398), Pinyin (0,
  600, 669×351)). A reload of the input views (`reloadInputViews`, nothing else changed) makes UIKit report the
  keyboard up as the report's begin frame, exactly, with no animation and no hide; it keeps the emoji keyboard,
  its numbers and a Pinyin composition, but closes the emoji search, and a reload during a show's animation is
  never answered. Until the keyboard is first put away after Sill opens (and before any reload) iOS also reports
  each switch itself and the keyboard's in-process views (a container and the remote keyboard's placeholder in
  another window of the scene, found by geometry, never by class) sit where the keyboard is drawn; after that,
  neither. After a fold the reload's report gives the other pose's keyboard for about a second.
- The rule, read and not indexed (DuoPosture, pure; `Tests/checks/duo`): `plausibleGlass` (as wide as the screen,
  down to its foot, under the fold's edge) and `keyboardGlass` (open flat the report; in the laptop pose the
  reading, else not known); `keyboardLook` (those views; `keyboardLookIsOff` when a switch's report puts the
  keyboard left more than 1.5 pt from the last look: around the emoji search); `keyboardReadDelays` (a coming
  keyboard after its animation, a switch every 40–70 ms from 50 ms while `keyboardReadsAgain`, a fold every
  150–200 ms, then two late reloads or more from a second on), `keyboardReportIsReading` (within 0.5 s of a
  reload, not animated, never a hide), `keyboardReadingIsStale` (the other pose's frame for 2 s after a fold),
  `keyboardSwitchReportWait` (0.4 s for a switch's own report, then reloads); `KeyboardHints`, `keyboardHints`,
  `keyboardPrediction` (instant: the last reading of each input mode's letters keyboard and of the other keyboard
  by width, kept across launches as `Sill.keyboardHints`, filled only by readings, assumed at once at a show or a
  switch and corrected by the reading); `keyboardStandIn` (the laptop pose: the compact row as before while 44 pt
  caps fit with 8 of black, 4 + 51 + 4 under English, else the toggle; the glass not known: the toggle, but
  nothing while a reading is on its way, `keyboardSettle` 0.8 s, 1.2 after a fold; open flat: the row 4 pt above
  the glass, 51 pt, never above the pane's foot, whenever the glass covers the rows, else the toggle);
  `keyboardToggle` (44×44 at 14,395: the pane's bottom leading corner, below). KeyboardFrameMonitor
  (InputOverlay.swift) looks first, reloads where looks tell nothing or are off, never while an input method
  composes, at most 40 reloads in 10 s. PortraitStreamScreen: the toggle a lit BarButton with the Keyboard
  symbol, "Hide the keyboard", Large Content Viewer, over the picture (never the Mac's touch); the controls
  hidden from sight, touch and VoiceOver while the row or the toggle stands in; DEBUG `keyboard: …` lines. Gone:
  the crease row, `laptopKeyboardHeight`, `measuredLaptopKeyboard`, `KeyboardPlane`, `planeAfterSwitch`, the
  learned heights.
- Timing (ms from the switch, or the show's first notification, to the decision; 4e9f412 → baf0901): show 6 → 6;
  😀 and ABC in the first keyboard session 60 and 72 → 60 and 72; in later sessions about 1000 and never → 28–40
  and 45–54.
- Verified at the merge (the plan's Results): `duo` 301,002 checks; CI's Build and check on baf0901; the iOS app
  Debug for the simulator and for a device (installed on an iPad mini); live on a private Duo simulator against a
  synthetic host, XCUITest taps, every photo judged by its pixels: Noah's sequence (English, 😀, ABC) 40/40 on a
  fresh install, 20/20 in a later keyboard session, 40/40 twice with a hardware keyboard seen and under load;
  Pinyin with its composition and candidates (no reload while composing), Japanese, the Globe key, folds both
  ways, open flat unchanged, every letter typed right after ABC (15/15). Noah's hand test on the Duo simulator
  against Sill for Mac and on an iPad mini: "The keyboard build is approved for a merge".
- The toggle at the left corner (2026-11-11, `duo-keyboard-followup`): Noah, on the merged build with the
  clipboard's chip over the toggle, "Why would you merge that with the overlap? Move the keyboard icon to the
  left corner instead and merge". `keyboardToggle(paneBottom:sides:)` gives the pane's bottom leading corner,
  44×44 at (14, 395) in the laptop pose, its leading edge on the key row's; placed from the leading edge, so the
  right corner in a right-to-left layout, always opposite the chip's bottom trailing corner. Same size, inset,
  action, label. Nothing else of Sill's sits there (the link's line hangs from the pane's top; the tour,
  Settings, the drawer and pairing take the keyboard down first); while it shows the chip is at most as wide as
  the room beside it, 8 pt clear (`clipboardChipMaxWidth`, 587 pt), so a long Mac name truncates. The duo mutants for the merged code (G the glass, K looks, F the
  row's fit, H hints, Q what is assumed, R readings, S the stand-in, T the toggle, its corner among them) and the
  checks they needed; these docs. Verified (the plan's "The toggle at the left corner"): `duo` 332,316 checks and
  170 of 170 mutants; the iOS app Debug for the simulator, only the StreamClient warning; harness photos with the
  real keyboard on "Sill 215c duo": the emoji keyboard, the toggle bottom left and the chip bottom right apart,
  right to left the other way round, `-SillAXDump` one element "Hide the keyboard" (14,395 44×44); main's build
  against this one pixel for pixel the same with the English row and open flat; Noah's sequence once in a later
  keyboard session against a synthetic host, 20/20 (😀 31–33 ms, ABC 48–54). Not run: run-all, the tour's mutants,
  Release and device builds (the disk); a real Duo. Known limits as at the merge: the emoji search closes as it
  opens in later keyboard sessions (no gentler way reads the glass; the options are in the plan), the first
  keyboard after a fresh install and a fold with the keyboard up show the row about 0.4 s late.
- **Untested, for Noah / for a Duo:** whether a real Duo (the reporters' iOS 27.2) reports the keyboard after a
  reload as the simulator does, and its own keyboard heights; the plan's P14 (the English row, 😀 the toggle, ABC
  the row, a tap on the toggle puts the keyboard away and clicks nothing on the Mac, Pinyin or Japanese,
  third-party keyboards, the toggle under a finger and at an accessibility text size, VoiceOver, open flat with
  the emoji keyboard, folds both ways with it up, a hardware keyboard).
