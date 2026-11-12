**The Settings window on a small screen (2026-10-14, branch `settings-window-height` from main at
985a733, PR #74; issue #59; the probe, the plan and the results are in
`docs/settings-window-plan.md`).** rosstex, a 14-inch MacBook Pro on macOS 26.6.2 with Sill 0.5.1:
"The Remote Access settings on Mac are too tall and cannot be resized." Mac app only: no wire change,
nothing on the iOS side, the CLI untouched.
- Cause (a scratch probe of the same setup on macOS 27.0.1): AppKit gives the selected pane's view a
  constraint named `NSViewController.preferredContentSize.height` (the hosting controller's
  preferredContentSize, SwiftUI's whole Form) at priority 501, just over the window's own 500, and
  lays the window out to it, keeping its top-left; the window is not resizable, so nothing shortens
  it (a 50-row pane made a 2,028 pt window). The constraint follows growth and every tab switch; in
  the probe it did not follow a pane that got shorter, but Sill's Remote Access pane shrank the
  window with it (909 → 734 pt). Sill's window adds 80 pt of title bar and toolbar. Remote Access
  with the internet switch on (909 to 983 pt) and rosstex's 951 pt window fit a 14-inch only at More
  Space (1,800 × 1,169); General (727) fits at the default scaling, Dock or not, but not at the
  larger-text scalings with the Dock (`Tests/checks/settings-window` has each case).
- Fix: `SettingsWindowController.heightCap`, the content view's height at most
  `SettingsWindowFit.contentLimit` (the screen's visible frame less the chrome and 12 pt above and
  below, whole points, at least 200) at priority 750; the Forms scroll. Set at show, on every tab
  switch (`SettingsTabController.onSelect`), on `NSApplication.didChangeScreenParametersNotification`
  and `windowDidChangeScreen`; a new cap lays a window on screen out at once. `place()` (after
  `windowDidResize` and `refit`) moves the window back inside the visible frame, 12 pt clear of the
  edge it ran past, when Sill's own changes leave it partly outside; never sideways, never while a
  mouse button is down (then once all are up, `placeOnRelease`), and never a window that fits where
  it is: a saved frame sets only the window's top-left, and AppKit orders a window that ran off the
  bottom while hidden back in at the screen's bottom, so a capped window can sit flush with the menu
  bar or the screen's bottom, the 24 pt on the other side. Sill's virtual display is never the screen
  (`SettingsWindowFit.screenIndex`). Rejected in the probe: an NSHostingController subclass clamping
  preferredContentSize (SwiftUI never calls its setter) and a SwiftUI `.frame(maxHeight:)` on the
  pane (lowered while a pane showed, it left the window tall: the probe's 501 constraint did not
  follow it down).
- `SettingsWindowFit` (pure, CoreGraphics): `Tests/checks/settings-window`, 307,709 checks (the
  issue's screens, an external 4K display, screens above and beside, windows partly off the screen,
  the virtual display, the test height, then 20,000 seeded random cases) and 27 of 27 mutants, in
  CI's mutants matrix.
- TEST ONLY, the bare binary; Sill.app ignores each with one line: `-SillSettingsAfter '<s>
  <tab>|close|report|end|height=<points>; …'` (opens Settings as the menu does and prints the window's
  frame, the pane's whole height and how much shows), `-SillTestScreenHeight <points>`,
  `-SillSettingsShot <dir>` (docs/DEVELOPMENT.md).
- Verified (the plan's Results; this Mac, a 14-inch at its default scaling, 949 pt under the menu
  bar; the bare binary on `--synthetic` on loopback, only while no device was connected, Sill.app
  untouched): `swift build -c release` clean from `git archive`, only the CaptureProbe warning;
  `run-all.sh`, all 41; the previews (130 files) identical to 985a733's; every tab at its natural
  height (limit 845) but Remote Access with the internet switch on (909: shows 845, scrolls, 12 pt
  from both edges, Sill having moved it); `-SillTestScreenHeight 700`: General (727) and Remote
  Access (909) capped at 596 and scrolling; the screen changing under the tall pane (`height=`, the
  notification's path): 845, 596, 396, 845, the window shrinking and growing; a pane growing past
  the cap, and a tab switch to it, with the window low: moved up to 12 pt over the bottom; a window
  opened at rosstex's saved frame (951 pt, its top at the menu bar; a saved frame sets only the
  top-left) capped at 925, 0 pt under the menu bar and 24 over the bottom, and a 70 and a 140 pt
  Dock under it, 855 and 785, its top kept; a pane grown while Settings was closed, reopened by
  AppKit at the screen's bottom, 24 pt under the menu bar; General and Streaming scrolled to their
  ends inside a 600 pt screen (231 and 72 pt); Sill.app's ignore lines, from the binary in a scratch
  bundle under `sandbox-exec` with binds denied; CI's "Build and check" on c2339e2 and, after the
  review's fixes, 1865ada. Photos without personal details in
  `~/Downloads/sill-handoff/settings-window/`.
- Review (2026-10-14, at bb2451e; it re-ran everything above with the same numbers): three findings,
  each fixed in a commit of its own (the plan's "The review"). Should fix: the untested lists left
  out macOS 26, the reporter's, and Sill's virtual display (now U6 and U7). Nits: "the 501
  constraint never shrinks" and "General does not fit a 14-inch with the Dock" (corrected above,
  with 20 checks for which pane fits which scaling); U1, U2 and the PR's steps promised 12 pt above
  and below (now: 12 pt only on a side Sill moved the window away from). Re-run after the fixes:
  `swift build -c release` clean from `git archive`, only the CaptureProbe warning; `run-all.sh`,
  all 41; `settings-window` 27 of 27 mutants; where a capped window sits, with a scratch build whose
  window was invisible and never activated (the screen unlocked, nobody at it).
- **Untested, for Noah** (the plan's U1 to U8, with Sill.app from this branch on the 14-inch): at
  the scaling at the far left with the Dock showing, every tab fits between the menu bar and the
  Dock (12 pt clear only on a side Sill moved it away from), General scrolls to Quit Sill and Remote
  Access (Remote Access and "Allow connections from the internet" on) to Sleep; with Settings open,
  change the scaling and the Dock's size and hiding: it follows each time (note a Dock change that
  shows only at the next tab click); drag it to a smaller external display and let go low: it moves
  up once the button is up, and grows back on the larger one; a held click on a tab never moves it;
  VoiceOver reaches Quit Sill in a capped General; macOS 26, the reporter's (everything was
  measured on 27.0.1, and merging closes #59): U1 on a Mac with 26, or a build for rosstex; with
  Sill's virtual display there (Virtual Display on, a window streaming), every tab shows on the
  built-in display and fits it, also once Virtual Display is turned off with Settings open; macOS 14
  or 15 if at hand.
